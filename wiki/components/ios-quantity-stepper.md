---
title: "QuantityStepper"
description: "Reusable stepper component for adjusting a numeric quantity within a configurable range"
category: "components"
source_files:
  - "ios/Inventario/Components/QuantityStepper.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# QuantityStepper

## Purpose

A lightweight SwiftUI component that wraps a `Stepper` to adjust an integer quantity within a configurable range. Used whenever the user needs to specify a product count.

## Interface

| Prop | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `quantity` | `Binding<Int>` | yes | — | The current quantity value, bound from the parent view |
| `range` | `ClosedRange<Int>` | no | `1...99` | The allowed range for the quantity |

The `quantity` binding uses the underscore-prefix initializer pattern (`self._quantity = quantity`) to receive a `Binding<Int>` directly.

## Usage

The stepper displays the current value inline: **Quantità: \(quantity)**.

```swift
struct ManualEntryView: View {    // See [ManualEntryView](../components/ios-manual-entry-view.md)
    @State private var quantity = 1

    var body: some View {
        QuantityStepper(quantity: $quantity)
    }
}
```

The range can be customized when the default `1...99` is not appropriate:

```swift
QuantityStepper(quantity: $quantity, range: 0...10)
```

## Usage Locations

- **[ManualEntryView](../components/ios-manual-entry-view.md)** — product count during manual entry
- **[ScanPreviewSheet](../components/ios-scan-preview-sheet.md)** — product count after scanning a barcode
- **[ItemDetailView](../components/ios-item-detail-view.md)** — editing quantity of an existing item

## Notes

- No custom styling is applied; the appearance is the platform-default `Stepper` with a text label.
- Validation is handled by the `Stepper` itself — it clamps values within the provided range and disables decrement/increment at the bounds.
