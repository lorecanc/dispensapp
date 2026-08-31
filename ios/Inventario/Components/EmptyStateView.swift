import SwiftUI

/// Empty state con illustrazione PantryTerracotta e card Material.
/// Usato quando la dispensa è vuota o la ricerca non produce risultati.
struct EmptyStateView: View {
    var imageName: String = "refrigerator.fill"
    var title: String = "La tua dispensa è vuota"
    var message: String = "Tocca + per aggiungere un prodotto."

    var body: some View {
        VStack(spacing: 16) {
            // Illustration Terracotta su cerchio Material tint
            ZStack {
                Circle()
                    .fill(Color.pantryTerracotta.opacity(0.12))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .fill(.thinMaterial)
                            .opacity(0.4)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.pantryTerracotta.opacity(0.18), lineWidth: 0.5)
                    )
                Image(systemName: imageName)
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(Color.pantryTerracotta)
                    .accessibilityHidden(true)
            }
            .padding(.top, 4)

            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHeading(.h2)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        // Card Material: regularMaterial + PantryCream 0.35 + PantryOat 0.5 + liquid glass radius
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.pantryCream.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(message)")
        .accessibilityHint("Stato vuoto della dispensa")
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
