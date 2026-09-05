import Foundation

/// Registry of categories/labels/compartments on iOS.
/// Source of truth is GET /api/categories: whoever fetches it (store, T10 consumer)
/// calls `update(with:)` with the result of `APIClient.fetchCategories()`.
/// The embedded snapshot below is the offline/first-launch fallback only.
enum CategoryRegistry {

    // MARK: - Public API (call sites: pickers, chips, detail/scan views)

    static var categories: [(key: String, label: String)] {
        lock.lock(); defer { lock.unlock() }
        return current.categories
    }

    static var validCategoryKeys: Set<String> {
        Set(categories.map(\.key))
    }

    static func displayName(for key: String) -> String {
        categories.first(where: { $0.key == key })?.label ?? key
    }

    /// Canonical category key -> compartment name (backend COMPARTMENT_MAP).
    static var compartmentMap: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return current.compartmentMap
    }

    // MARK: - Update from /api/categories

    /// Replaces the embedded snapshot with the GET /api/categories response.
    /// An empty categories list is ignored: the current snapshot is kept
    /// (a degraded server response must never wipe the registry).
    static func update(with response: CategoriesResponse) {
        guard !response.categories.isEmpty else { return }
        let next = Snapshot(
            categories: response.categories.map { (key: $0.key, label: $0.label) },
            compartmentMap: response.compartmentMap
        )
        lock.lock(); defer { lock.unlock() }
        current = next
    }

    /// Restores the embedded fallback snapshot (test isolation / offline recovery).
    static func resetToEmbedded() {
        lock.lock(); defer { lock.unlock() }
        current = embedded
    }

    // MARK: - Storage

    private struct Snapshot {
        var categories: [(key: String, label: String)]
        var compartmentMap: [String: String]
    }

    /// Offline fallback: static copy of the backend registry
    /// (config.py CATEGORY_LABELS + COMPARTMENT_MAP). It can drift from the
    /// server; `update(with:)` takes precedence once /api/categories is fetched.
    private static let embedded = Snapshot(
        categories: [
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
        ],
        compartmentMap: [
            "fresh-fruits": "Ortofrutta",
            "fresh-vegetables": "Ortofrutta",
            "yogurts": "Latticini e Uova",
            "fresh-milk": "Latticini e Uova",
            "uht-milk": "Latticini e Uova",
            "eggs": "Latticini e Uova",
            "cheeses": "Salumi e Formaggi",
            "cold-cuts": "Salumi e Formaggi",
            "meat": "Carne e Pesce",
            "fish": "Carne e Pesce",
            "canned-fish": "Dispensa Secca",
            "frozen-foods": "Surgelati",
            "pasta": "Dispensa Secca",
            "rice": "Dispensa Secca",
            "legumes": "Dispensa Secca",
            "canned-vegetables": "Dispensa Secca",
            "flours": "Dispensa Secca",
            "sauces-condiments": "Dispensa Secca",
            "oils-vinegars": "Dispensa Secca",
            "sweets-snacks": "Dispensa Secca",
            "beverages-water": "Bevande",
            "beverages-juices": "Bevande",
            "coffee-tea": "Bevande",
            "alcoholic-beverages": "Cantina",
            "bread-bakery": "Forno e Panetteria",
            "cleaning-hygiene": "Igiene e Casa",
        ]
    )

    private static let lock = NSLock()
    // All access goes through `lock` (mutable global, Swift-6-safe pattern).
    nonisolated(unsafe) private static var current = embedded
}
