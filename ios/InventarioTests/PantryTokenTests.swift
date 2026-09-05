import XCTest
import Security
@testable import Inventario

/// Tests for `PantryToken.value` (ios/Inventario/Networking/PantryToken.swift).
///
/// T1 (TDD): the getter currently does check-then-act against the Keychain
/// (read → legacy-UserDefaults migration → generate UUID + SecItemAdd) with no
/// memoization. Consequence: two racing readers can each generate a distinct
/// token, and every read pays a blocking Keychain XPC round-trip.
/// The fix under test: memoize the value after first read.
///
/// These tests run hosted (TEST_HOST = Inventario.app), so Keychain and
/// UserDefaults here are the app's own.
final class PantryTokenTests: XCTestCase {

    /// Mirrors the private query PantryToken uses internally
    /// (service "Inventario", account "pantryToken"). Duplicated on purpose:
    /// the tests must manipulate the Keychain item OUT OF BAND, exactly like
    /// the race window would.
    private static let keychainQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Inventario",
        kSecAttrAccount as String: "pantryToken",
    ]

    private static let legacyDefaultsKey = "pantryToken"

    override func setUp() {
        super.setUp()
        PantryToken.reset()
    }

    override func tearDown() {
        PantryToken.reset()
        super.tearDown()
    }

    // MARK: - Primary red test: memoization

    /// After the first read, deleting the underlying Keychain item out of band
    /// must NOT change the value the app hands out. Pre-fix there is no memo,
    /// so the second read sees an empty Keychain, regenerates a fresh UUID,
    /// and this assertion fails.
    func testMemoSurvivesKeychainDeletion() throws {
        let first = PantryToken.value
        XCTAssertFalse(first.isEmpty, "first read must produce a token")

        // Delete the item directly, WITHOUT going through reset() — simulates
        // the check-then-act race window where another reader has not yet
        // persisted, or the item vanishes after first read.
        let status = SecItemDelete(Self.keychainQuery as CFDictionary)
        XCTAssertEqual(status, errSecSuccess,
                       "test precondition: Keychain item should exist after the first read")

        let second = PantryToken.value
        XCTAssertEqual(first, second,
                       "PantryToken.value must be memoized: once read, the same token must be returned even if the Keychain item disappears (currently a fresh UUID is regenerated on every orphaned read)")
    }

    // MARK: - Race regression (probabilistic)

    /// N concurrent first reads must collapse to a single token. Pre-fix this
    /// is a genuine race: each thread can miss the Keychain entry and
    /// generate its own UUID. May pass spuriously — it is a regression guard,
    /// not the deterministic red.
    func testConcurrentReadsReturnSingleValue() {
        let iterations = 32
        let lock = NSLock()
        var values: [String] = []

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            let token = PantryToken.value
            lock.lock()
            values.append(token)
            lock.unlock()
        }

        XCTAssertEqual(Set(values).count, 1,
                       "concurrent reads observed \(Set(values).count) distinct tokens: \(Set(values)) — check-then-act race allows two readers to generate different UUIDs")
    }

    // MARK: - Behavior preservation

    /// `set` must take effect for all subsequent reads (and post-fix, must
    /// invalidate/update the memo).
    func testSetInvalidatesMemo() {
        let generated = PantryToken.value

        PantryToken.value = "token-B"

        XCTAssertEqual(PantryToken.value, "token-B")
        XCTAssertNotEqual(PantryToken.value, generated)
    }

    /// `reset()` must clear everything (post-fix, including the memo), so the
    /// next read produces a fresh, non-empty token.
    func testResetClearsMemo() {
        let a = PantryToken.value
        XCTAssertFalse(a.isEmpty)

        PantryToken.reset()

        let b = PantryToken.value
        XCTAssertFalse(b.isEmpty, "read after reset must produce a fresh token")
        XCTAssertNotEqual(a, b, "reset must invalidate both Keychain and memo")
    }

    /// Installations created before Keychain storage kept the token in
    /// UserDefaults("pantryToken"). First read must adopt that legacy value,
    /// persist it in the Keychain, and remove the defaults key (one-time
    /// migration).
    func testLegacyMigrationPreserved() throws {
        let legacy = "legacy-token-\(UUID().uuidString)"
        UserDefaults.standard.set(legacy, forKey: Self.legacyDefaultsKey)

        let value = PantryToken.value
        XCTAssertEqual(value, legacy, "legacy UserDefaults token must be adopted")

        // Keychain now holds it.
        var query = Self.keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess, "migrated token must be persisted to the Keychain")
        let stored = (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertEqual(stored, legacy)

        // ...and the legacy key was consumed exactly once.
        XCTAssertNil(UserDefaults.standard.string(forKey: Self.legacyDefaultsKey),
                     "migration must remove the UserDefaults key")
    }
}
