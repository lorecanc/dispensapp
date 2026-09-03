import Foundation

struct ScanResult: Codable, Sendable {
    let barcode: String
    let name: String?
    let brand: String?
    let categories: [String]
    let imageURL: String?
    let found: Bool
    let message: String?

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, categories, found, message
        case imageURL = "image_url"
    }

    /// True quando il prodotto manca o ha dati incompleti e vale la pena arricchirlo.
    var needsEnrichment: Bool {
        guard found else { return true }
        if name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { return true }
        return imageURL == nil
    }
}
