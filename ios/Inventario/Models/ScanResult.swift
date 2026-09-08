import Foundation

enum ProductSource: String, Codable, Sendable, Hashable, CaseIterable {
    case food
    case beauty
    case petfood
    case product

    var displayName: String {
        switch self {
        case .food: return "Alimentare"
        case .beauty: return "Cosmetici"
        case .petfood: return "Pet food"
        case .product: return "Non alimentare"
        }
    }
}

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
    /// Campi additivi (gemelli OFF): sorgente/tipo prodotto dal backend v3.
    /// Nil con backend non aggiornati. `var` + default: memberwise init
    /// invariato per i call site esistenti.
    var source: String? = nil
    var productType: String? = nil
    /// Campo additivo: gruppo PNNS OFF (pnns_groups_1 slugificato) dal backend v3.
    /// Nil con backend non aggiornati. `var` + default: memberwise init
    /// invariato per i call site esistenti.
    var pnnsGroup: String? = nil

    /// Vista tipizzata e tollerante di `source`: valori sconosciuti -> nil,
    /// mai fatalError/force-unwrap, mai fallimento di Decodable.
    var sourceEnum: ProductSource? { source.flatMap(ProductSource.init) }

    enum CodingKeys: String, CodingKey {
        case barcode, name, brand, categories, found, message, source
        case imageURL = "image_url"
        case suggestedCategory = "suggested_category"
        case productType = "product_type"
        case pnnsGroup = "pnns_group"
    }

    /// True quando il prodotto manca o ha dati incompleti e vale la pena arricchirlo.
    var needsEnrichment: Bool {
        guard found else { return true }
        if name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { return true }
        return imageURL == nil
    }
}
