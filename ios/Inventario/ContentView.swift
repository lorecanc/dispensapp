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
    @State private var showScanner = false

    var body: some View {
        List {
            Button {
                showScanner = true
            } label: {
                Label("Scansiona codice a barre", systemImage: "barcode.viewfinder")
            }
            NavigationLink(destination: ManualEntryView()) {
                Label("Inserimento manuale", systemImage: "pencil")
            }
        }
        .navigationTitle("Aggiungi prodotto")
        .fullScreenCover(isPresented: $showScanner) {
            ScannerViewWrapper()
        }
    }
}
