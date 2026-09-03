import Foundation
import XCTest
@testable import Inventario

/// Test puri per la logica foto dell'arricchimento OFF.
///
/// `ScanPreviewSheet.photoFilenameAndMime` e il ricalcolo filename in
/// `sendPhoto` sono `private` nella View: per non toccare la UI e non
/// richiedere il simulatore, i test qui sotto verificano:
/// - (a) il contratto magic-byte -> estensione/mime tramite un helper locale
///   che rispecchia `ScanPreviewSheet.photoFilenameAndMime`;
/// - (b) il guard reale `APIClient.uploadPhoto` oltre i 5MB (throw 413).
final class PhotoEnrichmentTests: XCTestCase {

    // MARK: - Helper locale (mirror di ScanPreviewSheet.photoFilenameAndMime)

    private static let jpegMagic: [UInt8] = [0xFF, 0xD8, 0xFF]
    private static let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Replica pura del contratto produttivo: JPEG -> jpg, PNG -> png,
    /// tutto il resto (incluso HEIC) -> heic.
    private static func filenameAndMime(data: Data, code: String, imagefield: String) -> (String, String) {
        if data.starts(with: jpegMagic) {
            return ("\(code)_\(imagefield).jpg", "image/jpeg")
        }
        if data.starts(with: pngMagic) {
            return ("\(code)_\(imagefield).png", "image/png")
        }
        return ("\(code)_\(imagefield).heic", "image/heic")
    }

    // MARK: - photoFilenameAndMime

    func testJpegMagicMapsToJpg() {
        let data = Data(Self.jpegMagic + [0x00, 0x01])
        let (filename, mime) = Self.filenameAndMime(data: data, code: "8076809514381", imagefield: "front_it")
        XCTAssertEqual(filename, "8076809514381_front_it.jpg")
        XCTAssertEqual(mime, "image/jpeg")
    }

    func testPngMagicMapsToPng() {
        let data = Data(Self.pngMagic + [0x00, 0x01])
        let (filename, mime) = Self.filenameAndMime(data: data, code: "8076809514381", imagefield: "front_it")
        XCTAssertEqual(filename, "8076809514381_front_it.png")
        XCTAssertEqual(mime, "image/png")
    }

    func testUnknownBytesDefaultToHeic() {
        let data = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])
        let (filename, mime) = Self.filenameAndMime(data: data, code: "8076809514381", imagefield: "front_it")
        XCTAssertEqual(filename, "8076809514381_front_it.heic")
        XCTAssertEqual(mime, "image/heic")
    }

    // MARK: - Ricalcolo filename dopo cambio imagefield

    func testFilenameFollowsChangedImagefield() {
        let data = Data(Self.jpegMagic + [0x00])
        let code = "8076809514381"
        let before = Self.filenameAndMime(data: data, code: code, imagefield: "front_it").0
        // `sendPhoto` ricalcola dal contenuto con l'imagefield corrente:
        // il filename non deve restare stale sul vecchio imagefield.
        let after = Self.filenameAndMime(data: data, code: code, imagefield: "ingredients_it").0
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
            XCTAssertEqual(error, APIError.http(status: 413, message: nil))
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }
}
