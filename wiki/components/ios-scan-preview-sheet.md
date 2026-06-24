---
title: "iOS Scan Preview Sheet"
description: "Scan result preview and save form for the Inventario iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Scan/ScanPreviewSheet.swift"
  - "ios/Inventario/Models/ScanResult.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# iOS Scan Preview Sheet

## Purpose

Presents a form with product data fetched from a barcode scan lookup (via Open Food Facts). Allows the user to review, edit, and save the product to inventory. Handles the loading, found, not-found, and error states of the scan API call.

## Entry Point

`ScanPreviewSheet` is presented as a `.sheet(item:)` from [ScannerViewWrapper](../components/ios-scanner-view.md) in the scanner view. It receives the scanned barcode string via the `barcode` property.

```swift
struct ScanPreviewSheet: View {
    let barcode: String
    // ...
}
```

## State Properties

| Property | Type | Default | Purpose |
|---|---|---|---|
| `scanResult` | `ScanResult?` | `nil` | Decoded response from the scan API |
| `isLoading` | `Bool` | `true` | Active while the scan API call is in flight |
| `error` | `APIError?` | `nil` | Set if the scan API call throws |
| `name` | `String` | `""` | Product name, pre-filled from API or edited by user |
| `brand` | `String` | `""` | Product brand, pre-filled from API |
| `selectedCategory` | `String` | `""` | Category key, pre-filled if match in `CategoryPicker.validCategoryKeys` |
| `expirationDate` | `Date` | `now + 30 days` | Default expiration |
| `quantity` | `Int` | `1` | Item count |
| `isSaving` | `Bool` | `false` | Disables save button while `store.add()` is in progress |
| `showError` | `Bool` | `false` | Controls save-failure alert |
| `errorMessage` | `String` | `""` | Localized error description shown in the alert |

## ScanResult Model

[ScanResult](../concepts/ios-models.md) is defined as a `Codable` struct:

```swift
struct ScanResult: Codable {
    let barcode: String
    let name: String?
    let brand: String?
    let categories: [String]
    let imageURL: String?
    let found: Bool
    let message: String?
}
```

The `found` field distinguishes between a product that was resolved via Open Food Facts (`true`) and one that was not found (`false`). When `found` is `false`, `name` and `brand` are typically `nil` and `message` contains guidance text.

## Lifecycle

### 1. Load Scan Result

The `.task` modifier calls `loadScanResult()` immediately on appear:

```swift
.task {
    await loadScanResult()
}
```

`loadScanResult` performs the [network call](../concepts/ios-networking.md) (to the [scan API endpoint](../api/scan.md)) and populates the editable fields:

```swift
private func loadScanResult() async {
    isLoading = true
    do {
        let result = try await client.scan(barcode: barcode)
        scanResult = result
        name = result.name ?? ""
        brand = result.brand ?? ""
        let rawCategory = result.categories.first ?? ""
        selectedCategory = [CategoryPicker](../components/ios-category-picker.md)`.validCategoryKeys.contains(rawCategory) ? rawCategory : ""
    } catch {
        self.error = error as? APIError ?? .transport(error)
    }
    isLoading = false
}
```

Key behaviors:
- Only the first category from `result.categories` is used if it matches `[CategoryPicker](../components/ios-category-picker.md)`.validCategoryKeys`.
- If the category from the API is not in the valid set, `selectedCategory` remains `""` (no category).

### 2. Render States

The body switches on three states:

```swift
if isLoading {
    ProgressView("Caricamento...")
} else if let error {
    ContentUnavailableView("Errore", systemImage: "exclamationmark.triangle", ...)
} else if let result = scanResult {
    formView(result: result)
}
```

| State | UI |
|---|---|
| Loading | Centered `ProgressView` with "Caricamento..." label |
| Error | `ContentUnavailableView` with the error's `localizedDescription` |
| Success | Full form view (see below) |

### 3. Form View Sections

The form (`formView`) is built inside a `Form` with up to four sections:

#### Product Image Section

If `result.imageURL` is present, an `AsyncImage` renders the product photo. It handles three phases:
- **`success`**: resizable image, aspect ratio `.fit`, max height 200, rounded corners.
- **`failure`**: placeholder rounded rectangle with a `photo` system image.
- **`empty`**: placeholder with a `ProgressView` spinner.

#### "Prodotto non trovato" Warning

Only shown when `result.found == false`:

```swift
if !result.found {
    Section {
        VStack(alignment: .leading, spacing: 8) {
            Label("Prodotto non trovato", systemImage: "exclamationmark.magnifyingglass")
                .foregroundStyle(.orange)
            Text(result.message ?? "Inserisci i dati manualmente.")
        }
    }
}
```

#### Details Section

- Barcode display: monospaced, secondary color.
- Name field: `TextField("Nome *", text: $name)`, autocorrection disabled, required (save disabled when empty).
- Brand field: `TextField("Marca", text: $brand)`, optional.

#### Picker & Date Section

- **CategoryPicker**: A SwiftUI `Picker` with a "Nessuna" (none) default and a fixed list of Italian category labels (yogurt, fresh-milk, pasta, canned-vegetables, rice, cheeses, eggs, fresh-fruits, fresh-vegetables, frozen-foods). Binds to `selectedCategory`.
- **DatePicker**: Date component only, defaulting to 30 days from now.
- **[QuantityStepper](../components/ios-quantity-stepper.md)**: A `Stepper` with range `1...99`, label "Quantità: X".

### 4. Save Flow

The toolbar "Salva" button is disabled when:
- The name field is empty (after trimming whitespace).
- `isSaving` is `true`.

On tap, it runs `saveItem()`:

```swift
private func saveItem() async {
    isSaving = true
    await store.add(
        barcode: barcode,
        name: name.trimmingCharacters(in: .whitespaces),
        brand: brand.trimmingCharacters(in: .whitespaces).nilIfEmpty,
        expirationDate: expirationDate,
        category: selectedCategory.nilIfEmpty,
        imageURL: scanResult?.imageURL,
        quantity: quantity
    )
    isSaving = false
    if let error = store.error {
        errorMessage = error.localizedDescription
        showError = true
    } else {
        dismiss()
    }
}
```

The save delegates to [InventoryStore.add(...)](../concepts/ios-state-management.md) which:
1. Calls `APIClient.create(...)` — a POST to `/api/inventory`.
2. Appends the returned `InventoryItem` to the local `items` array.
3. Re-sorts items by `expirationDate`.
4. Sets `store.error` on failure.

If save succeeds, the sheet dismisses. If save fails, a `.alert` modifier shows the error with an "OK" button.

### 5. Dismissal

The toolbar "Annulla" button calls `dismiss()` at any point, discarding unsaved changes.

## Error Handling

| Scenario | Mechanism | User Experience |
|---|---|---|
| Scan API failure (network, server error) | `loadScanResult` catches and sets `error` | Full-screen `ContentUnavailableView` with error description |
| Save failure (API call in `store.add`) | `store.error` read after save | `.alert` modal with localized error message |
| Empty name on save | Disabled "Salva" button | No action possible until name is filled |

## Navigation

The sheet is wrapped in a `NavigationStack` with:
- Title: "Prodotto scansionato", displayed inline.
- Leading toolbar: "Annulla" (cancellation action) — dismisses the sheet.
- Trailing toolbar: "Salva" (confirmation action) — triggers save.
