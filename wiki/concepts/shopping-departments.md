---
title: "Shopping Departments"
description: "Supermarket compartments model, legacy normalization, category suggestion cascade, storage derivation, spesa UI cleanup, and authenticated suggestions"
category: "concepts"
source_files:
  - "backend/services/compartment.py"
  - "backend/config.py"
  - "backend/services/shopping_markdown.py"
  - "backend/routes/suggestions.py"
  - "ios/Inventario/State/ShoppingStore.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingModels.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingListView.swift"
created: "2026-09-05"
last_updated: "2026-09-06"
---

# Shopping Departments

## Purpose

The 10 supermarket aisles ("reparti") that replace the legacy `frigo/cantina/dispensa/altro` buckets everywhere: backend inference and markdown export, iOS `Compartment` enum with offline keyword fallback, and the spesa UI which groups by inferred compartment with no manual compartment picker.

## The 10 Compartments

Canonical order (`SUPER_MARKET_COMPARTMENTS` in `backend/config.py`, mirrored by `Compartment.supermarketOrder` in `ShoppingModels.swift`):

`Ortofrutta` → `Latticini e Uova` → `Salumi e Formaggi` → `Carne e Pesce` → `Surgelati` → `Dispensa Secca` → `Bevande` → `Cantina` → `Forno e Panetteria` → `Igiene e Casa`

`COMPARTMENT_MAP` binds internal category keys to aisles (e.g. `fresh-fruits`/`fresh-vegetables` → Ortofrutta, `canned-fish` → Dispensa Secca, `alcoholic-beverages` → Cantina, `cleaning-hygiene` → Igiene e Casa). `/api/categories` exposes `compartments` + `compartment_map`; iOS [`CategoryRegistry.compartmentMap`](./category-registry.md) is its client-side mirror.

## Normalization

Both sides normalize identically; unknown input defaults to `Dispensa Secca`, never errors:

- **Backend** — `_normalize_tag` (`compartment.py:35-45`): `split(":")[-1]`, `OFF_TO_INTERNAL`, then `CATEGORY_ALIASES`. `_normalize_compartment` (`shopping_markdown.py:31-43`): legacy map `frigo → Latticini e Uova`, `cantina → Cantina`, `dispensa/altro → Dispensa Secca`, plus case-insensitive canonical match.
- **iOS** — `Compartment.normalized(_:)` (`ShoppingModels.swift:111-126`): same legacy map + case-insensitive match + `Dispensa Secca` fallback. `Compartment.resolved(for:)` (`129-147`) prefers a saved known/legacy compartment, resolves old category-valued strings via the registry, otherwise infers from the item name.

Backend `infer_compartment` cascade: OFF tags → explicit category → `_KEYWORD_MAP` name match → default. iOS mirrors the keyword table locally as an offline display heuristic (documented partial-dedup debt in `ShoppingModels.swift:169-171`); OFF aliases are intentionally not replicated client-side since the backend normalizes at persistence time. The keyword table ends with a pet-food row (`crocchette`, `pet-food`, `dog-food`, `cat-food` → Dispensa Secca), and `OFF_TO_INTERNAL` carries four cosmetics aliases (`cosmetics`, `shampoos`, `soaps`, `toothpastes` → `cleaning-hygiene`).

## Category Suggestion

`suggest_category` (`compartment.py:95-130`) proposes an internal category from OFF data (`off_category_tags` + `pnns_group`), returning `None` when nothing matches:

1. **Storage override** — `frozen-foods` wins over everything (freezer before canned goods); otherwise the first normalized `canned-vegetables`/`canned-fish` tag wins.
2. **First tag in `COMPARTMENT_MAP`** — the first normalized tag that is a known internal category.
3. **`PNNS_TO_INTERNAL` fallback** — coarse `pnns_groups_1` slug lookup (`config.py:229-240`): `fish-meat-eggs` → `meat`, `milk-and-dairy-products` → `fresh-milk`, `sugary-snacks`/`salty-snacks` → `sweets-snacks`, `fruits-and-vegetables` → `fresh-vegetables`, `cereals-and-potatoes` → `pasta`, `fat-and-sauces` → `oils-vinegars`, `beverages` → `beverages-juices` (`composite-foods` is intentionally excluded as too generic).
4. **`None`** — no suggestion.

## Storage Derivation

`storage_for_category` (`compartment.py:87-92`) is the backend twin of [`CategoryRegistry.storageLocation(for:)`](./category-registry.md): it normalizes via `normalize_category` and looks up `CATEGORY_STORAGE_DEFAULT` (`config.py:70-100`), falling back to `DEFAULT_STORAGE` (`"dispensa"`) for unknown keys. `GET /api/categories` ships the result per item as `storage_location` plus `storage_location_labels` (`Frigo`/`Freezer`/`Dispensa`), so the iOS registry mirrors the backend derivation without duplicating the table.

## Spesa Cleanup

- **No dispensa reference** — the add-item form is name + quantity only (`ShoppingListView.swift:340-370`); `store.addItem` passes `compartment: nil` on manual entry so the backend infers it (`ShoppingStore.swift:88-97`, `ShoppingListView.swift:352`). Compartment appears only as a non-editable badge (`Compartment.resolved(for:)` at `ShoppingListView.swift:409`) and section header.
- **Grouping** — `groupedItems` (`ShoppingListView.swift:19-28`) groups by `Compartment.resolved(for:)` and orders by `supermarketOrder`; sections are `DisclosureGroup`s, all expanded by default (`expandedCompartments` initialized from `supermarketOrder`). [CategoryPicker](../components/ios-category-picker.md) reuses the same `supermarketOrder` for its sheet sections.
- **Export sheet-only** — markdown export lives solely in the trailing overflow `Menu` (`ShoppingListView.swift:253-270`) → `store.exportMarkdown` → `exportShoppingMarkdown` → sheet with monospaced `Text` + `ShareLink` (`456-488`). No export button elsewhere, no dispensa navigation.
- **Optimistic check toggle** — `toggleChecked` flips locally and reverts on error (`ShoppingStore.swift:113-136`); delete rolls back the list on failure (`51-68`).

## Suggestions Behind Auth

`GET /api/suggestions` (`backend/routes/suggestions.py:11-36`) requires `require_known_token`: valid-but-unknown tokens get 401, so anonymous clients cannot enumerate `ScanHistory`. Optional `q` prefix filter (`ilike`), ordered by `times_scanned DESC, last_scanned_at DESC`, capped at 10, returning only `{barcode, name, category, times_scanned}`.

iOS treats suggestions as non-critical (`ShoppingStore.swift:165-177`): empty query clears, failures reset to `[]` without touching `error`. `ShoppingListView` debounces (350 ms, min 2 chars), tapping a suggestion infers its compartment from category-then-name and adds it directly (`ShoppingListView.swift:119-168`).

## Gotchas

- Legacy strings (`frigo`, `dispensa`, …) still in old rows normalize silently on both sides — don't migrate data, the mapping is the compatibility layer.
- Unknown compartment strings don't crash the exporter; they land in `## 📦 Altro` server-side, while iOS falls back to name inference — the two can disagree on garbage input.
- `tonno fresco` matches the Carne e Pesce keyword rule before the Dispensa Secca `tonno` rule — keyword order matters.
- `suggest_category` and `infer_compartment` are different cascades: the former proposes a *category* (frozen-override → tag → PNNS → None), the latter resolves a *department* (OFF tags → category → keywords → Dispensa Secca). Don't conflate their defaults — suggestion may return `None` where inference never does.
