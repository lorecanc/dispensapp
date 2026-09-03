import SwiftUI

struct ShoppingListView: View {
    @Environment(InventoryStore.self) private var pantryStore
    @State private var store = ShoppingStore()
    @State private var newItemName = ""
    @State private var newItemQuantity = 1
    @State private var suggestionQuery = ""
    @State private var showMarkdownSheet = false
    @State private var showCreateListSheet = false
    @State private var newListName = ""
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
        @Bindable var storeBindable = store

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
                        .listRowInsets(EdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0))

                        Button {
                            showCreateListSheet = true
                        } label: {
                            Label("Crea lista Spesa", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(Color.pantryMoss)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    // Lista selector se più liste
                    if store.lists.count > 1 {
                        Section {
                            Picker("Lista", selection: $storeBindable.selectedListId) {
                                ForEach(store.lists) { list in
                                    Text(list.name).tag(Optional(list.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(Color.pantryMoss)
                        }
                        .listRowBackground(Color.clear)
                    }

                    // Add item form — solo nome + quantità, senza Picker comparto
                    Section {
                        addItemSection
                    } header: {
                        Label("Aggiungi prodotto", systemImage: "plus.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.pantryMoss)
                            .textCase(nil)
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
                                    Task { await store.addItem(name: sug.name, quantity: newItemQuantity, compartment: inferred) }
                                    newItemName = ""
                                    suggestionQuery = ""
                                    store.suggestions = []
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
                                                    Task { await store.deleteItem(itemId: item.id) }
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

                    // Markdown preview card — riflette nuovi headings ## 🥬 Ortofrutta etc. dal backend
                    if let md = store.exportedMarkdown {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(md)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Color.textPrimary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(.thinMaterial)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .strokeBorder(Color.borderTerra, lineWidth: 0.5)
                                            )
                                    }

                                ShareLink(item: md, preview: SharePreview("Lista Spesa", image: Image(systemName: "cart"))) {
                                    Label("Condividi markdown", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.pantryMoss)
                            }
                            .pantryCardBackground(cornerRadius: 14)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            Label("Export Markdown", systemImage: "doc.text")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.pantryMoss)
                                .textCase(nil)
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
        .navigationTitle("Spesa")
        .searchable(text: $suggestionQuery, prompt: "Cerca suggerimenti...")
        .refreshable {
            await store.fetchLists()
            await store.checkInPantry()
        }
        .overlay(alignment: .top) {
            if let error = store.error {
                ErrorBanner(message: error.localizedDescription) {
                    store.error = nil
                }
            }
        }
        .toolbar {
            // T6: picker pantry in header, selezione condivisa via @Environment.
            ToolbarItem(placement: .topBarLeading) {
                pantryPickerMenu
            }
            // Unico Menu overflow puntini.
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        Task { await store.checkInPantry() }
                    } label: {
                        Label("Verifica dispensa", systemImage: "checkmark.shield")
                    }
                    Button {
                        Task {
                            await store.exportMarkdown()
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
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await store.checkInPantry() }
                } label: {
                    Image(systemName: "checkmark.shield")
                }
                .tint(Color.pantryMoss)
            }
        }
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: pantryStore.selectedPantryId) {
            // Single source pantry via @Environment; replica locale sincronizzata.
            store.selectPantry(pantryStore.selectedPantryId)
            await store.fetchLists()
            await store.checkInPantry()
        }
        .task(id: suggestionQuery) {
            if suggestionQuery.trimmingCharacters(in: .whitespaces).count < 2 {
                store.suggestions = []
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            await store.fetchSuggestions(q: suggestionQuery)
        }
        .sheet(isPresented: $showMarkdownSheet) {
            markdownSheet
        }
        .sheet(isPresented: $showCreateListSheet) {
            createListSheet
        }
    }

    // MARK: - Add item form (solo nome + quantità)

    // T6: picker pantry in header (personale/condivise), binding su store @Environment.
    private var pantryPickerMenu: some View {
        @Bindable var pantryStoreBindable = pantryStore
        return Menu {
            Picker("Dispensa", selection: $pantryStoreBindable.selectedPantryId) {
                ForEach(pantryStore.pantries) { pantry in
                    Text(pantry.name).tag(pantry.id)
                }
            }
        } label: {
            Label(pantryStore.selectedPantryName, systemImage: "house")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.pantryMoss)
                .lineLimit(1)
        }
        .tint(Color.pantryMoss)
        .accessibilityLabel("Seleziona dispensa")
        .accessibilityHint("Scegli tra dispensa personale e condivise")
    }

    private var addItemSection: some View {
        VStack(spacing: 12) {
            TextField("Nome prodotto", text: $newItemName)
                .autocorrectionDisabled()
                .onChange(of: newItemName) { _, new in
                    if new.count >= 2 { suggestionQuery = new }
                }

            HStack(spacing: 12) {
                QuantityStepper(quantity: $newItemQuantity)
                Spacer()
            }

            Button {
                Task {
                    guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let trimmed = newItemName.trimmingCharacters(in: .whitespaces)
                    // Nessun Picker comparto: inferenza lato backend/cliente da nome
                    await store.addItem(name: trimmed, quantity: newItemQuantity, compartment: nil)
                    newItemName = ""
                    suggestionQuery = ""
                }
            } label: {
                Label("Aggiungi", systemImage: "plus.circle.fill")
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

    // MARK: - Row

    private func shoppingRow(item: ShoppingListItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await store.toggleChecked(item: item) }
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

            pantryCheckBadge(for: item)

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
                Task { await store.toggleChecked(item: item) }
            } label: {
                Label(item.checked ? "Segna da acquistare" : "Segna completato", systemImage: item.checked ? "square" : "checkmark.square")
            }
            .accessibilityLabel(item.checked ? "Segna da acquistare \(item.name)" : "Segna completato \(item.name)")
            Button(role: .destructive) {
                Task { await store.deleteItem(itemId: item.id) }
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
        if let check = store.pantryChecks[item.id] {
            if !check.inPantry { parts.append("Da comprare") }
            else if check.status == "expired" { parts.append("Scaduto") }
            else if check.status == "expiring_soon" { parts.append("In scadenza") }
            else { parts.append("In dispensa") }
        }
        parts.append(item.checked ? "segnato" : "non segnato")
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func pantryCheckBadge(for item: ShoppingListItem) -> some View {
        if let check = store.pantryChecks[item.id] {
            if !check.inPantry {
                Label("Da comprare", systemImage: "cart.badge.questionmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.pantryStone)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.pantryStone.opacity(0.14))
                            .overlay(Capsule().fill(.thinMaterial).opacity(0.35))
                    }
                    .overlay(Capsule().strokeBorder(Color.pantryStone.opacity(0.28), lineWidth: 0.5))
                    .accessibilityLabel("Da comprare")
                    .accessibilityHint("Prodotto non presente in dispensa")
            } else if check.status == "expiring_soon" || check.status == "expired" {
                Label(check.status == "expired" ? "Scaduto" : "In scadenza", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.statusSoon)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.statusSoon.opacity(0.14))
                            .overlay(Capsule().fill(.thinMaterial).opacity(0.35))
                    }
                    .overlay(Capsule().strokeBorder(Color.statusSoon.opacity(0.28), lineWidth: 0.5))
                    .accessibilityLabel(check.status == "expired" ? "Scaduto in dispensa" : "In scadenza in dispensa")
                    .accessibilityHint("Prodotto presente ma vicino alla scadenza")
            } else {
                Label("In dispensa", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.statusFresh)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.statusFresh.opacity(0.14))
                            .overlay(Capsule().fill(.thinMaterial).opacity(0.35))
                    }
                    .overlay(Capsule().strokeBorder(Color.statusFresh.opacity(0.28), lineWidth: 0.5))
                    .accessibilityLabel("In dispensa")
                    .accessibilityHint("Prodotto già presente e fresco")
            }
        }
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
                            await store.createList(name: name.isEmpty ? "Spesa" : name)
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
