import SwiftUI

struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        // HIG: icona+label non solo colore; badge con Material leggero + bordo status
        Label(status.label, systemImage: status.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(status.color.opacity(0.14))
                    .overlay(
                        Capsule()
                            .fill(.thinMaterial)
                            .opacity(0.35)
                    )
            }
            .overlay(
                Capsule()
                    .strokeBorder(status.color.opacity(0.28), lineWidth: 0.5)
            )
            .clipShape(Capsule())
            .symbolEffect(.bounce, value: status)
            // Dynamic Type support: scalatura automatica con .caption
            .accessibilityLabel("Stato \(status.label)")
            .accessibilityValue(status.label)
            .accessibilityHint(status == .ok ? "Prodotto fresco" : status == .expiringSoon ? "Prodotto in scadenza a breve" : "Prodotto scaduto")
            .accessibilityAddTraits(.isStaticText)
            .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
