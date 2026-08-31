import SwiftUI

enum ItemStatus: String, CaseIterable {
    case ok
    case expiringSoon = "expiring_soon"
    case expired

    // Palette Terra: fresco/soon/expired mappati su StatusFresh/Soon/Expired con PantryMoss token.
    var color: Color {
        switch self {
        case .ok: return .statusFresh
        case .expiringSoon: return .statusSoon
        case .expired: return .statusExpired
        }
    }

    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .expiringSoon: return "exclamationmark.circle.fill"
        case .expired: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .ok: return "Ok"
        case .expiringSoon: return "In scadenza"
        case .expired: return "Scaduto"
        }
    }

    static func from(statusString: String) -> ItemStatus {
        ItemStatus(rawValue: statusString) ?? .ok
    }
}
