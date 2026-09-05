import SwiftUI

/// Picker di categoria a 2 livelli (T10): riga nel form che apre una sheet con
/// `List` a sezioni, una sezione per reparto nel canonico ordine supermarketOrder
/// di `Compartment` (icone riutilizzate da ShoppingModels). Un `Picker`/`Menu`
/// piatto con 26 opzioni non scala.
///
/// L'interfaccia pubblica resta `CategoryPicker(selection:)`: i call site
/// (ScanPreviewSheet, ManualEntryView), che lo usano in una Section di Form,
/// non cambiano.
struct CategoryPicker: View {
    @Binding var selection: String

    @State private var showCategoryList = false

    /// Letto dal registry a ogni render: prima era uno stored property catturato
    /// a init, quindi stale dopo `CategoryRegistry.update(with:)`.
    private var categories: [(key: String, label: String)] {
        CategoryRegistry.categories
    }

    /// Forwarded for backward compatibility — single source is CategoryRegistry.
    /// Computed: un `static let` freeze il valore al primo accesso.
    static var validCategoryKeys: Set<String> { CategoryRegistry.validCategoryKeys }

    var body: some View {
        Button {
            showCategoryList = true
        } label: {
            HStack {
                Text("Categoria")
                Spacer()
                Text(selectedLabel)
                    .foregroundStyle(Color.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Categoria")
        .accessibilityValue(selectedLabel)
        .accessibilityHint("Apri l'elenco delle categorie raggruppate per reparto")
        .sheet(isPresented: $showCategoryList) {
            categorySheet
        }
    }

    private var selectedLabel: String {
        selection.isEmpty ? "Nessuna" : CategoryRegistry.displayName(for: selection)
    }

    // MARK: - Sheet a sezioni

    private var grouped: [(compartment: String, rows: [(key: String, label: String)])] {
        Self.groupedRows(
            categories: categories,
            compartmentMap: CategoryRegistry.compartmentMap,
            order: Compartment.supermarketOrder.map(\.rawValue)
        )
    }

    private var categorySheet: some View {
        NavigationStack {
            List {
                // Voce per deselezionare (selection = "").
                Section {
                    categoryRow(key: "", label: "Nessuna")
                }
                ForEach(grouped, id: \.compartment) { group in
                    Section {
                        ForEach(group.rows, id: \.key) { category in
                            categoryRow(key: category.key, label: category.label)
                        }
                    } header: {
                        compartmentHeader(group.compartment)
                    }
                }
            }
            .navigationTitle("Categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { showCategoryList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Riga standard List (hit target nativo ≥44pt): tocca -> seleziona e chiudi.
    private func categoryRow(key: String, label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if selection == key {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.pantryMoss)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == key ? [.isButton, .isSelected] : .isButton)
        .onTapGesture {
            selection = key
            showCategoryList = false
        }
        // VoiceOver: .onTapGesture non espone un'azione Activate nativa; questa
        // replica la stessa azione del tap (seleziona e chiudi la sheet).
        .accessibilityAction {
            selection = key
            showCategoryList = false
        }
    }

    // Icone dai reparti noti (ShoppingModels): nessun simbolo nuovo.
    // I reparti sconosciuti (categorie server non mappate) hanno header solo testo.
    @ViewBuilder
    private func compartmentHeader(_ name: String) -> some View {
        if let compartment = Compartment(rawValue: name) {
            Label(compartment.label, systemImage: compartment.icon)
        } else {
            Text(name)
        }
    }

    // MARK: - Raggruppamento puro (testato in T14)

    /// Raggruppa le categorie per reparto nell'ordine canonico `order`.
    /// Le categorie senza mappa (o con reparto non in `order`) finiscono in
    /// "Altro"/al fondo in ordine alfabetico: nessuna categoria sparisce mai.
    static func groupedRows(
        categories: [(key: String, label: String)],
        compartmentMap: [String: String],
        order: [String]
    ) -> [(compartment: String, rows: [(key: String, label: String)])] {
        var buckets: [String: [(key: String, label: String)]] = [:]
        for category in categories {
            let compartment = compartmentMap[category.key] ?? fallbackCompartment
            buckets[compartment, default: []].append(category)
        }
        let ordered = order.compactMap { name -> (compartment: String, rows: [(key: String, label: String)])? in
            buckets[name].map { (compartment: name, rows: $0) }
        }
        let extras = buckets.keys
            .filter { !order.contains($0) }
            .sorted()
            .compactMap { name -> (compartment: String, rows: [(key: String, label: String)])? in
                buckets[name].map { (compartment: name, rows: $0) }
            }
        return ordered + extras
    }

    private static let fallbackCompartment = "Altro"
}
