import Foundation

// MARK: - Shopping Models

struct ShoppingList: Codable, Identifiable, Equatable {
    let id: Int
    let pantryId: Int
    let name: String
    let createdAt: Date
    var items: [ShoppingListItem]

    enum CodingKeys: String, CodingKey {
        case id, name, items
        case pantryId = "pantry_id"
        case createdAt = "created_at"
    }

    static func == (lhs: ShoppingList, rhs: ShoppingList) -> Bool {
        lhs.id == rhs.id
    }
}

struct ShoppingListItem: Codable, Identifiable, Equatable {
    let id: Int
    let shoppingListId: Int
    let name: String
    let quantity: Int
    var checked: Bool
    let compartment: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, checked, compartment
        case shoppingListId = "shopping_list_id"
        case createdAt = "created_at"
    }

    static func == (lhs: ShoppingListItem, rhs: ShoppingListItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct Suggestion: Codable, Identifiable, Equatable {
    let barcode: String
    let name: String
    let category: String?
    let timesScanned: Int

    var id: String { barcode.isEmpty ? "name:" + name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : barcode }

    enum CodingKeys: String, CodingKey {
        case barcode, name, category
        case timesScanned = "times_scanned"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode) ?? ""
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        timesScanned = try container.decode(Int.self, forKey: .timesScanned)
    }
}

struct PantryCheckItem: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let inPantry: Bool
    let status: String
}

struct PantryCheckResponse: Codable {
    let items: [PantryCheckItem]
}

// MARK: - Compartment (supermercato - 11 corsie)

enum Compartment: String, CaseIterable, Hashable {
    case ortofrutta = "Ortofrutta"
    case latticiniEUova = "Latticini e Uova"
    case salumiEFormaggi = "Salumi e Formaggi"
    case carneEPesce = "Carne e Pesce"
    case surgelati = "Surgelati"
    case dispensaSecca = "Dispensa Secca"
    case bevande = "Bevande"
    case cantina = "Cantina"
    case fornoEPanetteria = "Forno e Panetteria"
    case igieneECasa = "Igiene e Casa"
    case animali = "Animali"

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .ortofrutta: return "leaf.fill"
        case .latticiniEUova: return "drop.fill"
        case .salumiEFormaggi: return "fork.knife"
        case .carneEPesce: return "fish.fill"
        case .surgelati: return "snowflake"
        case .dispensaSecca: return "cabinet.fill"
        case .bevande: return "waterbottle.fill"
        case .cantina: return "wineglass.fill"
        case .fornoEPanetteria: return "flame.fill"
        case .igieneECasa: return "sparkles"
        case .animali: return "pawprint.fill"
        }
    }

    /// Ordine di percorrenza corsie supermercato (allineato a backend SUPER_MARKET_COMPARTMENTS).
    static var supermarketOrder: [Compartment] {
        [.ortofrutta, .latticiniEUova, .salumiEFormaggi, .carneEPesce, .surgelati, .dispensaSecca, .bevande, .cantina, .fornoEPanetteria, .igieneECasa, .animali]
    }

    // Compat: alias per codice esistente
    static var selectableCases: [Compartment] { supermarketOrder }
    static var addableCases: [Compartment] { supermarketOrder }

    // MARK: - Normalizzazione (legacy -> nuovi comparti)

    /// Normalizza stringa comparto -> Compartment noto. Gestisce legacy frigo/cantina/dispensa/altro + case-insensitive.
    static func normalized(_ raw: String?) -> Compartment {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return .dispensaSecca }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        // legacy mapping (backend _LEGACY_MAP, non esposta da /api/categories: resta locale)
        if lower == "frigo" { return .latticiniEUova }
        if lower == "cantina" { return .cantina }
        if lower == "dispensa" { return .dispensaSecca }
        if lower == "altro" { return .dispensaSecca }
        // match case-insensitive tra comparti noti
        for c in supermarketOrder where c.rawValue.lowercased() == lower {
            return c
        }
        // fallback: se stringa non riconosciuta, default Dispensa Secca (come backend)
        return .dispensaSecca
    }

    /// Risolve il comparto per un item: se ha compartment salvato usa quello, altrimenti inferisci da nome.
    static func resolved(for item: ShoppingListItem) -> Compartment {
        if let raw = item.compartment, !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            // se raw corrisponde a un comparto noto o legacy, usa normalized
            let knownLower = supermarketOrder.map { $0.rawValue.lowercased() }
            if knownLower.contains(lower) || ["frigo", "cantina", "dispensa", "altro"].contains(lower) {
                return normalized(raw)
            }
            // Compat con vecchi dati dove compartment conteneva la categoria:
            // se è una categoria nota nel registry, usa il suo comparto.
            if let norm = normalizeCategoryKey(raw), compartment(forCategoryKey: norm) != nil {
                return inferCompartment(fromCategory: raw)
            }
            // altrimenti inferisci dal nome
            return inferCompartment(fromName: item.name)
        }
        return inferCompartment(fromName: item.name)
    }

    // MARK: - Inferenza

    /// Categoria -> comparto: mappa del registry (`/api/categories`, fallback
    /// embedded in CategoryRegistry). Dedup del backend COMPARTMENT_MAP.
    private static func compartment(forCategoryKey key: String) -> Compartment? {
        CategoryRegistry.compartmentMap[key].flatMap(Compartment.init(rawValue:))
    }

    /// Normalizza una categoria grezza a chiave canonica (trim, lowercase,
    /// forma "prefix:key" + subset alias mirror backend config.py CATEGORY_ALIASES/
    /// OFF_TO_INTERNAL). Subset display/offline: la normalizzazione OFF completa
    /// resta del backend in persistenza.
    private static func normalizeCategoryKey(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var k = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if k.contains(":") { k = k.split(separator: ":").last.map(String.init) ?? k }
        k = k.trimmingCharacters(in: .whitespaces).lowercased()
        let aliases: [String: String] = [
            "dog-food": "animali",
            "dog-foods": "animali",
            "cat-food": "animali",
            "cat-foods": "animali",
            "pet-food": "animali",
            "pet-foods": "animali",
            "petfood": "animali",
            "yogurt": "yogurts",
            "milk": "fresh-milk",
            "tuna": "canned-fish",
            "sardines": "canned-fish",
            "water": "beverages-water",
            "juice": "beverages-juices",
            "coffee": "coffee-tea",
            "tea": "coffee-tea",
            "alcohol": "alcoholic-beverages",
            "cleaning": "cleaning-hygiene",
            "hygiene": "cleaning-hygiene",
        ]
        k = aliases[k] ?? k
        return k.isEmpty ? nil : k
    }

    // Keyword fallback (backend _KEYWORD_MAP). Resta locale: è una euristica di
    // display usata anche offline e il backend non la espone via /api/categories
    // (debito residuo documentato, dedup parziale approvato in D3).
    private static let keywordMap: [([String], Compartment)] = [
        (["mela", "pera", "banana", "frutta", "verdura", "insalata", "pomodoro", "zucchina", "carota", "patata", "cipolla", "agrumi", "kiwi", "uva"], .ortofrutta),
        (["latte", "yogurt", "uovo", "uova", "burro", "panna"], .latticiniEUova),
        (["formaggio", "parmigiano", "mozzarella", "salame", "prosciutto", "affettato", "salumi"], .salumiEFormaggi),
        (["pollo", "manzo", "maiale", "carne", "bistecca", "salsiccia", "pesce", "salmone", "tonno fresco", "merluzzo", "gamber"], .carneEPesce),
        (["surgelat", "gelato", "bastoncini", "piselli surgelati"], .surgelati),
        (["pane", "panino", "brioche", "cornetto", "focaccia", "baguette", "forno", "pasticceria"], .fornoEPanetteria),
        (["acqua", "succo", "bevanda", "bibita", "cola", "aranciata", "caffè", "caffe", "tè", "the", "tisana"], .bevande),
        (["vino", "birra", "prosecco", "champagne", "whisky", "vodka", "liquore", "alcol"], .cantina),
        (["detersivo", "sapone", "shampoo", "bagnoschiuma", "dentifricio", "candeggina", "igiene", "puliz"], .igieneECasa),
        (["crocchette", "pet-food", "dog-food", "cat-food"], .animali),
        (["pasta", "spaghetti", "riso", "farina", "olio", "passata", "pelati", "legumi", "ceci", "lenticchie", "fagioli", "biscotti", "cioccolato", "marmellata", "sale", "zucchero", "scatolame", "tonno"], .dispensaSecca),
    ]

    /// Inferisce comparto da categoria canonica via registry (ex replica backend COMPARTMENT_MAP).
    static func inferCompartment(fromCategory category: String?) -> Compartment {
        guard let cat = category, !cat.trimmingCharacters(in: .whitespaces).isEmpty else { return .dispensaSecca }
        if let norm = normalizeCategoryKey(cat), let comp = compartment(forCategoryKey: norm) {
            return comp
        }
        return .dispensaSecca
    }

    /// Replica backend: inferisce comparto da nome prodotto (keyword fallback).
    static func inferCompartment(fromName name: String?) -> Compartment {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return .dispensaSecca }
        let low = name.trimmingCharacters(in: .whitespaces).lowercased()
        for (keywords, comp) in keywordMap {
            for kw in keywords where low.contains(kw) {
                return comp
            }
        }
        return .dispensaSecca
    }

    /// Cascata completa: categoria (registry) -> nome (keyword) -> default.
    static func inferCompartment(name: String?, category: String?) -> Compartment {
        if let cat = category, let norm = normalizeCategoryKey(cat), let comp = compartment(forCategoryKey: norm) {
            return comp
        }
        if let name { return inferCompartment(fromName: name) }
        return .dispensaSecca
    }
}
