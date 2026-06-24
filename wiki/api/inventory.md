---
title: "Inventory API"
description: "CRUD endpoints for pantry inventory items — create, read, update, delete, and export"
category: "api"
source_files:
  - "backend/routes/inventory.py"
  - "backend/schemas.py"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Inventory API

## Overview

The inventory API manages pantry items in the Inventario app. It provides endpoints for creating items via barcode scan or manual entry, listing, updating, deleting, and exporting inventory data. [Expiration dates](../concepts/expiration-estimation.md) are estimated when not provided using a dedicated service.

## Endpoints

| Method | Path | Status | Description |
|--------|------|--------|-------------|
| POST | `/api/inventory` | 201 | Create an item from a barcode scan |
| POST | `/api/inventory/manual` | 201 | Create an item manually |
| PATCH | `/api/inventory/{item_id}` | 200 | Partially update an item |
| GET | `/api/inventory` | 200 | List all items, ordered by expiration date |
| GET | `/api/inventory/export` | 200 | Export inventory as markdown |
| DELETE | `/api/inventory/{item_id}` | 204 | Delete an item |

**Router prefix**: `/api` — [`backend/routes/inventory.py`](../modules/backend-routes-inventory.md)

### POST /api/inventory

**Description**: Creates a new inventory item from a barcode scan result.

**Request body** (`InventoryCreate`):

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `barcode` | `str` | yes | — | Scanned barcode |
| `name` | `str` | yes | — | Product name |
| `brand` | `Optional[str]` | no | `None` | Brand name |
| `expiration_date` | `Optional[date]` | no | `None` | If provided, used directly with `is_estimated=false` |
| `category` | `Optional[str]` | no | `None` | Product category |
| `image_url` | `Optional[str]` | no | `None` | Product image URL |
| `quantity` | `int` | no | `1` | Item count |

**Business logic**:
- If `expiration_date` is provided → stored as-is, `is_estimated=false`.
- If `expiration_date` is omitted → `estimate_expiration(category_tags=[category])` is called with the category as a tag (or `None` if no category). The result is stored with `is_estimated=true`.

**Response** (`201`): `InventoryOut`

**Source**: `backend/routes/inventory.py:20-43`

---

### POST /api/inventory/manual

**Description**: Creates a new inventory item via manual entry (no barcode required).

**Request body** (`InventoryCreateManual`):

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | `str` | yes | — | Product name |
| `brand` | `Optional[str]` | no | `None` | Brand name |
| `expiration_date` | `Optional[date]` | no | `None` | If provided, used directly with `is_estimated=false` |
| `category` | `Optional[str]` | no | `None` | Product category |
| `quantity` | `int` | no | `1` | Item count |

**Business logic**:
- If `expiration_date` is provided → stored as-is, `is_estimated=false`.
- If `expiration_date` is omitted and `category` is provided → `estimate_expiration(category_tags=[category])` is called, `is_estimated=true`.
- If neither `expiration_date` nor `category` is provided → `expiration_date` is set to `None`, `is_estimated=false`.

Unlike the barcode endpoint, manual items always store `barcode=None`. The estimation fallback only works when a category is present.

**Response** (`201`): `InventoryOut`

**Source**: `backend/routes/inventory.py:46-72`

---

### PATCH /api/inventory/{item_id}

**Description**: Partially updates an existing inventory item. Only the fields included in the body are updated.

**Request body** (`InventoryUpdate`):

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `name` | `Optional[str]` | no | — | Product name |
| `brand` | `Optional[str]` | no | — | Brand name |
| `expiration_date` | `Optional[date]` | no | — | Expiration date |
| `category` | `Optional[str]` | no | — | Product category |
| `image_url` | `Optional[str]` | no | — | Product image URL |
| `quantity` | `Optional[int]` | no | — | Item count |

At least one field must be provided. The schema uses a `model_validator` that raises `ValueError` if no fields are set (`backend/schemas.py:76-80`).

**Implementation**: Uses `model_dump(exclude_unset=True)` to apply only the fields the client explicitly sent, enabling true partial updates (`backend/routes/inventory.py:80`).

**Error handling**:
- `404` — item not found: raises `HTTPException(status_code=404, detail="Elemento non trovato")`.

**Response** (`200`): `InventoryOut`

**Source**: `backend/routes/inventory.py:75-85`

---

### GET /api/inventory

**Description**: Returns all inventory items ordered by expiration date ascending, with null dates last.

**Response** (`200`): `list[InventoryOut]`

Ordering is applied at the database level: `InventoryItem.expiration_date.asc().nulls_last()` (`backend/routes/inventory.py:92`).

**Source**: `backend/routes/inventory.py:88-95`

---

### GET /api/inventory/export

**Description**: Exports the entire inventory as a markdown table. Uses the [`to_markdown` service](../modules/backend-service-markdown-export.md) to render items.

**Response** (`200`): `PlainTextResponse(content=..., media_type="text/markdown")` — a plain text response with content type `text/markdown`.

Items are fetched with the same ordering as the list endpoint (expiration date ASC, nulls last).

**Source**: `backend/routes/inventory.py:98-106`

---

### DELETE /api/inventory/{item_id}

**Description**: Deletes an inventory item by ID.

**Error handling**:
- `404` — item not found: returns a `JSONResponse(status_code=404)` with a `MessageResponse` body (`{"message": "Elemento non trovato"}`). Notably, this uses `JSONResponse` directly rather than raising `HTTPException`.

**Response** (`204`): No content. On success, returns an empty `Response(status_code=204)`. The response body is empty.

**Source**: `backend/routes/inventory.py:109-119`

---

## [Schemas](../modules/backend-schemas.md)

### InventoryOut (response)

| Field | Type | Description |
|-------|------|-------------|
| `id` | `int` | Primary key |
| `barcode` | `Optional[str]` | Scanned barcode, `None` for manual entries |
| `name` | `str` | Product name |
| `brand` | `Optional[str]` | Brand name |
| `expiration_date` | `Optional[date]` | Expiration date, possibly estimated |
| `is_estimated` | `bool` | Whether the expiration date was estimated |
| `category` | `Optional[str]` | Product category |
| `image_url` | `Optional[str]` | Product image URL |
| `created_at` | `datetime` | Timestamp of creation |
| `quantity` | `int` | Item count (default 1) |
| `status` | `str` | **Computed field**: `"expired"` if past due, `"expiring_soon"` if within `EXPIRING_SOON_DAYS`, otherwise `"ok"`. Returns `"ok"` when `expiration_date` is `None`. |

`status` is a `@computed_field` on the Pydantic model (`backend/schemas.py:55-65`). It compares `expiration_date` against `date.today()` using the `EXPIRING_SOON_DAYS` threshold from configuration. See [Item Status](../concepts/item-status.md) for the status classification details.

### MessageResponse

Used for error responses on the DELETE endpoint.

| Field | Type | Description |
|-------|------|-------------|
| `message` | `str` | Human-readable message |

## Error Handling Summary

| Scenario | HTTP Status | Response Type | Details |
|----------|-------------|---------------|---------|
| Item not found (PATCH) | 404 | `HTTPException` | JSON `{"detail": "Elemento non trovato"}` |
| Item not found (DELETE) | 404 | `JSONResponse` | JSON `{"message": "Elemento non trovato"}` |
| No fields to update | 422 | Pydantic validation error | Validation error from `model_validator` |
| Validation errors | 422 | Pydantic validation error | Standard FastAPI request validation |

The DELETE endpoint uses `JSONResponse` directly instead of `HTTPException`, which means its error response shape differs from the PATCH endpoint's (`message` vs `detail` key).

## Dependencies

| Dependency | Source | Role |
|------------|--------|------|
| `estimate_expiration` | `backend/services/expiration.py` | Estimates expiration date from category tags |
| `to_markdown` | `backend/services/markdown_export.py` | Renders inventory items as a markdown table |
| `InventoryItem` | `backend/models.py` | SQLAlchemy ORM model |
| `get_db` | `backend/database.py` | FastAPI dependency for DB session |
