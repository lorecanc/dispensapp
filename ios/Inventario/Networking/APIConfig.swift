import Foundation

struct APIConfig {
    static var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8000" }
        set { UserDefaults.standard.set(newValue, forKey: "apiBaseURL") }
    }

    /// Validates that the string is a usable http/https URL with a host.
    static var isValidURL: Bool {
        guard let url = URL(string: baseURLString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// Optional URL — nil when the string is empty or malformed. Never force-unwraps.
    static var baseURL: URL? {
        guard isValidURL, let url = URL(string: baseURLString) else { return nil }
        return url
    }

    /// Validated fallback used only when callers need a guaranteed URL for display.
    static var fallbackURL: URL { URL(string: "http://127.0.0.1:8000")! }
}
