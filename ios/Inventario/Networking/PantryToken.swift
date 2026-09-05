import Foundation
import Security

/// Persiste `X-Pantry-Token` in Keychain (`kSecClassGenericPassword`,
/// `accessibleAfterFirstUnlockThisDeviceOnly`). Mai in UserDefaults, mai nei log.
/// - Prima lettura: se Keychain vuoto, migra una tantum il valore legacy da
///   UserDefaults `pantryToken` (conserva installazioni esistenti), altrimenti
///   genera `UUID().uuidString` e salva.
/// - Nessun fallback hardcoded a zero-UUID: ogni installazione ha il suo token.
///   Nota backend: senza `POST /api/pantries` disponibile, la creazione pantry
///   per-token al primo 401/403 non è implementata lato client; il backend deve
///   provisionare la pantry per il token ricevuto, altrimenti la UI mostra 401/403.
/// Sendable perché espone solo accesso statico thread-safe via Keychain.
enum PantryToken: Sendable {
    static let headerName = "X-Pantry-Token"
    private static let service = "Inventario"
    private static let account = "pantryToken"
    private static let defaultsKey = "pantryToken"

    private static let lock = NSLock()
    // All access goes through `lock` (mutable global, Swift-6-safe pattern).
    nonisolated(unsafe) private static var cached: String?

    static var value: String {
        get {
            lock.lock(); defer { lock.unlock() }
            if let cached { return cached }
            let resolved: String
            if let existing = readKeychain(), !existing.isEmpty {
                resolved = existing
            } else if let migrated = UserDefaults.standard.string(forKey: defaultsKey),
                      !migrated.isEmpty
            {
                // Migrazione una tantum da UserDefaults (installazioni pre-Keychain).
                writeKeychain(migrated)
                UserDefaults.standard.removeObject(forKey: defaultsKey)
                resolved = migrated
            } else {
                resolved = UUID().uuidString
                writeKeychain(resolved)
            }
            cached = resolved
            return resolved
        }
        set {
            lock.lock(); defer { lock.unlock() }
            writeKeychain(newValue)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            cached = newValue
        }
    }

    /// Alias richiesto da spec: `APIConfig.pantryToken` / `PantryToken.pantryToken`
    static var pantryToken: String {
        get { value }
        set { value = newValue }
    }

    /// Reset per test / debug.
    static func reset() {
        lock.lock(); defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        cached = nil
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
