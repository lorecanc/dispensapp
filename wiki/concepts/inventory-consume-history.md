---
title: "Inventory Consume & History"
description: "Atomic quantity decrement with an append-only ConsumptionEvent ledger and the Storico history UI"
category: "concepts"
source_files:
  - "backend/routes/inventory.py"
  - "backend/models.py"
  - "backend/schemas.py"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/Features/Inventory/InventoryListView.swift"
  - "ios/Inventario/Features/Inventory/ItemDetailView.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
---

# Inventory Consume & History

Consuming an item is an atomic server-side decrement that appends one row to an append-only `ConsumptionEvent` ledger. There is no update or delete API for events, and no actor token is persisted. Per-item history stays queryable after the item row is gone, and iOS surfaces zeroed items in a Storico sheet.

## Atomic Consume

`POST /api/pantries/{pantry_id}/inventory/{item_id}/consume` with body [`InventoryConsume`](../modules/backend-schemas.md) (`delta: 1–999`, optional `reason` ≤ 500 chars, blank collapses to `None`).

`_consume_scoped_item` (`backend/routes/inventory.py:158`) runs a single guarded `UPDATE ... SET quantity = quantity - delta WHERE id AND pantry AND quantity >= delta`:

- 0 rows + item missing → `404 Elemento non trovato`.
- 0 rows + item exists → `409 Quantità insufficiente` (over-consume is rejected, never clamped).
- Success → one `ConsumptionEvent` appended in the same transaction (`delta` stored negated, e.g. `-1`).

Contract A at zero: when the remaining quantity hits 0 the item row is **deleted**, and the endpoint returns a zero-quantity snapshot (id/created_at preserved). The ledger row survives because `item_id` is `ON DELETE SET NULL` / nullable.

## Append-Only Ledger

`ConsumptionEvent` (`backend/models.py:125`) on `consumption_events`: `pantry_id` (NOT NULL, CASCADE), `item_id` (nullable), `name_snapshot` (NOT NULL — the display name after row deletion), `barcode`, `delta`, `reason`, `created_at`. Index on `(pantry_id, created_at)`.

Rules: no update/delete endpoint exists for events, and `actor_token` is deliberately not written or stored (privacy). `ConsumptionEventOut` mirrors the columns with optional `item_id`.

## History Endpoint

`GET /api/pantries/{pantry_id}/inventory/{item_id}/history?limit&offset` filters on `pantry_id + item_id` only — it does **not** require the item row to exist — ordered `created_at DESC, id DESC`. Legacy shims `POST/GET /api/inventory/{item_id}/consume|history` target the default pantry.

## iOS Behavior

- `APIClient.consume` posts `{delta, reason?}`; `APIClient.history` GETs `.../history?limit=` (`ios/Inventario/Networking/APIClient.swift:529`).
- `InventoryStore.consume(item:delta:reason:)` (see [iOS State Management](../concepts/ios-state-management.md)) replaces the row on success, removes + inserts into `archivedIDs` at zero, and invalidates the per-item history cache; `409` surfaces as `"Quantità insufficiente per <name>."` (`ios/Inventario/State/InventoryStore.swift:395`). Offline consumes apply optimistically and enqueue a `.consume` outbox entry.
- `fetchHistory(itemId:)` is non-critical: `401/403/404` are logged (`history non-critical — cache only`) and fall back to cached/`[]` — never an error banner.
- UI: `ItemDetailView` only triggers consume (`Segna come consumato` → `decrementQuantity`, delta 1). The **Storico** sheet lives in `InventoryListView.historySheet` (ellipsis menu): one section per `archivedIDs` entry showing `abs(delta) × nameSnapshot` + timestamp, lazy-loading each section via `.task { fetchHistory }`, with a `ContentUnavailableView` when empty.
