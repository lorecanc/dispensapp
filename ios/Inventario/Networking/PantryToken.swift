import Foundation

/// Persiste `X-Pantry-Token` in `UserDefaults` (key `pantryToken`).
/// - Se mancante genera `UUID().uuidString` e salva.
/// - Legacy compat: finché non c'è UI pantry picker, la pantry default creata da migration ha
///   `owner_token = 00000000-0000-0000-0000-000000000000`. Per evitare 403 su pantry 1 al primo
///   avvio, se il token generato/salvato != legacy, lo sovrascrive con il legacy token.
///   Rimuovere questo fallback quando ci sarà gestione multi-pantry / membership.
/// Sendable perché espone solo accesso statico thread-safe via `UserDefaults`.
enum PantryToken: Sendable {
    static let headerName = "X-Pantry-Token"
    static let legacyToken = "00000000-0000-0000-0000-000000000000"
    private static let defaultsKey = "pantryToken"

    static var value: String {
        get {
            if let existing = UserDefaults.standard.string(forKey: defaultsKey), !existing.isEmpty {
                // Fallback legacy: forza 000... per compatibilità con pantry 1 esistente
                if existing != legacyToken {
                    // Sovrascrittura documentata — vedi fix 401 shopping-lists
                    UserDefaults.standard.set(legacyToken, forKey: defaultsKey)
                    return legacyToken
                }
                return existing
            }
            // Primo avvio: genera UUID come da spec, poi fallback a legacy per compatibilità
            let generated = UUID().uuidString
            if generated != legacyToken {
                UserDefaults.standard.set(legacyToken, forKey: defaultsKey)
                return legacyToken
            }
            UserDefaults.standard.set(generated, forKey: defaultsKey)
            return generated
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    /// Alias richiesto da spec: `APIConfig.pantryToken` / `PantryToken.pantryToken`
    static var pantryToken: String {
        get { value }
        set { value = newValue }
    }

    /// Reset per test / debug.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
