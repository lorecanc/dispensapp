import XCTest
@testable import Inventario

/// Logica pura di raggruppamento della sheet 2-livelli di CategoryPicker (T10/T14):
/// `groupedRows` è statica e senza stato, quindi testabile senza UI.
final class CategoryPickerTests: XCTestCase {

    private func cat(_ key: String, _ label: String) -> (key: String, label: String) {
        (key: key, label: label)
    }

    private let categories = [
        (key: "yogurts", label: "Yogurt"),
        (key: "pasta", label: "Pasta"),
        (key: "frozen-foods", label: "Surgelati"),
    ]

    private let compartmentMap = [
        "yogurts": "Latticini e Uova",
        "pasta": "Dispensa Secca",
        "frozen-foods": "Surgelati",
    ]

    func testSectionsFollowGivenOrder() {
        let grouped = CategoryPicker.groupedRows(
            categories: categories,
            compartmentMap: compartmentMap,
            order: ["Latticini e Uova", "Surgelati", "Dispensa Secca"]
        )
        XCTAssertEqual(grouped.map(\.compartment), ["Latticini e Uova", "Surgelati", "Dispensa Secca"])
    }

    /// L'ordine è quello passato, non l'ordine di input delle categorie.
    func testReversedOrderProducesReversedSections() {
        let grouped = CategoryPicker.groupedRows(
            categories: categories,
            compartmentMap: compartmentMap,
            order: ["Dispensa Secca", "Surgelati", "Latticini e Uova"]
        )
        XCTAssertEqual(grouped.map(\.compartment), ["Dispensa Secca", "Surgelati", "Latticini e Uova"])
    }

    /// Più categorie nello stesso reparto stanno nella stessa sezione,
    /// nell'ordine relativesi dell'input.
    func testCategoriesGroupedUnderTheirCompartment() {
        let grouped = CategoryPicker.groupedRows(
            categories: [cat("pasta", "Pasta"), cat("rice", "Riso"), cat("yogurts", "Yogurt")],
            compartmentMap: ["pasta": "Dispensa Secca", "rice": "Dispensa Secca", "yogurts": "Latticini e Uova"],
            order: ["Dispensa Secca", "Latticini e Uova"]
        )
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].rows.map(\.key), ["pasta", "rice"])
        XCTAssertEqual(grouped[1].rows.map(\.key), ["yogurts"])
    }

    /// Categoria senza mappa → "Altro"; reparto mappato ma fuori `order` → sezione
    /// propria in coda. Le sezioni extra sono ordinate per nome ("Altro" < "Enoteca").
    func testUnmappedAndOutOfOrderCompartmentsLandAtTheEnd() {
        let grouped = CategoryPicker.groupedRows(
            categories: [cat("pasta", "Pasta"), cat("scoops", "Coppette"), cat("spumante", "Spumante")],
            compartmentMap: ["pasta": "Dispensa Secca", "spumante": "Enoteca"],
            order: ["Dispensa Secca"]
        )
        XCTAssertEqual(grouped.map(\.compartment), ["Dispensa Secca", "Altro", "Enoteca"])
        XCTAssertEqual(grouped[1].rows.map(\.key), ["scoops"])
        XCTAssertEqual(grouped[2].rows.map(\.key), ["spumante"])
    }

    func testEmptyCategoriesYieldNoSections() {
        let grouped = CategoryPicker.groupedRows(
            categories: [],
            compartmentMap: ["yogurts": "Latticini e Uova"],
            order: ["Latticini e Uova", "Dispensa Secca"]
        )
        XCTAssertTrue(grouped.isEmpty)
    }

    /// Invariante di sicurezza: nessuna categoria sparisce mai, qualunque sia
    /// la combinazione di mappe/ordini.
    func testNoCategoryIsEverLost() {
        let input = [
            cat("pasta", "Pasta"),           // mappata, in ordine
            cat("meat", "Carne"),            // mappata, reparto fuori ordine
            cat("scoops", "Coppette"),       // senza mappa → Altro
            cat("eggs", "Uova"),             // senza mappa → Altro
            cat("sardines", "Sardine"),      // mappata, in ordine
        ]
        let grouped = CategoryPicker.groupedRows(
            categories: input,
            compartmentMap: ["pasta": "Dispensa Secca", "meat": "Carne e Pesce", "sardines": "Dispensa Secca"],
            order: ["Dispensa Secca"]
        )
        let output = grouped.flatMap(\.rows)
        XCTAssertEqual(output.count, input.count, "count in == count out")
        XCTAssertEqual(Set(output.map(\.key)), Set(input.map(\.key)))
    }
}
