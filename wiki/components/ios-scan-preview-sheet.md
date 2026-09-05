---
title: "iOS Scan Preview Sheet"
description: "Scan result preview, save form, and Open Food Facts contribute flow for the Inventario iOS app"
category: "components"
source_files:
  - "ios/Inventario/Features/Scan/ScanPreviewSheet.swift"
  - "ios/Inventario/Models/ScanResult.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# iOS Scan Preview Sheet

## Purpose

Presents a form with product data fetched from a barcode scan lookup (via Open Food Facts). Allows the user to review, edit, and save the product to inventory. Handles the loading, found, not-found, and error states of the scan API call. When the product is missing or incomplete (`needsEnrichment`), offers a contribute form and photo upload to enrich Open Food Facts under CC BY-SA / ODbL consent (see [Contribute](../api/contribute.md)).

## Entry Point

`ScanPreviewSheet` is presented as a `.sheet(item:)` from `ScannerViewWrapper` in the scanner view. It receives the scanned barcode string via the `barcode` property, with an optional pre-fetched `result` for tests / previews:

```swift
struct ScanPreviewSheet: View {
    let barcode: String
    var result: ScanResult? = nil
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
| `selectedCategory` | `String` | `""` | Category key, pre-filled if match in `CategoryRegistry.validCategoryKeys` |
| `expirationDate` | `Date` | `now + 30 days` | Default expiration |
| `quantity` | `Int` | `1` | Item count |
| `isSaving` | `Bool` | `false` | Disables save button while `store.add()` is in progress |
| `showError` | `Bool` | `false` | Controls save-failure alert |
| `errorMessage` | `String` | `""` | Localized error description shown in the alert |
| `showContribute` | `Bool` | `false` | Expands the contribute form |
| `contributeName/Brands/Quantity/Categories/Labels/GenericName/Comment` | `String` | `""` | Contribute form fields |
| `consentCCBYSA` | `Bool` | `false` | Mandatory CC BY-SA / ODbL consent toggle, gates both send buttons |
| `contributeLoading` | `Bool` | `false` | In-flight flag for `client.contribute` |
| `contributeSuccessMessage` | `String?` | `nil` | Success text after contribute |
| `contributeError` | `APIError?` | `nil` | Contribute failure |
| `selectedPhotoItem` | `PhotosPickerItem?` | `nil` | PhotosPicker selection |
| `photoData` | `Data?` | `nil` | Loaded photo bytes |
| `photoFilename` / `photoMimeType` | `String` | `"foto.jpg"` / `"image/jpeg"` | Recomputed from magic bytes on select and on send |
| `selectedImageField` | `String` | `"front_it"` | Photo view: `front_it`, `ingredients_it`, `nutrition_it`, `packaging_it` |
| `photoLoading` | `Bool` | `false` | In-flight flag for `client.uploadPhoto` |
| `photoSuccessMessage` / `photoError` | `String?` / `APIError?` | `nil` | Photo upload outcome |

## ScanResult Model

`ScanResult` is a `Codable, Sendable` struct:

```swift
struct ScanResult: Codable, Sendable {
    let barcode: String
    let name: String?
    let brand: String?
    let categories: [String]
    let imageURL: String?
    let found: Bool
    let message: String?
}
```

The `found` field distinguishes a product resolved via Open Food Facts (`true`) from one not found (`false`). When `found` is `false`, `name` and `brand` are typically `nil` and `message` contains guidance text.

### needsEnrichment

```swift
var needsEnrichment: Bool {
    guard found else { return true }
    if name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { return true }
    return imageURL == nil
}
```

True when the product is missing (`found == false`), has a blank name, or has no image. Drives the "Arricchisci su Open Food Facts" CTA section in the form. A complete product (found + name + image) hides the contribute UI entirely.

## Lifecycle

### 1. Load Scan Result

The `.task` modifier calls `loadScanResult()` immediately on appear. If the injected `result` is present (tests/previews), it is applied directly with no network call:

```swift
private func loadScanResult() async {
    if let result {
        apply(result)
        isLoading = false
        return
    }
    isLoading = true
    do {
        let result = try await store.client.scan(barcode: barcode)
        apply(result)
    } catch {
        self.error = error as? APIError ?? .transport(error)
    }
    isLoading = false
}

private func apply(_ result: ScanResult) {
    scanResult = result
    name = result.name ?? ""
    brand = result.brand ?? ""
    let rawCategory = result.categories.first ?? ""
    selectedCategory = CategoryRegistry.validCategoryKeys.contains(rawCategory) ? rawCategory : ""
}
```

Key behaviors:
- Only the first category from `result.categories` is used if it matches `CategoryRegistry.validCategoryKeys`.
- If the API category is not in the valid set, `selectedCategory` remains `""` (no category). Valid keys come from the [Category Registry](../concepts/category-registry.md).

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

The form (`formView`) is built inside a `Form`:

#### Product Image Section

If `result.imageURL` is present, an `AsyncImage` renders the product photo with `success` / `failure` / `empty` phases (max height 200, rounded corners, pantry-themed placeholders).

#### "Prodotto non trovato" Warning

Only shown when `result.found == false`: orange headline label plus `result.message` fallback text.

#### Details Section

- Barcode display: monospaced, secondary color.
- Name field: `TextField("Nome *", text: $name)`, autocorrection disabled, required (save disabled when empty).
- Brand field: `TextField("Marca", text: $brand)`, optional.

#### Picker & Date Section

- **CategoryPicker**: binds to `selectedCategory`.
- **DatePicker**: date component only, defaulting to 30 days from now.
- **QuantityStepper**: range `1...99`.

#### Enrichment CTA Section

Rendered only when `result.needsEnrichment` is true (see §4–5).

### 4. Contribute Form (CC BY-SA Consent)

`contributeSection(barcode:)` renders the "Arricchisci su Open Food Facts" section. Collapsed state shows an explanatory text (data published under CC BY-SA / ODbL) and an "Arricchisci su Open Food Facts" button that calls `prefillContribute(from:)` (name/brand/categories pre-filled from scan result or manual fields) and expands the form.

Expanded form fields: product name, brands, quantity (e.g. 500g), comma-separated categories, comma-separated labels, generic name, comment — plus a mandatory consent toggle:

> "Acconsento alla pubblicazione di dati e foto con licenza CC BY-SA / ODbL su Open Food Facts, con cessione irrevocabile delle foto come da termini OFF. Obbligatorio per inviare."

Send behavior (`sendContribute(code:)` → `store.client.contribute`):
- Sends trimmed fields (`nilIfEmpty`), a per-install `appUUID` persisted in `UserDefaults` (`persistedAppUUID()`), and `consent: consentCCBYSA`.
- Send button disabled while `!consentCCBYSA || contributeLoading || isContributeEmpty` (at least one of name/brands/quantity/categories/labels/genericName required; "Inserisci almeno un campo" hint otherwise).
- Shows `ProgressView("Invio in corso...")`, then success label or error text with an "Invia contributo" / "Riprova" retry button.

### 5. Photo Upload (PhotosPicker + Multipart)

Below a `Divider` in the same section:
- `PhotosPicker(selection: $selectedPhotoItem, matching: .images)` ("Scegli una foto" / "Cambia foto"); `.onChange` loads bytes via `loadSelectedPhoto(code:)` (`loadTransferable(type: Data.self)`).
- `Picker("Tipo di foto")`: `front_it` (Fronte), `ingredients_it` (Ingredienti), `nutrition_it` (Valori nutrizionali), `packaging_it` (Confezione).
- Send behavior (`sendPhoto(code:)` → `store.client.uploadPhoto` multipart): recomputes filename/MIME from magic bytes via `photoFilenameAndMime(data:code:imagefield:)` — JPEG magic → `.jpg`/`image/jpeg`, PNG magic → `.png`/`image/png`, otherwise `.heic`/`image/heic`, named `<code>_<imagefield>.<ext>`. This recompute on send guards against a stale filename if `selectedImageField` changed after picking.
- "Invia foto" button disabled while `!consentCCBYSA || photoLoading || photoData == nil` ("Scegli una foto per continuare" hint). 5 MB JPEG/PNG/HEIC limit and CC BY-SA notice shown in footnote text. Success/error UI mirrors the contribute flow.

### 6. Save Flow

The toolbar "Salva" button (`.glassProminent` + `pantryMoss` tint on iOS 26+) is disabled when the trimmed name is empty or `isSaving` is true. On tap, `saveItem()` delegates to `InventoryStore.add(...)` (POST `/api/inventory`); on success the sheet dismisses, on failure a `.alert` shows the error. "Annulla" dismisses at any point, discarding unsaved changes.

## Internal Visibility (for Tests)

Members intentionally left `internal` (no `private`) so unit tests can exercise logic without UI:

| Member | Kind | Test use |
|---|---|---|
| `var result: ScanResult?` | stored property | Inject a fixture to skip the network call in `loadScanResult()` |
| `static let jpegMagic / pngMagic` | static constants | Magic-byte prefixes asserted in photo tests |
| `static func photoFilenameAndMime(data:code:imagefield:)` | static func | Filename/MIME mapping (jpg/png/heic fallback) |

Everything else (`persistedAppUUID()`, `sendContribute`, `sendPhoto`, `loadSelectedPhoto`, `apply`, `saveItem`, all `@State`) stays `private`.

## Error Handling

| Scenario | Mechanism | User Experience |
|---|---|---|
| Scan API failure (network, server error) | `loadScanResult` catches and sets `error` | Full-screen `ContentUnavailableView` with error description |
| Save failure (API call in `store.add`) | `store.error` read after save | `.alert` modal with localized error message |
| Empty name on save | Disabled "Salva" button | No action possible until name is filled |
| Contribute failure | `contributeError` set | Inline red error text + "Riprova" button |
| Photo load/send failure | `photoError` set | Inline red error text + "Riprova" button |

## Navigation

The sheet is wrapped in a `NavigationStack` with:
- Title: "Prodotto scansionato", displayed inline.
- Leading toolbar: "Annulla" (cancellation action) — dismisses the sheet.
- Trailing toolbar: "Salva" (confirmation action) — triggers save.
