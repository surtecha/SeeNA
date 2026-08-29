import Combine
import Foundation
import Network

@MainActor
final class NetworkReachabilityService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var usesExpensiveInterface = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.surtecha.seena.network-monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let service = self else { return }
            let connected = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                service.isConnected = connected
                service.usesExpensiveInterface = expensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
