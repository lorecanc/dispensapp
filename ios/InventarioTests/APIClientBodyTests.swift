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

    // C1-1 Red: DatePicker produce local-midnight (ManualEntryView, ScanPreviewSheet);
    // l'outbound formatter (APIClient.dateFormatter, GMT) la rende come giorno-1
    // per utenti a est di UTC. Il giorno spedito deve eguagliare il giorno scelto.
    func testInventoryBodyPreservesPickedCalendarDayEastOfUTC() throws {
        let rome = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rome
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 6
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        let pickedMidnight = try XCTUnwrap(calendar.date(from: comps))
        // Sanity: il Date costruito è davvero la mezzanotte locale del giorno scelto.
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: pickedMidnight)
        XCTAssertEqual(roundTrip.year, 2026)
        XCTAssertEqual(roundTrip.month, 9)
        XCTAssertEqual(roundTrip.day, 6)

        let body = try APIClient.inventoryBody(
            name: "Prodotto", brand: nil, expirationDate: pickedMidnight,
            category: nil, quantity: 1
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let sent = try XCTUnwrap(json["expiration_date"] as? String)
        XCTAssertEqual(sent, "2026-09-06",
                       "local-midnight Europe/Rome del 2026-09-06 deve restare 2026-09-06 (GMT la rende 2026-09-05)")
    }
}
