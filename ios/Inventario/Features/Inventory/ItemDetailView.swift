import SwiftUI

struct ItemDetailView: View {
    @Environment(InventoryStore.self) private var store
    @State private var editQuantity: Int
    @State private var showDeleteConfirmation = false

    private let itemID: Int

    init(item: InventoryItem) {
        itemID = item.id
        _editQuantity = State(initialValue: item.quantity)
    }

    /// Item live dallo store, risolto a ogni render: i mutamenti di consume/
    /// update/delete si riflettono subito. Nil se l'item sparisce mentre il
    /// dettaglio è aperto (consumato a zero, eliminato, cambio dispensa).
    @MainActor
    private var liveItem: InventoryItem? {
        store.items.first { $0.id == itemID }
    }

    var body: some View {
        @Bindable var storeBindable = store

        NavigationStack {
            if let item = liveItem {
                ScrollView {
                    VStack(spacing: 20) {
                        CachedThumbnail(
                            url: item.imageURL.flatMap { URL(string: $0) },
                            side: 250,
                            contentMode: .fit
                        )
                        .padding(.horizontal)

                        VStack(spacing: 12) {
                            Text(item.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let brand = item.brand, !brand.isEmpty {
                                Text(brand)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .accessibilityLabel("Marca \(brand)")
                            }

                            if let category = item.category {
                                HStack(spacing: 4) {
                                    Image(systemName: "tag")
                                        .accessibilityHidden(true)
                                    Text(categoryDisplayName(category))
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .accessibilityLabel("Categoria \(categoryDisplayName(category))")
                                .accessibilityHint("Categoria del prodotto")
                            }

                            StatusBadge(status: ItemStatus.from(statusString: item.status))
                                .padding(.top, 4)

                            if let expirationDate = item.expirationDate {
                                HStack {
                                    Text("Scadenza:")
                                        .foregroundStyle(Color.textSecondary)
                                    Text(expirationDate.formatted(date: .long, time: .omitted))
                                        .fontWeight(.medium)
                                }
                                .font(.subheadline)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Scadenza \(expirationDate.formatted(date: .long, time: .omitted))")

                                if item.isEstimated {
                                    Label("Data stimata", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(Color.statusSoon)
                                        .accessibilityLabel("Data stimata")
                                        .accessibilityHint("Data di scadenza stimata dalla categoria, non esatta")
                                }
                            } else {
                                Text("Nessuna data di scadenza")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .accessibilityLabel("Nessuna data di scadenza")
                            }
                        }

                        Divider()

                        VStack(spacing: 16) {
                            Stepper("Quantità: \(editQuantity)", value: $editQuantity, in: 1...99)
                                .onChange(of: editQuantity) { _, newValue in
                                    // Solo le modifiche vere: il guard spezza il
                                    // loop quando è un sync esterno (consume) a
                                    // muovere lo stepper.
                                    guard newValue != item.quantity else { return }
                                    Task {
                                        await store.update(id: item.id, quantity: newValue)
                                    }
                                }
                                .onChange(of: item.quantity) { _, newValue in
                                    editQuantity = newValue
                                }
                                .accessibilityLabel("Quantità")
                                .accessibilityValue("\(editQuantity)")
                                .accessibilityHint("Regola la quantità del prodotto")
                                .dynamicTypeSize(.xSmall ... .accessibility2)

                            Button {
                                Task {
                                    await store.decrementQuantity(for: item)
                                }
                            } label: {
                                Label("Segna come consumato", systemImage: "fork.knife")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.statusFresh)
                            .accessibilityLabel("Segna come consumato")
                            .accessibilityHint("Diminuisce la quantità di uno")

                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Elimina", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Elimina \(item.name)")
                            .accessibilityHint("Elimina definitivamente il prodotto")
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
            } else {
                ContentUnavailableView(
                    "Prodotto non più in dispensa",
                    systemImage: "basket",
                    description: Text("Eliminato o consumato del tutto: chiudi per tornare alla lista.")
                )
                .navigationTitle("Dettaglio")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func categoryDisplayName(_ category: String) -> String {
        CategoryRegistry.displayName(for: category)
    }
}
