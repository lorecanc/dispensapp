import XCTest
@testable import Inventario

final class LocalInventoryCacheTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LocalInventoryCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeItem(id: Int, expirationDate: Date? = nil) -> InventoryItem {
        InventoryItem(
            id: id,
            barcode: "800\(id)",
            name: "Prodotto \(id)",
            brand: "Marca \(id)",
            expirationDate: expirationDate,
            isEstimated: false,
            category: "pasta",
            imageURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            quantity: 3,
            status: "ok"
        )
    }

    // MARK: - Round-trip

    func testSaveLoadRoundTrip() throws {
        let cache = LocalInventoryCache(directory: directory)
        let savedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let items = [
            makeItem(id: 1, expirationDate: Date(timeIntervalSince1970: 1_800_000_000)),
            makeItem(id: 2, expirationDate: nil),
        ]

        XCTAssertTrue(cache.save(items, pantryId: 7, savedAt: savedAt))

        let snapshot = try XCTUnwrap(cache.load(pantryId: 7))
        XCTAssertEqual(snapshot.pantryId, 7)
        XCTAssertEqual(snapshot.savedAt, savedAt)
        XCTAssertEqual(snapshot.items.map(\.id), [1, 2])

        // InventoryItem confronta solo l'id: verifiche puntuali sui campi.
        let first = snapshot.items[0]
        XCTAssertEqual(first.barcode, "8001")
        XCTAssertEqual(first.name, "Prodotto 1")
        XCTAssertEqual(first.brand, "Marca 1")
        XCTAssertEqual(first.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(first.category, "pasta")
        XCTAssertEqual(first.quantity, 3)
        XCTAssertEqual(first.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - File mancante

    func testLoadMissingFileReturnsNil() {
        let cache = LocalInventoryCache(directory: directory)
        XCTAssertNil(cache.load(pantryId: 99))
    }

    // MARK: - File corrotto → nil pulito

    func testLoadCorruptFileReturnsNilAndCleansUp() throws {
        let cache = LocalInventoryCache(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "pantry-3.json")
        try Data("non-è-json".utf8).write(to: fileURL)

        XCTAssertNil(cache.load(pantryId: 3))
        // Pulito: lo snapshot spazzatura non sopravvive alla lettura fallita.
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        // Il salvataggio successivo funziona senza ostacoli.
        XCTAssertTrue(cache.save([makeItem(id: 10)], pantryId: 3))
        XCTAssertEqual(cache.load(pantryId: 3)?.items.map(\.id), [10])
    }

    func testLoadKeyMismatchReturnsNil() throws {
        // File nominato pantry-8.json ma contenente pantryId 9 → scartato.
        let cache = LocalInventoryCache(directory: directory)
        XCTAssertTrue(cache.save([makeItem(id: 1)], pantryId: 9))
        let source = directory.appending(path: "pantry-9.json")
        let dest = directory.appending(path: "pantry-8.json")
        try FileManager.default.moveItem(at: source, to: dest)

        XCTAssertNil(cache.load(pantryId: 8))
    }

    // MARK: - Overwrite

    func testSaveOverwritesPreviousSnapshot() throws {
        let cache = LocalInventoryCache(directory: directory)
        XCTAssertTrue(cache.save([makeItem(id: 1), makeItem(id: 2)], pantryId: 5))
        XCTAssertTrue(cache.save([makeItem(id: 5)], pantryId: 5, savedAt: Date(timeIntervalSince1970: 1_600_000_000)))

        let snapshot = try XCTUnwrap(cache.load(pantryId: 5))
        XCTAssertEqual(snapshot.items.map(\.id), [5])
        XCTAssertEqual(snapshot.savedAt, Date(timeIntervalSince1970: 1_600_000_000))
    }

    // MARK: - Uno snapshot per pantry

    func testSnapshotsAreIsolatedPerPantry() throws {
        let cache = LocalInventoryCache(directory: directory)
        XCTAssertTrue(cache.save([makeItem(id: 1)], pantryId: 1))
        XCTAssertTrue(cache.save([makeItem(id: 2)], pantryId: 2))

        XCTAssertEqual(cache.load(pantryId: 1)?.items.map(\.id), [1])
        XCTAssertEqual(cache.load(pantryId: 2)?.items.map(\.id), [2])
    }

    // MARK: - Remove

    func testRemoveDeletesSnapshot() throws {
        let cache = LocalInventoryCache(directory: directory)
        XCTAssertTrue(cache.save([makeItem(id: 1)], pantryId: 4))
        cache.remove(pantryId: 4)
        XCTAssertNil(cache.load(pantryId: 4))
    }
}
