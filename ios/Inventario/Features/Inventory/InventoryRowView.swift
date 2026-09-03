import SwiftUI

struct InventoryRowView: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: item.imageURL.flatMap { URL(string: $0) }) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        // Liquid glass style: cornerRadius maggiore, .continuous
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.pantryOat.opacity(0.6), lineWidth: 0.5)
                        )
                case .failure:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.pantryOat.opacity(0.35))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(Color.textSecondary)
                        }
                case .empty:
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.pantryOat.opacity(0.25))
                        .frame(width: 56, height: 56)
                        .overlay {
                            ProgressView()
                                .tint(Color.pantryMoss)
                        }
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                if let category = item.category, !category.isEmpty {
                    // Category chip single source da CategoryRegistry
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.caption2)
                        Text(CategoryRegistry.displayName(for: category))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background {
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay(Capsule().fill(Color.pantryCream.opacity(0.45)))
                    }
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                    )
                    .accessibilityLabel(CategoryRegistry.displayName(for: category))
                    .accessibilityHint("Categoria prodotto")
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(status: ItemStatus.from(statusString: item.status))

                Text("×\(item.quantity)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        Capsule()
                            .fill(Color.pantryOat.opacity(0.35))
                    }
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                    )
            }
        }
        .padding(12)
        // Material content: regularMaterial + PantryCream 0.35 + PantryOat 0.5 + cornerRadius 18 liquid glass
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.pantryCream.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Accessibilità: VoiceOver combina nome, categoria, stato, quantità
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Tocca per dettagli, scorri a sinistra per eliminare, a destra per segnare consumato")
        .accessibilityAddTraits(.isButton)
        .dynamicTypeSize(.xSmall ... .accessibility3)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [item.name]
        if let brand = item.brand, !brand.isEmpty { parts.append(brand) }
        if let category = item.category { parts.append(CategoryRegistry.displayName(for: category)) }
        let status = ItemStatus.from(statusString: item.status)
        parts.append(status.label)
        parts.append("quantità \(item.quantity)")
        if let date = item.expirationDate {
            parts.append("scadenza \(date.formatted(date: .long, time: .omitted))")
        }
        return parts.joined(separator: ", ")
    }

    private var accessibilityValue: String {
        let status = ItemStatus.from(statusString: item.status)
        return "\(status.label), quantità \(item.quantity)"
    }

    private func categoryDisplayName(_ category: String) -> String {
        CategoryRegistry.displayName(for: category)
    }
}
