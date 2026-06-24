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

    enum CodingKeys: String, CodingKey {
        case id, barcode, name, brand, category, quantity, status
        case expirationDate = "expiration_date"
        case isEstimated = "is_estimated"
        case imageURL = "image_url"
        case createdAt = "created_at"
    }

    static func == (lhs: InventoryItem, rhs: InventoryItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var inventoryDate: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            if let date = formatter.date(from: dateString) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Handle ISO timestamps without timezone suffix (e.g. "2026-06-24T15:56:43.156523")
            let isoNoTzFormatter = DateFormatter()
            isoNoTzFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
            isoNoTzFormatter.locale = Locale(identifier: "en_US_POSIX")
            isoNoTzFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = isoNoTzFormatter.date(from: dateString) {
                return date
            }

            let ymdFormatter = DateFormatter()
            ymdFormatter.dateFormat = "yyyy-MM-dd"
            ymdFormatter.locale = Locale(identifier: "en_US_POSIX")
            ymdFormatter.timeZone = TimeZone(secondsFromGMT: 0)

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
