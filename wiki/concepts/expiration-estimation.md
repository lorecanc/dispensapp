---
title: "Expiration Date Estimation"
description: "Automatic shelf-life-based expiration date estimation when the user does not provide one"
category: "concepts"
source_files:
  - "backend/services/expiration.py"
  - "backend/config.py"
  - "backend/routes/inventory.py"
  - "backend/services/markdown_export.py"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# Expiration Date Estimation

## Purpose

When a user scans or manually adds an item without specifying an expiration date, the system estimates one based on the item's category. This removes friction during data entry while still providing a reasonable default that helps with expiration tracking. The full create-path decision (explicit date vs estimated vs none) is centralized in [`resolve_expiration()`](../modules/backend-service-expiration.md), called by the shared `_create_scoped_item` helper in `backend/routes/inventory.py`.

## The Algorithm

The estimation is performed by [estimate_expiration()](../modules/backend-service-expiration.md) in `backend/services/expiration.py`.

### Steps

1. **Default fallback**: If no category tags are provided, or if no tag matches a known category, the result is `reference_date + 30 days` (the `"default"` entry in `DEFAULT_SHELF_LIFE`).
2. **Tag iteration**: Each tag in the `category_tags` list is normalized: lowercased, stripped, split on `:` keeping the last segment (this removes language prefixes such as `en:`), then mapped through `CATEGORY_ALIASES` (e.g. `yogurt` → `yogurts`, `milk` → `fresh-milk`). The normalized string is then checked against every key in `DEFAULT_SHELF_LIFE` (except `"default"`) using **exact equality**. On the iOS side, these category keys correspond to the server-driven options in [CategoryPicker](../components/ios-category-picker.md) (see [Category Registry](./category-registry.md)).
3. **First-match wins**: The first tag that matches any shelf-life key determines the result. Tags are evaluated in order, and the loop stops as soon as a match is found.

### Signature

```python
def estimate_expiration(
    category_tags: Optional[list[str]] = None,
    reference_date: Optional[date] = None,
) -> date:
```

- `category_tags`: A list of category label strings (e.g. `["en:dairy", "en:yogurts"]`). If `None` or empty, the default 30-day value is used.
- `reference_date`: The base date for the calculation. Defaults to `date.today()`.

## DEFAULT_SHELF_LIFE Mapping

Defined in [backend/config.py](../config/backend-config.md): 26 categories plus the `"default"` fallback (extended to align with the OFF taxonomy — see [Backend Service — Expiration](../modules/backend-service-expiration.md) for the full table). The `"default"` key serves as the fallback when no category matches. Singular/plural variants are covered by `CATEGORY_ALIASES`.

## Matching Logic Details

Matching is **exact and case-insensitive** on the normalized tag: a tag like `"en:dairy-products"` normalizes to `"dairy-products"`, which equals no key and falls back to 30 days. Aliases rescue common variants (`"en:cheese"` → `"cheeses"` → 30 days; `"en:yogurt"` → `"yogurts"` → 14 days). Unknown tags can never accidentally match — adding new keys to `DEFAULT_SHELF_LIFE` is safe by construction (unlike the old substring rule).

### Example

For a tag `"en:yogurts"`:
1. Normalized: `"yogurts"` (after stripping `"en:"`, lowercasing, alias lookup is identity).
2. Iterates `DEFAULT_SHELF_LIFE` keys: `"yogurts" == "yogurts"` → match → 14 days.
3. Result: `reference_date + 14 days`.

For a tag `"en:pasta"` with a second tag `"en:cheeses"`:
1. First tag normalized: `"pasta"` → matches `"pasta"` → 365 days.
2. Second tag is never evaluated because the loop breaks on the first match.

## Create-Path: `resolve_expiration`

Routes don't call `estimate_expiration` directly. `_create_scoped_item` calls `resolve_expiration(expiration_date, category, off_category_tags, allow_none=manual)`:

- Explicit `expiration_date` → used as-is, `is_estimated=False`.
- Otherwise `category` + `off_category_tags` are merged, normalized (lower/strip/split/alias/dedup), and estimated → `(estimated, True)`.
- No usable tags + `allow_none=True` (manual entry without category) → `(None, False)`: the item keeps no expiration date instead of a fabricated estimate.

## The `is_estimated` Flag

Both creation endpoints in [backend/routes/inventory.py](../api/inventory.md) set `is_estimated` on the resulting `InventoryItem`:

| Endpoint | Condition | `is_estimated` |
|----------|-----------|----------------|
| `POST /api/inventory` | `expiration_date` provided | `False` |
| `POST /api/inventory` | `expiration_date` omitted | `True` (estimation runs) |
| `POST /api/inventory/manual` | `expiration_date` provided | `False` |
| `POST /api/inventory/manual` | `expiration_date` omitted AND `category` provided | `True` (estimation runs) |
| `POST /api/inventory/manual` | `expiration_date` omitted AND `category` omitted | `False` (expiration_date set to `None`, no estimation) |

The flag is persisted as a `Boolean` column in the `inventory_items` SQL table (`backend/models.py`), exposed through the [response schema](../modules/backend-schemas.md).

## User-Facing Implications

### iOS Display

Items with `is_estimated = True` display a warning indicator: **"⚠️ Data stimata"**. This signals to the user that the date was automatically calculated and may be incorrect.

### Markdown Export

The export function in `backend/services/markdown_export.py` appends the `ESTIMATED_NOTE` string (`"⚠️ Scadenza stimata, potrebbe scadere prima"`) to the "Note" column of any row where `is_estimated` is `True`. This ensures the estimated nature is visible when the inventory is shared or viewed as plain text.

### Accuracy Considerations

- The mapping is coarse: a single shelf-life value applies to an entire category (e.g. all `"fresh-vegetables"` get 7 days whether they are potatoes or lettuce).
- Exact matching means new `DEFAULT_SHELF_LIFE` keys can be added without risk of accidental matches; variants should be covered via `CATEGORY_ALIASES` instead.
