import SwiftUI

struct InventoryListView: View {
    @Environment(InventoryStore.self) private var store
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showSettings = false
    @State private var showDetailItem: InventoryItem?
    @State private var showScanner = false
    @State private var showAddForm = false
    @State private var newItemName = ""
    @State private var newItemQuantity = 1
    @State private var expandedHistory: Set<Int> = []

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

                // T7: inline form come spesa, aperto dal + ovale in primaryAction
                if showAddForm {
                    Section {
                        addItemSection
                    } header: {
                        Label("Aggiungi prodotto", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.pantryMoss)
                            .textCase(nil)
                    }
                    .listSectionSeparator(.hidden, edges: .bottom)
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
                                    // T8: consumo atomico server-side; no full-swipe per gesto intuitivo.
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            Task { await store.delete(id: item.id) }
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                        .tint(Color.statusExpired)
                                        .accessibilityLabel("Elimina \(item.name)")
                                        .accessibilityHint("Elimina il prodotto dalla dispensa")
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            Task { await store.consume(item: item) }
                                        } label: {
                                            Label("Consumato", systemImage: "fork.knife")
                                        }
                                        .tint(Color.statusFresh)
                                        .accessibilityLabel("Segna consumato \(item.name)")
                                        .accessibilityHint("Consuma una unità sul server")
                                    }
                                    .contextMenu {
                                        Button {
                                            Task { await store.consume(item: item) }
                                        } label: {
                                            Label("Consumato", systemImage: "fork.knife")
                                        }
                                        .accessibilityLabel("Segna consumato \(item.name)")
                                        Button(role: .destructive) {
                                            Task { await store.delete(id: item.id) }
                                        } label: {
                                            Label("Elimina", systemImage: "trash")
                                        }
                                        .accessibilityLabel("Elimina \(item.name)")
                                    }
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                // T9: storico consumi, collassato di default, senza swipe delete.
                                historyDisclosure(for: item)
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
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            // T6: picker pantry in header (personale/condivise), binding su store @Environment.
            ToolbarItem(placement: .topBarLeading) {
                pantryPickerMenu
            }
            // T7: + ovale in primaryAction, Label con testo, chrome Glass solo qui.
            ToolbarItem(placement: .primaryAction) {
                addOvalButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .tint(Color.pantryMoss)
                .accessibilityLabel("Scansiona codice a barre")
            }
            // Unico Menu overflow puntini.
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
                .accessibilityLabel("Altre azioni dispensa")
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
            await store.fetchPantries()
        }
        .task(id: store.selectedPantryId) {
            await store.refresh()
        }
    }

    // MARK: - T6 pantry picker (header)

    private var pantryPickerMenu: some View {
        @Bindable var storeBindable = store
        return Menu {
            Picker("Dispensa", selection: $storeBindable.selectedPantryId) {
                ForEach(store.pantries) { pantry in
                    Text(pantry.name).tag(pantry.id)
                }
            }
        } label: {
            Label(store.selectedPantryName, systemImage: "house")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.pantryMoss)
                .lineLimit(1)
        }
        .tint(Color.pantryMoss)
        .accessibilityLabel("Seleziona dispensa")
        .accessibilityHint("Scegli tra dispensa personale e condivise")
    }

    // T7: + ovale 44pt+, glassProminent iOS 26, fallback chrome pre-26.
    @ViewBuilder
    private var addOvalButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAddForm.toggle() }
            } label: {
                Label(showAddForm ? "Chiudi" : "Aggiungi", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.glassProminent)
            .tint(Color.pantryMoss)
            .accessibilityLabel(showAddForm ? "Chiudi modulo aggiunta" : "Aggiungi prodotto")
            .accessibilityHint("Apre il modulo inline come nella spesa")
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAddForm.toggle() }
            } label: {
                Label(showAddForm ? "Chiudi" : "Aggiungi", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background(Color.pantryMoss, in: Capsule())
            .tint(Color.pantryMoss)
            .accessibilityLabel(showAddForm ? "Chiudi modulo aggiunta" : "Aggiungi prodotto")
            .accessibilityHint("Apre il modulo inline come nella spesa")
        }
    }

    // MARK: - T7 inline add (come spesa) + T9 storico

    private var addItemSection: some View {
        VStack(spacing: 12) {
            TextField("Nome prodotto", text: $newItemName)
                .autocorrectionDisabled()

            HStack(spacing: 12) {
                QuantityStepper(quantity: $newItemQuantity)
                Spacer()
            }

            Button {
                Task {
                    guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    await store.addManual(
                        name: newItemName.trimmingCharacters(in: .whitespaces),
                        brand: nil,
                        expirationDate: nil,
                        category: nil,
                        quantity: newItemQuantity
                    )
                    guard store.error == nil else { return }
                    newItemName = ""
                    newItemQuantity = 1
                    withAnimation(.easeInOut(duration: 0.2)) { showAddForm = false }
                }
            } label: {
                Label("Aggiungi in dispensa", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.pantryMoss)
            .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
        .pantryCardBackground(cornerRadius: 14)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // T9: DisclosureGroup collassato di default, opacity 0.6, senza swipe delete.
    private func historyDisclosure(for item: InventoryItem) -> some View {
        DisclosureGroup(isExpanded: historyBinding(for: item.id)) {
            if let events = store.history[item.id] {
                if events.isEmpty {
                    Text("Nessun consumo registrato.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ForEach(events) { event in
                        HStack(spacing: 8) {
                            Image(systemName: "fork.knife")
                                .font(.caption2)
                                .foregroundStyle(Color.pantryMoss)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(abs(event.delta)) × \(event.nameSnapshot)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Color.textPrimary)
                                Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Caricamento storico…")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        } label: {
            Label("Storico consumati", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textSecondary)
        }
        .tint(Color.pantryMoss)
        .opacity(0.6)
        .accessibilityLabel("Storico consumati")
        .accessibilityHint("Mostra i consumi registrati per \(item.name)")
        .listRowInsets(EdgeInsets(top: 2, leading: 32, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func historyBinding(for id: Int) -> Binding<Bool> {
        Binding(
            get: { expandedHistory.contains(id) },
            set: { expanded in
                if expanded {
                    expandedHistory.insert(id)
                    Task { await store.fetchHistory(itemId: id) }
                } else {
                    expandedHistory.remove(id)
                }
            }
        )
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
