@preconcurrency import ARKit
import Combine
import CoreMotion
import Foundation
import UIKit

typealias MotionSnapshot = MotionStationarityReading

@MainActor
final class MotionStationarityService: ObservableObject {
    @Published private(set) var snapshot = MotionSnapshot.unavailable

    private let manager = CMMotionManager()
    private var evaluator = MotionStationarityEvaluator()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        evaluator.reset()
        snapshot = .unavailable
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.consume(motion)
        }
    }

    func lockReference() {
        let motion = manager.deviceMotion
        evaluator.lock(
            attitude: motion.map { Self.attitude(from: $0.attitude.quaternion) },
            timestamp: motion?.timestamp ?? ProcessInfo.processInfo.systemUptime
        )
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        evaluator.reset()
        snapshot = .unavailable
    }

    private func consume(_ motion: CMDeviceMotion) {
        let instantaneousAccelerationSquared =
            pow(motion.userAcceleration.x, 2)
                + pow(motion.userAcceleration.y, 2)
                + pow(motion.userAcceleration.z, 2)
        let rotation = sqrt(
            pow(motion.rotationRate.x, 2)
                + pow(motion.rotationRate.y, 2)
                + pow(motion.rotationRate.z, 2)
        )
        snapshot = evaluator.consume(
            attitude: Self.attitude(from: motion.attitude.quaternion),
            accelerationSquared: instantaneousAccelerationSquared,
            rotationRateMagnitude: rotation,
            timestamp: motion.timestamp
        )
    }

    private static func attitude(from value: CMQuaternion) -> MotionAttitude {
        MotionAttitude(x: value.x, y: value.y, z: value.z, w: value.w)
    }
}

@MainActor
final class SensorCoordinator: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var latestSample: DistanceSample?
    @Published private(set) var isRunning = false
    @Published private(set) var failureMessage: String?

    let motion = MotionStationarityService()
    private let profileRegistry: DeviceProfileRegistry
    private var session: ARSession?
    private let useMockData: Bool
    private var fusion = DistanceFusionEngine()
    private var trackingFrames: [Bool] = []
    private var mockTask: Task<Void, Never>?
    private var smoothedGaze: GazeAlignment?

    init(profileRegistry: DeviceProfileRegistry, useMockData: Bool = false) {
        self.profileRegistry = profileRegistry
        self.useMockData = useMockData
        super.init()
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
        let activeSession: ARSession
        if let session {
            activeSession = session
        } else {
            let newSession = ARSession()
            newSession.delegate = self
            newSession.delegateQueue = .main
            session = newSession
            activeSession = newSession
        }
        motion.start()
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = 1
        activeSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

    func stop() {
        session?.pause()
        motion.stop()
        mockTask?.cancel()
        mockTask = nil
        smoothedGaze = nil
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
            smoothedGaze = nil
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
        let cameraInverse = simd_inverse(frame.camera.transform)
        let eyeInCamera = simd_mul(cameraInverse, SIMD4<Float>(centre.x, centre.y, centre.z, 1))
        let lookAtWorld = simd_mul(
            face.transform,
            SIMD4<Float>(face.lookAtPoint.x, face.lookAtPoint.y, face.lookAtPoint.z, 1)
        )
        let lookAtCamera = simd_mul(cameraInverse, lookAtWorld)
        let gaze = smoothGaze(
            GazeAlignmentEngine.errors(
                eyeX: Double(eyeInCamera.x),
                eyeY: Double(eyeInCamera.y),
                eyeZ: Double(eyeInCamera.z),
                lookX: Double(lookAtCamera.x),
                lookY: Double(lookAtCamera.y),
                lookZ: Double(lookAtCamera.z)
            )
        )
        let rawDistance = Double(abs(eyeInCamera.z))
        guard let screen = ScreenContext.active else { return }
        let viewport = screen.bounds.size
        let projectedLeft = frame.camera.projectPoint(left, orientation: .portrait, viewportSize: viewport)
        let projectedRight = frame.camera.projectPoint(right, orientation: .portrait, viewportSize: viewport)
        let interEyePixels = hypot(projectedLeft.x - projectedRight.x, projectedLeft.y - projectedRight.y) * screen.scale
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
            gazeYawErrorDegrees: gaze?.yawErrorDegrees,
            gazePitchErrorDegrees: gaze?.pitchErrorDegrees,
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
                    gazeYawErrorDegrees: 0,
                    gazePitchErrorDegrees: 0,
                    luminance: 0.55,
                    faceCount: 1,
                    interEyePixels: 210
                )
                index += 0.2
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func smoothGaze(_ current: GazeAlignment?) -> GazeAlignment? {
        guard let current else {
            smoothedGaze = nil
            return nil
        }
        guard let previous = smoothedGaze else {
            smoothedGaze = current
            return current
        }
        let newSampleWeight = 0.22
        let smoothed = GazeAlignment(
            yawErrorDegrees: previous.yawErrorDegrees * (1 - newSampleWeight)
                + current.yawErrorDegrees * newSampleWeight,
            pitchErrorDegrees: previous.pitchErrorDegrees * (1 - newSampleWeight)
                + current.pitchErrorDegrees * newSampleWeight
        )
        smoothedGaze = smoothed
        return smoothed
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
