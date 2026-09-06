import Foundation
import XCTest
@testable import Inventario

/// B1 Red test: `listScoped` non invia limit/offset e il backend pagina con
/// limit=50 di default (backend/routes/inventory.py:283-284). `refresh()` assegna
/// la risposta come set completo → gli item 51+ spariscono in silenzio.
///
/// Stub simula il backend paginato: richiesta senza offset → primi 50,
/// richiesta con offset=50 → i restanti 20. Il path refresh-equivalente
/// (singola `listScoped`, come fa `InventoryStore.refresh`) dovrebbe raccogliere
/// tutti i 70: pre-fix ne raccoglie 50 → RED.
/// Il fix atteso rende `listScoped(pantryId:)` stessa paginante in trasparenza
/// (stessa firma, loop limit/offset interno): questo test diventa Green senza modifiche.
final class InventoryPagingRedTests: XCTestCase {

    /// Stub URLProtocol che serve due pagine in base al query-item `offset`.
    private final class PagedInventoryStub: URLProtocol {
        static var page1 = Data()
        static var page2 = Data()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let offset = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "offset" })?.value
                .flatMap(Int.init) ?? 0
            let body = offset >= 50 ? Self.page2 : Self.page1
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var originalBaseURL: String?

    override func setUp() {
        super.setUp()
        originalBaseURL = UserDefaults.standard.string(forKey: "apiBaseURL")
        APIConfig.baseURLString = "http://127.0.0.1:8000"
    }

    override func tearDown() {
        if let originalBaseURL {
            UserDefaults.standard.set(originalBaseURL, forKey: "apiBaseURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "apiBaseURL")
        }
        super.tearDown()
    }

    private func makeItem(id: Int) -> InventoryItem {
        InventoryItem(
            id: id,
            barcode: nil,
            name: "Prodotto \(id)",
            brand: nil,
            expirationDate: nil,
            isEstimated: false,
            category: nil,
            imageURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            quantity: 1,
            status: "ok"
        )
    }

    private func json(_ items: [InventoryItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(items)
    }

    private func stubbedClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PagedInventoryStub.self]
        return APIClient(session: URLSession(configuration: config))
    }

    func testListScopedCollectsFullPantryBeyondBackendCap() async throws {
        // Dispensa da 70 item: pagina 1 = 50 (cap backend), pagina 2 = 20.
        let all = (1...70).map { makeItem(id: $0) }
        PagedInventoryStub.page1 = try json(Array(all.prefix(50)))
        PagedInventoryStub.page2 = try json(Array(all.suffix(20)))

        // Path refresh-equivalente: InventoryStore.refresh assegna a items
        // esattamente il risultato di questa singola chiamata.
        let collected = try await stubbedClient().listScoped(pantryId: 1)

        XCTAssertEqual(
            collected.count, 70,
            "pantry da 70 item oltre il cap backend limit=50: raccolti \(collected.count), attesi 70"
        )
        XCTAssertEqual(Set(collected.map(\.id)), Set(1...70))
    }
}
