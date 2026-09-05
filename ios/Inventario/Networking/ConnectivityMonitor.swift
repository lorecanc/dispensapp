import Foundation
import Network
import Observation

/// Stato di connettività reattivo per lo store (consumato da T11).
/// Wrapper minimale di NWPathMonitor: consegne su queue dedicata, pubblicazioni su main actor.
@Observable
@MainActor
final class ConnectivityMonitor {
    private(set) var isOnline: Bool

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.inventario.app.connectivity", qos: .utility)
    private var isStarted = false

    /// `monitor` iniettabile per test/preview (NWPathMonitor è Sendable da iOS 17 = deployment target).
    init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        self.isOnline = monitor.currentPath.status == .satisfied
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(isOnline: online) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    /// Seam per la logica pura: aggiornabile nei test senza NWPath.
    func update(isOnline online: Bool) {
        isOnline = online
    }

    deinit {
        monitor.cancel()
    }
}
