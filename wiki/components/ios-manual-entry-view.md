---
title: "ManualEntryView (iOS)"
description: "SwiftUI form for manually adding inventory items"
category: "components"
source_files:
  - "ios/Inventario/Features/ManualEntry/ManualEntryView.swift"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/Components/CategoryPicker.swift"
  - "ios/Inventario/Components/QuantityStepper.swift"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# ManualEntryView (iOS)

## Purpose

`ManualEntryView` is a SwiftUI form that lets users add inventory items by typing product details (name, brand), selecting a category, picking an expiration date, and setting a quantity. It calls [InventoryStore.addManual(...)](../concepts/ios-state-management.md) on save and dismisses on success.

## Form Structure

The view is a `Form` with three sections:

1. **"Dettagli prodotto"** — Two text fields:
   - `Nome *` (required) — bound to `name`, trimmed whitespace must be non-empty for the form to be valid.
   - `Marca` (optional) — bound to `brand`, passed as `String?` via the `nilIfEmpty` extension.

2. **Implicit section** — Contains three controls:
   - [CategoryPicker](../components/ios-category-picker.md) — a `Picker` bound to `selectedCategory`. Lists ten categories (yogurt, fresh-milk, pasta, etc.) plus a "Nessuna" default option (empty string tag).
   - `DatePicker` — "Data di scadenza" bound to `expirationDate`. Defaults to 30 days from now (`Date().addingTimeInterval(86400 * 30)`).
   - [QuantityStepper](../components/ios-quantity-stepper.md) — bound to `quantity`, a `Stepper` in range `1...99`. Defaults to `1`.

3. **Save section** — A full-width "Salva" button that is disabled when `isFormValid` is false or `isSaving` is true. While saving, a `ProgressView` replaces the button label.

## Validation

```swift
private var isFormValid: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
}
```

The form is considered valid if the trimmed `name` is non-empty. There is no validation for brand, category, date, or quantity.

## Save Flow

`saveItem()` is called inside a `Task` when the user taps "Salva":

1. Sets `isSaving = true` (disables the button, shows spinner).
2. Calls `store.addManual(...)` with trimmed `name`, `brand.nilIfEmpty`, `expirationDate`, `selectedCategory.nilIfEmpty`, and `quantity`.
3. Sets `isSaving = false`.
4. Checks `store.error`:
   - If non-nil: sets `errorMessage` to the error's `localizedDescription` and toggles `showError` to present an alert.
   - If nil: calls `dismiss()` to pop the view.

## Error Handling

Errors surfaced from the store (API failures, network errors) are displayed in a SwiftUI `.alert` with title "Errore" and the error's `localizedDescription` as the message. The dialog has a single "OK" button to dismiss it.

## Toolbar

A "Annulla" button is placed in the `.cancellationAction` toolbar position and calls `dismiss()` immediately.

## String Extension: `nilIfEmpty`

Defined at file scope in `ManualEntryView.swift`:

```swift
extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
```

This is used when passing optional fields (`brand`, `category`) to the store, so empty strings are converted to `nil` rather than sent as blank values to the API.

## Dependencies

| Component | Role |
|-----------|------|
| `InventoryStore` | Observable state container; provides the `addManual()` method and holds `error` after each operation |
| `CategoryPicker` | Reusable picker for the ten predefined categories |
| `QuantityStepper` | Reusable stepper for quantity (1–99) |

## Store Method: `addManual`

`InventoryStore.addManual(name:brand:expirationDate:category:quantity:)` calls `APIClient.createManual(...)`, appends the returned `InventoryItem` to `items`, and re-sorts the list by expiration date.

```swift
func addManual(
    name: String,
    brand: String?,
    expirationDate: Date?,
    category: String?,
    quantity: Int
) async {
    error = nil
    do {
        let item = try await client.createManual(
            name: name,
            brand: brand,
            expirationDate: expirationDate,
            category: category,
            quantity: quantity
        )
        items.append(item)
        items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    } catch {
        self.error = error as? APIError ?? .transport(error)
    }
}
```
