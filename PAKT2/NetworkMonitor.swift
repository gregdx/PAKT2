import Network
import Combine
import Foundation

@MainActor
class NetworkMonitor: ObservableObject {
    @Published var isConnected = true

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "NetworkMonitor")

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            // Hoist the connected flag out of the (non-sendable) NWPath before
            // hopping to the main actor. Capturing `self` weakly inside the
            // Task keeps Swift 6 strict concurrency happy — capturing the
            // outer `self` var across the Task boundary was the previous bug.
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isConnected = connected
            }
        }
        m.start(queue: queue)
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    deinit {
        monitor?.cancel()
    }
}
