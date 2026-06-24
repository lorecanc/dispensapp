---
title: "EmptyStateView"
description: "Full-screen empty-state placeholder displayed when the inventory list has no items"
category: "components"
source_files:
  - "ios/Inventario/Components/EmptyStateView.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# EmptyStateView

## Purpose

A stateless SwiftUI view that renders a `ContentUnavailableView` placeholder when the pantry inventory is empty. Communicates to the user that no products are listed and hints at the next action.

## Appearance

The view displays a system-styled empty-state card with three elements:

- **Icon**: `"refrigerator"` system image
- **Title**: `"La tua dispensa è vuota"`
- **Description**: `"Tocca + per aggiungere un prodotto."`

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

- No parameters or bindings — the view is entirely static.
- Relies on SwiftUI's built-in `ContentUnavailableView` (iOS 17+), which provides platform-appropriate layout and styling for empty-state presentation.
