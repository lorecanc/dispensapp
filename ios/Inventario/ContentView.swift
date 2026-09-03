import SwiftUI

struct ContentView: View {
    @Environment(InventoryStore.self) private var store

    var body: some View {
        tabContent
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 26.0, *) {
            TabView {
                Tab("Dispensa", systemImage: "refrigerator") {
                    NavigationStack {
                        InventoryListView()
                    }
                }
                Tab("Aggiungi", systemImage: "plus.circle") {
                    NavigationStack {
                        AddMenuView()
                    }
                }
                Tab("Spesa", systemImage: "cart") {
                    NavigationStack {
                        ShoppingListView()
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .tabBarMinimizeBehavior(.onScrollDown)
        } else if #available(iOS 18.0, *) {
            TabView {
                Tab("Dispensa", systemImage: "refrigerator") {
                    NavigationStack {
                        InventoryListView()
                    }
                }
                Tab("Aggiungi", systemImage: "plus.circle") {
                    NavigationStack {
                        AddMenuView()
                    }
                }
                Tab("Spesa", systemImage: "cart") {
                    NavigationStack {
                        ShoppingListView()
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
        } else {
            TabView {
                NavigationStack {
                    InventoryListView()
                }
                .tabItem {
                    Label("Dispensa", systemImage: "refrigerator")
                }

                NavigationStack {
                    AddMenuView()
                }
                .tabItem {
                    Label("Aggiungi", systemImage: "plus.circle")
                }

                NavigationStack {
                    ShoppingListView()
                }
                .tabItem {
                    Label("Spesa", systemImage: "cart")
                }
            }
        }
    }
}

struct AddMenuView: View {
    @Environment(InventoryStore.self) private var store
    @State private var showScanner = false

    var body: some View {
        @Bindable var storeBindable = store

        ZStack {
            Color.pantryCream.ignoresSafeArea()

            List {
                Section {
                    VStack(spacing: 12) {
                        Text("Aggiungi un prodotto scansionando il barcode oppure inserendolo a mano.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showScanner = true
                        } label: {
                            Label("Scansiona codice a barre", systemImage: "barcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.pantryMoss)

                        NavigationLink(destination: ManualEntryView()) {
                            Label("Inserimento manuale", systemImage: "pencil")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.pantryMoss)
                        .foregroundStyle(Color.textPrimary)
                    }
                    .padding(12)
                    .pantryCardBackground(cornerRadius: 14)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } header: {
                    Label("Aggiungi prodotto", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.pantryMoss)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden, edges: .bottom)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.pantryCream)
            .listSectionSpacing(12)
            .tint(Color.pantryOat)
        }
        .overlay(alignment: .top) {
            if let error = store.error {
                ErrorBanner(message: error.localizedDescription) {
                    storeBindable.error = nil
                }
            }
        }
        .pantryToolbarGlass()
        .navigationTitle("Aggiungi prodotto")
        .dynamicTypeSize(.xSmall ... .accessibility2)
        .fullScreenCover(isPresented: $showScanner) {
            ScannerViewWrapper()
        }
    }
}
