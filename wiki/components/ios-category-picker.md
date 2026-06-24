---
title: "CategoryPicker"
description: "Picker component for selecting a product category from a predefined set of Italian-labeled options"
category: "components"
source_files:
  - "ios/Inventario/Components/CategoryPicker.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# CategoryPicker

## Purpose

A SwiftUI `Picker` that offers a predefined list of product categories with Italian display labels. Used wherever the user assigns or changes a product's category.

## Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `selection` | `Binding<String>` | yes | The selected category key; bound from the parent view |

## Category Mapping

The picker maps internal keys to Italian display labels:

| Key | Label |
|-----|-------|
| `""` (empty) | Nessuna |
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

The first option is **Nessuna** (empty string tag), representing no category.

## Static Validation Set

The component exposes a static set of valid keys for use elsewhere in the app:

```swift
static let validCategoryKeys: Set<String> = [
    "yogurt", "fresh-milk", "pasta", "canned-vegetables",
    "rice", "cheeses", "eggs", "fresh-fruits",
    "fresh-vegetables", "frozen-foods",
]
```

Note that the empty-string `""` key (Nessuna) is **not** included in `validCategoryKeys`, so valid category checks only pass when a concrete category is selected.

## Usage

```swift
@State private var selectedCategory: String = ""

CategoryPicker(selection: $selectedCategory)
```

## Usage Locations

- **[ManualEntryView](../components/ios-manual-entry-view.md)** — category selection during manual product entry
- **[ScanPreviewSheet](../components/ios-scan-preview-sheet.md)** — category selection after scanning a barcode

## Notes

- The categories list is defined as a private constant inside the struct; the mapping cannot be extended at runtime.
- The picker label is hardcoded to `"Categoria"` (Italian).
- Category selections feed into the [expiration date estimation](../concepts/expiration-estimation.md) system — when no expiration date is provided, the selected category determines the default shelf life via the backend's `DEFAULT_SHELF_LIFE` mapping.
