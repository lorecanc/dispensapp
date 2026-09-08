---
title: "CategoryPicker"
description: "Two-level category picker (button + department-grouped sheet) reading the server-driven CategoryRegistry"
category: "components"
source_files:
  - "ios/Inventario/Components/CategoryPicker.swift"
  - "ios/Inventario/Models/CategoryRegistry.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingModels.swift"
  - "ios/InventarioTests/CategoryPickerTests.swift"
created: "2026-06-24"
last_updated: "2026-09-06"
---

# CategoryPicker

## Purpose

A two-level category selector: a form row button showing the current category that opens a sheet with a `List` grouped into one section per supermarket department (*reparto*). Used wherever the user assigns or changes a product's category. The list is **server-driven**: options come from [CategoryRegistry](../concepts/category-registry.md) (`GET /api/categories`, with an embedded offline fallback), so the picker never hardcodes categories itself. A flat `Picker`/`Menu` with 26 options does not scale — hence the grouped sheet.

## Props / Interface

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `selection` | `Binding<String>` | yes | The selected category key; bound from the parent view |

```swift
struct CategoryPicker: View {
    @Binding var selection: String

    @State private var showCategoryList = false

    /// Read from the registry on every render (was a stored
    /// property captured at init, therefore stale after update).
    private var categories: [(key: String, label: String)] {
        CategoryRegistry.categories
    }

    /// Forwarded for backward compatibility — single source is CategoryRegistry.
    /// Computed: a `static let` would freeze the value at first access.
    static var validCategoryKeys: Set<String> { CategoryRegistry.validCategoryKeys }
    ...
}
```

Both the category list and `validCategoryKeys` are computed (not stored): the picker reflects `CategoryRegistry.update(with:)` results on the next render without touching this file. `validCategoryKeys` on the picker is a deprecated forwarder — new code should use `CategoryRegistry.validCategoryKeys` directly. The empty-string `""` key (Nessuna) is **not** included in `validCategoryKeys`, so validity checks only pass when a concrete category is selected.

## Category Source

`CategoryRegistry.categories` returns `[(key:label:)]` pairs — the live server snapshot after `update(with:)`, or the embedded fallback (mirror of backend `CATEGORY_LABELS`) on first launch/offline. The row button shows the selected label (or `"Nessuna"` for `""`):

```swift
Button {
    showCategoryList = true
} label: {
    HStack {
        Text("Categoria")
        Spacer()
        Text(selectedLabel)
            .foregroundStyle(Color.textSecondary)
        Image(systemName: "chevron.down")
            ...
    }
}
.sheet(isPresented: $showCategoryList) {
    categorySheet
}
```

## Grouping

Sections come from the pure, UI-free `groupedRows(categories:compartmentMap:order:)` helper, covered by `CategoryPickerTests`:

```swift
static func groupedRows(
    categories: [(key: String, label: String)],
    compartmentMap: [String: String],
    order: [String]
) -> [(compartment: String, rows: [(key: String, label: String)])]
```

- `order` is `Compartment.supermarketOrder` (the canonical 10-department order from [Shopping Departments](../concepts/shopping-departments.md)); sections follow that order regardless of category input order.
- Categories with no map entry (or a department outside `order`, e.g. a new server-side category) land in `fallbackCompartment = "Altro"` or a trailing own section sorted by name — no category is ever dropped.
- The sheet renders a leading `"Nessuna"` row (deselects to `selection = ""`) plus one `Section` per group; headers reuse the department icon via `Compartment(rawValue:)` (`Label(compartment.label, systemImage: compartment.icon)`), falling back to plain text for unknown departments. Rows are standard `List` rows (native ≥44pt hit target) with a checkmark on the current selection, presented with `.medium`/`.large` detents and a `Chiudi` toolbar button.

## Usage

```swift
@State private var selectedCategory: String = ""

CategoryPicker(selection: $selectedCategory)
```

## Usage Locations

- **[ManualEntryView](../components/ios-manual-entry-view.md)** — category selection during manual product entry
- **[ScanPreviewSheet](../components/ios-scan-preview-sheet.md)** — category selection after scanning a barcode

Both embed the picker in a `Form` `Section` without changes — the public `CategoryPicker(selection:)` interface is unchanged from the flat-picker era.

## Notes

- Rows expose explicit accessibility behavior: the button carries label/value/hint (`"Apri l'elenco delle categorie raggruppate per reparto"`), each row replicates its tap action via `.accessibilityAction` because `.onTapGesture` alone does not expose a native Activate action to VoiceOver.
- The picker label is hardcoded to `"Categoria"` (Italian).
- Category selections feed into the [expiration date estimation](../concepts/expiration-estimation.md) system — when no expiration date is provided, the selected category determines the default shelf life via the backend's `DEFAULT_SHELF_LIFE` mapping (with `CATEGORY_ALIASES` covering singular/plural variants).

## Related

- [Category Registry](../concepts/category-registry.md) — live category/compartment source this picker renders
- [Shopping Departments](../concepts/shopping-departments.md) — canonical department order and compartment inference
