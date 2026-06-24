---
title: "InventoryListView"
description: "Main inventory list view for the iOS app — filtering, grouping, swipe actions, search, and navigation"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/InventoryListView.swift"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/Features/Inventory/InventoryRowView.swift"
  - "ios/Inventario/Components/EmptyStateView.swift"
  - "ios/Inventario/Features/Inventory/StatusBadge.swift"
  - "ios/Inventario/Components/ErrorBanner.swift"
  - "ios/Inventario/Models/ItemStatus.swift"
  - "ios/Inventario/Models/InventoryItem.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# InventoryListView

## Purpose

`InventoryListView` is the primary inventory screen in the Inventario iOS app. It displays the user's pantry items (dispensa) in a grouped, searchable list with status-based sections, swipe-to-consume and swipe-to-delete actions, pull-to-refresh, and entry points for barcode scanning, settings, and item details.

## State Management

The view holds four local `@State` properties and reads the store from the environment:

```swift
@Environment(InventoryStore.self) private var store
@State private var searchText = ""
@State private var showSettings = false
@State private var showDetailItem: InventoryItem?
@State private var showScanner = false
```

- `store` — the observable [InventoryStore](../concepts/ios-state-management.md) that holds `items`, `isLoading`, and `error`.
- `searchText` — bound to the `.searchable` modifier, drives client-side filtering.
- `showSettings` / `showScanner` / `showDetailItem` — control sheet presentation.

A `@Bindable` projection of the store is created locally inside `body` to allow two-way binding to `store.error` for the dismiss action on `ErrorBanner`.

## Filtering

The `filteredItems` computed property performs a case-insensitive search across three fields:

```swift
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
```

When `searchText` is empty the full list is returned. Otherwise items matching on `name`, `brand`, or `category` are included. Optional `brand` and `category` fields are safely unwrapped with `?? false`.

## Grouping by Status

The `groupedItems` computed property groups the filtered results by [ItemStatus](../concepts/item-status.md):

```swift
private var groupedItems: [(ItemStatus, [InventoryItem])] {
    let grouped = Dictionary(grouping: filteredItems) {
        ItemStatus.from(statusString: $0.status)
    }
    return ItemStatus.allCases.compactMap { status in
        guard let items = grouped[status], !items.isEmpty else { return nil }
        return (status, items)
    }
}
```

It iterates `ItemStatus.allCases` (`.ok`, `.expiringSoon`, `.expired`) in declaration order and only includes non-empty groups. The resulting array drives the `List` sections.

### ItemStatus

Defined in `ItemStatus.swift`:

| Case | Raw Value | Color | Symbol | Label |
|------|-----------|-------|--------|-------|
| `.ok` | `"ok"` | `.green` | `checkmark.circle.fill` | "Ok" |
| `.expiringSoon` | `"expiring_soon"` | `.orange` | `exclamationmark.circle.fill` | "In scadenza" |
| `.expired` | `"expired"` | `.red` | `xmark.circle.fill` | "Scaduto" |

The static method `from(statusString:)` converts the API string to the enum, defaulting to `.ok` for unknown values.

## UI Structure

The view uses an `.insetGrouped` `List` with a conditional body:

- **Empty state**: when `groupedItems` is empty, [EmptyStateView](../components/ios-empty-state-view.md) is displayed (a `ContentUnavailableView` with refrigerator icon and "Tocca + per aggiungere un prodotto.").
- **Populated state**: a `ForEach` over `groupedItems` creates a `Section` per status group. Each section header is a `Label(status.label, systemImage: status.symbol)` styled with `status.color`.

### Row Content

Each item is rendered with [InventoryRowView](../components/ios-inventory-row-view.md), which shows:
- An `AsyncImage` thumbnail (56×56 rounded rectangle) with loading and failure fallbacks.
- The item name (`.headline`, single line).
- Optional brand name (`.caption`, secondary).
- Optional category with a tag icon and a localized display name (e.g. `"yogurt"` → `"Yogurt"`, `"fresh-milk"` → `"Latte fresco"`).
- A [StatusBadge](../components/ios-status-badge.md) (capsule-shaped label with status color and bounce animation).
- Quantity badge (`×N`).

## Swipe Actions

Each row has two swipe actions:

### Trailing Swipe (Delete)

```swift
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button(role: .destructive) {
        Task { await store.delete(id: item.id) }
    } label: {
        Label("Elimina", systemImage: "trash")
    }
}
```

- Destructive red action.
- Full swipe triggers deletion.
- Calls `store.delete(id:)` which sends a DELETE request to the API and removes the item from the local array.

### Leading Swipe (Consume)

```swift
.swipeActions(edge: .leading, allowsFullSwipe: true) {
    Button {
        Task { await store.decrementQuantity(for: item) }
    } label: {
        Label("Consumato", systemImage: "fork.knife")
    }
    .tint(.green)
}
```

- Green action.
- Full swipe decrements quantity.
- `decrementQuantity(for:)` in the store reduces `quantity` by 1 via an API update, or deletes the item entirely if quantity reaches 0.

## Search

The list is wrapped in `.searchable(text: $searchText, prompt: "Cerca nella dispensa...")`. This adds a native search bar to the navigation bar. Filtering is synchronous on the main thread via the computed property.

## Pull to Refresh

```swift
.refreshable {
    await store.refresh()
}
```

`.refreshable` reloads the full item list from the API. The store sets `isLoading = true` before the request and clears it on completion.

## Initial Load

A `.task` modifier triggers the first load when the view appears:

```swift
.task {
    await store.refresh()
}
```

## Error Handling

An [ErrorBanner](../components/ios-error-banner.md) overlay is displayed at the top when the store has an error:

```swift
.overlay(alignment: .top) {
    if let error = store.error {
        ErrorBanner(message: error.localizedDescription) {
            storeBindable.error = nil
        }
    }
}
```

`ErrorBanner` shows a red rounded pill with an exclamation icon, the error message, and a dismiss (×) button. It animates in/out with `.move(edge: .top).combined(with: .opacity)` transitions.

## Navigation / Toolbar

The navigation title is `"Dispensa"`.

### Toolbar Items

- **Barcode scanner button** (trailing): a `barcode.viewfinder` icon that sets `showScanner = true`, presenting [ScannerViewWrapper](../components/ios-scanner-view.md).
- **Menu** (trailing): an `ellipsis.circle` icon with two options:
  - "Impostazioni" → presents [SettingsView](../components/ios-settings-view.md).
  - "Esporta dispensa" → calls `store.exportMarkdown()`.

### Sheets

| Trigger | Sheet |
|---------|-------|
| `showSettings` | `SettingsView()` |
| `showDetailItem` (non-nil) | [ItemDetailView](../components/ios-item-detail-view.md)`(item: item)` — bound as `.sheet(item:)` so dismiss sets it back to `nil`. |
| `showScanner` | `ScannerViewWrapper()` |

The item detail sheet is triggered by an `.onTapGesture` on each `InventoryRowView` that sets `showDetailItem` to the tapped item.

## Key Files

| File | Role |
|------|------|
| `Features/Inventory/InventoryListView.swift` | Main list view with filtering, grouping, layout |
| `State/InventoryStore.swift` | Observable store managing items, CRUD, errors |
| `Features/Inventory/InventoryRowView.swift` | Single row displaying item thumbnail, name, brand, category, status badge, quantity |
| `Components/EmptyStateView.swift` | Empty state placeholder using `ContentUnavailableView` |
| `Features/Inventory/StatusBadge.swift` | Capsule badge showing status label and color |
| `Components/ErrorBanner.swift` | Dismissable error banner overlay |
| `Models/ItemStatus.swift` | Status enum with color, symbol, label, and raw-value mapping |
| `Models/InventoryItem.swift` | Codable item model with custom date decoding (see [iOS Models](../concepts/ios-models.md)) |
