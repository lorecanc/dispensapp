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
last_updated: "2026-09-05"
---

# iOS ItemDetailView

## Purpose

Presents a full-screen detail sheet for a single [InventoryItem](../concepts/ios-models.md). Resolves the item live from *[InventoryStore](../concepts/ios-state-management.md)* by ID on every render, so consume / update / delete mutations reflect immediately. Allows viewing product info, adjusting quantity, marking as consumed, or deleting the item. Shows a `ContentUnavailableView` fallback when the item disappears while open (fully consumed, deleted, pantry switch).

## Interface

The view takes an `InventoryItem` once at init and keeps only its ID. Everything else is resolved live.

| Property | Type | Source | Description |
|----------|------|--------|-------------|
| `itemID` | `Int` | `init(item:)` → `item.id` | Stable identity used for store lookup |
| `liveItem` | `InventoryItem?` | Computed `@MainActor`, `store.items.first { $0.id == itemID }` | Current item; `nil` when no longer in pantry |
| `store` | `InventoryStore` | `@Environment` | Shared observable state container |
| `editQuantity` | `Int` | `@State`, initialized from `item.quantity` | Local stepper value, two-way synced with `liveItem.quantity` |
| `showDeleteConfirmation` | `Bool` | `@State`, default `false` | Controls the delete confirmation dialog |

`@Bindable var storeBindable = store` is created at the top of `body` for SwiftUI observation.

## Layout Structure

Wrapped in a `NavigationStack` presented as a sheet with `.presentationDetents([.medium, .large])`. Body is conditional on `liveItem`:

```
NavigationStack
 ├── if let item = liveItem
 │    └── ScrollView
 │         └── VStack(spacing: 20)
 │              ├── CachedThumbnail (image area)
 │              ├── VStack(spacing: 12) — product info
 │              │    ├── name (.title2, .bold)
 │              │    ├── brand (.subheadline, .secondary) — conditional
 │              │    ├── category ("tag" icon + display name) — conditional
 │              │    ├── [StatusBadge](../components/ios-status-badge.md)
 │              │    ├── expiration date or "Nessuna data di scadenza"
 │              │    └── estimated date warning — conditional
 │              ├── Divider
 │              └── VStack(spacing: 16) — actions
 │                   ├── Stepper (quantità, 1-99, two-way sync)
 │                   ├── "Segna come consumato" button (green, .bordered)
 │                   └── "Elimina" button (destructive, .bordered)
 └── else ContentUnavailableView ("Prodotto non più in dispensa")
```

Navigation title is "Dettaglio", displayed inline in both branches.

## Image Handling

Renders via `CachedThumbnail(url:side:contentMode:)` with `side: 250`, `contentMode: .fit`, and horizontal padding — replacing the previous raw `AsyncImage`. URL comes from `item.imageURL.flatMap { URL(string: $0) }`, so a `nil` or malformed string yields a `nil` URL and the thumbnail's placeholder path.

## Product Info Display

- **Name**: Always shown in `.title2` bold weight.
- **Brand**: Shown as `.subheadline` secondary text only when `item.brand` is non-nil and non-empty.
- **Category**: Tag icon + `CategoryRegistry.displayName(for:)` name in secondary style. The local hardcoded API-value table was removed; all naming now comes from the shared `CategoryRegistry` (see [Category Registry](../concepts/category-registry.md)), so adding a category there updates this view automatically.
- **[StatusBadge](../components/ios-status-badge.md)**: Capsule badge from `ItemStatus.from(statusString: item.status)` (ok/expiring_soon/expired), with top padding.

## Expiration Info

- If `item.expirationDate` is present: "Scadenza:" plus date formatted `.date.long` / `.time.omitted`.
- If `item.isEstimated` is `true`: orange "Data stimata" label with `exclamationmark.triangle` icon below the date.
- If no date: "Nessuna data di scadenza" in secondary style.

## Quantity Stepper with Two-Way Sync

A [QuantityStepper](../components/ios-quantity-stepper.md)-style `Stepper("Quantità: \(editQuantity)", value: $editQuantity, in: 1...99)` with two `onChange` handlers:

1. `editQuantity` → store: guarded by `guard newValue != item.quantity else { return }`, then `await store.update(id: item.id, quantity: newValue)`. The guard breaks the feedback loop when an external sync (e.g. consume) moves the stepper.
2. `item.quantity` → `editQuantity`: `editQuantity = newValue`, so consume/history updates arriving via `liveItem` reposition the stepper without user input.

Range enforces a minimum of 1 — the stepper cannot zero out quantity.

## Consume Action

The "Segna come consumato" button (`fork.knife` label, green tint, `.bordered`) calls:

```swift
await store.decrementQuantity(for: item)
```

`decrementQuantity` decrements when `quantity > 1` and deletes when reaching zero; because the view reads `liveItem`, the stepper and info update live, and consuming the last unit flips the view to the missing-item state. History recording happens in the store layer, not in this view (see [Inventory Consume & History](../concepts/inventory-consume-history.md)).

## Delete Action

The "Elimina" button (`trash` label, destructive role, `.bordered`) sets `showDeleteConfirmation = true`, triggering a `confirmationDialog`:

```
Title: "Eliminare {item.name}?"
Message: "Questa azione non può essere annullata."
- "Elimina" (destructive) → await store.delete(id: item.id)
- "Annulla" (cancel) → dismisses dialog
```

After deletion `liveItem` becomes `nil` and the fallback view appears; the sheet itself is dismissed by the user.

## Missing-Item State

When `liveItem` is `nil`:

```swift
ContentUnavailableView(
  "Prodotto non più in dispensa",
  systemImage: "basket",
  description: Text("Eliminato o consumato del tutto: chiudi per tornare alla lista.")
)
```

## Accessibility (VoiceOver Fix)

Every interactive and informative element now carries explicit labels; decorative icons are hidden:

- Brand: `accessibilityLabel("Marca \(brand)")`.
- Category row: decorative `tag` image `accessibilityHidden`, row label `"Categoria \(name)"` + hint `"Categoria del prodotto"`.
- Expiration row: `.accessibilityElement(children: .combine)` with label `"Scadenza \(date)"`; estimated warning labelled `"Data stimata"` with hint explaining it is category-estimated, not exact.
- No-date text labelled `"Nessuna data di scadenza"`.
- Stepper: label `"Quantità"`, value `"\(editQuantity)"`, hint `"Regola la quantità del prodotto"`, clamped `.dynamicTypeSize(.xSmall ... .accessibility2)`.
- Consume button: label `"Segna come consumato"` + hint `"Diminuisce la quantità di uno"`.
- Delete button: label `"Elimina \(item.name)"` + hint `"Elimina definitivamente il prodotto"`.

## Sheet Presentation

```swift
.presentationDetents([.medium, .large])
```

Allows dragging between half-height (medium) and full-height (large) detents.
