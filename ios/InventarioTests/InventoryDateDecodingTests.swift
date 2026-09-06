import XCTest
@testable import Inventario

/// Tests for `JSONDecoder.DateDecodingStrategy.inventoryDate`
/// (ios/Inventario/Models/InventoryItem.swift).
///
/// T1-Red (TDD): the strategy currently tries, in order:
///   1. ISO8601DateFormatter [.withInternetDateTime, .withFractionalSeconds]
///   2. ISO8601DateFormatter [.withInternetDateTime]
///   3. DateFormatter "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" (GMT)
///   4. DateFormatter "yyyy-MM-dd" (GMT)
/// None of them accepts a naive timestamp WITHOUT fractional seconds
/// (e.g. "2026-09-06T10:02:00"), so decoding it must throw
/// DecodingError.dataCorrupted — that is the bug case below.
///
/// Semantics pinned: naive inputs (no timezone suffix) must decode to the
/// UTC instant, matching the existing GMT-configured fallback formatters.
final class InventoryDateDecodingTests: XCTestCase {

    /// Minimal payload: the only non-optional CodingKeys of InventoryItem.
    /// Optional keys (barcode, brand, expiration_date, image_url,
    /// storage_location) are omitted — the synthesized decoder uses
    /// decodeIfPresent for them.
    private static func payload(createdAt: String) -> Data {
        let json = """
        {
            "id": 1,
            "name": "Test Item",
            "is_estimated": false,
            "created_at": "\(createdAt)",
            "quantity": 3,
            "status": "ok"
        }
        """
        return Data(json.utf8)
    }

    /// Reference instant built from GMT DateComponents, so the expectation is
    /// independent of the machine's local timezone.
    private static func utcInstant(year: Int, month: Int, day: Int,
                                   hour: Int = 0, minute: Int = 0, second: Int = 0,
                                   nanosecond: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar.current.date(from: components)!
    }

    private func decodeItem(createdAt: String) throws -> InventoryItem {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .inventoryDate
        return try decoder.decode(InventoryItem.self, from: Self.payload(createdAt: createdAt))
    }

    // MARK: - Bug case (must fail pre-fix)

    /// "2026-09-06T10:02:00": naive, no fractional seconds, no timezone.
    /// Pre-fix NO formatter in the strategy accepts it, so decode throws
    /// DecodingError.dataCorrupted and this test is RED.
    /// Post-fix it must decode to the UTC instant 2026-09-06 10:02:00 +0000.
    func testNaiveTimestampWithoutFractionalSecondsDecodesAsUTC() throws {
        let item = try decodeItem(createdAt: "2026-09-06T10:02:00")
        let expected = Self.utcInstant(year: 2026, month: 9, day: 6, hour: 10, minute: 2, second: 0)
        XCTAssertEqual(item.createdAt, expected,
                       "naive timestamp without fractional seconds must decode as UTC (naive = UTC semantics)")
    }

    // MARK: - Already-supported variants (must stay green: regression guard)

    /// "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" fallback, GMT.
    func testNaiveTimestampWithFractionalSecondsDecodesAsUTC() throws {
        let item = try decodeItem(createdAt: "2026-09-06T10:02:00.123456")
        let expected = Self.utcInstant(year: 2026, month: 9, day: 6, hour: 10, minute: 2, second: 0,
                                       nanosecond: 123_456_000)
        // Tolerance: Date is Double-backed, exact equality of sub-second values
        // computed via different paths is not guaranteed. 1ms is far smaller
        // than any timezone offset, so "naive = UTC" is still pinned.
        XCTAssertEqual(item.createdAt.timeIntervalSince(expected), 0, accuracy: 0.001)
    }

    /// ISO8601 with Zulu timezone.
    func testTimestampWithZuluTimezoneDecodes() throws {
        let item = try decodeItem(createdAt: "2026-09-06T10:02:00Z")
        let expected = Self.utcInstant(year: 2026, month: 9, day: 6, hour: 10, minute: 2, second: 0)
        XCTAssertEqual(item.createdAt, expected)
    }

    /// ISO8601 with explicit zero offset.
    func testTimestampWithZeroOffsetTimezoneDecodes() throws {
        let item = try decodeItem(createdAt: "2026-09-06T10:02:00+00:00")
        let expected = Self.utcInstant(year: 2026, month: 9, day: 6, hour: 10, minute: 2, second: 0)
        XCTAssertEqual(item.createdAt, expected)
    }

    /// ISO8601 fractional seconds + Zulu timezone.
    func testTimestampWithFractionalSecondsAndZuluDecodes() throws {
        let item = try decodeItem(createdAt: "2026-09-06T10:02:00.123456Z")
        let expected = Self.utcInstant(year: 2026, month: 9, day: 6, hour: 10, minute: 2, second: 0,
                                       nanosecond: 123_456_000)
        XCTAssertEqual(item.createdAt.timeIntervalSince(expected), 0, accuracy: 0.001)
    }

    /// "yyyy-MM-dd" fallback: date-only must land on UTC midnight.
    func testDateOnlyDecodesAsUTCMidnight() throws {
        let item = try decodeItem(createdAt: "2026-09-06")
        let expected = Self.utcInstant(year: 2026, month: 9, day: 6)
        XCTAssertEqual(item.createdAt, expected,
                       "date-only value must decode to 2026-09-06 00:00:00 UTC")
    }
}
