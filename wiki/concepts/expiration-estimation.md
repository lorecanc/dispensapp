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
last_updated: "2026-06-24"
---

# Expiration Date Estimation

## Purpose

When a user scans or manually adds an item without specifying an expiration date, the system estimates one based on the item's category. This removes friction during data entry while still providing a reasonable default that helps with expiration tracking.

## The Algorithm

The estimation is performed by [estimate_expiration()](../modules/backend-service-expiration.md) in `backend/services/expiration.py`.

### Steps

1. **Default fallback**: If no category tags are provided, or if no tag matches a known category, the result is `reference_date + 30 days` (the `"default"` entry in `DEFAULT_SHELF_LIFE`).
2. **Tag iteration**: Each tag in the `category_tags` list is normalized by stripping everything up to and including the first colon (this removes language prefixes such as `en:`). The normalized string is then checked against every key in `DEFAULT_SHELF_LIFE` (except `"default"`) using substring matching (`key in normalized`). On the iOS side, these category keys correspond to the options in [CategoryPicker](../components/ios-category-picker.md).
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

Defined in [backend/config.py](../config/backend-config.md). The `"default"` key serves as the fallback when no category matches.

| Key | Days |
|------|------|
| `yogurts` | 14 |
| `fresh-milk` | 7 |
| `pasta` | 365 |
| `canned-vegetables` | 730 |
| `rice` | 365 |
| `cheeses` | 30 |
| `eggs` | 21 |
| `fresh-fruits` | 7 |
| `fresh-vegetables` | 7 |
| `frozen-foods` | 90 |
| `default` | 30 |

## Matching Logic Details

The substring match (`key in normalized`) means that a broad tag like `"en:dairy-products"` would match the key `"yogurts"` only if the normalized value literally contains the substring `"yogurts"`. In practice, the matching depends on the tag values provided by the upstream data source (Open Food Facts for scan-based creation, or the user-selected category for manual creation).

### Example

For a tag `"en:yogurts"`:
1. Normalized: `"yogurts"` (after stripping `"en:"`).
2. Iterates `DEFAULT_SHELF_LIFE` keys: `"yogurts" in "yogurts"` → match → 14 days.
3. Result: `reference_date + 14 days`.

For a tag `"en:pasta"` with a second tag `"en:cheeses"`:
1. First tag normalized: `"pasta"` → matches `"pasta"` → 365 days.
2. Second tag is never evaluated because the loop breaks on the first match.

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
- Substring matching can produce surprising results if a tag happens to contain a category key as a substring. Adding new keys to `DEFAULT_SHELF_LIFE` should account for this to avoid accidental matches.
