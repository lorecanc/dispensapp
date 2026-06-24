import Foundation

struct APIConfig {
    static var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8000" }
        set { UserDefaults.standard.set(newValue, forKey: "apiBaseURL") }
    }
    static var baseURL: URL { URL(string: baseURLString)! }
}
