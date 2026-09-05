---
title: "iOS Status Badge"
description: "Reusable SwiftUI badge component that displays an inventory item's status with color, icon, and label"
category: "components"
source_files:
  - "ios/Inventario/Features/Inventory/StatusBadge.swift"
  - "ios/Inventario/Models/ItemStatus.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# iOS Status Badge

## Purpose

StatusBadge is a reusable SwiftUI view that visually communicates an inventory item's expiration status. It renders a compact capsule-shaped label with an SF Symbol icon and a localized Italian label, color-coded by severity (Terra palette) — icon plus text, never color alone, per HIG.

## Interface

| Prop     | Type       | Description                            |
|----------|------------|----------------------------------------|
| `status` | `ItemStatus` | The status value driving color, icon, and label |

## ItemStatus Enum

[ItemStatus](../concepts/item-status.md) is a `String`-backed enum (defined in [iOS Models](../concepts/ios-models.md)) with three cases, each mapped to a display color, SF Symbol, and label string.

| Case          | Raw Value       | Color  | Symbol                     | Label          |
|---------------|-----------------|--------|----------------------------|----------------|
| `ok`          | `ok`            | `.statusFresh` (Terra) | `checkmark.circle.fill`    | Ok             |
| `expiringSoon`| `expiring_soon` | `.statusSoon` (Terra) | `exclamationmark.circle.fill` | In scadenza |
| `expired`     | `expired`       | `.statusExpired` (Terra) | `xmark.circle.fill`        | Scaduto        |

The enum also provides a static factory:

- `ItemStatus.from(statusString:)` — parses a raw `String` value and returns the matching case, defaulting to `.ok` on unknown input.

## Appearance

The badge renders as a horizontal capsule built on `Label(status.label, systemImage: status.symbol)`:

- **Font**: `.caption.weight(.semibold)`
- **Foreground**: the status color at full opacity
- **Background**: the status color at 14% opacity with a `thinMaterial` overlay at 35% (Liquid Glass)
- **Border**: status color at 28% opacity, 0.5pt (`strokeBorder`)
- **Padding**: 10 points horizontal, 4 points vertical
- **Shape**: `Capsule()` clip
- **Animation**: `.symbolEffect(.bounce, value: status)` — the icon bounces each time the status value changes
- **Accessibility**: combined label `"Stato <label>"` with value and a state-specific hint (`"Prodotto fresco"` / `"Prodotto in scadenza a breve"` / `"Prodotto scaduto"`); exposed as static text; Dynamic Type range `.xSmall ... .accessibility2`

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
