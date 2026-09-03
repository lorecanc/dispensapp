---
title: "Scan"
description: "Barcode scan endpoint that looks up product information via Open Food Facts"
category: "api"
source_files:
  - "backend/routes/scan.py"
  - "backend/schemas.py"
  - "backend/services/off.py"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Scan

## Endpoints

### POST /api/scan

**Description**: Accepts a barcode string (sent by the iOS [APIClient](../concepts/ios-networking.md)), delegates to the [Open Food Facts (OFF) API](../concepts/off-integration.md), and returns product details if found.

**Source**: [`backend/routes/scan.py`](../modules/backend-routes-scan.md)

#### Request

Accepts a JSON body with a single field.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `barcode` | `string` | yes | The EAN-13 (or other) barcode to look up |

```json
{
  "barcode": "8076809514381"
}
```

Schema: `ScanRequest` (`backend/schemas.py:9`)

#### Response

Returns a `ScanResponse` (`backend/schemas.py:13`) with the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `barcode` | `string` | The requested barcode |
| `name` | `string` or `null` | Product name (empty string when not found) |
| `brand` | `string` or `null` | Product brand |
| `categories` | `array` of `string` | Product category tags (last segment of OFF category hierarchy) |
| `image_url` | `string` or `null` | URL to the front-of-pack small image |
| `found` | `boolean` | Whether the product was found in OFF |
| `message` | `string` or `null` | Human-readable message (set only when `found` is `false`) |

#### Response States

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

Returned when OFF responds but has no data for this barcode (status != 1 or no product object).

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

Returned when the HTTP request to OFF fails (HTTP error, timeout, or invalid JSON).

```json
{
  "message": "Errore durante la comunicazione con Open Food Facts"
}
```

The error body uses `MessageResponse` (`backend/schemas.py:83`).

#### Backend Flow

1. `scan_barcode()` receives the `ScanRequest` body.
2. Calls [`fetch_product(barcode)`](../modules/backend-service-off.md) in `backend/services/off.py`.
3. `fetch_product` sends a GET to [`{OFF_BASE_URL}`](../config/backend-config.md)/{barcode}.json with a 10-second timeout.
4. Parses the OFF JSON response, extracting `product_name`, `brands`, `categories_tags`, and `image_front_small_url`.
5. `categories_tags` values are reduced to their last segment (e.g. `en:pastas` → `pastas`).
6. If `fetch_product` returns `None` → 502 Bad Gateway.
7. If `fetch_product` returns `{"found": False}` → 200 OK with `found=false` and a message.
8. Otherwise → 200 OK with `found=true` and the enriched product data.

## Contribute Endpoints (OFF Write, Opt-in)

Disabled by default; require `OFF_WRITE_ENABLED=true` (+ `OFF_USER`/`OFF_PASS`, see [backend config](../config/backend-config.md) and [OFF integration](../concepts/off-integration.md)). Both share an in-memory rate limit of 10 req/min per IP (`429`) and require `consent_cc_bysa=true` (CC BY-SA, `400` otherwise). Env default is OFF staging (`https://world.openfoodfacts.net/cgi`); prod only via explicit env. iOS module: `APIClient.contribute` / `APIClient.uploadPhoto`.

### POST /api/scan/contribute

**Description**: Sends metadata to OFF via `product_jqm2.pl` (`backend/routes/contribute.py` → `services/off.py:contribute_product`).

**Request** (`application/json`): `code` (`^\d{8,14}$`), `consent_cc_bysa` (bool, required), `lang` (default `it`), plus at least one of `product_name` (max 200), `brands` (max 200), `quantity` (max 64), `categories` (max 500).

**Responses**: `200 {"ok": true, "code", "message"}`; `400` missing consent / no field; `403` disabled; `429` rate-limit; `502` OFF transport/refusal.

### POST /api/scan/contribute/photo

**Description**: Uploads a product photo to OFF via `product_image_upload.pl` (`contribute.py` → `off.py:upload_product_image`).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `code` | form `string` | yes | Barcode `^\d{8,14}$` (`422` if invalid) |
| `imagefield` | form `string` | yes | Allowlist: `front_it`, `ingredients_it`, `nutrition_it`, `packaging_it` (`422` otherwise) |
| `consent_cc_bysa` | form `bool` | yes | Must be `true` (`400` otherwise) |
| `image` | file | yes | JPEG/PNG/HEIC, max 5MB (`413` over limit; `415` on empty or declared vs magic-byte mismatch) |

**Responses**: `200 {"ok": true, "code", "message": "Foto inviata a Open Food Facts"}`; `400`/`403`/`429` as above; `422` invalid `code`/`imagefield`; `413` oversize; `415` type not allowed; `502` OFF transport/refusal.

**Prod note**: the in-memory limiter is a no-dependency mitigation; replace with `slowapi` + Redis before go-live (see `TODO(prod)` in `contribute.py`) — no dependency added now.
