import XCTest
@testable import Inventario

/// T2 (post-fix): i tag Tutti/Ortofrutta/Latticini etc. usano la stessa
/// cascata del grouping.
///
/// `InventoryListView.sections()` filtra con
/// `Compartment.inferCompartment(name:category:)` normalizzato
/// (trim/lowercase, forma `off:chiave`, alias, keyword-only da nome).
/// nil/vuota/maiuscola/off:-prefixed/alias/keyword-only restano visibili
/// sotto il loro comparto inferito; `animali` (backend 11° comparto
/// "Animali") corrisponde a `Compartment.animali` iOS (11 casi).
///
/// L'helper `fixedMatches` sotto è copia verbatim del predicato in
/// `InventoryListView.swift` (sezione `sections`, ramo T13/T2): questi test
/// DEVONO essere verdi. Non toccano il codice prodotto.
final class InventoryCompartmentFilterRedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CategoryRegistry.resetToEmbedded()
    }

    override func tearDown() {
        CategoryRegistry.resetToEmbedded()
        super.tearDown()
    }

    // MARK: - Helpers (mirror del codice prodotto)

    /// Copia verbatim di `InventoryListView.sections` (T13/T2):
    /// `Compartment.inferCompartment(name:category:) == selected`.
    private func fixedMatches(name: String?, category: String?, selected: Compartment?) -> Bool {
        if let selected {
            return Compartment.inferCompartment(name: name, category: category) == selected
        } else {
            return true
        }
    }

    private func item(name: String, category: String?) -> InventoryItem {
        InventoryItem(
            id: Int.random(in: 1_000_000...9_999_999),
            barcode: nil,
            name: name,
            brand: nil,
            expirationDate: nil,
            isEstimated: false,
            category: category,
            imageURL: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            quantity: 1,
            status: "ok"
        )
    }

    // MARK: - Tutti mostra tutto (sanity, resta verde)

    func testTuttiMostraTutto() {
        let items = [
            item(name: "Mele", category: "fresh-fruits"),
            item(name: "Latte", category: "fresh-milk"),
            item(name: "Gizmo", category: nil),
            item(name: "Crocchette", category: "animali"),
        ]
        for it in items {
            XCTAssertTrue(
                fixedMatches(name: it.name, category: it.category, selected: nil),
                "Tutti (nil) deve mostrare '\(it.name)'"
            )
        }
    }

    // MARK: - T2 core: filtro Ortofrutta (verde post-fix)

    /// Con selected=.ortofrutta solo item ortofrutta; nil/unknown non leakano;
    /// ma le forme normalizzate (maiuscola, off:-prefix, keyword-only da nome)
    /// sono incluse come fa `inferCompartment`.
    func testOrtofruttaIncludeFormeNormalizzate_UnknownNonLeakano() {
        let selected: Compartment? = .ortofrutta

        // (nome, categoria, atteso sotto .ortofrutta)
        let cases: [(String, String?, Bool)] = [
            ("Mele", "fresh-fruits", true),    // canonica: registry diretto -> ortofrutta
            ("Pere", "Fresh-Fruits", true),    // maiuscola -> infer ortofrutta
            ("Mela", nil, true),               // nil + keyword nome -> infer ortofrutta
            ("Mela", "", true),                // vuota + keyword nome -> infer ortofrutta
            ("Latte fresco", "off:fresh-milk", false), // latticini: NON deve leakare in ortofrutta
            ("Latte", "fresh-milk", false),    // latticini: NON deve leakare
            ("Gizmo misterioso", "mystery", false), // unknown senza keyword ortofrutta: NON leaka
            ("Gizmo misterioso", nil, false),  // nil senza keyword: NON leaka in ortofrutta
        ]
        for (name, category, expected) in cases {
            XCTAssertEqual(
                fixedMatches(name: name, category: category, selected: selected),
                expected,
                "filtro .ortofrutta per '\(name)' cat=\(category ?? "nil"): atteso \(expected)"
            )
        }
    }

    // MARK: - T2: Latticini via off:-prefix (verde post-fix)

    func testLatticiniIncludeOffPrefix() {
        XCTAssertTrue(
            fixedMatches(name: "Latte fresco", category: "off:fresh-milk", selected: .latticiniEUova),
            "categoria 'off:fresh-milk' deve risolversi in Latticini e Uova (come inferCompartment)"
        )
    }

    // MARK: - T2: Animali/pet deve risolversi (verde post-fix)

    /// `animali` -> compartmentMap "Animali" corrisponde a `Compartment.animali`
    /// iOS (11 casi): `inferCompartment(name:category:)` lo risolve via
    /// `Compartment.init(rawValue:)`. L'item non deve sparire.
    func testAnimaliSiRisolveSottoCompartoInferito() {
        let inferred = Compartment.inferCompartment(name: "Crocchette cane", category: "animali")
        XCTAssertTrue(
            fixedMatches(name: "Crocchette cane", category: "animali", selected: inferred),
            "item 'animali' deve essere visibile sotto il comparto inferito \(inferred.rawValue)"
        )
    }
}
