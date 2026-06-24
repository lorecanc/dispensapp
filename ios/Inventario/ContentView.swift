import SwiftUI

struct ContentView: View {
    @Environment(InventoryStore.self) private var store

    var body: some View {
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
