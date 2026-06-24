import SwiftUI

struct ItemDetailView: View {
    @Environment(InventoryStore.self) private var store
    @State private var editQuantity: Int
    @State private var showDeleteConfirmation = false

    let item: InventoryItem

    init(item: InventoryItem) {
        self.item = item
        self._editQuantity = State(initialValue: item.quantity)
    }

    var body: some View {
        @Bindable var storeBindable = store

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: item.imageURL.flatMap { URL(string: $0) }) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 250)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        case .failure:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.secondary.opacity(0.2))
                                .frame(height: 200)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                }
                        case .empty:
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.secondary.opacity(0.2))
                                .frame(height: 200)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Text(item.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        if let brand = item.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if let category = item.category {
                            HStack(spacing: 4) {
                                Image(systemName: "tag")
                                Text(categoryDisplayName(category))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }

                        StatusBadge(status: ItemStatus.from(statusString: item.status))
                            .padding(.top, 4)

                        if let expirationDate = item.expirationDate {
                            HStack {
                                Text("Scadenza:")
                                    .foregroundStyle(.secondary)
                                Text(expirationDate.formatted(date: .long, time: .omitted))
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)

                            if item.isEstimated {
                                Label("Data stimata", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            Text("Nessuna data di scadenza")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    VStack(spacing: 16) {
                        Stepper("Quantità: \(editQuantity)", value: $editQuantity, in: 1...99)
                            .onChange(of: editQuantity) { _, newValue in
                                Task {
                                    await store.update(id: item.id, quantity: newValue)
                                }
                            }

                        Button {
                            Task {
                                await store.decrementQuantity(for: item)
                            }
                        } label: {
                            Label("Segna come consumato", systemImage: "fork.knife")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Elimina", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Dettaglio")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Eliminare \(item.name)?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    Task {
                        await store.delete(id: item.id)
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Questa azione non può essere annullata.")
            }
        }
        .presentationDetents([.medium, .large])
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
