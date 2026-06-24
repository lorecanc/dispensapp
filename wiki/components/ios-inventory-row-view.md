---
category: components
name: ios-inventory-row-view
title: InventoryRowView
description: >
  A SwiftUI row view for displaying an inventory item in a list. It shows the
  product image, name, brand, category, a status badge, and quantity in a
  compact HStack layout.
source_files:
  - ios/Inventario/Features/Inventory/InventoryRowView.swift
  - ios/Inventario/Features/Inventory/StatusBadge.swift
  - ios/Inventario/Models/InventoryItem.swift
  - ios/Inventario/Models/ItemStatus.swift
last_updated: 2026-06-24
glossary_terms:
  - ItemStatus
---

# InventoryRowView

`InventoryRowView` is a SwiftUI `View` that renders a single row inside an
inventory list. It takes an [InventoryItem](../concepts/ios-models.md) and lays it out as a horizontal row
with the item image, textual info, and status indicator.

## Row Layout

The top-level container is an `HStack(spacing: 12)` with two vertical stacks
on either side of a `Spacer`:

```
[HStack]
  [AsyncImage (56×56)]  [VStack (name, brand, category)]  [Spacer]  [VStack (StatusBadge, quantity)]
```

- **Left**: product image (56×56 rounded rect).
- **Center-left**: name (headline, line-limit 1), optional brand (caption,
  secondary style), optional category (tag icon + display name, tertiary
  style).
- **Center-right**: spacer pushes content to the edges.
- **Right**: `StatusBadge` above the quantity string (`×N`, caption,
  secondary style).

The row applies `.padding(.vertical, 4)` for compact spacing.

## Async Image Handling

The image is loaded from `item.imageURL` via SwiftUI's `AsyncImage`. The URL
is created with a `flatMap { URL(string: $0) }` so a nil or invalid string
produces a `nil` URL, which immediately yields the `.empty` phase.

| Phase | Rendering |
|---|---|
| `.success(let image)` | `resizable`, aspect-fill, clipped to `RoundedRectangle(cornerRadius: 8)`, 56×56 |
| `.failure` | Filled rounded rect (secondary opacity 0.2) with a `photo` SF Symbol overlay |
| `.empty` | Same filled rounded rect with a `ProgressView` spinner overlay |
| `@unknown default` | `EmptyView` |

## Category Display Name Mapping

The category identifier from the server (a kebab-case string) is mapped to an
Italian display name through a hardcoded `switch` in the private
`categoryDisplayName(_:)` method:

| Server value | Display name |
|---|---|
| `yogurt` | Yogurt |
| `fresh-milk` | Latte fresco |
| `pasta` | Pasta |
| `canned-vegetables` | Verdure in scatola |
| `rice` | Riso |
| `cheeses` | Formaggi |
| `eggs` | Uova |
| `fresh-fruits` | Frutta fresca |
| `fresh-vegetables` | Verdura fresca |
| `frozen-foods` | Surgelati |

Any unrecognised string falls through to the `default` branch and is returned
as-is.

The category label is rendered as an `HStack(spacing: 4)` containing a `tag`
SF Symbol (`Image(systemName: "tag")` at `.caption2` size) followed by the
display name text (also `.caption2`). The entire group uses
`.foregroundStyle(.tertiary)`.

## Status Badge Integration

The right-hand column embeds [StatusBadge](../components/ios-status-badge.md), initialised with
[ItemStatus.from](../concepts/item-status.md)`(statusString: item.status)`.

`ItemStatus` is an enum with three cases:

- **ok** → green capsule, `checkmark.circle.fill` icon, label `"Ok"`.
- **expiring_soon** → orange capsule, `exclamationmark.circle.fill` icon,
  label `"In scadenza"`.
- **expired** → red capsule, `xmark.circle.fill` icon, label `"Scaduto"`.

The badge is rendered as a `Label` inside a capsule shape with a tinted
background at 15 % opacity. A `.symbolEffect(.bounce)` animation triggers
whenever the `status` value changes.

If the raw string from the server does not match any known case,
`ItemStatus.from` defaults to `.ok`.

## Data Model

`InventoryItem` is a `Codable`, `Identifiable`, `Equatable` (by `id`) struct
with the following fields used by this view:

| Field | Type | Source key | Role |
|---|---|---|---|
| `name` | `String` | `name` | Primary label |
| `brand` | `String?` | `brand` | Optional secondary label |
| `category` | `String?` | `category` | Optional category key for display name lookup |
| `imageURL` | `String?` | `image_url` | Optional URL string for the image |
| `quantity` | `Int` | `quantity` | Numeric count shown as `×N` |
| `status` | `String` | `status` | Raw status key fed to `ItemStatus.from` |

## Glossary

- **ItemStatus**: An enum with cases `ok`, `expiring_soon`, and `expired`.
  Each case defines a `color`, `symbol` (SF Symbol name), and `label` (human-readable
  Italian string) used by `StatusBadge`.
