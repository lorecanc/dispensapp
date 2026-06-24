import SwiftUI

struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        Label(status.label, systemImage: status.symbol)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .clipShape(Capsule())
            .symbolEffect(.bounce, value: status)
    }
}
