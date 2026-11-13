import Network
import Observation

/// Tracks connectivity so the UI can explain why search or map tiles are unavailable.
/// Saved trips never need the network.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "traveli.network-monitor"))
    }

    deinit { monitor.cancel() }
}
