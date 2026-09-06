import SwiftUI

struct InventoryRowView: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            CachedThumbnail(url: item.imageURL.flatMap { URL(string: $0) }, side: 56)

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

                HStack(spacing: 4) {
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
                                .overlay(Capsule().fill(Color.pantryLinen.opacity(0.45)))
                        }
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                        )
                        .accessibilityLabel(CategoryRegistry.displayName(for: category))
                        .accessibilityHint("Categoria prodotto")
                    }

                    // T13: badge conservazione; override utente (item.storageLocation,
                    // T11) se presente, altrimenti derivazione dal registry (T12).
                    storageBadge

                    // T8c: badge tipo prodotto, solo con sorgente nota.
                    sourceBadge
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                if ItemStatus.from(statusString: item.status) != .ok {
                    StatusBadge(status: ItemStatus.from(statusString: item.status))
                }

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
        // Material content: regularMaterial + PantryLinen 0.35 + PantryOat 0.5 + cornerRadius 18 liquid glass
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.pantryLinen.opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Accessibilità: VoiceOver combina nome, categoria, conservazione, stato, quantità
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
        if let source = productSource { parts.append("Tipo: \(source.displayName)") }
        parts.append("Conservazione: \(storageLabel)")
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

    // MARK: - T13 badge conservazione

    private var storageLocationCode: String {
        item.storageLocation ?? CategoryRegistry.storageLocation(for: item.category ?? "")
    }

    private var storageLabel: String {
        CategoryRegistry.storageLabel(for: storageLocationCode)
    }

    private var storageBadge: some View {
        let label = storageLabel
        return HStack(spacing: 4) {
            if let icon = CategoryRegistry.storageIcon(for: storageLocationCode) {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().fill(Color.pantryLinen.opacity(0.45)))
        }
        .overlay(
            Capsule()
                .strokeBorder(Color.pantryOat, lineWidth: 0.5)
        )
        .accessibilityLabel("Conservazione: \(label)")
    }

    // MARK: - T8c badge tipo prodotto (capsula non tappabile, mai colori stato)

    private var productSource: ProductSource? {
        (item.source ?? item.productType).flatMap(ProductSource.init)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let source = productSource {
            Text(source.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule()
                        .fill(.thinMaterial)
                        .overlay(Capsule().fill(Color.pantryLinen.opacity(0.45)))
                }
                .overlay(
                    Capsule()
                        .strokeBorder(Color.pantryOat, lineWidth: 0.5)
                )
                .accessibilityLabel("Tipo: \(source.displayName)")
        }
    }
}
