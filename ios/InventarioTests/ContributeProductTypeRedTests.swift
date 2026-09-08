import Foundation
import XCTest
@testable import Inventario

/// TDD Red phase: `APIClient.contribute` / `uploadPhoto` devono inoltrare il
/// tipo prodotto (`ScanResult.source` / `productType`, cfr. `ScanPreviewSheet.saveItem`
/// che già li inoltra per la create inventario) come `product_type`, altrimenti
/// il backend scrive i contributi beauty/pet nel database food.
///
/// Firma attesa (post-fix, default nil = backward compat):
/// - `contribute(..., consent: Bool, productType: String? = nil)`
/// - `uploadPhoto(..., consent: Bool, productType: String? = nil)`
///
/// Pre-fix questi test NON compilano (`extra argument 'productType' in call`)
/// → Red = errore di compilazione, che è un Red accettabile.
final class ContributeProductTypeRedTests: XCTestCase {

    /// Stub URLProtocol che cattura l'ultima request e risponde ContributeResult ok.
    private final class CaptureStub: URLProtocol {
        static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lastRequest = request
            let url = request.url!
            let payload = #"{"ok":true,"code":"8001234567890","message":null}"#.data(using: .utf8)!
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var originalBaseURL: String?

    override func setUp() {
        super.setUp()
        CaptureStub.lastRequest = nil
        originalBaseURL = UserDefaults.standard.string(forKey: "apiBaseURL")
        APIConfig.baseURLString = "http://127.0.0.1:8000"
    }

    override func tearDown() {
        if let originalBaseURL {
            UserDefaults.standard.set(originalBaseURL, forKey: "apiBaseURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "apiBaseURL")
        }
        super.tearDown()
    }

    private func stubbedClient() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CaptureStub.self]
        return APIClient(session: URLSession(configuration: config))
    }

    // MARK: - 1. contribute inoltra product_type

    func testContributeForwardsProductTypeBeauty() async throws {
        _ = try await stubbedClient().contribute(
            code: "8001234567890",
            productName: "Crema viso",
            brands: "Acme",
            quantity: "50ml",
            categories: "creme",
            consent: true,
            productType: "beauty"
        )
        let request = try XCTUnwrap(CaptureStub.lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(
            json["product_type"] as? String, "beauty",
            "contribute(productType: \"beauty\") deve inviare \"product_type\": \"beauty\" nel JSON"
        )
    }

    // MARK: - 2. uploadPhoto inoltra product_type nel multipart

    func testUploadPhotoForwardsProductTypeBeauty() async throws {
        _ = try await stubbedClient().uploadPhoto(
            code: "8001234567890",
            imageData: Data([0x01, 0x02, 0x03]),
            filename: "8001234567890_front_it.jpg",
            mimeType: "image/jpeg",
            imagefield: "front_it",
            consent: true,
            productType: "beauty"
        )
        let request = try XCTUnwrap(CaptureStub.lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let raw = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(
            raw.contains(#"name="product_type""#),
            "uploadPhoto(productType:) deve includere il campo multipart product_type"
        )
        XCTAssertTrue(
            raw.contains("beauty"),
            "il campo multipart product_type deve valere \"beauty\""
        )
    }

    // MARK: - 3. nil productType omette la chiave (backward compat)

    func testContributeOmitsProductTypeWhenNil() async throws {
        _ = try await stubbedClient().contribute(
            code: "8001234567890",
            productName: "Pasta",
            brands: nil,
            quantity: nil,
            categories: nil,
            consent: true,
            productType: nil
        )
        let request = try XCTUnwrap(CaptureStub.lastRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(
            json["product_type"],
            "contribute(productType: nil) deve omettere la chiave product_type (comportamento attuale)"
        )
    }
}
