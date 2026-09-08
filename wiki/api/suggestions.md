---
title: "Suggestions"
description: "Scan-history autocomplete endpoint GET /api/suggestions — prefix search ordered by scan frequency"
category: "api"
source_files:
  - "backend/routes/suggestions.py"
  - "backend/routes/scan.py"
  - "backend/models.py"
  - "backend/tests/test_suggestions.py"
created: "2026-09-05"
last_updated: "2026-09-06"
---

# Suggestions

## Overview

`GET /api/suggestions` returns scan-history autocomplete entries from `ScanHistory`, ordered by usage frequency. It powers the shopping-list autocomplete (see [Shopping Departments](../concepts/shopping-departments.md)). It is a data route: access is gated by `require_known_token` (missing, malformed, or unknown `X-Pantry-Token` → `401`).

## Endpoints

| Method | Path | Status | Description |
|--------|------|--------|-------------|
| GET | `/api/suggestions` | 200 | List recent/frequent scan-history entries, optionally prefix-filtered |

**Router prefix**: `/api` — `backend/routes/suggestions.py` (tags `suggestions`)

### GET /api/suggestions

**Description**: Queries `ScanHistory`, optionally filtered by a case-insensitive name prefix, ordered by `times_scanned` descending then `last_scanned_at` descending, capped at 10 rows. Returns minimal fields per entry.

**Auth**: requires a known pantry token (`require_known_token`); `401` without it.

**Query parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `q` | `string` | no | Prefix filter, case-insensitive (`ilike`), trimmed; empty returns all |

**Response** (`200`): array of

| Field | Type | Description |
|-------|------|-------------|
| `barcode` | `string` | Scanned barcode value |
| `name` | `string` | Product name |
| `category` | `string` | Category key |
| `times_scanned` | `int` | Scan count |

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

**Behavior notes**:

- Prefix-only matching: `q=lat` matches `Latte fresco` and `latticino` but `q=tte` matches nothing (not a substring search).
- Whitespace in `q` is trimmed (`q=  LAT  ` works); empty `q` returns the top-10 by frequency.
- Result cap is 10 rows.
- `ScanHistory` rows now also carry nullable `source` / `product_type` (persisted by `POST /api/scan` from the OFF result in `backend/routes/scan.py`), but this endpoint does not expose them — the minimal-fields shape is unchanged.
- Ordering is unchanged: `times_scanned` descending, then `last_scanned_at` descending (`backend/routes/suggestions.py:23`).

**Source**: `backend/routes/suggestions.py:11-36`

---

## Error Handling Summary

| Scenario | HTTP Status | Details |
|----------|-------------|---------|
| Missing `X-Pantry-Token` | 401 | Auth gate (`require_known_token`) |
| Malformed token (not a UUID) | 401 | Same as `get_pantry_context` behavior |
| Valid UUID unknown to any pantry (owner or member) | 401 | CWE-287 guard |

## Tests

`backend/tests/test_suggestions.py` covers: 401 for missing/malformed/unknown tokens, 200 with a known owner token, case-insensitive prefix matching (including the no-substring rule), trim + empty-`q` ordering (`times_scanned` desc, `last_scanned_at` desc), the 10-row limit, and the minimal-fields shape.
