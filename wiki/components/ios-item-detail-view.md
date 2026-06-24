---
title: "iOS ItemDetailView"
description: "Detail view for a single inventory item in the iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/ItemDetailView.swift"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/Models/InventoryItem.swift"
  - "ios/Inventario/Features/Inventory/StatusBadge.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS ItemDetailView

## Purpose

Presents a full-screen detail sheet for a single [InventoryItem](../concepts/ios-models.md), allowing the user to view product info, adjust quantity, mark as consumed, or delete the item. All mutations propagate to *[InventoryStore](../concepts/ios-state-management.md)* which syncs with the backend API.

## Interface

The view receives an `InventoryItem` as its only input. Internal state handles local editing and confirmation dialogs.

| Property | Type | Source | Description |
|----------|------|--------|-------------|
| `item` | `InventoryItem` | Constructor parameter (let) | The item to display and edit |
| `store` | `InventoryStore` | `@Environment` | Shared observable state container |
| `editQuantity` | `Int` | `@State`, initialized from `item.quantity` | Local quantity value bound to the stepper |
| `showDeleteConfirmation` | `Bool` | `@State`, default `false` | Controls the delete confirmation dialog |

## Layout Structure

The view is wrapped in a `NavigationStack` and presented as a sheet with `.presentationDetents([.medium, .large])`. Content lives inside a `ScrollView` > `VStack(spacing: 20)`:

```
NavigationStack
 └── ScrollView
      └── VStack(spacing: 20)
           ├── AsyncImage (image area)
           ├── VStack(spacing: 12) — product info
           │    ├── name (.title2, .bold)
           │    ├── brand (.subheadline, .secondary) — conditional
           │    ├── category ("tag" icon + display name) — conditional
│    ├── [StatusBadge](../components/ios-status-badge.md)
│    ├── expiration date or "Nessuna data di scadenza"
           │    └── estimated date warning — conditional
           ├── Divider
           └── VStack(spacing: 16) — actions
                ├── Stepper (quantità, 1-99, auto-save)
                ├── "Segna come consumato" button (green, .bordered)
                └── "Elimina" button (destructive, .bordered)
```

## Image Handling

The `AsyncImage` component renders from `item.imageURL` (an optional `String` mapped to `URL`). Three states are handled:

- **success**: `resizable`, `aspectRatio(.fit)`, max 250 pt height, clipped with a 12 pt rounded rectangle.
- **failure**: A 200 pt rounded rectangle with a `photo` system image placeholder.
- **empty**: A 200 pt rounded rectangle with a `ProgressView` spinner, shown while the image loads.

If `item.imageURL` is `nil`, the entire `AsyncImage` block evaluates its `empty` phase, showing the spinner placeholder.

## Product Info Display

- **Name**: Always shown in `.title2` bold weight.
- **Brand**: Shown as `.subheadline` secondary text only when `item.brand` is non-nil and non-empty.
- **Category**: Shown as a tag icon + localized display name via `categoryDisplayName(_:)`, using secondary foreground style. The mapping is identical to the one in `InventoryRowView`:

| API value | Display name |
|-----------|-------------|
| `"yogurt"` | Yogurt |
| `"fresh-milk"` | Latte fresco |
| `"pasta"` | Pasta |
| `"canned-vegetables"` | Verdure in scatola |
| `"rice"` | Riso |
| `"cheeses"` | Formaggi |
| `"eggs"` | Uova |
| `"fresh-fruits"` | Frutta fresca |
| `"fresh-vegetables"` | Verdura fresca |
| `"frozen-foods"` | Surgelati |
| *(any other)* | Falls back to the raw string |

- **[StatusBadge](../components/ios-status-badge.md)**: A capsule-shaped badge using [ItemStatus](../concepts/item-status.md) (ok/expiring_soon/expired) with color-coded icon and label. The badge uses `.symbolEffect(.bounce)` on status change.

## Expiration Info

- If `item.expirationDate` is present: displays "Scadenza:" followed by the date formatted with `.date.long` / `.time.omitted` (e.g., "24 giugno 2026").
- If `item.isEstimated` is `true`: a warning label "Data stimata" with an orange `exclamationmark.triangle` icon is shown below the date.
- If no expiration date: displays "Nessuna data di scadenza" in secondary style.

## Quantity Stepper with Auto-Save

A [QuantityStepper](../components/ios-quantity-stepper.md) bound to `editQuantity` (range 1-99) displays "Quantità: {value}". On each value change, the `.onChange(of: editQuantity)` handler calls:

```swift
await store.update(id: item.id, quantity: newValue)
```

This sends a PATCH request via `InventoryStore.update(...)` and, on success, replaces the item in the local `items` array with the updated server response. The stepper range enforces a minimum of 1 — users cannot zero out quantity via the stepper.

## Consume Action

The "Segna come consumato" button (green tint, `.bordered` style) calls:

```swift
await store.decrementQuantity(for: item)
```

`decrementQuantity` checks the current quantity:
- If `quantity > 1`: calls `update(id:quantity:)` with `quantity - 1`.
- If `quantity <= 1`: calls `delete(id:)`, removing the item entirely.

This means consuming the last unit of an item deletes it from inventory.

## Delete Action

The "Elimina" button (destructive role, `.bordered` style) sets `showDeleteConfirmation = true`, which triggers a `confirmationDialog`:

```
Title: "Eliminare {item.name}?"
Message: "Questa azione non può essere annullata."
- "Elimina" (destructive) → calls await store.delete(id: item.id)
- "Annulla" (cancel) → dismisses dialog
```

On confirmation, `store.delete(id:)` sends a DELETE to the API and removes the item from the local array.

## Sheet Presentation

The view is presented as a sheet configured with:

```swift
.presentationDetents([.medium, .large])
```

This allows the user to drag between a half-height (medium) and full-height (large) detent. The navigation title is "Dettaglio" displayed inline.
