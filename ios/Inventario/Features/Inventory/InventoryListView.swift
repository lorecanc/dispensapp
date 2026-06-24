import SwiftUI

struct InventoryListView: View {
    @Environment(InventoryStore.self) private var store
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var showDetailItem: InventoryItem?
    @State private var showScanner = false

    private var filteredItems: [InventoryItem] {
        if searchText.isEmpty {
            return store.items
        }
        return store.items.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
            || ($0.category?.localizedCaseInsensitiveContains(searchText) ?? false)
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

    var body: some View {
        @Bindable var storeBindable = store

        List {
            if groupedItems.isEmpty {
                EmptyStateView()
                    .listRowSeparator(.hidden)
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
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        Task { await store.decrementQuantity(for: item) }
                                    } label: {
                                        Label("Consumato", systemImage: "fork.knife")
                                    }
                                    .tint(.green)
                                }
                        }
                    } header: {
                        Label(status.label, systemImage: status.symbol)
                            .foregroundStyle(status.color)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
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
}
