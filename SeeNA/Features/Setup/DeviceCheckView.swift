import AVFoundation
import SwiftUI

struct DeviceCheckView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var tier: DeviceCapabilityTier?
    @State private var didAutoContinue = false
#if DEBUG
    @State private var showingCalibrationHarness = false
#endif

    var body: some View {
        ScreenScaffold(
            title: "This iPhone is ready",
            subtitle: "SeeNA will use the front camera and motion sensors for this POC screening."
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
                detail: AVAudioApplication.shared.recordPermission == .granted ? "Ready" : "Voice permission not granted",
                state: AVAudioApplication.shared.recordPermission == .granted ? .ready : .warning
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
                if case .fullScreening = tier {
                    session.navigate(to: .phoneSetup)
                } else {
                    session.appError = .sensorUnavailable("A supported TrueDepth iPhone")
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
                guard !didAutoContinue else { return }
                didAutoContinue = true
                await dependencies.spokenPrompts.speakAndWait(
                    profile.isValidated
                        ? "Phone ready. Set it upright at eye level."
                        : "POC mode ready. Set the phone upright at eye level."
                )
                guard session.path.last == .deviceCheck else { return }
                session.navigate(to: .phoneSetup)
            } else {
                dependencies.spokenPrompts.speak("This iPhone cannot run the camera screening.")
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
        return profile.isValidated ? "Physically validated" : "POC sensor profile"
    }

    private var calibrationState: StatusRow.State {
        dependencies.profileRegistry.profile() == nil ? .warning : .ready
    }

    private var outcomeText: String {
        switch tier {
        case .fullScreening(let profile):
            return profile.isValidated
                ? "Ready for Landolt C and Gabor screening."
                : "Ready for POC Landolt C and Gabor screening. Exact tape-measure validation is not yet complete."
        case .accessibilityOnly: return "This iPhone cannot run the visual screening."
        case .unsupported: return "This device cannot safely run the SeeNA assessment."
        case nil: return "Checking device capabilities…"
        }
    }

    private var continueTitle: String {
        if case .fullScreening = tier { return "Continue" }
        return "Screening unavailable"
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
