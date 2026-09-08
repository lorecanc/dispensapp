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

    /// Canonical category key -> default storage location ("frigo"|"freezer"|"dispensa").
    static var storageDefaults: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return current.storageDefaults
    }

    /// Storage code -> display label.
    static var storageLabels: [String: String] {
        lock.lock(); defer { lock.unlock() }
        return current.storageLabels
    }

    /// Default storage location for a category; unknown keys fall back to "dispensa".
    static func storageLocation(for categoryKey: String) -> String {
        storageDefaults[categoryKey] ?? "dispensa"
    }

    /// Known storage codes, in picker display order.
    static let storageCodes = ["frigo", "freezer", "dispensa"]

    /// Storage code -> display label; unknown codes fall back to the raw code.
    static func storageLabel(for code: String) -> String {
        storageLabels[code] ?? code
    }

    /// Storage code -> SF Symbol name (icone già in uso nell'app: refrigerator.fill,
    /// snowflake, cabinet.fill). Codici sconosciuti -> nil, cioè solo testo:
    /// comportamento uniforme tra badge (InventoryRowView) e picker.
    static func storageIcon(for code: String) -> String? {
        switch code {
        case "frigo": return "refrigerator.fill"
        case "freezer": return "snowflake"
        case "dispensa": return "cabinet.fill"
        default: return nil
        }
    }

    // MARK: - Update from /api/categories

    /// Replaces the embedded snapshot with the GET /api/categories response.
    /// An empty categories list is ignored: the current snapshot is kept
    /// (a degraded server response must never wipe the registry). The same
    /// anti-wipe guard applies to the additive storage fields: missing or
    /// empty payload values keep the current maps.
    static func update(with response: CategoriesResponse) {
        guard !response.categories.isEmpty else { return }
        let payloadDefaults = Dictionary(
            response.categories.compactMap { cat in
                cat.storageLocation.map { (cat.key, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let payloadLabels = response.storageLocationLabels ?? [:]
        lock.lock(); defer { lock.unlock() }
        current = Snapshot(
            categories: response.categories.map { (key: $0.key, label: $0.label) },
            compartmentMap: response.compartmentMap,
            storageDefaults: payloadDefaults.isEmpty ? current.storageDefaults : payloadDefaults,
            storageLabels: payloadLabels.isEmpty ? current.storageLabels : payloadLabels
        )
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
        var storageDefaults: [String: String]
        var storageLabels: [String: String]
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
            ("animali", "Animali"),
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
            "animali": "Animali",
        ],
        storageDefaults: [
            // frigo
            "fresh-milk": "frigo",
            "yogurts": "frigo",
            "cheeses": "frigo",
            "cold-cuts": "frigo",
            "meat": "frigo",
            "fish": "frigo",
            "fresh-vegetables": "frigo",
            // freezer
            "frozen-foods": "freezer",
            // dispensa
            "fresh-fruits": "dispensa",
            "eggs": "dispensa",
            "uht-milk": "dispensa",
            "canned-vegetables": "dispensa",
            "canned-fish": "dispensa",
            "pasta": "dispensa",
            "rice": "dispensa",
            "legumes": "dispensa",
            "flours": "dispensa",
            "sauces-condiments": "dispensa",
            "oils-vinegars": "dispensa",
            "sweets-snacks": "dispensa",
            "bread-bakery": "dispensa",
            "beverages-water": "dispensa",
            "beverages-juices": "dispensa",
            "coffee-tea": "dispensa",
            "alcoholic-beverages": "dispensa",
            "cleaning-hygiene": "dispensa",
            "animali": "dispensa",
        ],
        storageLabels: [
            "frigo": "Frigo",
            "freezer": "Freezer",
            "dispensa": "Dispensa",
        ]
    )

    private static let lock = NSLock()
    // All access goes through `lock` (mutable global, Swift-6-safe pattern).
    nonisolated(unsafe) private static var current = embedded
}
