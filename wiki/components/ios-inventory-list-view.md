---
title: "InventoryListView"
description: "Main pantry list view — pantry picker, category chips, consume/delete actions, history sheet, and offline handling"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/InventoryListView.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# InventoryListView

## Purpose

`InventoryListView` is the primary screen of the Dispensa tab. It shows the selected pantry's items grouped by `ItemStatus` (`.ok`, `.expiringSoon`, `.expired`), with search, category filter chips, swipe-to-consume / swipe-to-delete, pull-to-refresh, an add-product pill, a pantry picker menu, and sheets for item detail, history (Storico), pantry management, scanner, and manual entry.

`ContentView` hosts it in a two-tab `TabView` (Dispensa / Spesa). There is no Add tab; adding happens in-list via the add-pill (`ios/Inventario/ContentView.swift`).

## Props / Interface

`InventoryListView` takes no init props. All inputs are `@Environment` / `@State`:

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `store` | `InventoryStore` (`@Environment`) | yes | Source of `items`, `pantries`, `selectedPantryId`, `selectedPantryName`, `archivedIDs`, `history`, `isOffline`, `error` |
| `searchText` | `String` (`@State`) | no | Drives `.searchable` client-side filter on name/brand/category |
| `selectedCategory` | `String?` (`@State`) | no | Category chip filter, options from `CategoryRegistry.categories` |
| `showDetailItem` | `InventoryItem?` (`@State`) | no | Presents `ItemDetailView` sheet on row tap |
| `showScanner` / `showManual` / `showAddChoice` | `Bool` (`@State`) | no | Add flow: `addProductPill` → confirmation dialog (Scansiona / Inserimento manuale) → `ScannerViewWrapper` or `ManualEntryView` sheet |
| `showHistorySheet` | `Bool` (`@State`) | no | Presents Storico history sheet (medium/large detents) from overflow menu |
| `showManagePantries` / `showDeletePantryConfirm` / `pendingDeletePantry` | state | no | Pantry management sheet + delete confirmation dialogs |
| `showSettings` / `showInviteMembers` | `Bool` (`@State`) | no | Presents `SettingsView` / `InviteMembersSheet` from overflow menu |
| `cachedSections` / `filterKey` | derived state | no | Cached `[(ItemStatus, [InventoryItem])]` recomputed in `.task(id: filterKey)` from items fingerprint + search + category + `archivedIDs` |

Key store calls: `store.refresh()`, `store.fetchPantries()`, `store.selectPantry(_:)`, `store.deletePantry(id:)`, `store.delete(id:)`, `store.consume(item:)` (atomic server-side), `store.fetchHistory(itemId:)`, `store.exportMarkdown()`.

## Usage

Hosted inside a `NavigationStack` in `ContentView`:

```swift
Tab("Dispensa", systemImage: "refrigerator") {
    NavigationStack {
        InventoryListView()
    }
}
```

Header: `navigationTitle` is `store.selectedPantryName`. Leading toolbar is `pantryPickerMenu` (Picker over `store.pantries` + "Gestisci dispense" sheet + "Elimina dispensa" confirm). Trailing toolbar is a scanner button plus a single `ellipsis.circle` overflow `Menu` (Inserimento manuale, Invita membri, Impostazioni, Storico, Esporta dispensa).

Body sections in the `List`:

- `categoryFilterBar`: horizontal chips (Tutti + `CategoryRegistry`), toggle `selectedCategory`.
- `addProductPill`: capsule button opening the Scansiona/Manuale choice dialog.
- Status sections: `ForEach(groupedItems)` with `Label(status.label, systemImage: status.symbol)` headers; rows are `InventoryRowView` with leading consume (`fork.knife`, `store.consume`) and trailing delete (`trash`, `store.delete`) swipe actions (`allowsFullSwipe: false`) plus matching `contextMenu` items.
- Empty states: `EmptyStateView()` when the pantry is empty, `EmptyStateView(magnifyingglass / Nessun risultato)` when filters match nothing.
- Overlay (top): `OfflinePill()` when `store.isOffline` (see [iOS Offline Outbox](../concepts/ios-offline-outbox.md)), unified `BannerView(style: .error, autoDismiss: true)` when `store.error != nil`.

Storico (`historySheet`): `NavigationStack` sheet listing `store.archivedIDs` with per-item `store.history[id]` events (`delta × nameSnapshot` + timestamp; see [Inventory Consume & History](../concepts/inventory-consume-history.md)), lazy `fetchHistory(itemId:)` per section, `ContentUnavailableView` when empty.

## Related

- [InventoryRowView](./ios-inventory-row-view.md)
- [StatusBadge](./ios-status-badge.md)
- [ItemDetailView](./ios-item-detail-view.md)
- [ScannerView](./ios-scanner-view.md)
- [SettingsView](./ios-settings-view.md)
- [EmptyStateView](./ios-empty-state-view.md)
- [ErrorBanner](./ios-error-banner.md)
- [iOS State Management](../concepts/ios-state-management.md)
- [Item Status](../concepts/item-status.md)
