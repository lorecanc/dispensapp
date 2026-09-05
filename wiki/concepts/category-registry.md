---
title: "Category Registry"
description: "Server-driven category/compartment registry on iOS — CategoryRegistry.update(with:) from GET /api/categories with embedded offline fallback"
category: "concepts"
source_files:
  - "ios/Inventario/Models/CategoryRegistry.swift"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/InventarioTests/CategoryRegistryTests.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
---

# Category Registry

`CategoryRegistry` (`ios/Inventario/Models/CategoryRegistry.swift`) is the iOS source of truth for category keys/labels and the canonical category-key → compartment map. It is server-driven: whoever fetches `GET /api/categories` (store, T10 consumer) passes the `APIClient.fetchCategories()` result to `update(with:)`. The embedded snapshot is the offline/first-launch fallback only.

## Public API

| Member | Description |
|--------|-------------|
| `categories` | Ordered `[(key:label:)]` pairs (pickers, chips, detail/scan views) |
| `validCategoryKeys` | `Set` of keys derived from `categories` |
| `displayName(for:)` | Label for a key, falling back to the raw key when unknown (case-sensitive) |
| `compartmentMap` | Canonical `[categoryKey: compartmentName]` map (mirrors backend `COMPARTMENT_MAP`) |

All access is serialized through an `NSLock`; the mutable `current` snapshot uses the `nonisolated(unsafe)` Swift-6-safe pattern.

## Update Flow

1. `APIClient.fetchCategories()` (`APIClient.swift:347`) performs `GET api/categories` and decodes a `CategoriesResponse`. Only `categories` (key/label) and `compartmentMap` are consumed; `defaultShelfLifeDays`, `labels`, `compartments` stay optional so backend evolution never breaks decoding.
2. `CategoryRegistry.update(with:)` replaces the whole snapshot with the server response. An empty `categories` list is ignored — the current snapshot is kept, so a degraded server response never wipes the registry.
3. `resetToEmbedded()` restores the embedded fallback (test isolation / offline recovery).

### Fetch Dedup

`InventoryStore.refreshCategoryRegistry()` (`InventoryStore.swift:252`) is best-effort and non-critical: offline keeps the embedded fallback with no error banner. A `categoriesSynced` flag makes the fetch once-per-session — the guard returns early when already synced, with one retry allowed only while a previous attempt failed.

## Embedded Fallback

The embedded snapshot is a static copy of the backend registry ([Backend Configuration](../config/backend-config.md) `CATEGORY_LABELS` + `COMPARTMENT_MAP`): 26 categories with Italian labels (e.g. `yogurts` → `Yogurt`, `cleaning-hygiene` → `Igiene e pulizia`) and the compartment map (e.g. `yogurts` → `Latticini e Uova`, `alcoholic-beverages` → `Cantina`). It can drift from the server; `update(with:)` takes precedence once `/api/categories` is fetched.

## Consumers

`Compartment.inferCompartment` resolves via the registry map first (including the `off:`-prefixed `prefix:key` form), then falls back to local name-keyword matching, defaulting to `Dispensa Secca` (`CategoryRegistryTests.swift:139-163`).

## Tests

`ios/InventarioTests/CategoryRegistryTests.swift` covers: embedded labels/count (26) and key uniqueness, unknown-key fallback, `compartmentMap` fallback, update-replaces-snapshot, reset-restores-embedded, empty-update-is-ignored (both on embedded and updated snapshots), decoding without optional fields, and `Compartment` inference following registry updates.
