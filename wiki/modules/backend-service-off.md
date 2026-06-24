---
title: "Open Food Facts Client Service"
description: "Async client for the Open Food Facts API — barcode lookup, error handling, and category normalization"
category: "modules"
source_files:
  - "backend/services/off.py"
  - "backend/config.py"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Open Food Facts Client Service

## Purpose

Provides a single async function `fetch_product` that looks up a product by barcode via the [Open Food Facts (OFF) public API](../concepts/off-integration.md). It normalises the response into a minimal dictionary the app can use directly, and handles all network and data errors gracefully so callers never need to deal with HTTP or JSON parsing. The [scan route](./backend-routes-scan.md) is the primary consumer of this service.

## Key Files

| File | Role |
|------|------|
| `backend/services/off.py` | Client function and error handling |
| `backend/config.py` | [`OFF_BASE_URL` constant](../config/backend-config.md) |

## Public API

`fetch_product(barcode: str) -> Optional[dict]`

The single exported function. It is `async` and returns:
- `None` — on any network error (HTTP error, timeout, connection issue) or JSON decode failure.
- `{"found": False}` — when the API responds successfully but the product does not exist (`status != 1` or `product` key is `None`).
- A dictionary with product data — on a successful lookup.

## Flow

```mermaid
graph LR
    Caller -->|barcode| Fetch["fetch_product(barcode)"]
    Fetch -->|"{OFF_BASE_URL}/{barcode}.json"| Httpx["httpx.AsyncClient\ntimeout=10s"]
    Httpx -->|HTTPError / TimeoutException / ValueError| RetNone["return None"]
    Httpx -->|response.json()| Parse["parse response"]
    Parse -->|"status != 1 or product is None"| NotFound["return {'found': False}"]
    Parse -->|valid product| Normalize["normalise fields"]
    Normalize --> Success["return product dict"]
```

## Error Handling Strategy

All exceptions are caught in a single `try` block:

| Exception | Behaviour |
|-----------|-----------|
| `httpx.HTTPError` | Network-level failure (DNS, connection refused, non-2xx status after `raise_for_status`) |
| `httpx.TimeoutException` | Request exceeds the 10-second client timeout |
| `ValueError` | Response body is not valid JSON |

Any of these produces a `return None` — the caller cannot distinguish between error types, but the contract is simple: "no product info available".

## Response Format

### Success (`found: true`, implicit)

| Key | Source | Notes |
|-----|--------|-------|
| `barcode` | function parameter `barcode` | Passed through unchanged |
| `name` | `product["product_name"]` | Defaults to `""` if missing |
| `brand` | `product["brands"]` | `None` if absent or empty string |
| `categories` | `product["categories_tags"]` | Array of normalised category strings |
| `image_url` | `product["image_front_small_url"]` | `None` if absent or empty string |

### Not found

```python
{"found": False}
```

### Error

```python
None
```

## Category Normalisation

The OFF API returns categories as tagged strings like `"en:yogurts"`, `"en:pasta"`, `"en:cheddar-cheese"`.

The function normalises each tag by splitting on `":"` and taking the last segment:

```python
[c.split(":")[-1] for c in product.get("categories_tags", [])]
```

This turns `"en:yogurts"` into `"yogurts"` and `"en:cheddar-cheese"` into `"cheddar-cheese"`. The result is a flat list of short category slugs that align with the `DEFAULT_SHELF_LIFE` keys in `config.py`. These normalized categories feed into the [scan API response](../api/scan.md).

## Testing

Unit tests for `fetch_product` live in the [backend test suite](./backend-tests.md) — see `test_off.py` for mocked HTTP scenarios.

## Usage Example

```python
from backend.services.off import fetch_product

result = await fetch_product("8000500313273")
if result is None:
    # network error — maybe retry later
    ...
elif "found" in result and not result["found"]:
    # barcode not in OFF database
    ...
else:
    name = result["name"]
    brand = result["brand"]
    categories = result["categories"]
    image_url = result["image_url"]
```
