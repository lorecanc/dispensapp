import SwiftUI

enum ItemStatus: String, CaseIterable {
    case ok
    case expiringSoon = "expiring_soon"
    case expired

    var color: Color {
        switch self {
        case .ok: return .green
        case .expiringSoon: return .orange
        case .expired: return .red
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
