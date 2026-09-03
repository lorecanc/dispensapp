import Foundation
import XCTest
@testable import Inventario

/// Test puri per la logica foto dell'arricchimento OFF.
///
/// `ScanPreviewSheet.photoFilenameAndMime` è `internal` così i test chiamano
/// la funzione reale senza UI/simulatore e verificano:
/// - (a) il contratto magic-byte -> estensione/mime reale;
/// - (b) il guard reale `APIClient.uploadPhoto` oltre i 5MB (throw 413).
final class PhotoEnrichmentTests: XCTestCase {

    // MARK: - photoFilenameAndMime

    func testJpegMagicMapsToJpg() {
        let data = Data(ScanPreviewSheet.jpegMagic + [0x00, 0x01])
        let (filename, mime) = ScanPreviewSheet.photoFilenameAndMime(data: data, code: "8076809514381", imagefield: "front_it")
        XCTAssertEqual(filename, "8076809514381_front_it.jpg")
        XCTAssertEqual(mime, "image/jpeg")
    }

    func testPngMagicMapsToPng() {
        let data = Data(ScanPreviewSheet.pngMagic + [0x00, 0x01])
        let (filename, mime) = ScanPreviewSheet.photoFilenameAndMime(data: data, code: "8076809514381", imagefield: "front_it")
        XCTAssertEqual(filename, "8076809514381_front_it.png")
        XCTAssertEqual(mime, "image/png")
    }

    func testUnknownBytesDefaultToHeic() {
        let data = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        let (filename, mime) = ScanPreviewSheet.photoFilenameAndMime(data: data, code: "8076809514381", imagefield: "front_it")
        XCTAssertEqual(filename, "8076809514381_front_it.heic")
        XCTAssertEqual(mime, "image/heic")
    }

    // MARK: - Ricalcolo filename dopo cambio imagefield

    func testFilenameFollowsChangedImagefield() {
        let data = Data(ScanPreviewSheet.jpegMagic + [0x00])
        let code = "8076809514381"
        let before = ScanPreviewSheet.photoFilenameAndMime(data: data, code: code, imagefield: "front_it").0
        // `sendPhoto` ricalcola dal contenuto con l'imagefield corrente:
        // il filename non deve restare stale sul vecchio imagefield.
        let after = ScanPreviewSheet.photoFilenameAndMime(data: data, code: code, imagefield: "ingredients_it").0
        XCTAssertNotEqual(before, after)
        XCTAssertTrue(after.contains("ingredients_it"))
        XCTAssertFalse(after.contains("front_it"))
    }

    // MARK: - Guard maxPhotoBytes (fail-fast 413)

    func testUploadPhotoOverLimitThrows413() async {
        let client = APIClient()
        let oversize = Data(repeating: 0xFF, count: 6 * 1024 * 1024)
        do {
            _ = try await client.uploadPhoto(
                code: "8076809514381",
                imageData: oversize,
                filename: "8076809514381_front_it.jpg",
                mimeType: "image/jpeg",
                imagefield: "front_it",
                consent: true
            )
            XCTFail("uploadPhoto oltre 5MB deve lanciare 413")
        } catch let error as APIError {
            // APIError.== per .http confronta solo status e ignora message.
            XCTAssertEqual(error, APIError.http(status: 413, message: nil))
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
}
