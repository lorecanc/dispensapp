import Foundation

struct InventoryItem: Codable, Identifiable, Equatable {
    let id: Int
    let barcode: String?
    let name: String
    let brand: String?
    let expirationDate: Date?
    let isEstimated: Bool
    let category: String?
    let imageURL: String?
    let createdAt: Date
    let quantity: Int
    let status: String
    /// Campo additivo (T11): scelta utente esplicita ("frigo"|"freezer"|"dispensa"),
    /// nil = derivata dalla categoria (backend persiste NULL). Decodifica tollerante
    /// su payload senza chiave; `var` + default: memberwise init invariato.
    var storageLocation: String? = nil
    /// Campi additivi (T8c): sorgente/tipo prodotto ("food"|"beauty"|"petfood"|"product"),
    /// nil = non impostato. Decodifica tollerante come sopra.
    var source: String? = nil
    var productType: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, barcode, name, brand, category, quantity, status, source
        case expirationDate = "expiration_date"
        case isEstimated = "is_estimated"
        case imageURL = "image_url"
        case createdAt = "created_at"
        case storageLocation = "storage_location"
        case productType = "product_type"
    }

    static func == (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension JSONDecoder.DateDecodingStrategy {
    // Shared formatters (configured once, never mutated afterwards) to avoid
    // allocating a formatter per decoded date field. Both formatter types are
    // documented as thread-safe once configured; ISO8601DateFormatter lacks a
    // Sendable annotation in the SDK, hence nonisolated(unsafe). The two ISO
    // variants are separate instances because mutating shared formatOptions
    // concurrently would race.
    private nonisolated(unsafe) static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601InternetDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoNoTzNoFractionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let isoNoTzFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let ymdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static var inventoryDate: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = iso8601Fractional.date(from: dateString) {
                return date
            }

            if let date = iso8601InternetDateTime.date(from: dateString) {
                return date
            }

            // Handle naive timestamps without fractional seconds (e.g. "2026-09-06T10:02:00");
            // the GMT-configured formatter interprets them as UTC.
            if let date = isoNoTzNoFractionFormatter.date(from: dateString) {
                return date
            }

            // Handle ISO timestamps without timezone suffix (e.g. "2026-06-24T15:56:43.156523")
            if let date = isoNoTzFormatter.date(from: dateString) {
                return date
            }

            if let date = ymdFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date: \(dateString)"
            )
        }
    }
}
