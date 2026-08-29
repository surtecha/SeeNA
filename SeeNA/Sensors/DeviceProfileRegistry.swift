import ARKit
import Foundation
import UIKit

@MainActor
final class DeviceProfileRegistry {
    private let localProfileKey = "seena.localValidatedDeviceProfile.v1"
    private(set) var profiles: [DeviceProfile]

    init(profiles: [DeviceProfile]? = nil) {
        self.profiles = profiles ?? Self.loadBundledProfiles()
        if profiles == nil,
           let data = UserDefaults.standard.data(forKey: localProfileKey),
           let local = try? JSONDecoder().decode(DeviceProfile.self, from: data) {
            replaceProfile(local)
        }
    }

    var hardwareIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return machine
    }

    func profile(for identifier: String? = nil) -> DeviceProfile? {
        let identifier = identifier ?? hardwareIdentifier
        return profiles.first { $0.hardwareIdentifiers.contains(identifier) }
    }

    func capabilityTier() -> DeviceCapabilityTier {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return .unsupported(reason: .nonIPhone)
        }
        guard #available(iOS 16.0, *) else {
            return .unsupported(reason: .operatingSystemTooOld)
        }
        guard let profile = profile() else {
            return .accessibilityOnly(reason: .unvalidatedDevice)
        }
        guard ARFaceTrackingConfiguration.isSupported else {
            return .accessibilityOnly(reason: .faceTrackingUnavailable)
        }
        guard screenMatches(profile) else {
            return .accessibilityOnly(reason: .unvalidatedDevice)
        }
        guard profile.isValidated,
              profile.validationEvidence.sampleCount >= 1_200,
              profile.minimumValidatedDistance <= 0.40,
              profile.maximumValidatedDistance >= 2.00 else {
            return .accessibilityOnly(reason: .unvalidatedDevice)
        }
        return .fullScreening(profile: profile)
    }

    func replaceProfile(_ profile: DeviceProfile) {
        profiles.removeAll { existing in
            !Set(existing.hardwareIdentifiers).isDisjoint(with: profile.hardwareIdentifiers)
        }
        profiles.append(profile)
    }

    func persistValidatedProfile(_ profile: DeviceProfile) throws {
        guard profile.isValidated,
              profile.validationEvidence.sampleCount >= 1_200,
              profile.minimumValidatedDistance <= 0.40,
              profile.maximumValidatedDistance >= 2.00 else {
            throw RegistryError.insufficientValidation
        }
        let data = try JSONEncoder().encode(profile)
        UserDefaults.standard.set(data, forKey: localProfileKey)
        replaceProfile(profile)
    }

    func deleteLocalValidatedProfile() {
        UserDefaults.standard.removeObject(forKey: localProfileKey)
        profiles = Self.loadBundledProfiles()
    }

    enum RegistryError: Error {
        case insufficientValidation
    }

    private func screenMatches(_ profile: DeviceProfile) -> Bool {
        let bounds = UIScreen.main.nativeBounds
        let runtimeWidth = Int(min(bounds.width, bounds.height).rounded())
        let runtimeHeight = Int(max(bounds.width, bounds.height).rounded())
        let profileWidth = min(profile.nativePixelWidth, profile.nativePixelHeight)
        let profileHeight = max(profile.nativePixelWidth, profile.nativePixelHeight)
        return runtimeWidth == profileWidth
            && runtimeHeight == profileHeight
            && abs(Double(UIScreen.main.nativeScale) - profile.displayScale) < 0.01
    }

    private static func loadBundledProfiles() -> [DeviceProfile] {
        let candidateURLs = [
            Bundle.main.url(forResource: "device-profiles", withExtension: "json"),
            Bundle.main.url(forResource: "device-profiles", withExtension: "json", subdirectory: "DeviceProfiles"),
            Bundle.main.url(forResource: "device-profiles", withExtension: "json", subdirectory: "Resources/DeviceProfiles")
        ]
        guard let url = candidateURLs.compactMap({ $0 }).first,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([DeviceProfile].self, from: data) else {
            return []
        }
        return decoded
    }
}
