import XCTest
@testable import Inventario

final class CategoryRegistryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CategoryRegistry.resetToEmbedded()
    }

    override func tearDown() {
        CategoryRegistry.resetToEmbedded()
        super.tearDown()
    }

    // MARK: - Embedded fallback (offline)

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
        // categorie aggiuntive (backend/config.py)
        XCTAssertEqual(CategoryRegistry.displayName(for: "cold-cuts"), "Salumi e affettati")
        XCTAssertEqual(CategoryRegistry.displayName(for: "cleaning-hygiene"), "Igiene e pulizia")
        XCTAssertEqual(CategoryRegistry.displayName(for: "animali"), "Animali")
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
        XCTAssertEqual(CategoryRegistry.validCategoryKeys.count, 27)
    }

    func testCategoriesCountAndUniqueness() {
        XCTAssertEqual(CategoryRegistry.categories.count, 27)
        let keys = CategoryRegistry.categories.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "keys should be unique")
        let labels = CategoryRegistry.categories.map(\.label)
        XCTAssertFalse(labels.contains(""))
    }

    func testEmbeddedCompartmentMapFallback() {
        XCTAssertEqual(CategoryRegistry.compartmentMap["yogurts"], "Latticini e Uova")
        XCTAssertEqual(CategoryRegistry.compartmentMap["alcoholic-beverages"], "Cantina")
        XCTAssertEqual(CategoryRegistry.compartmentMap["animali"], "Animali")
        XCTAssertNil(CategoryRegistry.compartmentMap["scoops"])
    }

    // MARK: - Update from /api/categories

    private func makeResponse() -> CategoriesResponse {
        CategoriesResponse(
            categories: [
                CategoriesResponse.Category(
                    key: "vegan", label: "Vegano", shelfLifeDays: 90, compartment: "Cantina"
                ),
            ],
            defaultShelfLifeDays: 180,
            labels: ["vegan": "Vegano"],
            compartments: ["Cantina"],
            compartmentMap: ["vegan": "Cantina"]
        )
    }

    func testUpdateReplacesEmbeddedSnapshot() {
        CategoryRegistry.update(with: makeResponse())
        XCTAssertEqual(CategoryRegistry.categories.count, 1)
        XCTAssertEqual(CategoryRegistry.displayName(for: "vegan"), "Vegano")
        XCTAssertEqual(CategoryRegistry.validCategoryKeys, ["vegan"])
        XCTAssertFalse(CategoryRegistry.validCategoryKeys.contains("yogurts"))
        XCTAssertEqual(CategoryRegistry.compartmentMap["vegan"], "Cantina")
        XCTAssertNil(CategoryRegistry.compartmentMap["yogurts"])
    }

    func testResetRestoresEmbeddedSnapshot() {
        CategoryRegistry.update(with: makeResponse())
        CategoryRegistry.resetToEmbedded()
        XCTAssertEqual(CategoryRegistry.categories.count, 27)
        XCTAssertTrue(CategoryRegistry.validCategoryKeys.contains("yogurts"))
        XCTAssertEqual(CategoryRegistry.compartmentMap["yogurts"], "Latticini e Uova")
    }

    /// m4: una risposta con categories vuote non deve azzerare il registry.
    func testEmptyCategoriesUpdateKeepsCurrentSnapshot() {
        let embeddedKeys = CategoryRegistry.validCategoryKeys
        CategoryRegistry.update(with: CategoriesResponse(
            categories: [],
            defaultShelfLifeDays: nil,
            labels: nil,
            compartments: nil,
            compartmentMap: [:]
        ))
        XCTAssertEqual(CategoryRegistry.validCategoryKeys, embeddedKeys)
        XCTAssertEqual(CategoryRegistry.categories.count, 27)

        // Vale anche su snapshot non-embedded: l'update vuoto è ignorato, non distruttivo.
        CategoryRegistry.update(with: makeResponse())
        CategoryRegistry.update(with: CategoriesResponse(
            categories: [],
            defaultShelfLifeDays: nil,
            labels: nil,
            compartments: nil,
            compartmentMap: [:]
        ))
        XCTAssertEqual(CategoryRegistry.validCategoryKeys, ["vegan"])
    }

    /// m4: i campi non consumati sono opzionali, la loro assenza non invalida il decode.
    func testDecodesResponseWithoutOptionalFields() throws {
        let json = """
        {
          "categories": [{ "key": "vegan", "label": "Vegano" }],
          "compartment_map": { "vegan": "Cantina" }
        }
        """
        let response = try JSONDecoder().decode(CategoriesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.categories.count, 1)
        XCTAssertEqual(response.categories.first?.key, "vegan")
        XCTAssertEqual(response.compartmentMap, ["vegan": "Cantina"])
        XCTAssertNil(response.defaultShelfLifeDays)
        XCTAssertNil(response.labels)
        XCTAssertNil(response.compartments)
    }

    // MARK: - Storage location (default di reparto per categoria)

    private func makeStorageResponse() -> CategoriesResponse {
        CategoriesResponse(
            categories: [
                CategoriesResponse.Category(
                    key: "gelato", label: "Gelato", shelfLifeDays: 365,
                    compartment: "Surgelati", storageLocation: "freezer"
                ),
                // Entry senza storage_location: non entra nella mappa.
                CategoriesResponse.Category(
                    key: "sushi", label: "Sushi", shelfLifeDays: 1,
                    compartment: nil, storageLocation: nil
                ),
            ],
            defaultShelfLifeDays: nil,
            labels: nil,
            compartments: nil,
            compartmentMap: ["gelato": "Surgelati"],
            storageLocationLabels: ["freezer": "Congelatore"]
        )
    }

    func testStorageLocationKnownAndFallback() {
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "yogurts"), "frigo")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "frozen-foods"), "freezer")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "pasta"), "dispensa")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "animali"), "dispensa")
        // Chiavi sconosciute (o senza mappatura embedded) → dispensa.
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "scoops"), "dispensa")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: ""), "dispensa")
    }

    /// Payload con storage_location/etichette → le mappe diventano i valori del payload.
    func testUpdateWithStorageFieldsReplacesMaps() {
        CategoryRegistry.update(with: makeStorageResponse())
        XCTAssertEqual(CategoryRegistry.storageDefaults, ["gelato": "freezer"])
        XCTAssertEqual(CategoryRegistry.storageLabels, ["freezer": "Congelatore"])
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "gelato"), "freezer")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "sushi"), "dispensa")
        // Snapshot sostituito: le chiavi embedded non sono più nella mappa default.
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "yogurts"), "dispensa")
    }

    /// Guardia anti-wipe: una risposta senza i campi additivi non azzera le mappe,
    /// né quelle embedded né quelle di un update precedente.
    func testUpdateWithoutStorageFieldsKeepsCurrentMaps() {
        // Da snapshot embedded: i default sopravvivono.
        CategoryRegistry.update(with: makeResponse())
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "yogurts"), "frigo")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "frozen-foods"), "freezer")

        // Con snapshot non-embedded: vince l'ultimo payload valido, non l'embedded.
        CategoryRegistry.update(with: makeStorageResponse())
        XCTAssertEqual(CategoryRegistry.storageDefaults, ["gelato": "freezer"])
        CategoryRegistry.update(with: makeResponse())
        XCTAssertEqual(CategoryRegistry.storageDefaults, ["gelato": "freezer"])
        XCTAssertEqual(CategoryRegistry.storageLabels, ["freezer": "Congelatore"])
        // categories/compartments invece sono sostituiti normalmente.
        XCTAssertEqual(CategoryRegistry.validCategoryKeys, ["vegan"])
    }

    func testResetRestoresEmbeddedStorageMaps() {
        CategoryRegistry.update(with: makeStorageResponse())
        XCTAssertNil(CategoryRegistry.storageDefaults["yogurts"])
        CategoryRegistry.resetToEmbedded()
        XCTAssertEqual(CategoryRegistry.storageDefaults["yogurts"], "frigo")
        XCTAssertEqual(CategoryRegistry.storageLocation(for: "frozen-foods"), "freezer")
        XCTAssertEqual(CategoryRegistry.storageLabels,
                       ["frigo": "Frigo", "freezer": "Freezer", "dispensa": "Dispensa"])
    }

    /// I campi additivi decodificano da JSON e possono restare assenti.
    func testDecodesStorageLocationFields() throws {
        let json = """
        {
          "categories": [
            { "key": "gelato", "label": "Gelato", "storage_location": "freezer" },
            { "key": "sushi", "label": "Sushi" }
          ],
          "compartment_map": {},
          "storage_location_labels": { "freezer": "Congelatore" }
        }
        """
        let response = try JSONDecoder().decode(CategoriesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.categories[0].storageLocation, "freezer")
        XCTAssertNil(response.categories[1].storageLocation)
        XCTAssertEqual(response.storageLocationLabels, ["freezer": "Congelatore"])
    }

    // MARK: - ShoppingModels integrate col registry

    func testInferCompartmentFromCategoryUsesRegistryMap() {
        XCTAssertEqual(Compartment.inferCompartment(fromCategory: "yogurts"), .latticiniEUova)
        XCTAssertEqual(Compartment.inferCompartment(fromCategory: "fresh-fruits"), .ortofrutta)
        XCTAssertEqual(Compartment.inferCompartment(fromCategory: "off:fresh-milk"), .latticiniEUova) // forma prefix:key
        XCTAssertEqual(Compartment.inferCompartment(fromCategory: "unknown-key"), .dispensaSecca)
    }

    func testInferCompartmentFollowsUpdatedRegistry() {
        CategoryRegistry.update(with: makeResponse())
        XCTAssertEqual(Compartment.inferCompartment(fromCategory: "vegan"), .cantina)
        XCTAssertEqual(Compartment.inferCompartment(name: nil, category: "vegan"), .cantina)
    }

    func testKeywordFallbackRemainsLocal() {
        XCTAssertEqual(Compartment.inferCompartment(fromName: "Latte intero"), .latticiniEUova)
        XCTAssertEqual(Compartment.inferCompartment(fromName: "Detersivo piatti"), .igieneECasa)
        XCTAssertEqual(Compartment.inferCompartment(fromName: "Gizmo misterioso"), .dispensaSecca)
    }

    func testInferCompartmentCascadeNameWhenCategoryUnknown() {
        XCTAssertEqual(Compartment.inferCompartment(name: "Acqua frizzante", category: "mystery"), .bevande)
        // categoria nota vince sul nome
        XCTAssertEqual(Compartment.inferCompartment(name: "Acqua frizzante", category: "cheeses"), .salumiEFormaggi)
    }
}
