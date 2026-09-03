---
title: "Open Food Facts Integration"
description: "Barcode scan integration with the Open Food Facts public API"
category: "concepts"
source_files:
  - "backend/services/off.py"
  - "backend/routes/scan.py"
  - "backend/schemas.py"
  - "backend/config.py"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Open Food Facts Integration

## Purpose

The Open Food Facts (OFF) integration enables the Inventario iOS app to look up product information by scanning a barcode. It acts as a bridge between the mobile client and the public OFF database, normalising the OFF response into the app's own data model.

## Integration Flow

```mermaid
sequenceDiagram
    participant iOS as iOS App
    participant API as FastAPI /api/scan
    participant OFF_svc as off.fetch_product()
    participant OFF_API as Open Food Facts API

    iOS->>+API: POST /api/scan { barcode }
    API->>+OFF_svc: fetch_product(barcode)
    OFF_svc->>+OFF_API: GET /api/v0/product/{barcode}.json
    alt OFF responds with product
        OFF_API-->>-OFF_svc: status=1 + product data
        OFF_svc->>OFF_svc: Extract & normalise fields
        OFF_svc-->>-API: { found: true, name, brand, categories, image_url }
        API-->>-iOS: 200 ScanResponse (found=true)
    else OFF responds no product
        OFF_API-->>-OFF_svc: status!=1 or missing product
        OFF_svc-->>-API: { found: false }
        API-->>-iOS: 200 ScanResponse (found=false, message)
    else OFF unreachable / error
        OFF_API--x-OFF_svc: HTTP or network error
        OFF_svc-->>-API: None
        API-->>-iOS: 502 MessageResponse (error message)
    end
```

## API Call Flow

### 1. Client request

The iOS app sends a POST request with the scanned barcode:

```json
{
  "barcode": "8000500310807"
}
```

The endpoint is defined at [routes/scan.py](../modules/backend-routes-scan.md) with a `ScanRequest` body schema (`schemas.py:9`), which simply wraps a `barcode: str` field.

### 2. Fetch from OFF

[fetch_product(barcode)](../modules/backend-service-off.md) in `services/off.py:8` constructs the URL from the configured base:

```
https://world.openfoodfacts.org/api/v0/product/{barcode}.json
```

The base URL is defined in `config.py:16` as `OFF_BASE_URL`. An `httpx.AsyncClient` with a 10-second timeout performs the GET request.

### 3. Parse response

The OFF API returns a JSON object with a `status` integer and a `product` object. The function checks:

- `status == 1` and `product` is not `None` → product found
- Otherwise → `{"found": False}`

When found, the following fields are extracted (`off.py:23-28`):

| Field | OFF source | Notes |
|-------|------------|-------|
| `barcode` | function argument | Passed through as-is |
| `name` | `product["product_name"]` | Defaults to `""` if missing |
| `brand` | `product["brands"]` | Set to `None` if missing or empty |
| `categories` | `product["categories_tags"]` | Each tag is normalised (see below) |
| `image_url` | `product["image_front_small_url"]` | Set to `None` if missing |

### 4. Response to client

The [scan endpoint](../api/scan.md) (`scan.py:29-36`) builds a `ScanResponse` (`schemas.py:13`) from `fetch_product`'s return value.

## Category Normalisation

OFF category tags follow the format `en:pasta`, `en:yogurts`, `fr:fromages`, etc. The integration strips the language prefix, keeping only the portion after the colon:

```python
[c.split(":")[-1] for c in product.get("categories_tags", [])]
```

**Examples:**

| OFF tag | Normalised value |
|---------|-----------------|
| `en:pasta` | `pasta` |
| `en:yogurts` | `yogurts` |
| `en:canned-vegetables` | `canned-vegetables` |

This normalisation is purely syntactic — it removes the language prefix but does not translate or further normalise the category string. Downstream code (such as `config.py`'s `DEFAULT_SHELF_LIFE` map) must match against the normalised values.

## Error States

The integration handles three distinct failure modes:

### OFF unreachable

Any `httpx.HTTPError`, `httpx.TimeoutException`, or non-JSON response (caught by `ValueError` on `response.json()`) causes `fetch_product` to return `None`. The scan endpoint returns a **502 Bad Gateway** with JSON body:

```json
{
  "message": "Errore durante la comunicazione con Open Food Facts"
}
```

### Product not found

OFF responds successfully but `status != 1` or `product` is missing. `fetch_product` returns `{"found": False}`. The endpoint returns **200 OK** with:

```json
{
  "barcode": "8000500310807",
  "found": false,
  "message": "Prodotto non trovato nel database Open Food Facts"
}
```

Note that the response is HTTP 200, not 404 — the scan itself succeeded, it simply found no matching product.

## Response Paths Summary

| Condition | HTTP Status | `found` | Body includes |
|-----------|-------------|---------|---------------|
| Product found | 200 | `true` | `barcode`, `name`, `brand`, `categories`, `image_url` |
| Product not in OFF | 200 | `false` | `barcode`, `message` (Italian: "Prodotto non trovato...") |
| OFF unreachable | 502 | — | `message` (Italian: "Errore durante la comunicazione...") |

Messages are in Italian because the app's primary user base is Italian-speaking.

## Configuration

| Setting | Value | Source |
|---------|-------|--------|
| `OFF_BASE_URL` | `https://world.openfoodfacts.org/api/v0/product` | [config.py](../config/backend-config.md) |
| HTTP timeout | 10 seconds | `off.py:11` (hardcoded in `httpx.AsyncClient`) |

The timeout is hardcoded in the service function and is not configurable at runtime. The base URL could be changed via `OFF_BASE_URL` if needed (e.g., to target a different OFF mirror).

## Write Path (Contribute Metadata + Photo)

Opt-in contribution flow via `POST /api/scan/contribute` (JSON metadati) and `POST /api/scan/contribute/photo` (multipart foto), implemented in `backend/routes/contribute.py` → `backend/services/off.py` (`product_jqm2.pl` / `product_image_upload.pl`). Disabled by default (`OFF_WRITE_ENABLED=false`).

### Photo flow

1. iOS `APIClient.uploadPhoto` sends multipart `code` + `imagefield` + `consent_cc_bysa` + `image` to `POST /api/scan/contribute/photo`.
2. Backend checks rate-limit (10 req/min per IP, in-memory) → `429` when exceeded.
3. Requires `consent_cc_bysa=true` (CC BY-SA licence) → `400` otherwise; requires `OFF_WRITE_ENABLED` → `403` otherwise.
4. Validates `code` (`^\d{8,14}$`) → `422`, and `imagefield` allowlist (`front_it`, `ingredients_it`, `nutrition_it`, `packaging_it`) → `422`.
5. Reads bytes: empty → `415`; over 5MB → `413`; `Content-Type` dichiarato vs magic-byte rilevati (JPEG/PNG/HEIC) mismatch → `415`.
6. Forwards to OFF staging with `OFF_USER`/`OFF_PASS` and app `User-Agent` (password e bytes mai nei log); OFF `status != 1` → `502`, altrimenti `200 {"ok": true, "code", "message"}`.

### Env

See [.env.example](../../.env.example) and [backend config](../config/backend-config.md): `OFF_WRITE_ENABLED`, `OFF_WRITE_BASE_URL` (default staging `https://world.openfoodfacts.net/cgi`, prod `https://world.openfoodfacts.org/cgi` solo via env), `OFF_USER`/`OFF_PASS` (vuoti di default, obbligatori per abilitare), `OFF_APP_NAME`/`OFF_APP_VERSION`, `OFF_CONTACT_EMAIL`. Invalid/insecure base URL falls back to staging with a warning.

### Consent

Both endpoints require explicit `consent_cc_bysa=true` because contributions are published under CC BY-SA. iOS gates the send button on the consent toggle.

### Rate limit (10/min in-memory)

`_RATE_LIMIT` dict per IP with a 60s sliding window (`_RATE_LIMIT_MAX=10`) shared by both contribute endpoints; no new dependencies. Cleared/isolated per test via fixture.

### Prod option (slowapi/Redis)

For production, replace the in-memory limiter with `slowapi` backed by Redis (shared across workers/hosts, persistent) before go-live — see the `TODO(prod)` in `backend/routes/contribute.py`. No extra dependency is added now to keep the current scope minimal.
