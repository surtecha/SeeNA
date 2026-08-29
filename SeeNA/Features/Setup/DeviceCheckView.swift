import AVFoundation
import SwiftUI

struct DeviceCheckView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var tier: DeviceCapabilityTier?
#if DEBUG
    @State private var showingCalibrationHarness = false
#endif

    var body: some View {
        ScreenScaffold(
            title: "Device compatibility",
            subtitle: "Numeric screening is enabled only for an exact iPhone model with completed physical calibration."
        ) {
            StatusRow(
                title: "Hardware identifier",
                detail: dependencies.profileRegistry.hardwareIdentifier,
                state: dependencies.profileRegistry.profile() == nil ? .warning : .ready
            )
            StatusRow(
                title: "Face tracking",
                detail: dependencies.sensorCoordinator.faceTrackingSupported ? "Available" : "Unavailable",
                state: dependencies.sensorCoordinator.faceTrackingSupported ? .ready : .unavailable
            )
            StatusRow(
                title: "Motion sensors",
                detail: dependencies.sensorCoordinator.motionSupported ? "Available" : "Unavailable",
                state: dependencies.sensorCoordinator.motionSupported ? .ready : .unavailable
            )
            StatusRow(
                title: "Device calibration",
                detail: calibrationDetail,
                state: calibrationState
            )
            StatusRow(
                title: "Microphone",
                detail: AVAudioSession.sharedInstance().recordPermission == .granted ? "Ready" : "Voice permission not granted",
                state: AVAudioSession.sharedInstance().recordPermission == .granted ? .ready : .warning
            )
            StatusRow(
                title: "Internet for voice transcription",
                detail: dependencies.network.isConnected
                    ? (dependencies.network.usesExpensiveInterface ? "Connected using mobile data" : "Connected")
                    : "Offline — operator response fallback remains available",
                state: dependencies.network.isConnected ? .ready : .warning
            )

            Text(outcomeText)
                .font(.body.weight(.semibold))
                .foregroundColor(SEENATheme.secondaryInk)
                .padding(18)
                .background(SEENATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(continueTitle) {
                if case .fullScreening = tier, !session.isAccessibilityOnly {
                    session.navigate(to: .phoneSetup)
                } else {
                    session.isAccessibilityOnly = true
                    session.navigate(to: .accessibilityIntroduction)
                }
            }
            .buttonStyle(PrimaryActionStyle())

#if DEBUG
            if dependencies.profileRegistry.profile() != nil {
                Button("Open physical calibration tool") { showingCalibrationHarness = true }
                    .buttonStyle(SecondaryActionStyle())
            }
#endif
        }
        .task {
            let assessment = dependencies.profileRegistry.capabilityTier()
            tier = assessment
            session.capabilityTier = assessment
            if case .fullScreening(let profile) = assessment {
                session.activeSession.deviceProfile = profile
            }
        }
        .navigationTitle("Compatibility")
        .navigationBarTitleDisplayMode(.inline)
#if DEBUG
        .sheet(isPresented: $showingCalibrationHarness, onDismiss: refreshTier) {
            DeviceCalibrationHarnessView()
        }
#endif
    }

    private var calibrationDetail: String {
        guard let profile = dependencies.profileRegistry.profile() else { return "No profile for this exact hardware" }
        return profile.isValidated ? "Validated profile v\(profile.profileVersion)" : "Candidate profile — physical calibration required"
    }

    private var calibrationState: StatusRow.State {
        dependencies.profileRegistry.profile()?.isValidated == true ? .ready : .warning
    }

    private var outcomeText: String {
        switch tier {
        case .fullScreening: return "This exact device is ready for numeric screening and accessibility setup."
        case .accessibilityOnly: return "Accessibility setup is available. Numeric screening remains disabled until this exact device passes calibration."
        case .unsupported: return "This device cannot safely run the SEENA assessment."
        case nil: return "Checking device capabilities…"
        }
    }

    private var continueTitle: String {
        if case .fullScreening = tier, !session.isAccessibilityOnly { return "Continue to phone setup" }
        return "Continue to accessibility setup"
    }

    private func refreshTier() {
        let assessment = dependencies.profileRegistry.capabilityTier()
        tier = assessment
        session.capabilityTier = assessment
        if case .fullScreening(let profile) = assessment {
            session.activeSession.deviceProfile = profile
        }
    }
}
