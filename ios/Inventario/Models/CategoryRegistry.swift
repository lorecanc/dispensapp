import Foundation

/// Single source of truth for product categories.
/// Keys are aligned with backend `DEFAULT_SHELF_LIFE` / `CATEGORY_LABELS` (26 keys).
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
        // 16 categorie aggiuntive allineate a backend/config.py
        ("legumes", "Legumi"),
        ("uht-milk", "Latte UHT"),
        ("cold-cuts", "Salumi e affettati"),
        ("meat", "Carne"),
        ("fish", "Pesce fresco"),
        ("canned-fish", "Pesce in scatola"),
        ("bread-bakery", "Pane e prodotti da forno"),
        ("flours", "Farine"),
        ("sauces-condiments", "Salse e condimenti"),
        ("oils-vinegars", "Oli e aceti"),
        ("sweets-snacks", "Dolci e snack"),
        ("beverages-water", "Acqua"),
        ("beverages-juices", "Succhi e bevande"),
        ("coffee-tea", "Caffè e tè"),
        ("alcoholic-beverages", "Bevande alcoliche"),
        ("cleaning-hygiene", "Igiene e pulizia"),
    ]

    static let validCategoryKeys: Set<String> = Set(categories.map(\.key))

    static func displayName(for key: String) -> String {
        categories.first(where: { $0.key == key })?.label ?? key
    }
}
