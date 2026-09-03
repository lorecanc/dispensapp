import XCTest
@testable import Inventario

/// Logica di arricchimento OFF: quando mostrare la CTA "Arricchisci su
/// Open Food Facts" (ScanPreviewSheet usa `result.needsEnrichment`).
final class ScanEnrichmentTests: XCTestCase {

    private func result(found: Bool, name: String? = nil, imageURL: String? = nil) -> ScanResult {
        ScanResult(
            barcode: "8076809514381",
            name: name,
            brand: "Barilla",
            categories: ["pasta"],
            imageURL: imageURL,
            found: found,
            message: nil
        )
    }

    func testNotFoundNeedsEnrichment() {
        XCTAssertTrue(result(found: false).needsEnrichment)
    }

    func testFoundWithEmptyNameNeedsEnrichment() {
        XCTAssertTrue(result(found: true, name: "", imageURL: "https://example.com/pic.jpg").needsEnrichment)
    }

    func testFoundWithBlankNameNeedsEnrichment() {
        XCTAssertTrue(result(found: true, name: "   ", imageURL: "https://example.com/pic.jpg").needsEnrichment)
    }

    func testFoundWithNameButNoImageNeedsEnrichment() {
        XCTAssertTrue(result(found: true, name: "Spaghetti", imageURL: nil).needsEnrichment)
    }

    func testFoundCompleteDoesNotNeedEnrichment() {
        XCTAssertFalse(
            result(found: true, name: "Spaghetti", imageURL: "https://example.com/pic.jpg").needsEnrichment
        )
    }
}
