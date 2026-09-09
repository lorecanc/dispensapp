---
title: "Shopping Departments"
description: "Supermarket compartments model, legacy normalization, category suggestion cascade, storage derivation, spesa UI cleanup, and authenticated suggestions"
category: "concepts"
source_files:
  - "backend/services/compartment.py"
  - "backend/routes/inventory.py"
  - "backend/config.py"
  - "backend/services/shopping_markdown.py"
  - "backend/routes/suggestions.py"
  - "ios/Inventario/State/ShoppingStore.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingModels.swift"
  - "ios/Inventario/Features/ShoppingList/ShoppingListView.swift"
created: "2026-09-05"
last_updated: "2026-09-09"
---

# Shopping Departments

## Purpose

The 11 supermarket aisles ("reparti") that replace the legacy `frigo/cantina/dispensa/altro` buckets everywhere: backend inference and markdown export, iOS `Compartment` enum with offline keyword fallback, inventory persistence with explicit-valid > suggest > None category priority, and the spesa UI which groups by inferred compartment with `CategoryPicker`-assisted manual entry plus a reused-scanner sheet.

## The 11 Compartments

Canonical order (`SUPER_MARKET_COMPARTMENTS` in `backend/config.py:300-312`, mirrored by `Compartment.supermarketOrder` in `ShoppingModels.swift:110-112`):

| # | Compartment | iOS icon |
|---|-------------|----------|
| 1 | Ortofrutta | leaf.fill |
| 2 | Latticini e Uova | drop.fill |
| 3 | Salumi e Formaggi | fork.knife |
| 4 | Carne e Pesce | fish.fill |
| 5 | Surgelati | snowflake |
| 6 | Dispensa Secca | cabinet.fill |
| 7 | Bevande | waterbottle.fill |
| 8 | Cantina | wineglass.fill |
| 9 | Forno e Panetteria | flame.fill |
| 10 | Igiene e Casa | sparkles |
| 11 | Animali | pawprint.fill |

`COMPARTMENT_MAP` (`config.py:315-343`) binds internal category keys to aisles (e.g. `fresh-fruits`/`fresh-vegetables` → Ortofrutta, `canned-fish` → Dispensa Secca, `alcoholic-beverages` → Cantina, `cleaning-hygiene` → Igiene e Casa, `animali` → Animali). `/api/categories` exposes `compartments` + `compartment_map`; iOS [`CategoryRegistry.compartmentMap`](./category-registry.md) is its client-side mirror.

## Normalization

Both sides normalize identically; unknown input defaults to `Dispensa Secca`, never errors:

- **Backend** — `_normalize_tag` (`compartment.py:46-56`): `split(":")[-1]`, `OFF_TO_INTERNAL`, then `CATEGORY_ALIASES`. `_normalize_compartment` (`shopping_markdown.py:31-43`): legacy map `frigo → Latticini e Uova`, `cantina → Cantina`, `dispensa/altro → Dispensa Secca`, plus case-insensitive canonical match.
- **iOS** — `Compartment.normalized(_:)` (`ShoppingModels.swift:121-136`): same legacy map + case-insensitive match + `Dispensa Secca` fallback. `Compartment.resolved(for:)` (`139-157`) prefers a saved known/legacy compartment, resolves old category-valued strings via the registry, otherwise infers from the item name.

Backend `infer_compartment` cascade (`compartment.py:74-110`): OFF tags → explicit category → `_KEYWORD_MAP` name match → default. iOS mirrors the keyword table locally as an offline display heuristic (documented partial-dedup debt in `ShoppingModels.swift:200-202`); OFF aliases are intentionally not replicated client-side beyond a display subset since the backend normalizes at persistence time. The keyword table ends with a pet-food row (`crocchette`, `pet-food`, `dog-food`, `cat-food` → Animali, `compartment.py:42`), and `OFF_TO_INTERNAL` carries pet-food variants (`dog-food`, `cat-food`, `pet-food`, `petfood`, … → `animali`, `config.py:237-246`) plus four cosmetics aliases (`cosmetics`, `shampoos`, `soaps`, `toothpastes` → `cleaning-hygiene`).

iOS mirror (`ShoppingModels.swift:78-112,171-215`): `.animali` case (`pawprint.fill`) appended to `supermarketOrder`, `selectableCases`/`addableCases` derive from it; `normalizeCategoryKey` carries an alias subset (`dog-food`/`cat-food`/`pet-food`/`petfood` → `animali` plus yogurt/milk/tuna/water/juice/coffee/tea/alcohol/cleaning/hygiene); the keyword row `["crocchette", "pet", "pet-food", "dog-food", "cat-food"]` → `.animali` sits before the Dispensa Secca catch-all so pet names win over the generic `tonno` rule.

## Category Suggestion

`suggest_category` (`compartment.py:121-195`) is now 4-arg — `(off_category_tags, pnns_group, source, product_type)` — proposing an internal category from OFF data, returning `None` (defer) with a `_log_safe` warning when nothing matches:

| Step | Rule | Source |
|------|------|--------|
| 0. Normalize + filter | `_normalize_tag` each tag, drop `GENERIC_OPF` exact matches plus the `productsfacts`-substring rule (`_is_generic_opf`) | `compartment.py:66-71`, `config.py:251-256` |
| 0b. Petfood guard | When `source` or `product_type` normalizes to `petfood`, strip `HUMAN_FOOD_ONLY` (`tuna`, `sardines`, `canned-fish`, `fish`, `meat`, `fish-meat-eggs`) from the filtered tags | `compartment.py:150-155`, `config.py:259-266` |
| 1. Storage override | `frozen-foods` wins over everything; otherwise the first filtered `canned-vegetables`/`canned-fish` tag wins | `compartment.py:170-174` |
| 2. First tag in `COMPARTMENT_MAP` | First filtered tag that is a known internal category — except `cleaning-hygiene` from `source`/`product_type == "product"` alone defers (`cleaning-bloccato-per-product`) | `compartment.py:177-182` |
| 3. `PNNS_TO_INTERNAL` fallback | Coarse `pnns_group` slug lookup (`config.py:271-282`): `fish-meat-eggs` → `meat`, `milk-and-dairy-products` → `fresh-milk`, `sugary-snacks`/`salty-snacks` → `sweets-snacks`, `fruits-and-vegetables` → `fresh-vegetables`, `cereals-and-potatoes` → `pasta`, `fat-and-sauces` → `oils-vinegars`, `beverages` → `beverages-juices` (`composite-foods` excluded as too generic). Guarded: petfood + `HUMAN_FOOD_ONLY` pnns defers (`pnns-human-food-escluso-per-petfood`); `cleaning-hygiene` mapping + `is_product` defers | `compartment.py:185-192` |
| 4. `None` | No suggestion — `_defer(reason)` logs `source/product_type/tags/pnns/esito=None` via `_log_safe` and returns `None` (`nessun-match`) | `compartment.py:157-167,194-195` |

## Inventory Persistence

`_create_scoped_item` (`backend/routes/inventory.py:57-131`) persists with explicit priority `valida > suggest > None`:

| Priority | Behavior | Source |
|----------|----------|--------|
| 1. Explicit valid | `normalize_category(body.category)`; spurious values not in `COMPARTMENT_MAP` are demoted to `None` and continue the cascade | `inventory.py:69-71` |
| 2. Suggest | `suggest_category(body.off_category_tags, pnns_group, resolved_source, resolved_product_type)` where source/product_type resolve from explicit params or body fields | `inventory.py:72-82` |
| 3. None | `category=None` persists as `None` (defer, never a category default); logs a fallback warning with barcode/source/product_type/tags/pnns via `_log_safe` | `inventory.py:83-91` |

Compartment and expiration derive from the resolved category: `expiration_date, is_estimated = resolve_expiration(..., category=category, off_category_tags=..., allow_none=manual)`; `compartment = body.compartment or infer_compartment(name=body.name, category=category, off_category_tags=...)` (`inventory.py:92-104`). `_update_scoped_item` applies the same explicit-valid rule on PATCH (`inventory.py:167-170`).

## Storage Derivation

`storage_for_category` (`compartment.py:113-118`) is the backend twin of [`CategoryRegistry.storageLocation(for:)`](./category-registry.md): it normalizes via `normalize_category` and looks up `CATEGORY_STORAGE_DEFAULT` (`config.py:72-103`), falling back to `DEFAULT_STORAGE` (`"dispensa"`) for unknown keys. `GET /api/categories` ships the result per item as `storage_location` plus `storage_location_labels` (`Frigo`/`Freezer`/`Dispensa`), so the iOS registry mirrors the backend derivation without duplicating the table. `animali` maps to `dispensa` like the other dry goods.

## Spesa Cleanup

- **Manual add with CategoryPicker** — the add-item form is name + quantity + [`CategoryPicker`](../components/ios-category-picker.md) (`ShoppingListView.swift:358-394`); on submit the compartment derives from the picked category (`Compartment.inferCompartment(fromCategory:)` at `370-372`) or stays `nil` so the backend infers it. Typing (≥2 chars) still feeds `suggestionQuery` (`382-384`). Compartment appears otherwise only as a non-editable badge (`Compartment.resolved(for:)` at `499`) and section header.
- **Add-choice deferred via pendingAdd** — the "Aggiungi prodotto" pill opens `showAddChoice`; the choice (`ShoppingAddMethod.scanner/.manual`) is stored in `pendingAdd` and acted on in `onChange(of: showAddChoice)` after dismissal, dodging the iOS 17 double-sheet race (`ShoppingListView.swift:17-20,104-118,398-403`). Both choice buttons are 44pt targets (`421,440`).
- **Scanner sheet** — `ShoppingScannerSheet` (`676-849`) reuses `ScannerView` + `ScanSessionStore` with no fork (`699`); scan-queue rows show per-row `+` for `.found`/`.notFound` plus delete, all 44pt (`754-775`), an `Aggiungi tutti (n)` bulk save for found rows (`788-795`), not-found hint text (`820`), and a manual fallback form when `DataScannerViewController` is unavailable (`709-720`). `addScanned` infers the compartment via `Compartment.inferCompartment(name:category:)` from `suggestedCategory ?? categories.first` (`825-833`); fallback adds with `compartment: nil` (`843-848`).
- **Grouping** — `groupedItems` (`ShoppingListView.swift:24-33`) groups by `Compartment.resolved(for:)` and orders by `supermarketOrder`; sections are `DisclosureGroup`s, all expanded by default (`expandedCompartments` initialized from `supermarketOrder`). [CategoryPicker](../components/ios-category-picker.md) reuses the same `supermarketOrder` for its sheet sections.
- **ForEach identity** — compartment sections key on `\.0.rawValue` (`198`); rows iterate `Identifiable` items/suggestions/lists directly (`136,201,325`).
- **Export sheet-only** — markdown export lives solely in the trailing overflow `Menu` (`ShoppingListView.swift:269-288`) → `store.exportMarkdown` → `exportShoppingMarkdown` → sheet with monospaced `Text` + `ShareLink` (`546-578`). No export button elsewhere, no dispensa navigation.
- **Optimistic check toggle** — `toggleChecked` flips locally and reverts on error (`ShoppingStore.swift:113-136`); delete rolls back the list on failure (`51-68`). The row checkbox is a 44pt target with combined accessibility label (`462-479,530-534`).

## Suggestions Behind Auth

`GET /api/suggestions` (`backend/routes/suggestions.py:11-36`) requires `require_known_token`: valid-but-unknown tokens get 401, so anonymous clients cannot enumerate `ScanHistory`. Optional `q` prefix filter (`ilike`), ordered by `times_scanned DESC, last_scanned_at DESC`, capped at 10, returning only `{barcode, name, category, times_scanned}`.

iOS treats suggestions as non-critical (`ShoppingStore.swift:165-177`): empty query clears, failures reset to `[]` without touching `error`. `ShoppingListView` debounces (350 ms, min 2 chars), tapping a suggestion infers its compartment from category-then-name and adds it directly (`ShoppingListView.swift:295-303,134-183`).

## Gotchas

- Legacy strings (`frigo`, `dispensa`, …) still in old rows normalize silently on both sides — don't migrate data, the mapping is the compatibility layer.
- Unknown compartment strings don't crash the exporter; they land in `## 📦 Altro` server-side, while iOS falls back to name inference — the two can disagree on garbage input.
- `tonno fresco` matches the Carne e Pesce keyword rule before the Dispensa Secca `tonno` rule — keyword order matters. On iOS the `.animali` keyword row likewise precedes the Dispensa Secca catch-all, so `crocchette`-style names win over generic pantry keywords.
- `suggest_category` and `infer_compartment` are different cascades: the former proposes a *category* (filter → frozen-override → tag → guarded PNNS → None), the latter resolves a *department* (OFF tags → category → keywords → Dispensa Secca). Don't conflate their defaults — suggestion may return `None` where inference never does.
- `cleaning-hygiene` never comes from `source`/`product_type == "product"` alone — both the tag and PNNS paths defer with a warning; petfood inputs additionally strip `HUMAN_FOOD_ONLY` tags/groups.
- `GENERIC_OPF` filtering includes the `productsfacts`-substring rule, so bare openproductsfacts tags defer instead of mis-categorizing as cleaning/hygiene.
- Inventory rows may legitimately persist `category=None` (defer); compartment still resolves via `infer_compartment` from name/tags, and expiration falls back per `allow_none=manual`.
