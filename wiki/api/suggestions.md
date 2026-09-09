---
title: "Suggestions"
description: "Autocomplete endpoint GET /api/suggestions — shopping scan-history or pantry inventory scopes"
category: "api"
source_files:
  - "backend/routes/suggestions.py"
  - "backend/routes/scan.py"
  - "backend/models.py"
  - "backend/tests/test_suggestions.py"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/Features/Inventory/InventoryListView.swift"
  - "ios/Inventario/Features/ManualEntry/ManualEntryView.swift"
created: "2026-09-05"
last_updated: "2026-09-09"
---

# Suggestions

## Overview

`GET /api/suggestions` returns autocomplete entries, optionally prefix-filtered, capped at 10 rows. It supports two scopes via `?scope=`: `shopping` (default, unchanged — `ScanHistory` ordered by scan frequency) powers the shopping-list autocomplete (see [Shopping Departments](../concepts/shopping-departments.md)), while `scope=pantry` merges the caller's pantry inventory with scan history for pantry-side autocomplete. It is a data route: access is gated by `require_known_token` (missing, malformed, or unknown `X-Pantry-Token` → `401`).

## Endpoints

| Method | Path | Status | Description |
|--------|------|--------|-------------|
| GET | `/api/suggestions` | 200 | Autocomplete entries, optionally prefix-filtered; `scope=shopping` (default) or `scope=pantry` |

**Router prefix**: `/api` — `backend/routes/suggestions.py` (tags `suggestions`)

### GET /api/suggestions

**Description**: `scope=shopping` queries `ScanHistory` ordered by `times_scanned` descending then `last_scanned_at` descending, capped at 10 rows. `scope=pantry` merges the last 200 inventory rows (owned + membered pantries plus legacy `pantry_id IS NULL` rows) with the top-10 `ScanHistory` rows, de-duplicated case-insensitively, ranked by merged `times_scanned`, capped at 10. Returns minimal fields per entry.

**Auth**: requires a known pantry token (`require_known_token`); `401` without it.

**Query parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | `string` | no | Prefix filter, case-insensitive (`ilike`), trimmed; empty returns all |
| `scope` | `string` | no | `shopping` (default) or `pantry`; any non-`pantry` value behaves as `shopping` |

**Response** (`200`): array of

| Field | Type | Description |
|-------|------|-------------|
| `barcode` | `string` | Scanned barcode value (pantry scope: `""` when the merged rows have no barcode) |
| `name` | `string` | Product name |
| `category` | `string` | Category key |
| `times_scanned` | `int` | Scan count (pantry scope: merged occurrence/scan count, see below) |

```json
[
  {
    "barcode": "003",
    "name": "Pasta integrale",
    "category": "pasta",
    "times_scanned": 10
  }
]
```

**Behavior notes — both scopes**:

- Prefix-only matching: `q=lat` matches `Latte fresco` and `latticino` but `q=tte` matches nothing (not a substring search).
- Whitespace in `q` is trimmed (`q=  LAT  ` works); empty `q` returns the top-10 by frequency/rank.
- Result cap is 10 rows in both scopes.
- LIKE metacharacters are escaped in both scopes: `_escape_like` escapes `\`, `%`, `_` before building the `ilike(f"{prefix}%", escape="\\")` filter (`backend/routes/suggestions.py:12-13`, applied at lines 29, 70, 97).
- `ScanHistory` rows now also carry nullable `source` / `product_type` (persisted by `POST /api/scan` from the OFF result in `backend/routes/scan.py`), but this endpoint does not expose them — the minimal-fields shape is unchanged.
- Shopping ordering is unchanged: `times_scanned` descending, then `last_scanned_at` descending (`backend/routes/suggestions.py:30-34`).

**Behavior notes — `scope=pantry`** (`backend/routes/suggestions.py:47-116`):

- Pantry set: `Pantry.id` rows where `owner_token == token`, union `PantryMember.pantry_id` rows where `member_token == token`. If the union is empty, returns `[]` without querying further.
- Inventory filter: `pantry_id IN (pantry_ids)` OR (`pantry_id IS NULL` AND `created_by_token == token`) — the second branch keeps legacy pre-pantry rows visible to their creator.
- Window: the 200 most recent matching `InventoryItem` rows (`order_by(id.desc()).limit(200)`), so new inserts past the limit stay eligible.
- Case-insensitive name merge: key is `(name or "").lower()`; empty names are skipped. Each first-seen name starts at `times_scanned: 1` with `barcode` (`or ""`) and `category`; repeats increment `times_scanned` by 1 and backfill `barcode` (when empty and the row has one) and `category` (when `None` and the row has one).
- History fold-in: top-10 `ScanHistory` rows under the same prefix filter and shopping ordering. A history name absent from the merge is inserted with its own `barcode`/`category`/`times_scanned`; a name already present adds `s.times_scanned` to the merged count (history does not backfill `barcode`/`category` into an existing inventory entry).
- Final ranking: merged values sorted by `times_scanned` descending, first 10 returned.

**Source**: `backend/routes/suggestions.py:16-44` (shopping path), `backend/routes/suggestions.py:47-116` (pantry path)

---

## iOS Clients

All callers use `APIClient.fetchSuggestions(q:scope:)` (`ios/Inventario/Networking/APIClient.swift:345-358`). `scope` defaults to `"shopping"` and is omitted from the URL when shopping, so existing shopping calls keep an identical URL; `scope=pantry` is appended only for pantry callers.

- `InventoryListView` (`ios/Inventario/Features/Inventory/InventoryListView.swift:265-275`): `.task(id: searchText)` debounces 350 ms, requires ≥ 2 trimmed characters (else clears), guards `Task.isCancelled`, then calls `fetchSuggestions(q:trimmed, scope: "pantry")`; failures clear the list. Results render in `pantrySuggestionsSection`, and tapping a row prefills `manualPrefillName` / `manualPrefillCategory`, clears the search, and opens `ManualEntryView(initialName:initialCategory:)`.
- `ManualEntryView` (`ios/Inventario/Features/ManualEntry/ManualEntryView.swift:145-155`): `.task(id: name)` with the same ≥ 2 chars / 350 ms / cancellation / clear-on-error pattern calls `fetchSuggestions(q:trimmed, scope: "pantry")`. Tapping a suggestion sets `name` and (when non-empty) `selectedCategory`, resets the storage override flag, and clears the list. `initialName` / `initialCategory` (default `""`) prefill the form `onAppear` when set by the inventory-list handoff.

## Error Handling Summary

| Scenario | HTTP Status | Details |
|----------|-------------|---------|
| Missing `X-Pantry-Token` | 401 | Auth gate (`require_known_token`) |
| Malformed token (not a UUID) | 401 | Same as `get_pantry_context` behavior |
| Valid UUID unknown to any pantry (owner or member) | 401 | CWE-287 guard |

## Tests

`backend/tests/test_suggestions.py` covers: 401 for missing/malformed/unknown tokens, 200 with a known owner token, case-insensitive prefix matching (including the no-substring rule), trim + empty-`q` ordering (`times_scanned` desc, `last_scanned_at` desc), the 10-row limit, and the minimal-fields shape.
