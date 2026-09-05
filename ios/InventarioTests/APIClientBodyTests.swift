import XCTest
@testable import Inventario

final class APIClientBodyTests: XCTestCase {

    private func offTags(in body: Data) throws -> [String]? {
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        return json?["off_category_tags"] as? [String]
    }

    // Il backend dà 422 su liste >50 o tag >200 char: il body deve già rispettarli.
    func testInventoryBodyCapsOffTagsToBackendLimits() throws {
        let tags: [String] = (0..<60).map { i in
            i % 10 == 0 ? String(repeating: "x", count: 201) : "en:tag-\(i)"
        }
        let body = try APIClient.inventoryBody(
            barcode: "8001234567890", name: "Prodotto", brand: nil,
            expirationDate: nil, category: nil, quantity: 1, offTags: tags
        )
        let sent = try XCTUnwrap(offTags(in: body))
        XCTAssertLessThanOrEqual(sent.count, 50)
        XCTAssertTrue(sent.allSatisfy { $0.count <= 200 })
        // Ordine preservato: scartati i >200 char, tenuti i primi 50 validi.
        XCTAssertEqual(sent, Array(tags.filter { $0.count <= 200 }.prefix(50)))
    }

    func testInventoryBodyOmitsOffTagsWhenAllTooLong() throws {
        let tags = [String(repeating: "y", count: 250), String(repeating: "z", count: 301)]
        let body = try APIClient.inventoryBody(
            name: "Prodotto", brand: nil, expirationDate: nil,
            category: nil, quantity: 1, offTags: tags
        )
        XCTAssertNil(try offTags(in: body))
    }

    func testInventoryBodyOmitsEmptyOffTags() throws {
        let body = try APIClient.inventoryBody(
            name: "Prodotto", brand: nil, expirationDate: nil,
            category: nil, quantity: 1, offTags: []
        )
        XCTAssertNil(try offTags(in: body))
    }
}
