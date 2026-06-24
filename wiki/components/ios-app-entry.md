---
category: components
title: iOS App Entry Point
last_updated: 2026-06-24
source_files:
  - ios/Inventario/InventarioApp.swift
  - ios/Inventario/ContentView.swift
  - ios/Inventario/State/InventoryStore.swift
---

# iOS App Entry Point

The iOS app entry point is defined in `InventarioApp.swift` and `ContentView.swift`. These files set up the SwiftUI scene, inject the global state container, and define the tab-based navigation structure.

## App Entry Point

`InventarioApp` is the `@main` entry point. It creates a single `InventoryStore` instance as `@State` and passes it down via `.environment(store)`.

```swift
@main
struct InventarioApp: App {
    @State private var store = InventoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
```

`ContentView` retrieves the store through `@Environment(InventoryStore.self)`:

```swift
@Environment(InventoryStore.self) private var store
```

## Tab Navigation

`ContentView` presents a `TabView` with two tabs:

| Tab | Label | Icon | Destination |
|-----|-------|------|-------------|
| 1 | Dispensa | `refrigerator` | `NavigationStack` → [InventoryListView](../components/ios-inventory-list-view.md) |
| 2 | Aggiungi | `plus.circle` | `NavigationStack` → `AddMenuView` |

Both tabs wrap their content in a `NavigationStack` to support push navigation.

## AddMenuView

`AddMenuView` is defined inline in `ContentView.swift`. It presents a `List` with two options for adding a product:

1. **Scansiona codice a barre** — A `Button` with the `barcode.viewfinder` icon. Tapping it sets `showScanner = true`, which presents [ScannerViewWrapper](../components/ios-scanner-view.md) as a `.fullScreenCover`.

2. **Inserimento manuale** — A `NavigationLink` with the `pencil` icon. Tapping it pushes [ManualEntryView](../components/ios-manual-entry-view.md) onto the navigation stack.

The view's navigation title is "Aggiungi prodotto".

```swift
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
```

## InventoryStore

[InventoryStore](../concepts/ios-state-management.md) is an `@Observable`, `@MainActor` class that holds all inventory state and provides methods to interact with the [API client](../concepts/ios-networking.md):

- **Properties**: `items` (sorted by expiration date), `isLoading`, `error`, `exportedMarkdown`
- **Methods**: `refresh()`, `add(...)`, `addManual(...)`, `update(...)`, `delete(id:)`, `decrementQuantity(for:)`, `exportMarkdown()`

The store is injected via `.environment()` at the app root and accessed via `@Environment` in any descendant view.

## Navigation Diagram

```mermaid
graph TD
    InventarioApp -->|.environment(store)| ContentView
    ContentView -->|tab 1| DispensaTab["Dispensa Tab"]
    ContentView -->|tab 2| AggiungiTab["Aggiungi Tab"]

    DispensaTab --> NavigationStack1["NavigationStack"]
    NavigationStack1 --> InventoryListView

    AggiungiTab --> NavigationStack2["NavigationStack"]
    NavigationStack2 --> AddMenuView

    AddMenuView --> ScanButton["Button: Scansiona codice a barre"]
    AddMenuView --> ManualLink["NavigationLink: Inserimento manuale"]

    ScanButton -->|fullScreenCover| ScannerViewWrapper
    ManualLink --> ManualEntryView
```

The app uses a simple two-tab layout: the *Dispensa* (pantry) tab lists all items, and the *Aggiungi* (add) tab provides two entry methods — barcode scanning or manual form input.
