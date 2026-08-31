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

// MARK: - Compartment helpers

enum Compartment: String, CaseIterable {
    case frigo
    case cantina
    case dispensa
    case altro

    var label: String {
        switch self {
        case .frigo: return "Frigo"
        case .cantina: return "Cantina"
        case .dispensa: return "Dispensa"
        case .altro: return "Altro"
        }
    }

    var icon: String {
        switch self {
        case .frigo: return "snowflake"
        case .cantina: return "wineglass"
        case .dispensa: return "cabinet.fill"
        case .altro: return "shippingbox"
        }
    }

    /// Normalizza stringa comparto -> Compartment noto, altro per valori non riconosciuti.
    static func normalized(_ raw: String?) -> Compartment {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return .dispensa }
        let lower = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if lower == "frigo" { return .frigo }
        if lower == "cantina" { return .cantina }
        if lower == "dispensa" { return .dispensa }
        return .altro
    }

    static var selectableCases: [Compartment] { [.frigo, .cantina, .dispensa, .altro] }

    static var addableCases: [Compartment] { [.frigo, .cantina, .dispensa, .altro] }
}
