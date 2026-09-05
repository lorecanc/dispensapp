import Foundation

struct ScanResult: Codable, Sendable {
    let barcode: String
    let name: String?
    let brand: String?
    let categories: [String]
    let imageURL: String?
    let found: Bool
    let message: String?
    /// Campo additivo (T11): categoria suggerita dal backend dagli tag OFF.
    /// Nil con backend non aggiornati. `var` + default: memberwise init
    /// invariato per i call site esistenti (mock di test inclusi).
    var suggestedCategory: String? = nil

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, categories, found, message
        case imageURL = "image_url"
        case suggestedCategory = "suggested_category"
    }

    /// True quando il prodotto manca o ha dati incompleti e vale la pena arricchirlo.
    var needsEnrichment: Bool {
        guard found else { return true }
        if name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { return true }
        return imageURL == nil
    }
}
