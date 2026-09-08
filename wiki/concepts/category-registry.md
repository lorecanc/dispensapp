---
title: "Category Registry"
description: "Server-driven category/compartment/storage registry on iOS — CategoryRegistry.update(with:) from GET /api/categories with embedded offline fallback"
category: "concepts"
source_files:
  - "backend/routes/categories.py"
  - "ios/Inventario/Models/CategoryRegistry.swift"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/InventarioTests/CategoryRegistryTests.swift"
created: "2026-09-05"
last_updated: "2026-09-06"
---

# Category Registry

`CategoryRegistry` (`ios/Inventario/Models/CategoryRegistry.swift`) is the iOS source of truth for category keys/labels, the canonical category-key → compartment map, and the category-key → storage-location maps. It is server-driven: whoever fetches `GET /api/categories` (store, T10 consumer) passes the `APIClient.fetchCategories()` result to `update(with:)`. The embedded snapshot is the offline/first-launch fallback only.

## Public API

| Member | Description |
|--------|-------------|
| `categories` | Ordered `[(key:label:)]` pairs (pickers, chips, detail/scan views) |
| `validCategoryKeys` | `Set` of keys derived from `categories` |
| `displayName(for:)` | Label for a key, falling back to the raw key when unknown (case-sensitive) |
| `compartmentMap` | Canonical `[categoryKey: compartmentName]` map (mirrors backend `COMPARTMENT_MAP`) |
| `storageDefaults` | Canonical `[categoryKey: storageCode]` map (mirrors backend `CATEGORY_STORAGE_DEFAULT`) |
| `storageLabels` | `[storageCode: displayLabel]` map (mirrors backend `STORAGE_LOCATION_LABELS`) |
| `storageLocation(for:)` | Default storage code for a key; unknown keys fall back to `"dispensa"` |
| `storageCodes` | Known storage codes in picker display order: `["frigo", "freezer", "dispensa"]` |
| `storageLabel(for:)` | Display label for a code, falling back to the raw code when unknown |
| `storageIcon(for:)` | SF Symbol for a code (`refrigerator.fill` / `snowflake` / `cabinet.fill`), `nil` for unknown codes |

All access is serialized through an `NSLock`; the mutable `current` snapshot uses the `nonisolated(unsafe)` Swift-6-safe pattern.

## Snapshot

The registry state is a single `Snapshot` value with four fields — categories, compartment map, and the two additive storage maps:

```swift
private struct Snapshot {
    var categories: [(key: String, label: String)]
    var compartmentMap: [String: String]
    var storageDefaults: [String: String]
    var storageLabels: [String: String]
}
```

`update(with:)` replaces the whole snapshot; `resetToEmbedded()` restores the embedded fallback (test isolation / offline recovery).

## Update Flow

1. `APIClient.fetchCategories()` (`APIClient.swift:354`) performs `GET api/categories` and decodes a `CategoriesResponse`. Consumed are `categories` (key/label/`storage_location`) plus `compartmentMap` and `storageLocationLabels`; `defaultShelfLifeDays`, `labels`, `compartments` stay optional so backend evolution never breaks decoding.
2. `CategoryRegistry.update(with:)` replaces the whole snapshot with the server response. An empty `categories` list is ignored — the current snapshot is kept, so a degraded server response never wipes the registry.
3. The same anti-wipe guard applies to the additive storage fields: per-item `storage_location` values are collected into `payloadDefaults` and `storage_location_labels` into `payloadLabels`; when either is missing or empty the current map is kept instead of being cleared:

```swift
current = Snapshot(
    categories: response.categories.map { (key: $0.key, label: $0.label) },
    compartmentMap: response.compartmentMap,
    storageDefaults: payloadDefaults.isEmpty ? current.storageDefaults : payloadDefaults,
    storageLabels: payloadLabels.isEmpty ? current.storageLabels : payloadLabels
)
```

This means a backend that predates the storage fields (nil labels, no per-item locations) updates categories/compartments normally while leaving the storage maps untouched — and a newer payload replaces them wholesale. `InventoryStore.refreshCategoryRegistry()` (`InventoryStore.swift:252`) drives the fetch best-effort and non-critical: offline keeps the embedded fallback with no error banner, and a `categoriesSynced` flag makes the fetch once-per-session.

## Embedded Fallback

The embedded snapshot is a static copy of the backend registry ([Backend Configuration](../config/backend-config.md) `CATEGORY_LABELS` + `COMPARTMENT_MAP` + `CATEGORY_STORAGE_DEFAULT` + `STORAGE_LOCATION_LABELS`): 26 categories with Italian labels (e.g. `yogurts` → `Yogurt`, `cleaning-hygiene` → `Igiene e pulizia`), the compartment map (e.g. `yogurts` → `Latticini e Uova`, `alcoholic-beverages` → `Cantina`), 26 storage defaults (7 `frigo` including `fresh-milk`/`meat`/`fish`, 1 `freezer` for `frozen-foods`, 18 `dispensa` including `pasta`/`eggs`/`alcoholic-beverages`), and 3 storage labels (`frigo` → `Frigo`, `freezer` → `Freezer`, `dispensa` → `Dispensa`). It can drift from the server; `update(with:)` takes precedence once `/api/categories` is fetched.

## Backend Contract

`GET /api/categories` (`backend/routes/categories.py:15-36`) returns one `storage_location` per item plus the label table:

```python
{"key": key, "label": ..., "shelf_life_days": days,
 "compartment": COMPARTMENT_MAP.get(key),
 "storage_location": storage_for_category(key)}
# top level: "storage_location_labels": STORAGE_LOCATION_LABELS
```

`storage_for_category` normalizes via `normalize_category` and falls back to `DEFAULT_STORAGE` (`"dispensa"`) for unknown keys — the same fallback `storageLocation(for:)` applies client-side.

## Consumers

- `Compartment.inferCompartment` resolves via the registry map first (including the `off:`-prefixed `prefix:key` form), then falls back to local name-keyword matching, defaulting to `Dispensa Secca` (`CategoryRegistryTests.swift:229-252`).
- [CategoryPicker](../components/ios-category-picker.md) reads `categories` and `compartmentMap` live at each render to build its 2-level department-grouped sheet.
- Storage UI reads the storage maps: `InventoryRowView` shows a badge from `item.storageLocation ?? storageLocation(for:)` with `storageLabel(for:)`/`storageIcon(for:)`; `ManualEntryView` and `ScanPreviewSheet` default the storage picker from `storageLocation(for: selectedCategory)` until the user touches it.

## Tests

`ios/InventarioTests/CategoryRegistryTests.swift` covers: embedded labels/count (26) and key uniqueness, unknown-key fallback, `compartmentMap` fallback, update-replaces-snapshot, reset-restores-embedded, empty-update-is-ignored (both on embedded and updated snapshots), decoding without optional fields, storage known-key/fallback lookups, update-with-storage-fields-replaces-maps, update-without-storage-fields-keeps-current-maps (both from embedded and from a prior storage payload), reset-restores-storage-maps, `storage_location` JSON decoding, and `Compartment` inference following registry updates.

## Related

- [CategoryPicker](../components/ios-category-picker.md) — 2-level category sheet built on this registry
- [Shopping Departments](./shopping-departments.md) — compartment inference and the storage-derivation backend twin
