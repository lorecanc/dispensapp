import SwiftUI

struct InventoryListView: View {
    @Environment(InventoryStore.self) private var store
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showSettings = false
    @State private var showDetailItem: InventoryItem?
    @State private var showScanner = false
    @State private var showManagePantries = false
    @State private var showInviteMembers = false
    @State private var showDeletePantryConfirm = false
    @State private var pendingDeletePantry: Pantry?
    @State private var showManageDeleteConfirm = false
    @State private var showHistorySheet = false
    @State private var showAddChoice = false
    @State private var showManual = false

    // MARK: - Filtering

    // T8: cached result, recomputed only when a relevant input changes (see
    // FilterKey), not on every body evaluation.
    @State private var cachedSections: [(ItemStatus, [InventoryItem])]?

    private var groupedItems: [(ItemStatus, [InventoryItem])] {
        cachedSections ?? Self.sections(
            items: store.items,
            archivedIDs: store.archivedIDs,
            searchText: searchText,
            selectedCategory: selectedCategory
        )
    }

    /// Aggregates every input `sections` derives from. `InventoryItem` is
    /// id-only Equatable, so store content enters as a full-field
    /// fingerprint: any visible change (consume, update, refresh, reorder)
    /// flips it.
    private struct FilterKey: Hashable {
        let itemsFingerprint: Int
        let searchText: String
        let selectedCategory: String?
        let archivedIDs: Set<Int>
    }

    private var filterKey: FilterKey {
        var hasher = Hasher()
        for item in store.items {
            hasher.combine(item.id)
            hasher.combine(item.barcode)
            hasher.combine(item.name)
            hasher.combine(item.brand)
            hasher.combine(item.expirationDate)
            hasher.combine(item.isEstimated)
            hasher.combine(item.category)
            hasher.combine(item.imageURL)
            hasher.combine(item.createdAt)
            hasher.combine(item.quantity)
            hasher.combine(item.status)
        }
        return FilterKey(
            itemsFingerprint: hasher.finalize(),
            searchText: searchText,
            selectedCategory: selectedCategory,
            archivedIDs: store.archivedIDs
        )
    }

    private static func sections(
        items: [InventoryItem],
        archivedIDs: Set<Int>,
        searchText: String,
        selectedCategory: String?
    ) -> [(ItemStatus, [InventoryItem])] {
        let filtered = items.filter { item in
            guard !archivedIDs.contains(item.id) else { return false }
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
        let grouped = Dictionary(grouping: filtered) {
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

                Section {
                    addProductPill
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if groupedItems.isEmpty {
                    if store.items.isEmpty {
                        EmptyStateView()
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        // No results per search/filter — reuse EmptyState con messaggio diverso
                        EmptyStateView(
                            imageName: "magnifyingglass",
                            title: "Nessun risultato",
                            message: "Prova a cambiare ricerca o filtro categoria."
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
        // O2/T13: offline → pill discreta (mai banner rosso); errori veri → banner
        // che si auto-chiude. Monitor già avviato da InventoryStore.init.
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if store.isOffline {
                    OfflinePill()
                        .padding(.top, 8)
                }
                if let error = store.error {
                    BannerView(message: error.localizedDescription, style: .error, autoDismiss: true) {
                        storeBindable.error = nil
                    }
                }
            }
        }
        .navigationTitle(store.selectedPantryName)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            // Leading: gestione dispense (selezione + gestione).
            ToolbarItem(placement: .topBarLeading) {
                pantryPickerMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .tint(Color.pantryMoss)
                .accessibilityLabel("Scansiona codice a barre")
            }
            // Unico Menu overflow puntini.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(destination: ManualEntryView()) {
                        Label("Inserimento manuale", systemImage: "pencil")
                    }

                    Button {
                        showInviteMembers = true
                    } label: {
                        Label("Invita membri", systemImage: "person.badge.plus")
                    }
                    .accessibilityLabel("Invita membri")
                    .accessibilityHint("Apri inviti e membri: chi ha il link può unirsi")

                    Button {
                        showSettings = true
                    } label: {
                        Label("Impostazioni", systemImage: "gearshape")
                    }

                    Button {
                        showHistorySheet = true
                    } label: {
                        Label("Storico", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Storico consumati")
                    .accessibilityHint("Mostra i consumi registrati")

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
        .sheet(isPresented: $showManual) {
            NavigationStack {
                ManualEntryView()
            }
        }
        .sheet(isPresented: $showManagePantries) {
            managePantriesSheet
        }
        .sheet(isPresented: $showInviteMembers) {
            InviteMembersSheet()
        }
        .sheet(isPresented: $showHistorySheet) {
            historySheet
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Elimina dispensa?",
            isPresented: $showDeletePantryConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                Task { await store.deletePantry(id: store.selectedPantryId) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("La dispensa \(store.selectedPantryName) verrà eliminata.")
        }
        .task {
            await store.fetchPantries()
        }
        .task(id: store.selectedPantryId) {
            await store.refresh()
        }
        .task(id: filterKey) {
            cachedSections = Self.sections(
                items: store.items,
                archivedIDs: store.archivedIDs,
                searchText: searchText,
                selectedCategory: selectedCategory
            )
        }
    }

    // MARK: - Pantry picker + gestione

    private var pantryPickerMenu: some View {
        @Bindable var storeBindable = store
        return Menu {
            Picker("Dispensa", selection: $storeBindable.selectedPantryId) {
                ForEach(store.pantries) { pantry in
                    Text(pantry.name).tag(pantry.id)
                }
            }
            Divider()
            Button {
                showManagePantries = true
            } label: {
                Label("Gestisci dispense", systemImage: "folder.badge.gearshape")
            }
            Button(role: .destructive) {
                showDeletePantryConfirm = true
            } label: {
                Label("Elimina dispensa", systemImage: "trash")
            }
        } label: {
            HStack(spacing: 4) {
                Label(store.selectedPantryName, systemImage: "house")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.pantryMoss)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pantryMoss)
            }
        }
        .tint(Color.pantryMoss)
        .accessibilityLabel("Gestione dispense, \(store.selectedPantryName)")
        .accessibilityHint("Scegli la dispensa, gestisci l'elenco o elimina quella corrente")
    }

    private var managePantriesSheet: some View {
        NavigationStack {
            List {
                ForEach(store.pantries) { pantry in
                    HStack {
                        Text(pantry.name)
                        Spacer()
                        if pantry.id == store.selectedPantryId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.pantryMoss)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.selectPantry(pantry.id)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletePantry = pantry
                            showManageDeleteConfirm = true
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Gestisci dispense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        showManagePantries = false
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .confirmationDialog(
                "Elimina dispensa?",
                isPresented: $showManageDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    if let pantry = pendingDeletePantry {
                        Task {
                            await store.deletePantry(id: pantry.id)
                        }
                        pendingDeletePantry = nil
                    }
                }
                Button("Annulla", role: .cancel) { pendingDeletePantry = nil }
            } message: {
                Text("La dispensa verrà eliminata definitivamente.")
            }
        }
    }

    // MARK: - T9 storico

    private var addProductPill: some View {
        Button {
            showAddChoice = true
        } label: {
            HStack(spacing: 8) {
                Label("Aggiungi prodotto", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pantryMoss)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().fill(Color.pantryCream.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aggiungi prodotto")
        .accessibilityHint("Scegli tra scansione codice e inserimento manuale")
        .confirmationDialog(
            "Aggiungi prodotto",
            isPresented: $showAddChoice,
            titleVisibility: .visible
        ) {
            Button {
                showScanner = true
            } label: {
                Label("Scansiona", systemImage: "barcode.viewfinder")
            }
            Button {
                showManual = true
            } label: {
                Label("Inserimento manuale", systemImage: "pencil")
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    // MARK: - Storico consumati (sheet da menu ellipsis)

    private var historySheet: some View {
        NavigationStack {
            Group {
                if store.archivedIDs.isEmpty {
                    ContentUnavailableView(
                        "Nessuno storico",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("I prodotti consumati fino a zero appariranno qui.")
                    )
                } else {
                    List {
                        ForEach(store.archivedIDs.sorted(), id: \.self) { id in
                            Section(header: Text(sectionTitle(for: id))) {
                                if let events = store.history[id] {
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
                                    .task {
                                        await store.fetchHistory(itemId: id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Storico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        showHistorySheet = false
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    private func sectionTitle(for id: Int) -> String {
        store.history[id]?.first?.nameSnapshot ?? "Prodotto #\(id)"
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
