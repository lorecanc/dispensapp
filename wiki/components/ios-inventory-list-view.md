---
title: "InventoryListView"
description: "Main pantry list view — pantry picker, category chips, consume/delete actions, history sheet, and offline handling"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/InventoryListView.swift"
created: "2026-06-24"
last_updated: "2026-09-09"
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
| `searchText` | `String` (`@State`) | no | Drives `.searchable` client-side filter on name/brand/category; when trimmed text is ≥2 chars a 350ms-debounce `.task(id: searchText)` calls `APIClient.shared.fetchSuggestions(q:scope:"pantry")` into `pantrySuggestions` |
| `selectedCompartment` | `Compartment?` (`@State`) | no | Reparto chip filter, options from `Compartment.supermarketOrder`; match via `Compartment.inferCompartment(name:category:)` — nil/unknown maps to `dispensaSecca`, never hidden |
| `expandedCompartments` | `Set<String>` (`@State`) | no | Expanded `DisclosureGroup` state, pre-expanded for all `ItemStatus × Compartment.supermarketOrder` keys as `"status#compartment"`; toggled via `binding(for:status:comp:)` |
| `pantrySuggestions` / `manualPrefillName` / `manualPrefillCategory` | state | no | Suggestion results plus prefill for `ManualEntryView(initialName:initialCategory:)`; tapping a suggestion fills prefill, clears `pantrySuggestions`/`searchText`, and opens `showManual` |
| `showDetailItem` | `InventoryItem?` (`@State`) | no | Presents `ItemDetailView` sheet on row tap |
| `showScanner` / `showManual` / `showAddChoice` | `Bool` (`@State`) | no | Add flow: `addProductPill` → confirmation dialog (Scansiona / Inserimento manuale) → `ScannerViewWrapper` or `ManualEntryView` sheet |
| `showHistorySheet` | `Bool` (`@State`) | no | Presents Storico history sheet (medium/large detents) from overflow menu |
| `showManagePantries` / `showDeletePantryConfirm` / `pendingDeletePantry` | state | no | Pantry management sheet + delete confirmation dialogs |
| `showSettings` / `showInviteMembers` | `Bool` (`@State`) | no | Presents `SettingsView` / `InviteMembersSheet` from overflow menu |
| `cachedSections` / `filterKey` | derived state | no | Cached `[(ItemStatus, [InventoryItem])]` recomputed in `.task(id: filterKey)` from items fingerprint (incl. `source` / `productType`) + search + compartment + `archivedIDs` |

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

Body is split into extracted helpers to keep type-checking light: `inventoryListContent` / `statusSection(status:items:)` / `compartmentGroup(status:compartment:items:)` / `selectableInventoryRow(for:)` / `overflowMenu`. Status iteration uses `ForEach(groupedItems, id: \.0.rawValue)`.

Body sections in the `List`:

- `compartmentFilterBar`: horizontal chips (Tutti + `Compartment.supermarketOrder`), toggle `selectedCompartment`; reparto-only filtering, no `ProductSource` filter pills.
- `addProductPill`: capsule button opening the Scansiona/Manuale choice dialog.
- `pantrySuggestionsSection`: shown only when `pantrySuggestions` is non-empty; rows show name + category display name with `×N` (`timesScanned`) and `plus.circle` affordance; tap prefills `ManualEntryView(initialName:initialCategory:)`.
- Status sections (`statusSection`): one `Section` per `ItemStatus`; `.ok` sections render without a status header, other statuses render a `Label(status.label, systemImage: status.symbol)` header. Inside each, items are sub-grouped by `compartmentGroups(for:)` (via `Compartment.inferCompartment(name:category:)`, ordered by `Compartment.supermarketOrder`) with `ForEach(..., id: \.0.rawValue)`.
- Compartment groups (`compartmentGroup`): each `(Compartment, [InventoryItem])` renders as a `DisclosureGroup` with `isExpanded: binding(for:status:comp:)` and a `compartmentHeader` label (icon + label + count capsule); rows are `selectableInventoryRow`.
- Rows (`selectableInventoryRow`): `InventoryRowView` with leading consume (`fork.knife`, `store.consume`) and trailing delete (`trash`, `store.delete`) swipe actions (`allowsFullSwipe: false`) plus matching `contextMenu` items.
- Empty states: `EmptyStateView()` when the pantry is empty, `EmptyStateView(magnifyingglass / Nessun risultato / "Prova a cambiare ricerca o filtri.")` when filters match nothing.
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
