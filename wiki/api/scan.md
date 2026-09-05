---
title: "Scan"
description: "Barcode scan lookup via Open Food Facts plus opt-in contribute and photo upload endpoints"
category: "api"
source_files:
  - "backend/routes/scan.py"
  - "backend/routes/contribute.py"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# Scan

## Overview

The scan API looks up product data by barcode via Open Food Facts (OFF) and, when enabled, forwards user-contributed metadata and photos to OFF (see [Contribute](./contribute.md)). The read path (`POST /api/scan`) is always available; the write paths (`POST /api/scan/contribute`, `POST /api/scan/photo`) are opt-in and disabled by default.

## Endpoints

| Method | Path | Status | Description |
|--------|------|--------|-------------|
| POST | `/api/scan` | 200 | Look up a barcode via OFF |
| POST | `/api/scan/contribute` | 200 | Contribute product metadata to OFF (opt-in) |
| POST | `/api/scan/contribute/photo` | 200 | Upload a product photo to OFF (opt-in) |

**Router prefixes**: `/api` — `backend/routes/scan.py` (tags `scan`), `backend/routes/contribute.py` (tags `contribute`)

### POST /api/scan

**Description**: Accepts a barcode string, delegates to the OFF API via `fetch_product(barcode)`, and returns product details if found. On a successful lookup it also records the scan in `ScanHistory` without blocking the response.

**Request body** (`ScanRequest`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `barcode` | `string` | yes | Barcode matching `^\d{8,14}$` (`422` otherwise) |

```json
{
  "barcode": "8076809514381"
}
```

**Response** (`200`): `ScanResponse`

| Field | Type | Description |
|-------|------|-------------|
| `barcode` | `string` | The requested barcode |
| `name` | `string` or `null` | Product name (empty string when not found) |
| `brand` | `string` or `null` | Product brand |
| `categories` | `array` of `string` | Category tags reduced to last hierarchy segment (e.g. `en:pastas` → `pastas`) |
| `image_url` | `string` or `null` | Front-of-pack small image URL |
| `found` | `boolean` | Whether the product was found in OFF |
| `message` | `string` or `null` | Set only when `found` is `false` |

**Response states**:

**1. Product found (200 OK)**

```json
{
  "barcode": "8076809514381",
  "name": "Pasta Barilla",
  "brand": "Barilla",
  "categories": ["pasta", "groceries"],
  "image_url": "https://images.openfoodfacts.org/images/products/.../front_small.jpg",
  "found": true,
  "message": null
}
```

**2. Product not found (200 OK)**

Returned when OFF responds but has no data for this barcode (`status != 1` or no product object).

```json
{
  "barcode": "0000000000000",
  "name": "",
  "brand": null,
  "categories": [],
  "image_url": null,
  "found": false,
  "message": "Prodotto non trovato nel database Open Food Facts"
}
```

**3. OFF communication failure (502 Bad Gateway)**

Returned when the HTTP request to OFF fails (HTTP error, timeout, or invalid JSON). Body is `{"detail": "Errore durante la comunicazione con Open Food Facts"}`.

**Backend flow** (`backend/routes/scan.py:19-82`):

1. `scan_barcode()` receives the `ScanRequest` body.
2. Calls `fetch_product(barcode)` with a 10-second timeout against `{OFF_BASE_URL}/{barcode}.json`.
3. If `fetch_product` returns `None` → `502`.
4. If result is `{"found": False}` → `200` with `found=false` (no history write).
5. Otherwise persists `ScanHistory` in a worker thread via `anyio.to_thread.run_sync` (synchronous SQLAlchemy session must not block the event loop): increments `times_scanned` or creates a row (`name` falls back to barcode for the NOT NULL constraint, `category` is the first tag), updates `name`/`category`/`last_scanned_at`. This history powers [Suggestions](./suggestions.md). Failures roll back and are logged without blocking the scan response.
6. Returns `200` with `found=true` and the enriched product data.

**Source**: `backend/routes/scan.py:18-82`

---

### POST /api/scan/contribute

**Description**: Forwards user-supplied product metadata to OFF via `contribute_product` (`product_jqm2.pl`). Disabled by default; requires `OFF_WRITE_ENABLED=true` (+ `OFF_USER`/`OFF_PASS`). Full reference: [Contribute](./contribute.md). See backend config and OFF integration concepts for staging/prod base URLs.

**Request body** (`application/json`, `ContributeRequest`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | `string` | yes | Barcode, `^\d{8,14}$` (`422` otherwise) |
| `consent_cc_bysa` | `bool` | yes | Must be `true`; `false` → `400` (CC BY-SA consent) |
| `lang` | `string` | no | Default `it`; pattern `^[a-z]{2}(-[A-Z]{2})?$`, blank/`None` normalized to `it` |
| `product_name` | `string` | no* | Max 200 chars |
| `brands` | `string` | no* | Max 200 chars |
| `quantity` | `string` | no* | Max 64 chars |
| `categories` | `string` | no* | Max 500 chars |
| `labels` | `string` | no* | Max 500 chars |
| `generic_name` | `string` | no* | Max 200 chars |
| `comment` | `string` | no | Max 500 chars (metadata only, does not satisfy the at-least-one rule) |
| `app_uuid` | `string` | no | Max 64 chars (metadata only, does not satisfy the at-least-one rule) |

\* At least one of `product_name`, `generic_name`, `brands`, `quantity`, `categories`, `labels` must be non-blank, otherwise `422` (`at_least_one_field`). Blank strings are stripped to `None` before validation.

**Response** (`200`): `{"ok": true, "code": "<barcode>", "message": "Contributo inviato a Open Food Facts"}`

**Error handling**:

| Scenario | Status | Detail |
|----------|--------|--------|
| Rate limit exceeded (10 req/min per IP, in-memory, shared with photo endpoint) | 429 | `Troppe richieste, riprova tra poco` |
| Missing consent (`consent_cc_bysa=false`) | 400 | `Consenso CC BY-SA obbligatorio per contribuire a Open Food Facts` |
| Write disabled (`OFF_WRITE_ENABLED=false`) | 403 | `Contribuzione a Open Food Facts disabilitata sul server` |
| Validation failure (bad `code`, empty fields, bad `lang`) | 422 | Pydantic validation error |
| OFF transport error (`httpx.HTTPError`, `ValueError`) | 502 | `Errore durante la comunicazione con Open Food Facts` |
| OFF refusal (`status != 1`) | 502 | `Open Food Facts ha rifiutato il contributo` |

**Source**: `backend/routes/contribute.py:96-136`

---

### POST /api/scan/contribute/photo

**Description**: Uploads a product photo to OFF via `upload_product_image` (`product_image_upload.pl`). Same opt-in gate and rate limit as the metadata endpoint.

**Request body** (`multipart/form-data`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | form `string` | yes | Barcode `^\d{8,14}$` (`422` if invalid) |
| `imagefield` | form `string` | yes | Must match `^(?:front\|ingredients\|nutrition\|packaging\|other)(?:_[a-z]{2})?$` — e.g. `front`, `front_it`, `nutrition_it`, `other` (`422` otherwise) |
| `consent_cc_bysa` | form `bool` | yes | Must be `true` (`400` otherwise) |
| `image` | file | yes | JPEG/PNG/HEIC, max 5 MB; declared `Content-Type` must match magic-byte detection (`415` on empty, unknown, or mismatch); JPEG/PNG below 640×160 px → `422`; HEIC skips dimension check |

Oversize uploads fail fast: a `Content-Length` pre-check (5 MB + 1 KB multipart tolerance) returns `413` before reading the body; the actual byte length is re-checked after read (`413` over limit).

**Response** (`200`): `{"ok": true, "code": "<barcode>", "message": "Foto inviata a Open Food Facts"}`

**Error handling**:

| Scenario | Status | Detail |
|----------|--------|--------|
| Rate limit exceeded (shared bucket with metadata endpoint) | 429 | `Troppe richieste, riprova tra poco` |
| Missing consent | 400 | `Consenso CC BY-SA obbligatorio per contribuire a Open Food Facts` |
| Write disabled | 403 | `Contribuzione a Open Food Facts disabilitata sul server` |
| Invalid `code` / `imagefield` / too-small image | 422 | `code non valido` / `imagefield non valido` / `Immagine troppo piccola (minimo 640x160 px)` |
| Oversize image | 413 | `Immagine troppo grande (max 5MB)` |
| Empty or type-mismatched image | 415 | `Tipo immagine non consentito (JPEG/PNG/HEIC)` |
| OFF transport error or refusal | 502 | Same `502` shapes as the metadata endpoint |

**Prod note**: the in-memory limiter is a no-dependency mitigation; replace with `slowapi` + Redis before go-live (see `TODO(prod)` in `contribute.py`).

**Source**: `backend/routes/contribute.py:232-305`

---

## Error Handling Summary

| Scenario | HTTP Status | Response shape | Details |
|----------|-------------|----------------|---------|
| OFF unreachable (scan) | 502 | `HTTPException` | JSON `{"detail": "Errore durante la comunicazione con Open Food Facts"}` |
| Product not found (scan) | 200 | `ScanResponse` | `found=false` with Italian not-found message |
| Consent missing (contribute/photo) | 400 | `HTTPException` | CC BY-SA consent required |
| Write disabled (contribute/photo) | 403 | `HTTPException` | `OFF_WRITE_ENABLED` gate |
| Validation failure | 422 | Pydantic / `HTTPException` | Barcode pattern, at-least-one-field, `imagefield` allowlist, min dimensions |
| Oversize photo | 413 | `HTTPException` | 5 MB limit |
| Bad image type | 415 | `HTTPException` | JPEG/PNG/HEIC magic-byte check |
| Rate limited | 429 | `HTTPException` | 10 req/min per IP |
| OFF refusal | 502 | `HTTPException` | OFF returned `status != 1` |

## Dependencies

| Dependency | Source | Role |
|------------|--------|------|
| `fetch_product` | `backend/services/off.py` | OFF read (`GET {OFF_BASE_URL}/{barcode}.json`) |
| `contribute_product` | `backend/services/off.py` | OFF metadata write (`product_jqm2.pl`) |
| `upload_product_image` | `backend/services/off.py` | OFF photo upload (`product_image_upload.pl`) |
| `ScanHistory` | `backend/models.py` | ORM model for scan counts (`times_scanned`, `last_scanned_at`) |
| `get_db` | `backend/database.py` | FastAPI dependency for DB session |
| `BARCODE_PATTERN` | `backend/schemas.py` | Shared `^\d{8,14}$` pattern for scan and contribute routes |
