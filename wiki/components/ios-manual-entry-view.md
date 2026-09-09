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
last_updated: "2026-09-09"
---

# ManualEntryView (iOS)

## Purpose

`ManualEntryView` is a SwiftUI form that lets users add inventory items by typing product details (name, brand), selecting a category, picking an expiration date, and setting a quantity. It supports prefill via `init(initialName:initialCategory:)` and live name suggestions from the pantry, calls [InventoryStore.addManual(...)](../concepts/ios-state-management.md) on save, and dismisses on success.

## Initialization / Prefill

```swift
let initialName: String
let initialCategory: String

init(initialName: String = "", initialCategory: String = "") {
    self.initialName = initialName
    self.initialCategory = initialCategory
}
```

Defaults are empty so existing call sites are unchanged. On `.onAppear` the view copies the initials into state only if the corresponding state is still empty:

```swift
.onAppear {
    if name.isEmpty && !initialName.isEmpty { name = initialName }
    if selectedCategory.isEmpty && !initialCategory.isEmpty { selectedCategory = initialCategory }
}
```

This is used for prefill from a pantry-suggestion tap in the inventory list.

## Form Structure

The view is a `Form` with three sections:

1. **"Dettagli prodotto"** — Two text fields plus an inline suggestion list:
   - `Nome *` (required) — bound to `name`, trimmed whitespace must be non-empty for the form to be valid.
   - Suggestion rows (rendered only when `suggestions` is non-empty, directly below the `Nome` field) — each row shows the suggestion name, its display category, and a `×timesScanned` count.
   - `Marca` (optional) — bound to `brand`, passed as `String?` via the `nilIfEmpty` extension.

 2. **Implicit section** — Contains three controls:
    - [CategoryPicker](../components/ios-category-picker.md) — a `Picker` bound to `selectedCategory`, fed by the server-driven [CategoryRegistry](../concepts/category-registry.md) plus a "Nessuna" default option (empty string tag).
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

## Name Suggestions

A `.task(id: name)` modifier debounces input and fetches pantry-scoped suggestions:

```swift
.task(id: name) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard trimmed.count >= 2 else { suggestions = []; return }
    try? await Task.sleep(for: .milliseconds(350))
    guard !Task.isCancelled else { return }
    do {
        suggestions = try await APIClient.shared.fetchSuggestions(q: trimmed, scope: "pantry")
    } catch {
        suggestions = []
    }
}
```

- No request until the trimmed name is at least 2 characters; shorter input clears the list.
- 350 ms debounce via `Task.sleep`; a new keystroke cancels the previous task (`Task.isCancelled` guard).
- Scope is always `"pantry"`; failures clear the list rather than surfacing an error.

Tapping a suggestion fills the form and clears the list:

```swift
Button {
    name = sug.name
    if let cat = sug.category, !cat.isEmpty {
        selectedCategory = cat
        storageTouched = false
    }
    suggestions = []
}
```

The suggestion name overwrites `name`, its non-empty category overwrites `selectedCategory` and resets `storageTouched` (so the derived storage location follows the new category), and the list is cleared.

## Save Flow

`saveItem()` is called inside a `Task` when the user taps "Salva":

1. Sets `isSaving = true` (disables the button, shows spinner).
2. Calls `store.addManual(...)` with trimmed `name`, trimmed `brand.nilIfEmpty`, `expirationDate`, `selectedCategory.nilIfEmpty`, `quantity`, and `storageLocation: storageTouched ? selectedStorage : nil` (nil preserves the category-derived default).
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
| `CategoryPicker` | Server-driven picker (CategoryRegistry) for the category |
| `QuantityStepper` | Reusable stepper for quantity (1–99) |

## Store Method: `addManual`

`InventoryStore.addManual(name:brand:expirationDate:category:quantity:)` goes through the offline-first path: when offline it enqueues a local create in the [outbox](../concepts/ios-offline-outbox.md) and returns; online it calls the pantry-scoped `client.createManualScoped(pantryId:selectedPantryId, ...)`, appends the returned `InventoryItem` to `items`, and re-sorts the list by expiration date.

```swift
func addManual(
    name: String,
    brand: String?,
    expirationDate: Date?,
    category: String?,
    quantity: Int
) async {
    error = nil
    if isOffline {
        enqueueLocalCreate(barcode: nil, name: name, brand: brand, expirationDate: expirationDate, category: category, imageURL: nil, quantity: quantity)
        return
    }
    do {
        let item = try await client.createManualScoped(
            pantryId: selectedPantryId,
            name: name,
            brand: brand,
            expirationDate: expirationDate,
            category: category,
            quantity: quantity
        )
        guard !Task.isCancelled else { return }
        items.append(item)
        items.sort { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }
    } catch {
        if Task.isCancelled { return }
        self.error = error as? APIError ?? .transport(error)
    }
}
```
