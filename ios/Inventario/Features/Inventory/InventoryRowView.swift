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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                case .empty:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay {
                            ProgressView()
                        }
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)

                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let category = item.category {
                    HStack(spacing: 4) {
                        Image(systemName: "tag")
                            .font(.caption2)
                        Text(categoryDisplayName(category))
                            .font(.caption2)
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: ItemStatus.from(statusString: item.status))

                Text("×\(item.quantity)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func categoryDisplayName(_ category: String) -> String {
        switch category {
        case "yogurt": return "Yogurt"
        case "fresh-milk": return "Latte fresco"
        case "pasta": return "Pasta"
        case "canned-vegetables": return "Verdure in scatola"
        case "rice": return "Riso"
        case "cheeses": return "Formaggi"
        case "eggs": return "Uova"
        case "fresh-fruits": return "Frutta fresca"
        case "fresh-vegetables": return "Verdura fresca"
        case "frozen-foods": return "Surgelati"
        default: return category
        }
    }
}
