import XCTest
@testable import Inventario

final class APIConfigTests: XCTestCase {
    private var originalURL: String?

    override func setUp() {
        super.setUp()
        originalURL = UserDefaults.standard.string(forKey: "apiBaseURL")
    }

    override func tearDown() {
        if let originalURL {
            UserDefaults.standard.set(originalURL, forKey: "apiBaseURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "apiBaseURL")
        }
        super.tearDown()
    }

    func testValidURLs() {
        let valid = [
            "http://127.0.0.1:8000",
            "http://localhost:8000",
            "https://example.com",
            "https://app.example.com/api",
            "http://192.168.1.10:3000"
        ]
        for url in valid {
            APIConfig.baseURLString = url
            XCTAssertTrue(APIConfig.isValidURL, "should be valid: \(url)")
            XCTAssertNotNil(APIConfig.baseURL, "baseURL should not be nil for valid: \(url)")
        }
    }

    func testInvalidURLsDoNotCrashAndReturnNil() {
        let invalid = [
            "",
            "   ",
            "not a url",
            "ftp://example.com",
            "http://",
            "https://",
            "://missing-scheme.com",
            "http:/one-slash.com",
            "http:// ",
            "ht!tp://invalid",
        ]
        for url in invalid {
            APIConfig.baseURLString = url
            // must not crash
            let isValid = APIConfig.isValidURL
            let base = APIConfig.baseURL
            XCTAssertFalse(isValid, "should be invalid: \(url)")
            XCTAssertNil(base, "baseURL should be nil for invalid: \(url)")
        }
    }

    func testEmptyStringIsInvalidAndFallbackWorks() {
        APIConfig.baseURLString = ""
        XCTAssertFalse(APIConfig.isValidURL)
        XCTAssertNil(APIConfig.baseURL)
        // fallback must always be valid and non-crashing
        let fallback = APIConfig.fallbackURL
        XCTAssertNotNil(fallback)
        XCTAssertEqual(fallback.host, "127.0.0.1")
    }

    func testFallbackIsAlwaysValid() {
        // anche con URL invalido, fallbackURL non deve crashare
        APIConfig.baseURLString = "invalid:://"
        let fallback = APIConfig.fallbackURL
        XCTAssertEqual(fallback.absoluteString, "http://127.0.0.1:8000")
    }

    func testSchemeMustBeHttpOrHttps() {
        APIConfig.baseURLString = "ftp://example.com"
        XCTAssertFalse(APIConfig.isValidURL)
        APIConfig.baseURLString = "ws://example.com"
        XCTAssertFalse(APIConfig.isValidURL)
        APIConfig.baseURLString = "http://example.com"
        XCTAssertTrue(APIConfig.isValidURL)
        APIConfig.baseURLString = "https://example.com"
        XCTAssertTrue(APIConfig.isValidURL)
        APIConfig.baseURLString = "HTTP://example.com"
        XCTAssertTrue(APIConfig.isValidURL)
        APIConfig.baseURLString = "HTTPS://example.com"
        XCTAssertTrue(APIConfig.isValidURL)
    }

    func testHostRequired() {
        APIConfig.baseURLString = "http://"
        XCTAssertFalse(APIConfig.isValidURL)
        XCTAssertNil(APIConfig.baseURL)
        APIConfig.baseURLString = "http:///path"
        XCTAssertFalse(APIConfig.isValidURL)
    }
}
