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
