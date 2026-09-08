---
title: "Contribute"
description: "Opt-in Open Food Facts write API for product metadata and photos via staging"
category: "api"
source_files:
  - "backend/routes/contribute.py"
  - "backend/services/off.py"
created: "2026-09-05"
last_updated: "2026-09-06"
---

# Contribute

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/scan/contribute` | Contribute product metadata to OFF (opt-in) |
| POST | `/api/scan/contribute/photo` | Upload a product photo to OFF (opt-in) |

**Router**: `APIRouter(prefix="/api", tags=["contribute"])` — `backend/routes/contribute.py:17`

Both endpoints are disabled by default behind `OFF_WRITE_ENABLED` and share an in-memory per-IP rate limit (10 req/min, 60 s window). Write host is resolved per `product_type` via `resolve_write_url()` (see [OFF service](../modules/backend-service-off.md) and [OFF integration](../concepts/off-integration.md)); staging write base URL defaults to `https://world.openfoodfacts.net/cgi`, prod `.org` twins only via env override.

### POST /api/scan/contribute

**Description**: Forwards user-supplied product metadata to OFF staging via `product_jqm2.pl`.

**Request** (`application/json`, [`ContributeRequest`](../modules/backend-schemas.md)):

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `code` | `string` | yes | `BARCODE_PATTERN` (`^\d{8,14}$`), else 422 |
| `product_name` | `string` | no* | max 200, stripped to `None` if blank |
| `brands` | `string` | no* | max 200 |
| `quantity` | `string` | no* | max 64 |
| `categories` | `string` | no* | max 500 |
| `labels` | `string` | no* | max 500 |
| `generic_name` | `string` | no* | max 200 |
| `comment` | `string` | no | max 500, metadata only |
| `app_uuid` | `string` | no | max 64, metadata only |
| `consent_cc_bysa` | `bool` | yes | must be `true`, else 400 |
| `lang` | `string` | no | default `it`, pattern `^[a-z]{2}(-[A-Z]{2})?$`, blank/`None` → `it`, normalized case |
| `product_type` | `string` | no | default `food`, allowlist `food\|beauty\|petfood\|product` via `_normalize_product_type` (trimmed, lowercased; blank/`None` → `food`), else 422 |

\* At least one of `product_name`, `generic_name`, `brands`, `quantity`, `categories`, `labels` must be non-blank (`at_least_one_field`, else 422). `comment`/`app_uuid` do not satisfy the rule.

**Response**: `ContributeResponse` (`200`): `{"ok": true, "code": "<barcode>", "message": "Contributo inviato a Open Facts"}`

**Source**: `backend/routes/contribute.py:57-161`

### POST /api/scan/contribute/photo

**Description**: Uploads a product photo to OFF staging via `product_image_upload.pl`.

**Request** (`multipart/form-data`):

| Field | Type | Required | Validation |
|-------|------|----------|------------|
| `code` | form `string` | yes | `BARCODE_PATTERN`, else 422 |
| `imagefield` | form `string` | yes | `^(?:front\|ingredients\|nutrition\|packaging\|other)(?:_[a-z]{2})?$`, else 422 |
| `consent_cc_bysa` | form `bool` | yes | must be `true`, else 400 |
| `image` | file | yes | JPEG/PNG/HEIC, max 5 MB; magic-byte check, else 415; JPEG/PNG min 640x160 px, else 422 |
| `product_type` | form `string` | no | default `food`, same 4-value allowlist as metadata (`food\|beauty\|petfood\|product`), else 422 `product_type non valido` |

Guard order (fail-fast): declared `Content-Length` pre-check (413, 5 MB + 1 KB multipart tolerance, body not read) runs BEFORE `product_type` validation (422), then consent (400) → write gate (403) → `code`/`imagefield` validation (422).

Oversize fails fast on declared `Content-Length` then on actual bytes (413). Declared `Content-Type` must match magic-byte detection. HEIC skips dimension check.

**Response** (`200`): `{"ok": true, "code": "<barcode>", "message": "Foto inviata a Open Facts"}`

**Source**: `backend/routes/contribute.py:257-337`

## OFF Mapping

| Local field | OFF form field | Endpoint |
|-------------|----------------|----------|
| `product_name` | `product_name_{lang}` | `product_jqm2.pl` |
| `generic_name` | `generic_name_{lang}` | `product_jqm2.pl` |
| `brands` | `add_brands` (never bare `brands`) | `product_jqm2.pl` |
| `categories` | `add_categories` | `product_jqm2.pl` |
| `labels` | `add_labels` | `product_jqm2.pl` |
| `quantity` | `quantity` | `product_jqm2.pl` |
| `lang` | `lc` + `lang` (normalized to 2-letter lower) | `product_jqm2.pl` |
| `comment` | `comment` (default `Contributo via {APP} {VER}`) | `product_jqm2.pl` |
| `app_uuid` | `app_uuid` (only if set) | `product_jqm2.pl` |
| `product_type` | `product_type` (metadata form only; photo resolves host via `resolve_write_url` without a form field) | `product_jqm2.pl` |
| photo bytes | `imgupload_{imagefield}` multipart + `code`, `imagefield`, `user_id`, `password` | `product_image_upload.pl` |

Write URL via `resolve_write_url(product_type)` (`backend/services/off.py:187-203`): `food` → `world.openfoodfacts.org`, `beauty` → `world.openbeautyfacts.org`, `petfood` → `world.openpetfoodfacts.org`, `product` → `world.openproductsfacts.org`; any staging `.net` base falls back to `https://world.openfoodfacts.net/cgi` for all types.

Auth: `user_id`/`password` from `OFF_USER`/`OFF_PASS` plus staging Basic (`off:off`) via `off_basic_auth()` and app `User-Agent` via `off_user_agent()`. Password and image bytes are never logged. Timeouts: 15 s metadata, 30 s photo.

**Source**: `backend/services/off.py:206-318`

## Validation & Guards

- `lang`: max 8, pattern-gated, case-normalized (`it`, `it-IT`); service re-normalizes to 2-letter lower (`_normalize_lang`).
- `product_type`: max 16, `_normalize_product_type` allowlist `food|beauty|petfood|product` (trimmed, lowercased; blank/`None` → `food`); JSON rejects invalid with Pydantic 422, photo rejects with 422 `product_type non valido` after the 413 `Content-Length` pre-check.
- `max_length`: enforced by Pydantic (`product_name`/`brands`/`generic_name` 200, `quantity`/`app_uuid` 64, `categories`/`labels`/`comment` 500).
- Rate limit: `_check_rate_limit(ip)`, shared bucket across both endpoints, 10 req/min per IP (`backend/routes/contribute.py:42-54`).
- Photo: allowlist `front|ingredients|nutrition|packaging|other` + optional `_[a-z]{2}` suffix; filename sanitized (`_safe_filename`, 128 chars); HEIC brand allowlist fail-closed (`mif1`/`msf1` → 415).
- Write gate: `OFF_WRITE_ENABLED = requested and OFF_USER and OFF_PASS and valid_url` (`backend/config.py:303-305`); invalid `OFF_WRITE_BASE_URL` host/scheme falls back to staging default.
- Transport: `httpx.HTTPError`/`ValueError` → 502; OFF `status != 1` (parsed via `_parse_off_status`, accepts `1`/`"ok"`) → 502 refusal.

## Errors

| Status | When | Detail |
|--------|------|--------|
| 400 | `consent_cc_bysa=false` | `Consenso CC BY-SA obbligatorio per contribuire a Open Facts` |
| 403 | `OFF_WRITE_ENABLED=false` | `Contribuzione a Open Facts disabilitata sul server` |
| 413 | photo over 5 MB (declared or actual) | `Immagine troppo grande (max 5MB)` |
| 415 | empty, unknown, or `Content-Type`/magic mismatch | `Tipo immagine non consentito (JPEG/PNG/HEIC)` |
| 422 | bad `code`, empty product fields, bad `lang`, bad `imagefield`, image under 640x160 px | Pydantic error / `code non valido` / `imagefield non valido` / `Immagine troppo piccola (minimo 640x160 px)` |
| 422 | bad `product_type` (not `food\|beauty\|petfood\|product`) | Pydantic error (metadata) / `product_type non valido` (photo) |
| 429 | >10 req/min per IP | `Troppe richieste, riprova tra poco` |
| 502 | OFF transport error or `status != 1` refusal | `Errore durante la comunicazione con Open Facts` / `Open Facts ha rifiutato il contributo` |

**Prod note**: in-memory limiter is a no-dependency mitigation; replace with `slowapi`/Redis-backed auth before go-live (`TODO(prod)` in `backend/routes/contribute.py:41`).
