import SwiftUI

struct InventoryListView: View {
    @Environment(InventoryStore.self) private var store
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showSettings = false
    @State private var showDetailItem: InventoryItem?
    @State private var showScanner = false

    // MARK: - Filtering

    private var filteredItems: [InventoryItem] {
        store.items.filter { item in
            let matchesSearch: Bool
            if searchText.isEmpty {
                matchesSearch = true
            } else {
                matchesSearch = item.name.localizedCaseInsensitiveContains(searchText)
                    || (item.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (item.category?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            let matchesCategory: Bool
            if let selectedCategory {
                matchesCategory = item.category == selectedCategory
            } else {
                matchesCategory = true
            }
            return matchesSearch && matchesCategory
        }
    }

    private var groupedItems: [(ItemStatus, [InventoryItem])] {
        let grouped = Dictionary(grouping: filteredItems) {
            ItemStatus.from(statusString: $0.status)
        }
        return ItemStatus.allCases.compactMap { status in
            guard let items = grouped[status], !items.isEmpty else { return nil }
            return (status, items)
        }
    }

    // Single source per chip: CategoryRegistry
    private var categoryOptions: [(key: String, label: String)] {
        CategoryRegistry.categories
    }

    var body: some View {
        @Bindable var storeBindable = store

        ZStack {
            Color.pantryCream.ignoresSafeArea()

            List {
                // MARK: Category filter chips — single source CategoryRegistry
                Section {
                    categoryFilterBar
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if groupedItems.isEmpty {
                    if store.items.isEmpty {
                        EmptyStateView()
                            .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        // No results per search/filter — reuse EmptyState con messaggio diverso
                        EmptyStateView(
                            imageName: "magnifyingglass",
                            title: "Nessun risultato",
                            message: "Prova a cambiare ricerca o filtro categoria."
                        )
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(groupedItems, id: \.0) { status, items in
                        Section {
                            ForEach(items) { item in
                                InventoryRowView(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        showDetailItem = item
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            Task { await store.delete(id: item.id) }
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                        .tint(Color.statusExpired)
                                        .accessibilityLabel("Elimina \(item.name)")
                                        .accessibilityHint("Elimina il prodotto dalla dispensa")
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            Task { await store.decrementQuantity(for: item) }
                                        } label: {
                                            Label("Consumato", systemImage: "fork.knife")
                                        }
                                        .tint(Color.statusFresh)
                                        .accessibilityLabel("Segna consumato \(item.name)")
                                        .accessibilityHint("Diminuisce la quantità di uno o elimina se unico")
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        } header: {
                            // HIG: icona+label per stato, colori palette
                            Label(status.label, systemImage: status.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(status.color)
                                .textCase(nil)
                                .padding(.vertical, 2)
                        }
                        .listSectionSeparator(.hidden, edges: .bottom)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.pantryCream)
            .listSectionSpacing(12)
            // PantryOat per separatori se visibili
            .tint(Color.pantryOat)
        }
        .searchable(text: $searchText, prompt: "Cerca nella dispensa...")
        .refreshable {
            await store.refresh()
        }
        .overlay(alignment: .top) {
            if let error = store.error {
                ErrorBanner(message: error.localizedDescription) {
                    storeBindable.error = nil
                }
            }
        }
        .navigationTitle("Dispensa")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .tint(Color.pantryMoss)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    NavigationLink(destination: ManualEntryView()) {
                        Label("Inserimento manuale", systemImage: "pencil")
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Label("Impostazioni", systemImage: "gearshape")
                    }

                    Button {
                        Task { await store.exportMarkdown() }
                    } label: {
                        Label("Esporta dispensa", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(Color.pantryMoss)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $showDetailItem) { item in
            ItemDetailView(item: item)
        }
        .sheet(isPresented: $showScanner) {
            ScannerViewWrapper()
        }
        .task {
            await store.refresh()
        }
    }

    // MARK: - Category filter chips

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(label: "Tutti", isSelected: selectedCategory == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                }
                .accessibilityLabel("Filtro Tutti")
                .accessibilityHint("Mostra tutti i prodotti senza filtro categoria")
                .accessibilityValue(selectedCategory == nil ? "Selezionato" : "Non selezionato")
                .accessibilityAddTraits(selectedCategory == nil ? .isSelected : [])

                ForEach(categoryOptions, id: \.key) { option in
                    let isSelected = selectedCategory == option.key
                    categoryChip(label: option.label, isSelected: isSelected) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = isSelected ? nil : option.key
                        }
                    }
                    .accessibilityLabel("Filtro \(option.label)")
                    .accessibilityHint("Filtra la dispensa per categoria \(option.label)")
                    .accessibilityValue(isSelected ? "Selezionato" : "Non selezionato")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func categoryChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.pantryMoss : Color.pantryCream)
                        .overlay {
                            if !isSelected {
                                Capsule()
                                    .fill(.thinMaterial)
                                    .opacity(0.55)
                            }
                        }
                }
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.pantryMoss : Color.pantryOat, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        // Material per non-selected: thinMaterial + PantryCream + PantryOat 0.5
        // Selezionato: PantryMoss primary
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
