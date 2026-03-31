import Network
import Combine
import Foundation

@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected = true

    private let queue = DispatchQueue(label: "NetworkMonitor")

    func start() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
