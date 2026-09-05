import SwiftUI

struct ShoppingListView: View {
    @Environment(InventoryStore.self) private var pantryStore
    @State private var store = ShoppingStore()
    @State private var newItemName = ""
    @State private var newItemQuantity = 1
    @State private var suggestionQuery = ""
    @State private var showMarkdownSheet = false
    @State private var showCreateListSheet = false
    @State private var showManageListsSheet = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteList: ShoppingList?
    @State private var newListName = ""
    @State private var isAddExpanded = false
    @State private var expandedCompartments: Set<String> = Set(Compartment.supermarketOrder.map(\.rawValue))

    // Raggruppamento per comparto inferito (se item ha compartment salvato usalo, altrimenti inferisci da nome)
    private var groupedItems: [(Compartment, [ShoppingListItem])] {
        guard let items = store.selectedList?.items else { return [] }
        let grouped = Dictionary(grouping: items) { item in
            Compartment.resolved(for: item)
        }
        return Compartment.supermarketOrder.compactMap { comp in
            guard let arr = grouped[comp], !arr.isEmpty else { return nil }
            return (comp, arr)
        }
    }

    private func isExpanded(_ comp: Compartment) -> Bool {
        expandedCompartments.contains(comp.rawValue)
    }

    private func binding(for comp: Compartment) -> Binding<Bool> {
        Binding(
            get: { expandedCompartments.contains(comp.rawValue) },
            set: { expanded in
                if expanded { expandedCompartments.insert(comp.rawValue) }
                else { expandedCompartments.remove(comp.rawValue) }
            }
        )
    }

    var body: some View {
        ZStack {
            Color.pantryCream.ignoresSafeArea()

            List {
                if store.lists.isEmpty && !store.isLoading {
                    Section {
                        EmptyStateView(
                            imageName: "cart",
                            title: "Nessuna lista",
                            message: "Crea la tua prima lista della spesa."
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                        Button {
                            showCreateListSheet = true
                        } label: {
                            Label("Crea lista Spesa", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(Color.pantryMoss)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } else {
                    // Add item: pill disclosure + card espandibile, add diretto su Invio
                    Section {
                        VStack(spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isAddExpanded.toggle()
                                }
                            } label: {
                                HStack {
                                    Label("Aggiungi prodotto", systemImage: "plus.circle")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.pantryMoss)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.pantryMoss)
                                        .rotationEffect(.degrees(isAddExpanded ? 180 : 0))
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
                            .accessibilityLabel(isAddExpanded ? "Comprimi aggiunta prodotto" : "Espandi aggiunta prodotto")
                            .accessibilityValue(isAddExpanded ? "Espansa" : "Compressa")
                            .accessibilityHint("Tocca per espandere o comprimere il modulo di aggiunta")

                            if isAddExpanded {
                                addItemSection
                                    .padding(12)
                                    .pantryCardBackground(cornerRadius: 14)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .listSectionSeparator(.hidden, edges: .bottom)

                    // Suggestions (debounced)
                    if !store.suggestions.isEmpty {
                        Section {
                            ForEach(store.suggestions) { sug in
                                Button {
                                    newItemName = sug.name
                                    suggestionQuery = sug.name
                                    // Inferisci comparto da categoria se disponibile, altrimenti da nome
                                    let inferred: String? = {
                                        if let cat = sug.category {
                                            return Compartment.inferCompartment(fromCategory: cat).rawValue
                                        }
                                        return Compartment.inferCompartment(fromName: sug.name).rawValue
                                    }()
                                    Task {
                                        await store.addItem(pantryId: pantryStore.selectedPantryId, name: sug.name, quantity: newItemQuantity, compartment: inferred)
                                        if store.error == nil {
                                            newItemName = ""
                                            suggestionQuery = ""
                                            store.suggestions = []
                                        }
                                    }
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
                            }
                        } header: {
                            Label("Suggerimenti", systemImage: "lightbulb")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.pantryMoss)
                                .textCase(nil)
                        }
                        .listSectionSeparator(.hidden, edges: .bottom)
                    }

                    // Gruppi per comparto — DisclosureGroup collassabili (default expanded)
                    if let selected = store.selectedList, selected.items.isEmpty {
                        Section {
                            Text("Lista vuota — aggiungi prodotti sopra.")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    } else {
                        ForEach(groupedItems, id: \.0) { compartment, items in
                            Section {
                                DisclosureGroup(isExpanded: binding(for: compartment)) {
                                    ForEach(items) { item in
                                        shoppingRow(item: item)
                                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button(role: .destructive) {
                                                    Task { await store.deleteItem(pantryId: pantryStore.selectedPantryId, itemId: item.id) }
                                                } label: {
                                                    Label("Elimina", systemImage: "trash")
                                                }
                                                .tint(Color.statusExpired)
                                                .accessibilityLabel("Elimina \(item.name) dalla spesa")
                                                .accessibilityHint("Rimuove il prodotto dalla lista della spesa")
                                            }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Label(compartment.label, systemImage: compartment.icon)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.pantryMoss)
                                        Spacer()
                                        Text("\(items.count)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color.textSecondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.pantryOat.opacity(0.35)))
                                            .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))
                                            .accessibilityLabel("\(items.count) prodotti in \(compartment.label)")
                                    }
                                    .contentShape(Rectangle())
                                }
                                .tint(Color.pantryMoss)
                            } header: {
                                // Header vuoto: label dentro DisclosureGroup già mostra comparto + count
                                EmptyView()
                            }
                            .listSectionSeparator(.hidden, edges: .bottom)
                        }
                    }

                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.pantryCream)
            .listSectionSpacing(12)
            .tint(Color.pantryOat)
        }
        .navigationTitle(store.selectedList?.name ?? "Spesa")
        .searchable(text: $suggestionQuery, prompt: "Cerca suggerimenti...")
        .refreshable {
            await store.fetchLists(pantryId: pantryStore.selectedPantryId)
        }
        .overlay(alignment: .top) {
            if let error = store.error {
                BannerView(message: error.localizedDescription, style: .error, autoDismiss: true) {
                    store.error = nil
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                listManagementMenu
            }
            // Unico Menu overflow (nessun duplicato).
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task {
                            await store.exportMarkdown(pantryId: pantryStore.selectedPantryId)
                            showMarkdownSheet = true
                        }
                    } label: {
                        Label("Esporta markdown", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showCreateListSheet = true
                    } label: {
                        Label("Nuova lista", systemImage: "plus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(Color.pantryMoss)
                .accessibilityLabel("Altre azioni spesa")
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: pantryStore.selectedPantryId) {
            // Single source pantry via @Environment; ShoppingStore non ha stato proprio.
            await store.fetchLists(pantryId: pantryStore.selectedPantryId)
        }
        .task(id: suggestionQuery) {
            if suggestionQuery.trimmingCharacters(in: .whitespaces).count < 2 {
                store.suggestions = []
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await store.fetchSuggestions(q: suggestionQuery)
        }
        .sheet(isPresented: $showMarkdownSheet) {
            markdownSheet
        }
        .sheet(isPresented: $showManageListsSheet) {
            manageListsSheet
        }
        .sheet(isPresented: $showCreateListSheet) {
            createListSheet
        }
    }

    // MARK: - Add item form (solo nome + quantità)

    // Gestione liste: Picker nel Menu leading + sheet di gestione (tap nome).
    private var listManagementMenu: some View {
        @Bindable var storeBindable = store
        return Menu {
            Picker("Lista", selection: $storeBindable.selectedListId) {
                ForEach(store.lists) { list in
                    Text(list.name).tag(Optional(list.id))
                }
            }
            Divider()
            Button {
                showManageListsSheet = true
            } label: {
                Label("Gestisci liste", systemImage: "list.bullet")
            }
            Button {
                showCreateListSheet = true
            } label: {
                Label("Nuova lista", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.selectedList?.name ?? "Spesa")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.pantryMoss)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pantryMoss)
            }
            .contentShape(Rectangle())
        }
        .tint(Color.pantryMoss)
        .accessibilityLabel("Gestisci liste della spesa")
        .accessibilityHint("Cambia lista attiva o gestisci le liste")
        .accessibilityValue(store.selectedList?.name ?? "Spesa")
    }

    private var addItemSection: some View {
        VStack(spacing: 12) {
            TextField("Nome prodotto", text: $newItemName, prompt: Text("Es. Pasta"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityHint("Invio per aggiungere")
                .onSubmit {
                    Task {
                        guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
                        await store.addItem(pantryId: pantryStore.selectedPantryId, name: trimmed, quantity: newItemQuantity, compartment: nil)
                        if store.error == nil {
                            newItemName = ""
                            suggestionQuery = ""
                            store.suggestions = []
                        }
                    }
                }
                .onChange(of: newItemName) { _, new in
                    if new.count >= 2 { suggestionQuery = new }
                }

            HStack(spacing: 12) {
                QuantityStepper(quantity: $newItemQuantity)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Row

    private func shoppingRow(item: ShoppingListItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.toggleChecked(pantryId: pantryStore.selectedPantryId, item: item) }
            } label: {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(item.checked ? Color.pantryMoss : Color.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked ? "Segnato: \(item.name)" : "Non segnato: \(item.name)")
            .accessibilityValue(item.checked ? "Completato" : "Da acquistare")
            .accessibilityHint("Tocca per segnare come \(item.checked ? "da acquistare" : "completato")")
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.checked ? Color.textSecondary : Color.textPrimary)
                    .strikethrough(item.checked, color: Color.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("×\(item.quantity)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(Color.pantryOat.opacity(0.35))
                        }
                        .overlay(Capsule().strokeBorder(Color.pantryOat, lineWidth: 0.5))

                    // Badge comparto inferito (non editabile)
                    Text(Compartment.resolved(for: item).label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer(minLength: 8)

            if item.checked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.pantryMoss.opacity(0.6))
                    .font(.caption)
            }
        }
        .padding(12)
        .pantryCardBackground(cornerRadius: 14)
        .opacity(item.checked ? 0.75 : 1)
        .contextMenu {
            Button {
                Task { await store.toggleChecked(pantryId: pantryStore.selectedPantryId, item: item) }
            } label: {
                Label(item.checked ? "Segna da acquistare" : "Segna completato", systemImage: item.checked ? "square" : "checkmark.square")
            }
            .accessibilityLabel(item.checked ? "Segna da acquistare \(item.name)" : "Segna completato \(item.name)")
            Button(role: .destructive) {
                Task { await store.deleteItem(pantryId: pantryStore.selectedPantryId, itemId: item.id) }
            } label: {
                Label("Elimina", systemImage: "trash")
            }
            .accessibilityLabel("Elimina \(item.name)")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(shoppingRowAccessibilityLabel(for: item))
        .accessibilityValue(item.checked ? "Completato, quantità \(item.quantity)" : "Da acquistare, quantità \(item.quantity)")
        .accessibilityHint("Tocca la casella per cambiare stato, scorri per eliminare")
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    private func shoppingRowAccessibilityLabel(for item: ShoppingListItem) -> String {
        var parts = [item.name, "quantità \(item.quantity)"]
        parts.append(Compartment.resolved(for: item).label)
        parts.append(item.checked ? "segnato" : "non segnato")
        return parts.joined(separator: ", ")
    }

    // MARK: - Sheets

    private var markdownSheet: some View {
        NavigationStack {
            ScrollView {
                if let md = store.exportedMarkdown {
                    Text(md)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                        .padding()
                }
            }
            .background(Color.pantryCream)
            .navigationTitle("Markdown Spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { showMarkdownSheet = false }
                }
                if let md = store.exportedMarkdown {
                    ToolbarItem(placement: .confirmationAction) {
                        ShareLink(item: md, preview: SharePreview("Lista Spesa")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(Color.pantryMoss)
                    }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    private var manageListsSheet: some View {
        NavigationStack {
            List {
                Section("Liste") {
                    ForEach(store.lists) { list in
                        HStack {
                            Button {
                                store.selectedListId = list.id
                            } label: {
                                HStack {
                                    Text(list.name)
                                        .foregroundStyle(Color.textPrimary)
                                    Spacer()
                                    if store.selectedListId == list.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.pantryMoss)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Seleziona lista \(list.name)")
                            Button(role: .destructive) {
                                pendingDeleteList = list
                                showDeleteConfirm = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .tint(Color.statusExpired)
                            .accessibilityLabel("Elimina lista \(list.name)")
                        }
                    }
                }
            }
            .navigationTitle("Gestisci liste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { showManageListsSheet = false }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .confirmationDialog(
                "Elimina lista?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Elimina", role: .destructive) {
                    if let list = pendingDeleteList {
                        Task {
                            await store.deleteShoppingList(pantryId: pantryStore.selectedPantryId, id: list.id)
                        }
                        pendingDeleteList = nil
                    }
                }
                Button("Annulla", role: .cancel) { pendingDeleteList = nil }
            } message: {
                Text("La lista verrà eliminata definitivamente.")
            }
        }
    }

    private var createListSheet: some View {
        NavigationStack {
            Form {
                Section("Nome lista") {
                    TextField("Es. Spesa settimanale", text: $newListName)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Nuova lista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        showCreateListSheet = false
                        newListName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crea") {
                        Task {
                            let name = newListName.trimmingCharacters(in: .whitespaces)
                            await store.createList(pantryId: pantryStore.selectedPantryId, name: name.isEmpty ? "Spesa" : name)
                            showCreateListSheet = false
                            newListName = ""
                        }
                    }
                    .tint(Color.pantryMoss)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}
