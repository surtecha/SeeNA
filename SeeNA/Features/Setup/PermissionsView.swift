import AVFoundation
import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var dependencies: AppDependencies
    @State private var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
    @State private var isRequesting = false

    var body: some View {
        ScreenScaffold(
            title: "Camera and voice permission",
            subtitle: "Camera frames are analysed in memory and never uploaded. Short voice clips are sent only for transcription and are deleted after processing."
        ) {
            StatusRow(
                title: "Front camera",
                detail: cameraGranted ? "Permission granted" : "Measures distance and head position",
                state: cameraGranted ? .ready : .warning
            )
            StatusRow(
                title: "Microphone",
                detail: microphoneGranted ? "Permission granted" : "Records bounded direction responses",
                state: microphoneGranted ? .ready : .warning
            )

            Button(isRequesting ? "Requesting…" : "Allow permissions") {
                Task { await requestPermissions() }
            }
            .buttonStyle(PrimaryActionStyle())
            .disabled(isRequesting)

            if cameraGranted || session.isAccessibilityOnly {
                Button("Continue") { session.navigate(to: .deviceCheck) }
                    .buttonStyle(SecondaryActionStyle())
            }
        }
        .navigationTitle("Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func requestPermissions() async {
        isRequesting = true
        defer { isRequesting = false }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        } else {
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }
        microphoneGranted = await dependencies.audioRecorder.requestPermission()
        if !cameraGranted { session.isAccessibilityOnly = true }
    }
}
