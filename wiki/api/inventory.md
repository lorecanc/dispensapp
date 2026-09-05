---
title: "Inventory API"
description: "Pantry-scoped inventory CRUD, atomic consume, and consumption history"
category: "api"
source_files:
  - "backend/routes/inventory.py"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# Inventory API

## Endpoints

Scoped routes require pantry membership via `get_current_pantry` (`X-Pantry-Token` header; see [Pantry Sharing](../concepts/pantry-sharing.md)). Non-member on an existing pantry returns `403`; an item that does not belong to the pantry returns `404`. All scoped routes use strict `pantry_id` matching (`allow_null=False`).

### GET /api/pantries/{pantry_id}/inventory

**Description**: List pantry items with `quantity > 0`, ordered by expiration date ascending (nulls last).

**Request**: Path `pantry_id: int`. Query `limit: int = 50 (1-100)`, `offset: int = 0`. Header `X-Pantry-Token`.

**Response**: `200` `list[InventoryOut]`.

**Source**: `backend/routes/inventory.py:269-277`

### POST /api/pantries/{pantry_id}/inventory

**Description**: Create an item from a barcode scan. Resolves expiration via `resolve_expiration`, infers `compartment` when omitted, normalizes category, stores `pantry_id` and `created_by_token`.

**Request**: Path `pantry_id: int`. Body `InventoryCreate` (`barcode`, `name`, `brand`, `expiration_date`, `category`, `image_url`, `quantity`, `compartment`). Header `X-Pantry-Token`.

**Response**: `201` `InventoryOut`. `500` on persistence failure.

**Source**: `backend/routes/inventory.py:280-289`

### POST /api/pantries/{pantry_id}/inventory/manual

**Description**: Create an item via manual entry (`barcode=None`). Same expiration/compartment handling as the barcode route, with `allow_none=True` so a missing date and category yields `expiration_date=None`.

**Request**: Path `pantry_id: int`. Body `InventoryCreateManual` (same fields minus `barcode`). Header `X-Pantry-Token`.

**Response**: `201` `InventoryOut`. `500` on persistence failure.

**Source**: `backend/routes/inventory.py:292-303`

### GET /api/pantries/{pantry_id}/inventory/export

**Description**: Export pantry items (`quantity > 0`, same expiration ordering) as a markdown table via the `to_markdown` service.

**Request**: Path `pantry_id: int`. Header `X-Pantry-Token`.

**Response**: `200` `PlainTextResponse` with `media_type="text/markdown"`.

**Source**: `backend/routes/inventory.py:306-322`

### GET /api/pantries/{pantry_id}/inventory/{item_id}

**Description**: Return a single item scoped to the pantry.

**Request**: Path `pantry_id: int`, `item_id: int`. Header `X-Pantry-Token`.

**Response**: `200` `InventoryOut`. `404` `{"detail": "Elemento non trovato"}` when the item is missing or belongs to another pantry.

**Source**: `backend/routes/inventory.py:325-332`

### PATCH /api/pantries/{pantry_id}/inventory/{item_id}

**Description**: Partially update an item. Applies only explicitly sent fields (`model_dump(exclude_unset=True)`), normalizing `category` and stringifying `image_url`.

**Request**: Path `pantry_id: int`, `item_id: int`. Body `InventoryUpdate` (all fields optional, at least one required). Header `X-Pantry-Token`.

**Response**: `200` `InventoryOut`. `404` when the item is missing or out of scope. `422` on empty/invalid body. `500` on persistence failure.

**Source**: `backend/routes/inventory.py:335-343`

### DELETE /api/pantries/{pantry_id}/inventory/{item_id}

**Description**: Delete an item scoped to the pantry.

**Request**: Path `pantry_id: int`, `item_id: int`. Header `X-Pantry-Token`.

**Response**: `204` empty body. `404` when the item is missing or out of scope. `500` on persistence failure.

**Source**: `backend/routes/inventory.py:346-354`

### POST /api/pantries/{pantry_id}/inventory/{item_id}/consume

**Description**: Atomically decrement `quantity` by `delta` (`UPDATE ... WHERE quantity >= delta`). Writes a `ConsumptionEvent` (`delta=-delta`, name/barcode snapshot, no actor token; see [Inventory Consume & History](../concepts/inventory-consume-history.md)). When the remainder reaches zero the row is deleted and a zero-quantity snapshot is returned (Contract A); history remains queryable.

**Request**: Path `pantry_id: int`, `item_id: int`. Body `InventoryConsume` (`delta: int`, `reason: str | None`). Header `X-Pantry-Token`.

**Response**: `200` `InventoryOut` (updated item, or snapshot with `quantity=0` after deletion). `404` when the item is missing or out of scope. `409` `{"detail": "Quantità insufficiente"}` when stock is insufficient. `500` on persistence failure.

**Source**: `backend/routes/inventory.py:438-451`

### GET /api/pantries/{pantry_id}/inventory/{item_id}/history

**Description**: List consumption events for a pantry + item pair, newest first (`created_at DESC, id DESC`; see [Inventory Consume & History](../concepts/inventory-consume-history.md)). Does not require the item row to exist, so history survives zero-quantity deletion (Contract A).

**Request**: Path `pantry_id: int`, `item_id: int`. Query `limit: int = 50 (1-100)`, `offset: int = 0`. Header `X-Pantry-Token`.

**Response**: `200` `list[ConsumptionEventOut]`.

**Source**: `backend/routes/inventory.py:454-466`

### Legacy shims (deprecated)

**Description**: Unscoped `/api/inventory*` routes bound to `DEFAULT_PANTRY_ID = 1` for legacy clients. New clients must use `/api/pantries/{id}/inventory`. Shims validate the token against the default pantry and include pre-T3 rows with `pantry_id NULL` (`allow_null=True`); scoped routes never include NULL rows.

**Request**: `POST /api/inventory`, `POST /api/inventory/manual`, `GET /api/inventory`, `GET /api/inventory/export`, `GET /api/inventory/{item_id}`, `PATCH /api/inventory/{item_id}`, `DELETE /api/inventory/{item_id}`, `POST /api/inventory/{item_id}/consume`, `GET /api/inventory/{item_id}/history`, each with `X-Pantry-Token` and the same bodies/query params as their scoped counterparts.

**Response**: Same shapes and status codes as the scoped counterparts (`201` on create, `200` on read/update/consume/history, `204` on delete, `404`/`409` on consume errors).

**Source**: `backend/routes/inventory.py:360-432, 472-493`
