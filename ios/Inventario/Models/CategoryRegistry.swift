import Foundation

/// Single source of truth for product categories.
/// Keys are aligned with backend `DEFAULT_SHELF_LIFE` (e.g. `yogurts` plural).
enum CategoryRegistry {
    static let categories: [(key: String, label: String)] = [
        ("yogurts", "Yogurt"),
        ("fresh-milk", "Latte fresco"),
        ("pasta", "Pasta"),
        ("canned-vegetables", "Verdure in scatola"),
        ("rice", "Riso"),
        ("cheeses", "Formaggi"),
        ("eggs", "Uova"),
        ("fresh-fruits", "Frutta fresca"),
        ("fresh-vegetables", "Verdura fresca"),
        ("frozen-foods", "Surgelati"),
    ]

    static let validCategoryKeys: Set<String> = Set(categories.map(\.key))

    static func displayName(for key: String) -> String {
        categories.first(where: { $0.key == key })?.label ?? key
    }
}
