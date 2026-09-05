---
title: "iOS App Entry Point"
description: "App entry, tab navigation, and inventario:// deep-link invite flow"
category: "components"
source_files:
  - ios/Inventario/InventarioApp.swift
  - ios/Inventario/ContentView.swift
  - ios/Inventario/State/InventoryStore.swift
  - ios/Inventario/Info.plist
created: "2026-06-24"
last_updated: "2026-09-05"
---

# iOS App Entry Point

The iOS app entry point is defined in `InventarioApp.swift` and `ContentView.swift`. These files set up the SwiftUI scene, inject the global state container, define the tab-based navigation structure, and handle the `inventario://` deep-link invite flow.

## App Entry Point

`InventarioApp` is the `@main` entry point. It creates a single `InventoryStore` instance as `@State`, passes it down via `.environment(store)`, and holds transient `pendingInviteToken` state for the invite confirmation dialog.

```swift
@main
struct InventarioApp: App {
    @State private var store = InventoryStore()
    @State private var pendingInviteToken: String?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .onOpenURL { url in
                    if let token = Self.inviteToken(from: url) {
                        pendingInviteToken = token
                    } else {
                        pendingInviteToken = nil
                    }
                }
                .confirmationDialog(
                    "Unirti alla dispensa condivisa?",
                    isPresented: Binding(
                        get: { pendingInviteToken != nil },
                        set: { if !$0 { pendingInviteToken = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Unisciti") {
                        if let token = pendingInviteToken {
                            pendingInviteToken = nil
                            Task { await store.acceptInviteToken(token) }
                        }
                    }
                    Button("Annulla", role: .cancel) {
                        pendingInviteToken = nil
                    }
                } message: {
                    Text("La dispensa condivisa verrà aggiunta al tuo elenco.")
                }
        }
    }
}
```

`ContentView` retrieves the store through `@Environment(InventoryStore.self)`:

```swift
@Environment(InventoryStore.self) private var store
```

## Deep-Link Invite Flow

The `inventario` URL scheme is registered in `Info.plist` via `CFBundleURLTypes`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>inventario</string>
        </array>
    </dict>
</array>
```

Incoming URLs are handled with `.onOpenURL` on the root view (see [Invite Members Sheet](../components/ios-invite-members-sheet.md) and [Pantry Sharing](../concepts/pantry-sharing.md)). `inviteToken(from:)` parses and validates the token in two steps:

1. **Query item:** `?token=<value>` (trimmed of whitespace/newlines).
2. **Fallback:** last path component (e.g. `inventario://invite/<token>`), ignoring `/` separators and a bare `invite` segment.

Both paths are validated by `isValidInviteToken(_:)` against `^[A-Za-z0-9_-]{20,64}$`. Invalid scheme, missing token, or failed validation returns `nil` and clears `pendingInviteToken`.

When a valid token is found, it is stored in `pendingInviteToken`, which drives a `confirmationDialog` ("Unirti alla dispensa condivisa?"). Tapping "Unisciti" clears the pending state and calls `Task { await store.acceptInviteToken(token) }`; "Annulla" (cancel role) just clears the pending state.

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
- **Methods**: `refresh()`, `add(...)`, `addManual(...)`, `update(...)`, `delete(id:)`, `decrementQuantity(for:)`, `exportMarkdown()`, `acceptInviteToken(_:)`

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

    InventarioURL["inventario:// URL"] -->|onOpenURL| inviteToken["inviteToken(from:)"]
    inviteToken -->|valid| pendingInviteToken["pendingInviteToken"]
    pendingInviteToken -->|confirmationDialog| acceptInviteToken["store.acceptInviteToken(token)"]
```

The app uses a simple two-tab layout: the *Dispensa* (pantry) tab lists all items, and the *Aggiungi* (add) tab provides two entry methods — barcode scanning or manual form input. Shared-pantry invites arrive via `inventario://` deep link, are validated locally, confirmed by the user, then accepted through the store.
