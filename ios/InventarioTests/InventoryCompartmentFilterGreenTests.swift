import XCTest
@testable import Inventario

/// T2 Green gate: verifica il predicato REALE di produzione per proxy.
///
/// `InventoryListView.sections()` è private, quindi questi test chiamano
/// direttamente `Compartment.inferCompartment(name:category:)` — la stessa
/// funzione usata sia dal filtro (riga T13/T2) che dal grouping
/// (`compartment(for:)`). Il predicato `matches` sotto replica verbatim la
/// riga di produzione:
///   `Compartment.inferCompartment(name:category:) == selected`
/// (nil = Tutti mostra tutto).
/// La verifica statica del sorgente (grep: contiene `inferCompartment` +
/// `== selectedCompartment`, non contiene più `compartmentMap[category]`)
/// è documentata nel report Green, non in XCTest.
///
/// A differenza di `InventoryCompartmentFilterRedTests` (copia locale con
/// nome `fixedMatches`), qui l'asserzione è contro il simbolo prodotto reale:
/// se il fix regredisce a `compartmentMap[category]`, questi test restano
/// verdi sul proxy ma la verifica grep fallisce — i due controlli sono
/// complementari per disegno.
final class InventoryCompartmentFilterGreenTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CategoryRegistry.resetToEmbedded()
    }

    override func tearDown() {
        CategoryRegistry.resetToEmbedded()
        super.tearDown()
    }

    // MARK: - Proxy del predicato reale (verbatim produzione)

    /// Replica verbatim `InventoryListView.sections` ramo T13/T2.
    private func matches(name: String?, category: String?, selected: Compartment?) -> Bool {
        if let selected {
            return Compartment.inferCompartment(name: name, category: category) == selected
        } else {
            return true
        }
    }

    // MARK: - Tutti mostra tutto

    func testTuttiMostraTutto() {
        let cases: [(String, String?)] = [
            ("Mele", "fresh-fruits"),
            ("Latte", "fresh-milk"),
            ("Gizmo misterioso", nil),
            ("Crocchette cane", "animali"),
        ]
        for (name, category) in cases {
            XCTAssertTrue(
                matches(name: name, category: category, selected: nil),
                "Tutti (nil) deve mostrare '\(name)' cat=\(category ?? "nil")"
            )
        }
    }

    // MARK: - Ortofrutta: forme normalizzate incluse, unknown non leaka

    func testOrtofruttaFormeNormalizzate() {
        // Dirette su inferCompartment (proxy del filtro reale).
        XCTAssertEqual(Compartment.inferCompartment(name: "Mele", category: "fresh-fruits"), .ortofrutta)
        XCTAssertEqual(Compartment.inferCompartment(name: "Pere", category: "Fresh-Fruits"), .ortofrutta, "maiuscola -> trim/lowercase")
        XCTAssertEqual(Compartment.inferCompartment(name: "Mele", category: "off:fresh-fruits"), .ortofrutta, "off:-prefix -> chiave canonica")
        XCTAssertEqual(Compartment.inferCompartment(name: "Mela", category: nil), .ortofrutta, "nil + keyword nome")
        XCTAssertEqual(Compartment.inferCompartment(name: "Mela", category: ""), .ortofrutta, "vuota + keyword nome")

        // Via predicato (stessa riga di produzione).
        XCTAssertTrue(matches(name: "Mele", category: "fresh-fruits", selected: .ortofrutta))
        XCTAssertTrue(matches(name: "Pere", category: "Fresh-Fruits", selected: .ortofrutta))
        XCTAssertTrue(matches(name: "Mele", category: "off:fresh-fruits", selected: .ortofrutta))
        XCTAssertTrue(matches(name: "Mela", category: nil, selected: .ortofrutta))
        XCTAssertTrue(matches(name: "Mela", category: "", selected: .ortofrutta))

        // Non-leak: latticini e unknown non appaiono sotto Ortofrutta.
        XCTAssertFalse(matches(name: "Latte fresco", category: "off:fresh-milk", selected: .ortofrutta))
        XCTAssertFalse(matches(name: "Latte", category: "fresh-milk", selected: .ortofrutta))
        XCTAssertFalse(matches(name: "Gizmo misterioso", category: "mystery", selected: .ortofrutta))
        XCTAssertFalse(matches(name: "Gizmo misterioso", category: nil, selected: .ortofrutta))
    }

    // MARK: - Latticini via off:-prefix

    func testLatticiniIncludeOffPrefix() {
        XCTAssertEqual(
            Compartment.inferCompartment(name: "Latte fresco", category: "off:fresh-milk"),
            .latticiniEUova
        )
        XCTAssertTrue(matches(name: "Latte fresco", category: "off:fresh-milk", selected: .latticiniEUova))
    }

    // MARK: - nil/unknown -> dispensaSecca

    func testNilUnknownFallbackDispensaSecca() {
        XCTAssertEqual(Compartment.inferCompartment(name: nil, category: nil), .dispensaSecca)
        XCTAssertEqual(Compartment.inferCompartment(name: "Gizmo misterioso", category: nil), .dispensaSecca)
        XCTAssertEqual(Compartment.inferCompartment(name: "Gizmo misterioso", category: "mystery"), .dispensaSecca)
        // Il fallback è visibile sotto Dispensa Secca, non sotto Ortofrutta.
        XCTAssertTrue(matches(name: "Gizmo misterioso", category: nil, selected: .dispensaSecca))
        XCTAssertTrue(matches(name: "Gizmo misterioso", category: "mystery", selected: .dispensaSecca))
    }

    // MARK: - Animali: ultimo in supermarketOrder, risolve pet/animali

    func testAnimaliUltimoInSupermarketOrder() {
        XCTAssertEqual(Compartment.supermarketOrder.last, .animali)
        XCTAssertTrue(Compartment.supermarketOrder.contains(.animali))
        XCTAssertEqual(Compartment.supermarketOrder.count, 11)
    }

    func testAnimaliRisolvePetEAnimali() {
        // Chiave canonica backend.
        XCTAssertEqual(Compartment.inferCompartment(name: "Crocchette cane", category: "animali"), .animali)
        // Alias categoria (mirror backend CATEGORY_ALIASES/OFF_TO_INTERNAL).
        XCTAssertEqual(Compartment.inferCompartment(name: "x", category: "pet-food"), .animali)
        XCTAssertEqual(Compartment.inferCompartment(name: "x", category: "dog-food"), .animali)
        XCTAssertEqual(Compartment.inferCompartment(name: "x", category: "cat-food"), .animali)
        XCTAssertEqual(Compartment.inferCompartment(name: "x", category: "off:pet-food"), .animali, "off:-prefix + alias")
        // Keyword da nome (fallback quando la categoria è nil).
        XCTAssertEqual(Compartment.inferCompartment(name: "Crocchette cane", category: nil), .animali)
        // Visibilità sotto il comparto inferito (non sparisce).
        let inferred = Compartment.inferCompartment(name: "Crocchette cane", category: "animali")
        XCTAssertEqual(inferred, .animali)
        XCTAssertTrue(matches(name: "Crocchette cane", category: "animali", selected: inferred))
        XCTAssertTrue(matches(name: "Crocchette cane", category: "pet-food", selected: .animali))
    }
}
