import SwiftUI

// Queue item state for the central scan session.
enum ScanItemState: String, Sendable {
    case pending
    case loading
    case found
    case notFound
    case error
}

// Single scan in the checkout-style queue.
struct ScanQueueItem: Identifiable, Sendable {
    let id: UUID
    let barcode: String
    var state: ScanItemState
    var result: ScanResult?
    var errorMessage: String?
    let createdAt: Date
}

@Observable
@MainActor
final class ScanSessionStore {
    var queue: [ScanQueueItem] = []

    let cooldown: TimeInterval = 1.5
    let maxQueueSize = 20

    // Single debounce source of truth: per-barcode last accepted time.
    private var lastSeen: [String: Date] = [:]

    private let client: APIClient
    private let fetcher: (@Sendable (String) async throws -> ScanResult)?

    init(
        client: APIClient = .shared,
        fetcher: (@Sendable (String) async throws -> ScanResult)? = nil
    ) {
        self.client = client
        self.fetcher = fetcher
    }

    // Debounced enqueue: nil/empty discarded, same barcode inside
    // cooldown skipped, different barcodes pass immediately.
    @discardableResult
    func enqueue(_ barcode: String?) -> UUID? {
        guard let code = barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty
        else { return nil }
        let now = Date()
        if let last = lastSeen[code], now.timeIntervalSince(last) < cooldown {
            return nil
        }
        if queue.contains(where: { $0.barcode == code && ($0.state == .pending || $0.state == .loading) }) {
            return nil
        }
        lastSeen[code] = now
        while queue.count >= maxQueueSize {
            if let finished = queue.firstIndex(where: {
                $0.state == .found || $0.state == .notFound || $0.state == .error
            }) {
                queue.remove(at: finished)
            } else {
                queue.removeFirst()
            }
        }
        let item = ScanQueueItem(
            id: UUID(),
            barcode: code,
            state: .pending,
            result: nil,
            errorMessage: nil,
            createdAt: now
        )
        queue.append(item)
        return item.id
    }

    // Main entry: enqueue then fetch off-main via APIClient (already Sendable).
    func enqueueAndFetch(_ barcode: String?) async {
        guard let id = enqueue(barcode) else { return }
        await fetch(id: id)
    }

    func fetch(id: UUID) async {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].state = .loading
        queue[index].errorMessage = nil
        let barcode = queue[index].barcode
        do {
            let result: ScanResult
            if let fetcher {
                result = try await fetcher(barcode)
            } else {
                result = try await client.scan(barcode: barcode)
            }
            if result.found {
                updateState(id: id, to: .found, result: result)
            } else {
                updateState(id: id, to: .notFound, result: result)
            }
        } catch {
            if let apiError = error as? APIError, apiError == .notFound {
                updateState(id: id, to: .notFound, errorMessage: apiError.localizedDescription)
            } else {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                updateState(id: id, to: .error, errorMessage: message)
            }
        }
    }

    func updateState(id: UUID, to state: ScanItemState, result: ScanResult? = nil, errorMessage: String? = nil) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].state = state
        queue[index].result = result
        queue[index].errorMessage = errorMessage
    }

    // Drop items already saved to inventory; caller saves first.
    func clearSaved() {
        queue.removeAll(where: { $0.state == .found })
    }

    func clear() {
        queue.removeAll()
        lastSeen.removeAll()
    }

    func delete(id: UUID) {
        queue.removeAll(where: { $0.id == id })
    }

    func retry(id: UUID) async {
        guard queue.firstIndex(where: { $0.id == id }) != nil else { return }
        updateState(id: id, to: .pending)
        await fetch(id: id)
    }
}
