import Foundation
import XCTest
@testable import SEENACore

final class DeviceProfileCatalogTests: XCTestCase {
    func testBundledCatalogDecodesAndIdentifiersAreUnique() throws {
        let profiles = try loadProfiles()
        XCTAssertFalse(profiles.isEmpty)

        let identifiers = profiles.flatMap(\.hardwareIdentifiers)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)

        for profile in profiles {
            XCTAssertEqual(profile.schemaVersion, 1)
            XCTAssertGreaterThan(profile.nativePixelWidth, 0)
            XCTAssertGreaterThan(profile.nativePixelHeight, profile.nativePixelWidth)
            XCTAssertGreaterThan(profile.displayScale, 0)
            XCTAssertGreaterThan(profile.pixelsPerInch, 0)
            XCTAssertLessThan(profile.minimumValidatedDistance, profile.maximumValidatedDistance)
        }
    }

    func testCatalogCoversEverySupportedIPhoneSeventeenVariant() throws {
        let profilesByIdentifier = Dictionary(
            uniqueKeysWithValues: try loadProfiles().compactMap { profile in
                profile.hardwareIdentifiers.first.map { ($0, profile) }
            }
        )

        let expected: [String: (variant: String, width: Int, height: Int)] = [
            "iPhone18,3": ("Base", 1_206, 2_622),
            "iPhone18,4": ("Air", 1_260, 2_736),
            "iPhone18,1": ("Pro", 1_206, 2_622),
            "iPhone18,2": ("Pro Max", 1_320, 2_868)
        ]

        for (identifier, specification) in expected {
            let profile = try XCTUnwrap(profilesByIdentifier[identifier])
            XCTAssertEqual(profile.marketingFamily, "iPhone 17")
            XCTAssertEqual(profile.variant, specification.variant)
            XCTAssertEqual(profile.nativePixelWidth, specification.width)
            XCTAssertEqual(profile.nativePixelHeight, specification.height)
            XCTAssertEqual(profile.displayScale, 3)
            XCTAssertEqual(profile.pixelsPerInch, 460)

            // Catalog coverage permits the qualitative journey. It must never
            // be mistaken for physical or clinical validation evidence.
            XCTAssertFalse(profile.isValidated)
            XCTAssertEqual(profile.validationEvidence.sampleCount, 0)
            XCTAssertNil(profile.displayRasterValidation)
            XCTAssertNil(profile.clinicalValidationEvidence)
        }
    }

    private func loadProfiles() throws -> [DeviceProfile] {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let catalogURL = testDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("SeeNA/Resources/DeviceProfiles/device-profiles.json")
        return try JSONDecoder().decode(
            [DeviceProfile].self,
            from: Data(contentsOf: catalogURL)
        )
    }
}
