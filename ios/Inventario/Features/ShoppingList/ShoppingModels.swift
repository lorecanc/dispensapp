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

    var id: String { barcode }

    enum CodingKeys: String, CodingKey {
        case barcode, name, category
        case timesScanned = "times_scanned"
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

// MARK: - Compartment (supermercato - 10 corsie)

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
        }
    }

    /// Ordine di percorrenza corsie supermercato (allineato a backend SUPER_MARKET_COMPARTMENTS).
    static var supermarketOrder: [Compartment] {
        [.ortofrutta, .latticiniEUova, .salumiEFormaggi, .carneEPesce, .surgelati, .dispensaSecca, .bevande, .cantina, .fornoEPanetteria, .igieneECasa]
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
        // legacy mapping (backend _LEGACY_MAP)
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
            // stored value potrebbe già essere un comparto canonico con casing diverso: gestito sopra.
            // se è un valore libero ma non vuoto, trattalo comunque come compartment esplicito se match case-insensitive, altrimenti fallback a inferenza nome
            // per compatibilità, se normalized non è default o raw conteneva già un comparto, usa normalized
            // altrimenti inferisci da nome (es. vecchi dati con compartment = categoria)
            // Se raw non è un comparto noto, prova prima a vedere se è una categoria -> infer da categoria
            let fromCat = inferCompartment(fromCategory: raw)
            // se raw era una categoria nota che mappa a un comparto diverso da default, usa quello
            // Altrimenti fallback a nome. Questo copre compatibilità con vecchi compartment = "dispensa" etc.
            // Check se raw normalizzato come categoria ha mapping: se infer da categoria != dispensaSecca o raw lower è una categoria conosciuta, usa quello.
            if categoryToCompartment[normalizeCategoryKey(raw) ?? ""] != nil {
                return fromCat
            }
            // altrimenti inferisci dal nome
            return inferCompartment(fromName: item.name)
        }
        return inferCompartment(fromName: item.name)
    }

    // MARK: - Inferenza (replica backend services/compartment.py)

    // Categoria interna -> comparto (backend COMPARTMENT_MAP)
    private static let categoryToCompartment: [String: Compartment] = [
        "fresh-fruits": .ortofrutta,
        "fresh-vegetables": .ortofrutta,
        "yogurts": .latticiniEUova,
        "fresh-milk": .latticiniEUova,
        "uht-milk": .latticiniEUova,
        "eggs": .latticiniEUova,
        "cheeses": .salumiEFormaggi,
        "cold-cuts": .salumiEFormaggi,
        "meat": .carneEPesce,
        "fish": .carneEPesce,
        "canned-fish": .dispensaSecca,
        "frozen-foods": .surgelati,
        "pasta": .dispensaSecca,
        "rice": .dispensaSecca,
        "legumes": .dispensaSecca,
        "canned-vegetables": .dispensaSecca,
        "flours": .dispensaSecca,
        "sauces-condiments": .dispensaSecca,
        "oils-vinegars": .dispensaSecca,
        "sweets-snacks": .dispensaSecca,
        "beverages-water": .bevande,
        "beverages-juices": .bevande,
        "coffee-tea": .bevande,
        "alcoholic-beverages": .cantina,
        "bread-bakery": .fornoEPanetteria,
        "cleaning-hygiene": .igieneECasa,
    ]

    // Alias + OFF mapping -> canonico (backend CATEGORY_ALIASES + OFF_TO_INTERNAL)
    private static let aliasMap: [String: String] = [
        // identità canoniche
        "yogurts": "yogurts",
        "fresh-milk": "fresh-milk",
        "pasta": "pasta",
        "canned-vegetables": "canned-vegetables",
        "rice": "rice",
        "cheeses": "cheeses",
        "eggs": "eggs",
        "fresh-fruits": "fresh-fruits",
        "fresh-vegetables": "fresh-vegetables",
        "frozen-foods": "frozen-foods",
        "legumes": "legumes",
        "uht-milk": "uht-milk",
        "cold-cuts": "cold-cuts",
        "meat": "meat",
        "fish": "fish",
        "canned-fish": "canned-fish",
        "bread-bakery": "bread-bakery",
        "flours": "flours",
        "sauces-condiments": "sauces-condiments",
        "oils-vinegars": "oils-vinegars",
        "sweets-snacks": "sweets-snacks",
        "beverages-water": "beverages-water",
        "beverages-juices": "beverages-juices",
        "coffee-tea": "coffee-tea",
        "alcoholic-beverages": "alcoholic-beverages",
        "cleaning-hygiene": "cleaning-hygiene",
        // alias legacy
        "yogurt": "yogurts",
        "cheese": "cheeses",
        "milk": "fresh-milk",
        "uht-milks": "uht-milk",
        "legume": "legumes",
        "cold-cut": "cold-cuts",
        "canned-fishs": "canned-fish",
        "bread": "bread-bakery",
        "flour": "flours",
        "sauce": "sauces-condiments",
        "oil": "oils-vinegars",
        "sweet": "sweets-snacks",
        "snack": "sweets-snacks",
        "water": "beverages-water",
        "juice": "beverages-juices",
        "coffee": "coffee-tea",
        "tea": "coffee-tea",
        "alcohol": "alcoholic-beverages",
        "cleaning": "cleaning-hygiene",
        "hygiene": "cleaning-hygiene",
        // OFF variants
        "milks": "fresh-milk",
        "pasteurized-milk": "fresh-milk",
        "fruits": "fresh-fruits",
        "vegetables": "fresh-vegetables",
        "pulses": "legumes",
        "lentils": "legumes",
        "pastas": "pasta",
        "flour": "flours",
        "sauces": "sauces-condiments",
        "condiments": "sauces-condiments",
        "oils": "oils-vinegars",
        "vinegars": "oils-vinegars",
        "sweets": "sweets-snacks",
        "snacks": "sweets-snacks",
        "biscuits": "sweets-snacks",
        "chocolate": "sweets-snacks",
        "charcuterie": "cold-cuts",
        "hams": "cold-cuts",
        "salamis": "cold-cuts",
        "meats": "meat",
        "fishes": "fish",
        "tuna": "canned-fish",
        "sardines": "canned-fish",
        "breads": "bread-bakery",
        "bakery": "bread-bakery",
        "pastries": "bread-bakery",
        "frozen-food": "frozen-foods",
        "waters": "beverages-water",
        "juices": "beverages-juices",
        "coffees": "coffee-tea",
        "teas": "coffee-tea",
        "wines": "alcoholic-beverages",
        "beers": "alcoholic-beverages",
        "spirits": "alcoholic-beverages",
        "detergents": "cleaning-hygiene",
    ]

    private static func normalizeCategoryKey(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var k = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if k.contains(":") { k = k.split(separator: ":").last.map(String.init) ?? k }
        k = k.trimmingCharacters(in: .whitespaces).lowercased()
        if let mapped = aliasMap[k] { return mapped }
        return k.isEmpty ? nil : k
    }

    // Keyword fallback (backend _KEYWORD_MAP)
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
    ]

    /// Replica backend: inferisce comparto da categoria canonica.
    static func inferCompartment(fromCategory category: String?) -> Compartment {
        guard let cat = category, !cat.trimmingCharacters(in: .whitespaces).isEmpty else { return .dispensaSecca }
        if let norm = normalizeCategoryKey(cat), let comp = categoryToCompartment[norm] {
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

    /// Cascata completa: categoria -> nome -> default (come backend infer_compartment senza OFF tags).
    static func inferCompartment(name: String?, category: String?) -> Compartment {
        if let cat = category, let norm = normalizeCategoryKey(cat), let comp = categoryToCompartment[norm] {
            return comp
        }
        if let name { return inferCompartment(fromName: name) }
        return .dispensaSecca
    }
}
