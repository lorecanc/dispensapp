---
title: "iOS State Management"
description: "InventoryStore @Observable pattern, CRUD operations, error propagation, and sorting behavior"
category: "concepts"
source_files:
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/Models/InventoryItem.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS State Management

## Overview

The iOS app uses a single `InventoryStore` class as the central source of truth for inventory state. It is annotated with `@Observable` and `@MainActor` so SwiftUI views automatically re-render when any stored property changes, and all asynchronous work runs on the main actor.

The store never holds cached or derived state — every mutation is the result of a completed network request. The [APIClient](../concepts/ios-networking.md) is the only dependency and is instantiated privately inside the store.

The store is consumed by the following views:
- [InventoryListView](../components/ios-inventory-list-view.md) — displays items and triggers CRUD operations.
- [ItemDetailView](../components/ios-item-detail-view.md) — updates and deletes individual items.
- [ManualEntryView](../components/ios-manual-entry-view.md) — adds items via `addManual(...)`.
- [ScanPreviewSheet](../components/ios-scan-preview-sheet.md) — adds scanned items via `add(...)`.

## @Observable Pattern

The `@Observable` macro (iOS 17+) replaces `ObservableObject` / `@Published` for the store. SwiftUI tracks property reads at compile time and only invalidates views that actually read changed properties.

```swift
@Observable
@MainActor
final class InventoryStore {
    var items: [InventoryItem] = []
    var isLoading = false
    var error: APIError?
    var exportedMarkdown: String?
}
```

- **items** ([InventoryItem](../concepts/ios-models.md)): the full inventory list, always sorted by expiration date.
- **isLoading**: `true` while `refresh()` is in flight.
- **error**: set on failure and reset to `nil` before every operation.
- **exportedMarkdown**: populated by `exportMarkdown()` with a markdown string from the server.

## State Properties

| Property | Type | Mutated by | Reset behavior |
|---|---|---|---|
| `items` | `[InventoryItem]` | `refresh`, `add`, `addManual`, `update`, `delete`, `decrementQuantity` | Replaced entirely by `refresh`; appended/replaced/removed by CRUD |
| `isLoading` | `Bool` | `refresh` | Set `true` before the request, `false` after (regardless of success or failure) |
| `error` | `APIError?` | Every public method | Set to `nil` at the start of every method, set on failure |
| `exportedMarkdown` | `String?` | `exportMarkdown` | Set to result on success, unchanged on failure |

## Error Propagation

Every public method follows the same pattern:

1. Reset `error` to `nil`.
2. Execute the network call in a `do`/`catch` block.
3. On failure, cast the caught error to `APIError`; if the cast fails, wrap it in `.transport(error)`.

```swift
error = nil
do {
    // network call
} catch {
    self.error = error as? APIError ?? .transport(error)
}
```

`APIError` is an enum with cases `invalidURL`, `transport(Error)`, `decoding(Error)`, `http(status:message:)`, `notFound`, and `offline`. The `.transport` fallback in the store means any unexpected error type is surfaced rather than silently ignored.

Views observe `error` and can present an alert or banner when it becomes non-nil. The store does not auto-clear the error — the view is responsible for resetting it (or the next operation will overwrite it).

## CRUD Operations

### refresh (Read All)

Replaces `items` entirely with the server response. Sets `isLoading = true` before the request and `false` after completion, regardless of outcome.

```swift
func refresh() async {
    isLoading = true
    error = nil
    do {
        items = try await client.list()
    } catch {
        self.error = error as? APIError ?? .transport(error)
    }
    isLoading = false
}
```

### add (Create from Scan)

Sends a `POST /api/inventory` with barcode, name, brand, expiration date, category, image URL, and quantity. Appends the returned item and sorts by expiration date.

### addManual (Create Manual)

Sends a `POST /api/inventory/manual` — same as `add` but without barcode or image URL. After appending, sorts by expiration date.

### update (Partial Update)

Sends a `PATCH /api/inventory/{id}`. All fields are optional — only non-nil values are included in the request body. On success, finds the item by `id` in the local array and replaces it in-place.

```swift
if let index = items.firstIndex(where: { $0.id == id }) {
    items[index] = updated
}
```

### delete

Sends a `DELETE /api/inventory/{id}`. The server returns 204 or 200. On success, removes the item from the local array.

```swift
items.removeAll { $0.id == id }
```

## Decrement Logic

`decrementQuantity(for:)` is a convenience that reduces quantity by one or deletes the item entirely:

```swift
func decrementQuantity(for item: InventoryItem) async {
    if item.quantity > 1 {
        await update(id: item.id, quantity: item.quantity - 1)
    } else {
        await delete(id: item.id)
    }
}
```

This method reads `item.quantity` from the passed model — it does not re-fetch from the store. The caller should pass the current `InventoryItem` value. If quantity is 1, the item is deleted server-side; if greater than 1, a PATCH is sent with quantity-1.

## Sorting Behavior

Items are sorted by `expirationDate` in ascending order. Items with a `nil` expiration date sort to the end (treated as `.distantFuture`).

```swift
items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
```

Sorting is applied after `add` and `addManual`. The `refresh` method relies on the server returning items in the correct order (no local re-sort). The `update` method does not re-sort — the replaced item retains its position.

## Markdown Export

`exportMarkdown()` fetches a markdown representation of the inventory from `GET /api/inventory/export` and stores it in `exportedMarkdown`. The request sets `Accept: text/markdown`. The response body is decoded as UTF-8 text; failures (network, non-2xx status, or invalid encoding) set `error`.

The view layer reads `exportedMarkdown` after the async call completes, typically to present a share sheet or preview.

## Threading Guarantee

The entire class runs on `@MainActor`. The `APIClient` is also annotated `@MainActor`, so all networking completion callbacks arrive on the main thread. This eliminates the need for `DispatchQueue.main.async` wrappers and lets SwiftUI observation work without explicit `receive(on:)` operators.
