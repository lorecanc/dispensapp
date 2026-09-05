---
title: "CategoryPicker"
description: "Picker component for selecting a product category from the server-driven CategoryRegistry"
category: "components"
source_files:
  - "ios/Inventario/Components/CategoryPicker.swift"
  - "ios/Inventario/Models/CategoryRegistry.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# CategoryPicker

## Purpose

A SwiftUI `Picker` that offers the product categories with Italian display labels. Used wherever the user assigns or changes a product's category. The list is **server-driven**: options come from [CategoryRegistry](../concepts/category-registry.md) (`GET /api/categories`, with an embedded offline fallback), so the picker never hardcodes categories itself.

## Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `selection` | `Binding<String>` | yes | The selected category key; bound from the parent view |

```swift
struct CategoryPicker: View {
    @Binding var selection: String

    private let categories = CategoryRegistry.categories

    /// Forwarded for backward compatibility — single source is CategoryRegistry.
    static let validCategoryKeys: Set<String> = CategoryRegistry.validCategoryKeys
    ...
}
```

## Category Source

`CategoryRegistry.categories` returns `[(key:label:)]` pairs — the live server snapshot after `update(with:)`, or the embedded fallback (mirror of backend `CATEGORY_LABELS`) on first launch/offline. The picker renders a `"Nessuna"` (empty-string) option plus one row per registry entry:

```swift
Picker("Categoria", selection: $selection) {
    Text("Nessuna").tag("")
    ForEach(categories, id: \.key) { cat in
        Text(cat.label).tag(cat.key)
    }
}
```

The empty-string `""` key (Nessuna) is **not** included in `validCategoryKeys`, so valid category checks only pass when a concrete category is selected. `validCategoryKeys` on the picker is a deprecated forwarder — new code should use `CategoryRegistry.validCategoryKeys` directly.

## Usage

```swift
@State private var selectedCategory: String = ""

CategoryPicker(selection: $selectedCategory)
```

## Usage Locations

- **[ManualEntryView](../components/ios-manual-entry-view.md)** — category selection during manual product entry
- **[ScanPreviewSheet](../components/ios-scan-preview-sheet.md)** — category selection after scanning a barcode

## Notes

- The categories list is resolved at runtime from `CategoryRegistry`; it updates automatically after the next `fetchCategories` without touching this file.
- The picker label is hardcoded to `"Categoria"` (Italian).
- Category selections feed into the [expiration date estimation](../concepts/expiration-estimation.md) system — when no expiration date is provided, the selected category determines the default shelf life via the backend's `DEFAULT_SHELF_LIFE` mapping (with `CATEGORY_ALIASES` covering singular/plural variants).
