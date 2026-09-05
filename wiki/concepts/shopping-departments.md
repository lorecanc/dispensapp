---
title: "Shopping Departments"
description: "Supermarket compartments model, legacy normalization, spesa UI cleanup, and authenticated suggestions"
category: "concepts"
source_files:
  - "backend/services/compartment.py"
  - "backend/services/shopping_markdown.py"
  - "backend/routes/suggestions.py"
  - "ios/Inventario/State/ShoppingStore.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingModels.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingListView.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
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

- **Backend** — `_normalize_tag` (`compartment.py:30-40`): `split(":")[-1]`, `OFF_TO_INTERNAL`, then `CATEGORY_ALIASES`. `_normalize_compartment` (`shopping_markdown.py:31-43`): legacy map `frigo → Latticini e Uova`, `cantina → Cantina`, `dispensa/altro → Dispensa Secca`, plus case-insensitive canonical match.
- **iOS** — `Compartment.normalized(_:)` (`ShoppingModels.swift:111-126`): same legacy map + case-insensitive match + `Dispensa Secca` fallback. `Compartment.resolved(for:)` (`129-147`) prefers a saved known/legacy compartment, resolves old category-valued strings via the registry, otherwise infers from the item name.

Backend `infer_compartment` cascade: OFF tags → explicit category → `_KEYWORD_MAP` name match → default. iOS mirrors the keyword table locally as an offline display heuristic (documented partial-dedup debt in `ShoppingModels.swift:169-171`); OFF aliases are intentionally not replicated client-side since the backend normalizes at persistence time.

## Spesa Cleanup

- **No dispensa reference** — the add-item form is name + quantity only (`ShoppingListView.swift:340-370`); `store.addItem` passes `compartment: nil` on manual entry so the backend infers it (`ShoppingStore.swift:88-97`, `ShoppingListView.swift:352`). Compartment appears only as a non-editable badge (`Compartment.resolved(for:)` at `ShoppingListView.swift:409`) and section header.
- **Grouping** — `groupedItems` (`ShoppingListView.swift:19-28`) groups by `Compartment.resolved(for:)` and orders by `supermarketOrder`; sections are `DisclosureGroup`s, all expanded by default (`expandedCompartments` initialized from `supermarketOrder`).
- **Export sheet-only** — markdown export lives solely in the trailing overflow `Menu` (`ShoppingListView.swift:253-270`) → `store.exportMarkdown` → `exportShoppingMarkdown` → sheet with monospaced `Text` + `ShareLink` (`456-488`). No export button elsewhere, no dispensa navigation.
- **Optimistic check toggle** — `toggleChecked` flips locally and reverts on error (`ShoppingStore.swift:113-136`); delete rolls back the list on failure (`51-68`).

## Suggestions Behind Auth

`GET /api/suggestions` (`backend/routes/suggestions.py:11-36`) requires `require_known_token`: valid-but-unknown tokens get 401, so anonymous clients cannot enumerate `ScanHistory`. Optional `q` prefix filter (`ilike`), ordered by `times_scanned DESC, last_scanned_at DESC`, capped at 10, returning only `{barcode, name, category, times_scanned}`.

iOS treats suggestions as non-critical (`ShoppingStore.swift:165-177`): empty query clears, failures reset to `[]` without touching `error`. `ShoppingListView` debounces (350 ms, min 2 chars), tapping a suggestion infers its compartment from category-then-name and adds it directly (`ShoppingListView.swift:119-168`).

## Gotchas

- Legacy strings (`frigo`, `dispensa`, …) still in old rows normalize silently on both sides — don't migrate data, the mapping is the compatibility layer.
- Unknown compartment strings don't crash the exporter; they land in `## 📦 Altro` server-side, while iOS falls back to name inference — the two can disagree on garbage input.
- `tonno fresco` matches the Carne e Pesce keyword rule before the Dispensa Secca `tonno` rule — keyword order matters.
