---
title: "EmptyStateView"
description: "Full-screen empty-state placeholder displayed when the inventory list has no items"
category: "components"
source_files:
  - "ios/Inventario/Components/EmptyStateView.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# EmptyStateView

## Purpose

A configurable SwiftUI view that renders an illustrated Material card when the pantry inventory is empty or a search yields no results. Communicates to the user that no products are listed and hints at the next action.

## Interface

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `imageName` | `String` | `"refrigerator.fill"` | SF Symbol for the Terracotta illustration medallion |
| `title` | `String` | `"La tua dispensa è vuota"` | Heading text |
| `message` | `String` | `"Tocca + per aggiungere un prodotto."` | Hint text |

All three have defaults, so `EmptyStateView()` renders the standard empty-pantry card while callers can override each slot (e.g. a no-search-results variant).

## Appearance

A centered `VStack` (spacing 16, padding 28, full width) inside a Liquid-Glass card (`regularMaterial` + `pantryCream` 0.35 overlay, `pantryOat` 0.5 border, 20pt continuous corners, soft shadow):

- **Illustration**: 96pt circle filled with `pantryTerracotta` at 12% + `thinMaterial` overlay + hairline border, with the symbol at 42pt in `pantryTerracotta` (hidden from VoiceOver).
- **Title**: `.title3.semibold`, `textPrimary`, centered, exposed as heading (h2).
- **Message**: `.subheadline`, `textSecondary`, centered.

Accessibility: children combined into one element labeled `"<title>, <message>"` with hint `"Stato vuoto della dispensa"`; Dynamic Type range `.xSmall ... .accessibility2`.

## Usage

```swift
struct InventoryListView: View {
    var body: some View {
        if groupedItems.isEmpty {
            EmptyStateView()
        } else {
            // list content
        }
    }
}
```

## Usage Location

- **[InventoryListView](../components/ios-inventory-list-view.md)** — shown as an overlay (via conditional branch) when `groupedItems` is empty.

## Notes

- Renders a custom illustrated card (Terra palette + Material), not the system `ContentUnavailableView`.
- Relies on Terra semantic colors (`pantryTerracotta`, `pantryCream`, `pantryOat`, `textPrimary`/`textSecondary`) — see [Apple Dependencies](../dependencies/apple-dependencies.md).
