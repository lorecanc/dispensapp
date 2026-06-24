---
title: "iOS Status Badge"
description: "Reusable SwiftUI badge component that displays an inventory item's status with color, icon, and label"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/StatusBadge.swift"
  - "ios/Inventario/Models/ItemStatus.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS Status Badge

## Purpose

StatusBadge is a reusable SwiftUI view that visually communicates an inventory item's expiration status. It renders a compact capsule-shaped label with an SF Symbol icon and a localized Italian label, color-coded by severity.

## Interface

| Prop     | Type       | Description                            |
|----------|------------|----------------------------------------|
| `status` | `ItemStatus` | The status value driving color, icon, and label |

## ItemStatus Enum

[ItemStatus](../concepts/item-status.md) is a `String`-backed enum (defined in [iOS Models](../concepts/ios-models.md)) with three cases, each mapped to a display color, SF Symbol, and label string.

| Case          | Raw Value       | Color  | Symbol                     | Label          |
|---------------|-----------------|--------|----------------------------|----------------|
| `ok`          | `ok`            | green  | `checkmark.circle.fill`    | Ok             |
| `expiringSoon`| `expiring_soon` | orange | `exclamationmark.circle.fill` | In scadenza |
| `expired`     | `expired`       | red    | `xmark.circle.fill`        | Scaduto        |

The enum also provides a static factory:

- `ItemStatus.from(statusString:)` — parses a raw `String` value and returns the matching case, defaulting to `.ok` on unknown input.

## Appearance

The badge renders as a horizontal capsule:

- **Font**: `.caption`
- **Foreground**: the status color at full opacity
- **Background**: the status color at 15% opacity
- **Padding**: 8 points horizontal, 3 points vertical
- **Shape**: `Capsule()` clip
- **Animation**: `.symbolEffect(.bounce, value: status)` — the icon bounces each time the status value changes

## Usage

The component is instantiated with a single binding:

```swift
StatusBadge(status: item.status)
```

It expects an `ItemStatus` value, typically obtained from the model or parsed from a stored string:

```swift
let status = ItemStatus.from(statusString: "expiring_soon")
StatusBadge(status: status)
```
