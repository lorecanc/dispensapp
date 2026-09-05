import XCTest
@testable import Inventario

final class OutboxStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "OutboxStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCreate(tempId: Int, quantity: Int = 3) -> OutboxStore.Mutation {
        .create(.init(
            barcode: "800\(abs(tempId))",
            name: "Prodotto \(tempId)",
            brand: "Marca",
            expirationDate: Date(timeIntervalSince1970: 1_800_000_000),
            category: "pasta",
            imageURL: nil,
            quantity: quantity,
            tempId: tempId
        ))
    }

    private func makeUpdate(itemId: Int, quantity: Int) -> OutboxStore.Mutation {
        .update(.init(itemId: itemId, name: nil, brand: nil, expirationDate: nil, category: nil, quantity: quantity))
    }

    // MARK: - Persistenza di default (M2)

    func testDefaultDirectoryLivesInApplicationSupportNotCaches() throws {
        let store = OutboxStore()
        XCTAssertEqual(store.directory.lastPathComponent, "InventarioOutbox")
        let appSupport = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        XCTAssertTrue(
            store.directory.path.hasPrefix(appSupport.path),
            "Le entry outbox sono l'unica copia delle mutazioni non syncate: mai in Caches (purgeabile)"
        )
    }

    // MARK: - Enqueue / persistenza / reload

    func testEnqueueRoundTripPreservesTypesAndPayloads() throws {
        var store = OutboxStore(directory: directory)
        store.enqueue(makeCreate(tempId: -1), pantryId: 7)
        store.enqueue(.consume(.init(itemId: 42, delta: 2, reason: "cena")), pantryId: 7)
        store.enqueue(makeUpdate(itemId: 42, quantity: 5), pantryId: 7)
        store.enqueue(.delete(.init(itemId: 43)), pantryId: 7)

        // Istanza nuova, stessa directory: tutto rileggibile da disco.
        let reloaded = OutboxStore(directory: directory).entries
        XCTAssertEqual(reloaded.count, 4)
        XCTAssertEqual(reloaded.map(\.pantryId), [7, 7, 7, 7])
        XCTAssertEqual(reloaded[1].mutation, .consume(.init(itemId: 42, delta: 2, reason: "cena")))
        XCTAssertEqual(reloaded[2].mutation, makeUpdate(itemId: 42, quantity: 5))
        XCTAssertEqual(reloaded[3].mutation, .delete(.init(itemId: 43)))

        guard case .create(let payload) = reloaded[0].mutation else {
            return XCTFail("prima entry non .create")
        }
        XCTAssertEqual(payload.tempId, -1)
        XCTAssertEqual(payload.barcode, "8001")
        XCTAssertEqual(payload.name, "Prodotto -1")
        XCTAssertEqual(payload.quantity, 3)
        XCTAssertEqual(payload.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testCorruptFileYieldsEmptyQueueAndIsRewritten() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appending(path: "outbox.json")
        try Data("non-è-json".utf8).write(to: fileURL)

        var store = OutboxStore(directory: directory)
        XCTAssertTrue(store.isEmpty)

        store.enqueue(.delete(.init(itemId: 1)), pantryId: 1)
        XCTAssertEqual(OutboxStore(directory: directory).count, 1)
    }

    // MARK: - FIFO

    private func deleteItemIds(of entries: [OutboxStore.Entry]) -> [Int] {
        entries.map { entry in
            guard case .delete(let payload) = entry.mutation else { return -999 }
            return payload.itemId
        }
    }

    func testEntriesAreFifoAndRemoveKeepsOrder() throws {
        var store = OutboxStore(directory: directory)
        let first = store.enqueue(.delete(.init(itemId: 1)), pantryId: 1)
        store.enqueue(.delete(.init(itemId: 2)), pantryId: 1)
        store.enqueue(.delete(.init(itemId: 3)), pantryId: 1)

        // Ordine di lettura = ordine di inserimento (FIFO).
        XCTAssertEqual(deleteItemIds(of: OutboxStore(directory: directory).entries), [1, 2, 3])

        store.remove(id: first.id)
        XCTAssertEqual(deleteItemIds(of: OutboxStore(directory: directory).entries), [2, 3])
    }

    // MARK: - Last-write-wins: l'ordine di coda definisce il vincitore

    func testLastWriteWinsUsesEnqueueOrder() throws {
        var store = OutboxStore(directory: directory)
        store.enqueue(makeUpdate(itemId: 7, quantity: 5), pantryId: 1)
        store.enqueue(makeUpdate(itemId: 7, quantity: 7), pantryId: 1)

        // Il replay è FIFO: il server riceve 5 poi 7 → lo stato finale vince (7).
        let quantities: [Int?] = OutboxStore(directory: directory).entries.map { entry in
            guard case .update(let p) = entry.mutation else { return nil }
            return p.quantity
        }
        XCTAssertEqual(quantities, [5, 7])
    }

    // MARK: - Temp-id: allocazione monotona persistente

    func testNextTempIdDecrementsAndNeverReusesAcrossReloads() throws {
        var store = OutboxStore(directory: directory)
        XCTAssertEqual(store.nextTempId(), -1)
        XCTAssertEqual(store.nextTempId(), -2)

        // Riavvio (istanza nuova): il contatore sopravvive, niente collisioni.
        var reloaded = OutboxStore(directory: directory)
        XCTAssertEqual(reloaded.nextTempId(), -3)
    }

    // MARK: - Temp-id → server-id: remapping delle entry successive

    func testRemapTempIdUpdatesSubsequentEntriesAndPersists() throws {
        var store = OutboxStore(directory: directory)
        let createEntry = store.enqueue(makeCreate(tempId: -1), pantryId: 1)
        store.enqueue(.consume(.init(itemId: -1, delta: 1, reason: nil)), pantryId: 1)
        store.enqueue(makeUpdate(itemId: -1, quantity: 9), pantryId: 1)
        store.enqueue(.delete(.init(itemId: -1)), pantryId: 1)
        // Riferimento non-temp che non deve essere toccato.
        store.enqueue(.consume(.init(itemId: 42, delta: 1, reason: nil)), pantryId: 1)

        // Replay riuscito della create: via la entry, poi remap.
        store.remove(id: createEntry.id)
        store.remapTempId(-1, to: 55)

        let reloaded = OutboxStore(directory: directory).entries
        XCTAssertEqual(reloaded[0].mutation, .consume(.init(itemId: 55, delta: 1, reason: nil)))
        XCTAssertEqual(reloaded[1].mutation, makeUpdate(itemId: 55, quantity: 9))
        XCTAssertEqual(reloaded[2].mutation, .delete(.init(itemId: 55)))
        XCTAssertEqual(reloaded[3].mutation, .consume(.init(itemId: 42, delta: 1, reason: nil)))
    }

    func testRemapTempIdLeavesCreateEntriesUntouched() throws {
        var store = OutboxStore(directory: directory)
        store.enqueue(makeCreate(tempId: -1), pantryId: 1)
        store.enqueue(makeCreate(tempId: -2), pantryId: 1)
        store.remapTempId(-1, to: 100)

        // Le create restano con il proprio tempId (l'id server lo decide il replay).
        let reloaded = OutboxStore(directory: directory).entries
        guard case .create(let first) = reloaded[0].mutation, case .create(let second) = reloaded[1].mutation else {
            return XCTFail("entry non .create")
        }
        XCTAssertEqual(first.tempId, -1)
        XCTAssertEqual(second.tempId, -2)
    }

    // MARK: - Politica di replay: scarto 404/409, stop sui transienti

    func testDecisionDropsConflictsAndClientErrors() {
        XCTAssertEqual(OutboxStore.decision(for: .notFound), .drop)
        XCTAssertEqual(OutboxStore.decision(for: .http(status: 404, message: nil)), .drop)
        XCTAssertEqual(OutboxStore.decision(for: .http(status: 409, message: nil)), .drop)
        XCTAssertEqual(OutboxStore.decision(for: .http(status: 422, message: "x")), .drop)
        XCTAssertEqual(OutboxStore.decision(for: .decoding(URLError(.cannotDecodeContentData))), .drop)
    }

    func testDecisionStopsOnTransientAndServerErrors() {
        XCTAssertEqual(OutboxStore.decision(for: .offline), .stop)
        XCTAssertEqual(OutboxStore.decision(for: .transport(URLError(.timedOut))), .stop)
        XCTAssertEqual(OutboxStore.decision(for: .http(status: 500, message: nil)), .stop)
        XCTAssertEqual(OutboxStore.decision(for: .http(status: 503, message: nil)), .stop)
        XCTAssertEqual(OutboxStore.decision(for: .invalidURL), .stop)
    }
}
