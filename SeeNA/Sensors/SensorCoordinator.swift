@preconcurrency import ARKit
import Combine
import CoreMotion
import Foundation
import UIKit

struct MotionSnapshot: Sendable {
    let attitudeDriftDegrees: Double
    let accelerationRMS: Double
    let rotationRateMagnitude: Double
    let stableDuration: TimeInterval

    var isStable: Bool {
        attitudeDriftDegrees < 1.5
            && accelerationRMS < 0.02
            && rotationRateMagnitude < 0.08
            && stableDuration >= 1
    }

    static let unavailable = MotionSnapshot(
        attitudeDriftDegrees: .infinity,
        accelerationRMS: .infinity,
        rotationRateMagnitude: .infinity,
        stableDuration: 0
    )
}

@MainActor
final class MotionStationarityService: ObservableObject {
    @Published private(set) var snapshot = MotionSnapshot.unavailable

    private let manager = CMMotionManager()
    private var referenceQuaternion: CMQuaternion?
    private var stableSince: Date?
    private var accelerationSquaredWindow: [Double] = []

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.consume(motion)
        }
    }

    func lockReference() {
        referenceQuaternion = manager.deviceMotion?.attitude.quaternion
        stableSince = nil
        accelerationSquaredWindow.removeAll(keepingCapacity: true)
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        referenceQuaternion = nil
        stableSince = nil
        accelerationSquaredWindow.removeAll(keepingCapacity: true)
        snapshot = .unavailable
    }

    private func consume(_ motion: CMDeviceMotion) {
        if referenceQuaternion == nil { referenceQuaternion = motion.attitude.quaternion }
        let drift = Self.angularDifferenceDegrees(referenceQuaternion, motion.attitude.quaternion)
        let instantaneousAccelerationSquared =
            pow(motion.userAcceleration.x, 2)
                + pow(motion.userAcceleration.y, 2)
                + pow(motion.userAcceleration.z, 2)
        accelerationSquaredWindow.append(instantaneousAccelerationSquared)
        if accelerationSquaredWindow.count > 30 {
            accelerationSquaredWindow.removeFirst(accelerationSquaredWindow.count - 30)
        }
        let accelerationRMS = sqrt(
            accelerationSquaredWindow.reduce(0, +) / Double(max(1, accelerationSquaredWindow.count))
        )
        let rotation = sqrt(
            pow(motion.rotationRate.x, 2)
                + pow(motion.rotationRate.y, 2)
                + pow(motion.rotationRate.z, 2)
        )
        let instantStable = drift < 1.5 && accelerationRMS < 0.02 && rotation < 0.08
        if instantStable {
            stableSince = stableSince ?? Date()
        } else {
            stableSince = nil
        }
        snapshot = MotionSnapshot(
            attitudeDriftDegrees: drift,
            accelerationRMS: accelerationRMS,
            rotationRateMagnitude: rotation,
            stableDuration: stableSince.map { Date().timeIntervalSince($0) } ?? 0
        )
    }

    private static func angularDifferenceDegrees(_ lhs: CMQuaternion?, _ rhs: CMQuaternion) -> Double {
        guard let lhs else { return .infinity }
        let dot = abs(lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z + lhs.w * rhs.w)
        return 2 * acos(min(1, max(-1, dot))) * 180 / .pi
    }
}

@MainActor
final class SensorCoordinator: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var latestSample: DistanceSample?
    @Published private(set) var isRunning = false
    @Published private(set) var failureMessage: String?

    let motion = MotionStationarityService()
    private let profileRegistry: DeviceProfileRegistry
    private let session = ARSession()
    private let useMockData: Bool
    private var fusion = DistanceFusionEngine()
    private var trackingFrames: [Bool] = []
    private var mockTask: Task<Void, Never>?

    init(profileRegistry: DeviceProfileRegistry, useMockData: Bool = false) {
        self.profileRegistry = profileRegistry
        self.useMockData = useMockData
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    var faceTrackingSupported: Bool { ARFaceTrackingConfiguration.isSupported }
    var motionSupported: Bool { motion.isAvailable }

    func start() {
        guard !isRunning else { return }
        failureMessage = nil
        if useMockData {
            startMockStream()
            isRunning = true
            return
        }
        guard ARFaceTrackingConfiguration.isSupported else {
            failureMessage = "Face tracking is unavailable on this device."
            return
        }
        guard motion.isAvailable else {
            failureMessage = "Motion sensing is unavailable on this device."
            return
        }
        motion.start()
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = 1
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session.pause()
        motion.stop()
        mockTask?.cancel()
        mockTask = nil
        isRunning = false
    }

    func lockPhoneReference() {
        motion.lockReference()
    }

    @discardableResult
    func captureBaseline() -> Bool {
        guard let sample = latestSample,
              let ar = sample.rawARDistanceMetres,
              let pixels = sample.interEyePixels,
              let measured = sample.correctedDistanceMetres ?? sample.fusedDistanceMetres ?? sample.rawARDistanceMetres,
              (0.34...0.46).contains(measured),
              sample.phoneStable else { return false }
        fusion.setBaseline(arDistance: ar, interEyePixels: pixels)
        return true
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let frame = session.currentFrame else { return }
        let faces = anchors.compactMap { $0 as? ARFaceAnchor }.filter(\.isTracked)
        trackingFrames.append(!faces.isEmpty)
        if trackingFrames.count > 90 { trackingFrames.removeFirst(trackingFrames.count - 90) }
        let coverage = trackingFrames.isEmpty ? 0 : Double(trackingFrames.filter { $0 }.count) / Double(trackingFrames.count)

        guard let face = faces.first else {
            latestSample = DistanceSample(
                rawARDistanceMetres: nil,
                relativeScaleDistanceMetres: nil,
                fusedDistanceMetres: nil,
                correctedDistanceMetres: nil,
                distanceStandardDeviation: nil,
                trackingCoverage: coverage,
                phoneStable: motion.snapshot.isStable,
                attitudeDriftDegrees: motion.snapshot.attitudeDriftDegrees,
                accelerationRMS: motion.snapshot.accelerationRMS,
                headYawDegrees: 0,
                headPitchDegrees: 0,
                luminance: Self.averageLuminance(frame.capturedImage),
                faceCount: faces.count,
                interEyePixels: nil
            )
            return
        }

        let leftTransform = simd_mul(face.transform, face.leftEyeTransform)
        let rightTransform = simd_mul(face.transform, face.rightEyeTransform)
        let left = SIMD3<Float>(leftTransform.columns.3.x, leftTransform.columns.3.y, leftTransform.columns.3.z)
        let right = SIMD3<Float>(rightTransform.columns.3.x, rightTransform.columns.3.y, rightTransform.columns.3.z)
        let centre = (left + right) / 2
        let eyeInCamera = simd_mul(simd_inverse(frame.camera.transform), SIMD4<Float>(centre.x, centre.y, centre.z, 1))
        let rawDistance = Double(abs(eyeInCamera.z))
        let viewport = UIScreen.main.bounds.size
        let projectedLeft = frame.camera.projectPoint(left, orientation: .portrait, viewportSize: viewport)
        let projectedRight = frame.camera.projectPoint(right, orientation: .portrait, viewportSize: viewport)
        let interEyePixels = hypot(projectedLeft.x - projectedRight.x, projectedLeft.y - projectedRight.y) * UIScreen.main.scale
        let angles = Self.eulerAnglesDegrees(face.transform)
        let profile = profileRegistry.profile()
        let estimate = fusion.estimate(
            rawARDistance: rawDistance,
            interEyePixels: interEyePixels,
            yawDegrees: angles.yaw,
            profile: profile
        )

        latestSample = DistanceSample(
            rawARDistanceMetres: rawDistance,
            relativeScaleDistanceMetres: estimate.relative,
            fusedDistanceMetres: estimate.fused,
            correctedDistanceMetres: estimate.corrected,
            distanceStandardDeviation: estimate.standardDeviation,
            trackingCoverage: coverage,
            phoneStable: motion.snapshot.isStable,
            attitudeDriftDegrees: motion.snapshot.attitudeDriftDegrees,
            accelerationRMS: motion.snapshot.accelerationRMS,
            headYawDegrees: angles.yaw,
            headPitchDegrees: angles.pitch,
            luminance: Self.averageLuminance(frame.capturedImage),
            faceCount: faces.count,
            interEyePixels: interEyePixels
        )
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        failureMessage = "Face tracking stopped. Reposition the phone and try again."
        isRunning = false
    }

    func sessionWasInterrupted(_ session: ARSession) {
        failureMessage = "Face tracking was interrupted. The active block was discarded."
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        failureMessage = nil
        guard isRunning, !useMockData else { return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = 1
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func startMockStream() {
        mockTask?.cancel()
        mockTask = Task { [weak self] in
            var index = 0.0
            while !Task.isCancelled {
                guard let self else { return }
                let distance = 0.40 + 0.02 * sin(index)
                latestSample = DistanceSample(
                    rawARDistanceMetres: distance,
                    relativeScaleDistanceMetres: distance,
                    fusedDistanceMetres: distance,
                    correctedDistanceMetres: distance,
                    distanceStandardDeviation: 0.006,
                    trackingCoverage: 0.98,
                    phoneStable: true,
                    attitudeDriftDegrees: 0.2,
                    accelerationRMS: 0.004,
                    headYawDegrees: 0.5,
                    headPitchDegrees: 0.4,
                    luminance: 0.55,
                    faceCount: 1,
                    interEyePixels: 210
                )
                index += 0.2
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private static func eulerAnglesDegrees(_ matrix: simd_float4x4) -> (yaw: Double, pitch: Double) {
        let yaw = atan2(Double(matrix.columns.0.z), Double(matrix.columns.2.z))
        let pitch = asin(max(-1, min(1, -Double(matrix.columns.1.z))))
        return (yaw * 180 / .pi, pitch * 180 / .pi)
    }

    private static func averageLuminance(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0,
              let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        let step = max(8, min(width, height) / 32)
        var total = 0
        var count = 0
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                total += Int(pointer[y * bytesPerRow + x])
                count += 1
            }
        }
        return count == 0 ? 0 : Double(total) / Double(count * 255)
    }
}
