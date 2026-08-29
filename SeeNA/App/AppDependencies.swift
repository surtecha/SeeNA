import Foundation
import Combine

@MainActor
final class AppDependencies: ObservableObject {
    let profileRegistry: DeviceProfileRegistry
    let sessionStore: SessionStore
    let sensorCoordinator: SensorCoordinator
    let audioRecorder: AudioBlockRecorder
    let spokenPrompts: SpokenPromptService
    let backend: BackendClient
    let network: NetworkReachabilityService
    let brightness: BrightnessManager

    init(
        profileRegistry: DeviceProfileRegistry,
        sessionStore: SessionStore,
        sensorCoordinator: SensorCoordinator,
        audioRecorder: AudioBlockRecorder,
        spokenPrompts: SpokenPromptService,
        backend: BackendClient,
        network: NetworkReachabilityService,
        brightness: BrightnessManager
    ) {
        self.profileRegistry = profileRegistry
        self.sessionStore = sessionStore
        self.sensorCoordinator = sensorCoordinator
        self.audioRecorder = audioRecorder
        self.spokenPrompts = spokenPrompts
        self.backend = backend
        self.network = network
        self.brightness = brightness
    }

    static func live() -> AppDependencies {
        let registry = DeviceProfileRegistry()
        return AppDependencies(
            profileRegistry: registry,
            sessionStore: SessionStore(),
            sensorCoordinator: SensorCoordinator(profileRegistry: registry),
            audioRecorder: AudioBlockRecorder(),
            spokenPrompts: SpokenPromptService(),
            backend: BackendClient(configuration: .bundle),
            network: NetworkReachabilityService(),
            brightness: BrightnessManager()
        )
    }

    static func preview() -> AppDependencies {
        let registry = DeviceProfileRegistry(profiles: [])
        return AppDependencies(
            profileRegistry: registry,
            sessionStore: SessionStore(inMemory: true),
            sensorCoordinator: SensorCoordinator(profileRegistry: registry, useMockData: true),
            audioRecorder: AudioBlockRecorder(),
            spokenPrompts: SpokenPromptService(),
            backend: BackendClient(configuration: .unavailable),
            network: NetworkReachabilityService(),
            brightness: BrightnessManager(isEnabled: false)
        )
    }
}
