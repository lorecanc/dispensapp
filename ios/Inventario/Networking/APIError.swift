import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case transport(Error)
    case decoding(Error)
    case http(status: Int, message: String?)
    case notFound
    case offline

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL): return true
        case (.transport, .transport): return false
        case (.decoding, .decoding): return false
        case (.http(let l, _), .http(let r, _)): return l == r
        case (.notFound, .notFound): return true
        case (.offline, .offline): return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL non valido."
        case .transport(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorNotConnectedToInternet {
                return "Nessuna connessione internet."
            }
            return "Errore di rete: \(error.localizedDescription)"
        case .decoding(let error):
            return "Errore durante l'elaborazione dei dati: \(error.localizedDescription)"
        case .http(let status, let message):
            if let msg = message, !msg.isEmpty {
                return "Errore del server (\(status)): \(msg)"
            }
            return "Errore del server (\(status))."
        case .notFound:
            return "Risorsa non trovata."
        case .offline:
            return "Nessuna connessione internet."
        }
    }
}
