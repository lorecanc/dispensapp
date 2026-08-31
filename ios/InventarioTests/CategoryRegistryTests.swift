import XCTest
@testable import Inventario

final class CategoryRegistryTests: XCTestCase {

    func testDisplayNameKnownKeys() {
        XCTAssertEqual(CategoryRegistry.displayName(for: "yogurts"), "Yogurt")
        XCTAssertEqual(CategoryRegistry.displayName(for: "fresh-milk"), "Latte fresco")
        XCTAssertEqual(CategoryRegistry.displayName(for: "pasta"), "Pasta")
        XCTAssertEqual(CategoryRegistry.displayName(for: "canned-vegetables"), "Verdure in scatola")
        XCTAssertEqual(CategoryRegistry.displayName(for: "rice"), "Riso")
        XCTAssertEqual(CategoryRegistry.displayName(for: "cheeses"), "Formaggi")
        XCTAssertEqual(CategoryRegistry.displayName(for: "eggs"), "Uova")
        XCTAssertEqual(CategoryRegistry.displayName(for: "fresh-fruits"), "Frutta fresca")
        XCTAssertEqual(CategoryRegistry.displayName(for: "fresh-vegetables"), "Verdura fresca")
        XCTAssertEqual(CategoryRegistry.displayName(for: "frozen-foods"), "Surgelati")
    }

    func testDisplayNameUnknownFallsBackToKey() {
        XCTAssertEqual(CategoryRegistry.displayName(for: "unknown"), "unknown")
        XCTAssertEqual(CategoryRegistry.displayName(for: ""), "")
        XCTAssertEqual(CategoryRegistry.displayName(for: "YOGURTS"), "YOGURTS") // case sensitive
    }

    func testValidCategoryKeysSet() {
        XCTAssertTrue(CategoryRegistry.validCategoryKeys.contains("yogurts"))
        XCTAssertTrue(CategoryRegistry.validCategoryKeys.contains("pasta"))
        XCTAssertFalse(CategoryRegistry.validCategoryKeys.contains("default"))
        XCTAssertFalse(CategoryRegistry.validCategoryKeys.contains("unknown"))
        XCTAssertEqual(CategoryRegistry.validCategoryKeys.count, 10)
    }

    func testCategoriesCountAndUniqueness() {
        XCTAssertEqual(CategoryRegistry.categories.count, 10)
        let keys = CategoryRegistry.categories.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "keys should be unique")
        let labels = CategoryRegistry.categories.map(\.label)
        XCTAssertFalse(labels.contains(""))
    }
}
