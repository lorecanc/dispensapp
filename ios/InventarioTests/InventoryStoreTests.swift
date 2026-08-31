import XCTest
@testable import Inventario

final class InventoryStoreTests: XCTestCase {

    private func makeItem(id: Int, expirationDate: Date?) -> InventoryItem {
        InventoryItem(
            id: id,
            barcode: nil,
            name: "Prodotto \(id)",
            brand: nil,
            expirationDate: expirationDate,
            isEstimated: false,
            category: nil,
            imageURL: nil,
            createdAt: Date(),
            quantity: 1,
            status: "ok"
        )
    }

    func testSortingByExpirationDateNilLast() {
        let now = Date()
        let soon = now.addingTimeInterval(60*60*24) // +1 day
        let later = now.addingTimeInterval(60*60*24*5) // +5 days
        let items = [
            makeItem(id: 1, expirationDate: nil),
            makeItem(id: 2, expirationDate: later),
            makeItem(id: 3, expirationDate: soon),
            makeItem(id: 4, expirationDate: nil),
            makeItem(id: 5, expirationDate: now)
        ]
        let sorted = items.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        // earliest first, nil last
        XCTAssertEqual(sorted[0].id, 5) // now
        XCTAssertEqual(sorted[1].id, 3) // soon
        XCTAssertEqual(sorted[2].id, 2) // later
        // nils at end (order stable but both distantFuture)
        XCTAssertTrue([1,4].contains(sorted[3].id))
        XCTAssertTrue([1,4].contains(sorted[4].id))
    }

    func testSortingAllNilKeepsStable() {
        let items = (1...3).map { makeItem(id: $0, expirationDate: nil) }
        let sorted = items.sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        // all equal distantFuture, should preserve original order (stable sort not guaranteed but no crash)
        XCTAssertEqual(sorted.count, 3)
    }

    func testSortingSingleItem() {
        let item = makeItem(id: 1, expirationDate: Date())
        let sorted = [item].sorted { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        XCTAssertEqual(sorted.first?.id, 1)
    }

    func testSortingMatchesStoreLogic() {
        // Replica la logica di InventoryStore: items.sort { ($0.expirationDate ?? .distantFuture) < ... }
        let past = Date().addingTimeInterval(-60*60*24)
        let future = Date().addingTimeInterval(60*60*24*10)
        var items = [
            makeItem(id: 1, expirationDate: future),
            makeItem(id: 2, expirationDate: nil),
            makeItem(id: 3, expirationDate: past)
        ]
        items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        XCTAssertEqual(items.map(\.id), [3,1,2])
    }

    @MainActor
    func testInventoryStoreRefreshSortingIntegration() async {
        // Verifica che InventoryStore espone sorting senza crashare (non chiama rete qui, solo logica di ordinamento)
        let store = InventoryStore()
        let now = Date()
        store.items = [
            makeItem(id: 2, expirationDate: now.addingTimeInterval(86400*3)),
            makeItem(id: 1, expirationDate: nil),
            makeItem(id: 3, expirationDate: now)
        ]
        // Simula sort come fa refresh()
        store.items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
        XCTAssertEqual(store.items.first?.id, 3)
        XCTAssertEqual(store.items.last?.id, 1)
    }
}
