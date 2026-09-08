import SwiftUI

struct InventoryListView: View {
    @Environment(InventoryStore.self) private var store
    @State private var searchText = ""
    @State private var selectedCompartment: Compartment? = nil
    @State private var showSettings = false
    @State private var showDetailItem: InventoryItem?
    @State private var showScanner = false
    @State private var showManagePantries = false
    @State private var showCreatePantry = false
    @State private var newPantryName = ""
    @State private var isCreatingPantry = false
    @State private var showInviteMembers = false
    @State private var showDeletePantryConfirm = false
    @State private var pendingDeletePantry: Pantry?
    @State private var showManageDeleteConfirm = false
    @State private var showHistorySheet = false
    @State private var showAddChoice = false
    @State private var showManual = false
    @State private var showJoinPantry = false
    @State private var pendingAdd: AddMethod?
    @State private var expandedCompartments: Set<String> = Set(ItemStatus.allCases.flatMap { status in Compartment.supermarketOrder.map { "\(status.rawValue)#\($0.rawValue)" } })
    @State private var pantrySuggestions: [Suggestion] = []
    @State private var manualPrefillName = ""
    @State private var manualPrefillCategory = ""

    /// Scelta dal foglio "Aggiungi prodotto". L'azione effettiva è rimandata
    /// alla chiusura del foglio (onChange su showAddChoice) per evitare la
    /// race iOS 17 in cui il secondo sheet viene inghiottito dal primo.
    private enum AddMethod {
        case scanner, manual
    }

    // MARK: - Filtering

    // T8: cached result, recomputed only when a relevant input changes (see
    // FilterKey), not on every body evaluation.
    @State private var cachedSections: [(ItemStatus, [InventoryItem])]?

    private var groupedItems: [(ItemStatus, [InventoryItem])] {
        cachedSections ?? Self.sections(
            items: store.items,
            archivedIDs: store.archivedIDs,
            searchText: searchText,
            selectedCompartment: selectedCompartment
        )
    }

    /// Aggregates every input `sections` derives from. `InventoryItem` is
    /// id-only Equatable, so store content enters as a full-field
    /// fingerprint: any visible change (consume, update, refresh, reorder)
    /// flips it.
    private struct FilterKey: Hashable {
        let itemsFingerprint: Int
        let searchText: String
        let selectedCompartment: Compartment?
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
            hasher.combine(item.source)
            hasher.combine(item.productType)
        }
        return FilterKey(
            itemsFingerprint: hasher.finalize(),
            searchText: searchText,
            selectedCompartment: selectedCompartment,
            archivedIDs: store.archivedIDs
        )
    }

    private static func sections(
        items: [InventoryItem],
        archivedIDs: Set<Int>,
        searchText: String,
        selectedCompartment: Compartment?
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
            // T13: filtro per comparto via CategoryRegistry.compartmentMap.
            // Category nil/sconosciuta -> visibile solo con "Tutti" (nil).
            let matchesCompartment: Bool
            if let selectedCompartment {
                guard let category = item.category else { return false }
                matchesCompartment = CategoryRegistry.compartmentMap[category] == selectedCompartment.rawValue
            } else {
                matchesCompartment = true
            }
            return matchesSearch && matchesCompartment
        }
        let grouped = Dictionary(grouping: filtered) {
            ItemStatus.from(statusString: $0.status)
        }
        return ItemStatus.allCases.compactMap { status in
            guard let items = grouped[status], !items.isEmpty else { return nil }
            return (status, items)
        }
    }

    // Single source per chip: ordine canonico supermarketOrder (ShoppingModels).
    private var compartmentOptions: [Compartment] {
        Compartment.supermarketOrder
    }

    private func compartment(for item: InventoryItem) -> Compartment {
        Compartment.inferCompartment(name: item.name, category: item.category)
    }

    private func compartmentGroups(for items: [InventoryItem]) -> [(Compartment, [InventoryItem])] {
        let grouped = Dictionary(grouping: items, by: compartment(for:))
        return Compartment.supermarketOrder.compactMap { comp in
            guard let arr = grouped[comp], !arr.isEmpty else { return nil }
            return (comp, arr)
        }
    }

    private func binding(for status: ItemStatus, comp: Compartment) -> Binding<Bool> {
        let key = "\(status.rawValue)#\(comp.rawValue)"
        return Binding(
            get: { expandedCompartments.contains(key) },
            set: { expanded in
                if expanded { expandedCompartments.insert(key) }
                else { expandedCompartments.remove(key) }
            }
        )
    }

    var body: some View {
        @Bindable var storeBindable = store

        ZStack {
            Color.pantryCream.ignoresSafeArea()

            List {
                inventoryListContent
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
                overflowMenu
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
                ManualEntryView(initialName: manualPrefillName, initialCategory: manualPrefillCategory)
            }
        }
        .onChange(of: showManual) { _, presented in
            if !presented { manualPrefillName = ""; manualPrefillCategory = "" }
        }
        .sheet(isPresented: $showManagePantries) {
            managePantriesSheet
        }
        .sheet(isPresented: $showCreatePantry) {
            createPantrySheet
        }
        .sheet(isPresented: $showInviteMembers) {
            InviteMembersSheet()
        }
        .sheet(isPresented: $showJoinPantry) {
            JoinPantrySheet()
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
            pantrySuggestions = []
            await store.refresh()
        }
        .task(id: filterKey) {
            cachedSections = Self.sections(
                items: store.items,
                archivedIDs: store.archivedIDs,
                searchText: searchText,
                selectedCompartment: selectedCompartment
            )
        }
        .task(id: searchText) {
            let trimmed = searchText.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else { pantrySuggestions = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                pantrySuggestions = try await APIClient.shared.fetchSuggestions(q: trimmed, scope: "pantry")
            } catch {
                pantrySuggestions = []
            }
        }
    }

    // MARK: - Menu overflow (estratto dal body: alleggerisce il type-check)

    private var overflowMenu: some View {
        Menu {
            Button {
                showManual = true
            } label: {
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
                showJoinPantry = true
            } label: {
                Label("Unisciti a una dispensa", systemImage: "link.badge.plus")
            }
            .accessibilityHint("Apri la schermata per unirti a una dispensa con un codice invito")

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
                showCreatePantry = true
            } label: {
                Label("Nuova dispensa", systemImage: "plus")
            }
            .accessibilityHint("Crea una nuova dispensa e la seleziona")
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
        .accessibilityHint("Scegli la dispensa, creala, gestisci l'elenco o elimina quella corrente")
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

    private var createPantrySheet: some View {
        NavigationStack {
            Form {
                Section("Nome dispensa") {
                    TextField("Es. Dispensa estiva", text: $newPantryName)
                        .accessibilityLabel("Nome dispensa")
                        .autocorrectionDisabled()
                    if store.isOffline {
                        Text("Non disponibile offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Nuova dispensa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        showCreatePantry = false
                        newPantryName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        guard !isCreatingPantry else { return }
                        isCreatingPantry = true
                        Task {
                            let name = newPantryName.trimmingCharacters(in: .whitespaces)
                            await store.createPantry(name: name.isEmpty ? "Dispensa" : name)
                            isCreatingPantry = false
                            showCreatePantry = false
                            newPantryName = ""
                        }
                    }
                    .tint(Color.pantryMoss)
                    .disabled(isCreatingPantry || store.isOffline)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            // Sheet chiusa via swipe durante il Task: niente flag bloccato a true.
            .onDisappear { isCreatingPantry = false }
        }
    }

    // MARK: - Suggerimenti dispensa (scope pantry)

    private var pantrySuggestionsSection: some View {
        Section {
            ForEach(pantrySuggestions) { sug in
                pantrySuggestionRow(for: sug)
            }
        } header: {
            Label("Suggerimenti", systemImage: "lightbulb")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.pantryMoss)
                .textCase(nil)
        }
        .listSectionSeparator(.hidden, edges: .bottom)
    }

    private func pantrySuggestionRow(for sug: Suggestion) -> some View {
        Button {
            manualPrefillName = sug.name
            manualPrefillCategory = sug.category ?? ""
            pantrySuggestions = []
            searchText = ""
            showManual = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sug.name)
                        .foregroundStyle(Color.textPrimary)
                        .font(.subheadline.weight(.medium))
                    if let cat = sug.category {
                        Text(CategoryRegistry.displayName(for: cat))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                Text("×\(sug.timesScanned)")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.pantryMoss)
            }
        }
        .accessibilityLabel("\(sug.name), \(sug.timesScanned) scansioni")
        .accessibilityHint("Tocca per inserire \(sug.name) con inserimento manuale")
    }

    // MARK: - Sezioni lista (estratte dal body: alleggeriscono il type-check)

    @ViewBuilder
    private var inventoryListContent: some View {
        // MARK: Compartment filter chips — single source Compartment.supermarketOrder
        Section {
            compartmentFilterBar
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

        if !pantrySuggestions.isEmpty {
            pantrySuggestionsSection
        }

        if groupedItems.isEmpty {
            inventoryEmptySections
        } else {
            ForEach(groupedItems, id: \.0) { status, items in
                statusSection(status: status, items: items)
            }
        }
    }

    @ViewBuilder
    private var inventoryEmptySections: some View {
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
                message: "Prova a cambiare ricerca o filtri."
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private func statusSection(status: ItemStatus, items: [InventoryItem]) -> some View {
        if status == .ok {
            Section {
                ForEach(compartmentGroups(for: items), id: \.0) { compartment, cItems in
                    compartmentGroup(status: status, compartment: compartment, items: cItems)
                }
            }
            .listSectionSeparator(.hidden, edges: .bottom)
        } else {
            Section {
                ForEach(compartmentGroups(for: items), id: \.0) { compartment, cItems in
                    compartmentGroup(status: status, compartment: compartment, items: cItems)
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

    private func compartmentGroup(status: ItemStatus, compartment: Compartment, items: [InventoryItem]) -> some View {
        DisclosureGroup(isExpanded: binding(for: status, comp: compartment)) {
            ForEach(items) { item in
                selectableInventoryRow(for: item)
            }
        } label: {
            compartmentHeader(compartment: compartment, count: items.count)
        }
        .tint(Color.pantryMoss)
    }

    private func compartmentHeader(compartment: Compartment, count: Int) -> some View {
        HStack(spacing: 8) {
            Label(compartment.label, systemImage: compartment.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.pantryMoss)
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.pantryOat.opacity(0.35)))
                .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
                .accessibilityLabel("\(count) prodotti in \(compartment.label)")
        }
        .contentShape(Rectangle())
    }

    // MARK: - Riga selezionabile (estratta dal body: alleggerisce il type-check)

    private func selectableInventoryRow(for item: InventoryItem) -> some View {
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
                    .overlay(Capsule().fill(Color.pantryLinen.opacity(0.35)))
                    .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aggiungi prodotto")
        .accessibilityHint("Scegli tra scansione codice e inserimento manuale")
        .sheet(isPresented: $showAddChoice) {
            addChoiceSheet
        }
        .onChange(of: showAddChoice) { _, isPresented in
            guard !isPresented, let pending = pendingAdd else { return }
            pendingAdd = nil
            switch pending {
            case .scanner:
                showScanner = true
            case .manual:
                showManual = true
            }
        }
    }

    private var addChoiceSheet: some View {
        VStack(spacing: 12) {
            Text("Aggiungi prodotto")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Button {
                pendingAdd = .scanner
                showAddChoice = false
            } label: {
                Label("Scansiona", systemImage: "barcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pantryMoss)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().fill(Color.pantryLinen.opacity(0.35)))
            }
            .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
            .accessibilityLabel("Scansiona codice a barre")
            .accessibilityHint("Apri la camera per scansionare un codice a barre")

            Button {
                pendingAdd = .manual
                showAddChoice = false
            } label: {
                Label("Inserimento manuale", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pantryMoss)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().fill(Color.pantryLinen.opacity(0.35)))
            }
            .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
            .accessibilityLabel("Inserimento manuale")
            .accessibilityHint("Apri il modulo per inserire un prodotto a mano")

            Button("Annulla") { showAddChoice = false }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding()
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .dynamicTypeSize(.xSmall ... .accessibility2)
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

    // MARK: - Compartment filter chips

    private var compartmentFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                compartmentChip(label: "Tutti", isSelected: selectedCompartment == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCompartment = nil
                    }
                }
                .accessibilityLabel("Filtro Tutti")
                .accessibilityHint("Mostra tutti i prodotti senza filtro reparto")
                .accessibilityValue(selectedCompartment == nil ? "Selezionato" : "Non selezionato")
                .accessibilityAddTraits(selectedCompartment == nil ? .isSelected : [])

                ForEach(compartmentOptions, id: \.self) { compartment in
                    let isSelected = selectedCompartment == compartment
                    compartmentChip(label: compartment.label, icon: compartment.icon, isSelected: isSelected) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCompartment = isSelected ? nil : compartment
                        }
                    }
                    .accessibilityLabel("Filtro \(compartment.label)")
                    .accessibilityHint("Filtra la dispensa per reparto \(compartment.label)")
                    .accessibilityValue(isSelected ? "Selezionato" : "Non selezionato")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func compartmentChip(
        label: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Label(label, systemImage: icon)
                } else {
                    Text(label)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.pantryLinen : Color.textPrimary)
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
            // T13: hit target HIG >=44pt; la capsule resta sul contenuto.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Material per non-selected: thinMaterial + PantryCream + PantryOat 0.5
        // Selezionato: PantryMoss primary
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }
}
