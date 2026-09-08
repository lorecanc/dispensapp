---
title: "iOS State Management"
description: "InventoryStore multi-pantry single-source, optimistic outbox with FIFO replay, snapshot cold-start, and provisioning"
category: "concepts"
source_files:
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/State/OutboxStore.swift"
  - "ios/Inventario/State/LocalInventoryCache.swift"
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/Models/InventoryItem.swift"
created: "2026-06-24"
last_updated: "2026-09-06"
---

# iOS State Management

## Overview

The iOS app uses a single `InventoryStore` (`@Observable`, `@MainActor`) as the source of truth for multi-pantry inventory state. SwiftUI views re-render when observed properties change; all async work runs on the main actor.

Supporting types are pure and testable (no network, no `MainActor`):

- `OutboxStore` — persistent FIFO queue (`outbox.json` in Application Support) of offline mutations.
- `LocalInventoryCache` — per-pantry JSON snapshots (`pantry-<id>.json` in Caches) for instant cold-start.

Consumers: `InventoryListView`, `ItemDetailView`, `ManualEntryView` (`addManual`), `ScanPreviewSheet` (`add`).

## @Observable Pattern

```swift
@Observable
@MainActor
final class InventoryStore {
    var items: [InventoryItem] = []
    var pantries: [Pantry] = []
    var history: [Int: [ConsumptionEvent]] = [:]
    var archivedIDs: Set<Int> = []
    var isLoading = false
    var error: APIError?
    var exportedMarkdown: String?
    var selectedPantryId: Int = /* UserDefaults "selectedPantryId", default 1 */
}
```

| Property | Mutated by | Notes |
|---|---|---|
| `items` | `refresh`, CRUD, `consume`, outbox enqueue, `selectPantry`/`deletePantry` | Always sorted by expiration date; cleared on pantry switch |
| `pantries` | `fetchPantries`, provisioning, `deletePantry` | Verified list — network calls only target IDs in this list (B2 gate) |
| `history` | `fetchHistory`, `consume`, delete paths | Per-item consumption events; cleared on pantry switch |
| `archivedIDs` | `consume` to zero, deletes | Local-only transient: IDs removed from list but visible in history via cache |
| `isLoading` | `refresh` | `true` during request, reset via `defer` |
| `error` | Every public method via `setError(from:)` | Reset to `nil` at method start; `.offline` never populates it (pill `isOffline` covers it) |
| `exportedMarkdown` | `exportMarkdown` | Cleared on pantry switch |
| `selectedPantryId` | `selectPantry`, `fetchPantries`, `deletePantry` | Persisted to `UserDefaults`; `didSet` clears `items`/`history`/`archivedIDs`/`exportedMarkdown`/`error` on change |

## Multi-Pantry Selection

`selectedPantryId` defaults to the persisted value (fallback `1`). `selectPantry(_:)` just assigns it — the `didSet` does the state hygiene (clears previous pantry data to avoid leaks), and callers then `refresh()`.

`selectedPantryName` derives from `pantries` (fallback `"Dispensa"`).

## selectPantry / deletePantry

`deletePantry(id:)` is optimistic with full rollback:

1. Snapshot `pantries`, `selectedPantryId`, `items`, `history`, `exportedMarkdown`.
2. Remove locally; if it was selected, select `pantries.first` (or clear list state if none left).
3. `DELETE /pantries/{id}`; on success `cache.remove(pantryId:)` so no ghost snapshot survives.
4. On failure restore all snapshots and `setError(from:)` (no-ops on `Task.isCancelled`).

## Refresh, Snapshot Cold-Start, Category Registry

`refresh()`:

1. `isLoading = true` (deferred reset), `error = nil`.
2. If `items` is empty, load `cache.load(pantryId:)` synchronously — stale-but-instant cold-start (P4), before and regardless of network.
3. B2 gate: return early unless `selectedPantryId` is in verified `pantries` (avoids chained 403s on ghost IDs; `fetchPantries()` retries after verification).
4. `listScoped(pantryId:)` → sort by `expirationDate ?? .distantFuture` → `cache.save(items, pantryId:)` → `refreshCategoryRegistry()`.

`refreshCategoryRegistry()` is best-effort and non-critical: once per session it fetches `fetchCategories()` into `CategoryRegistry`; offline keeps the embedded fallback with no banner and retries next session if it failed.

## Error Propagation

Single setter `setError(from:)`:

- `classify(_:)` maps `URLError` codes (not-connected, timeout, cannot-connect/find-host, connection-lost, data-not-allowed) to `APIError.offline`.
- `.offline` returns early — no banner; the `isOffline` pill (driven by `ConnectivityMonitor`) is the UI signal.
- All public methods reset `error = nil` first, guard `Task.isCancelled`, and route failures through `setError(from:)` (except `consume` 409 and `fetchHistory`, see below).

`isAuthFailure(_:)` = HTTP 401/403. `isTransientProvisionError(_:)` = `.transport`/`.offline`, HTTP 429 or 5xx.

## Scoped CRUD + Consume

All item calls are pantry-scoped (`createScoped`, `createManualScoped`, `updateScoped`, `deleteScoped`, `consume`, `history`, `exportScoped`). Online path appends/replaces/removes locally and re-sorts by expiration date. `update` re-sorts (unlike the old single-pantry version). `delete` also clears `history[id]` and `archivedIDs`.

`consume(item:delta:reason:)` uses server-side atomic `POST consume`:

- `quantity <= 0` → remove from `items`, insert into `archivedIDs`.
- Else replace in place and drop cached `history[id]` (reloaded on next open).
- HTTP 409 → user-facing `"Quantità insufficiente per <name>."`; other failures via `setError(from:)`.
- `decrementQuantity(for:)` is `consume(delta: 1)`.

`fetchHistory(itemId:)` is non-critical: 401/403/404 and `.notFound` only log (`os.Logger`, category `"store"`, no sensitive data / CWE-532: no `print` on network paths) and default missing entries to `[]` — never a banner.

`exportMarkdown()` fetches `GET` export with `Accept: text/markdown` into `exportedMarkdown` for the share sheet.

## Optimistic Outbox (Offline)

When `isOffline` (or a request fails with classified `.offline` mid-flight), every mutation applies locally first, persists the snapshot, enqueues, and returns — no banner (see [iOS Offline Outbox](../concepts/ios-offline-outbox.md)):

- `enqueueLocalCreate` — allocates a negative temp-id via `outbox.nextTempId()` (`-1, -2, …`, monotonic counter persisted in the same JSON so restarts never reuse IDs), appends a visible `InventoryItem` with that ID (including `source`/`productType` plus `offTags`/`storageLocation`), sorts, `cache.save`, enqueues `.create` with `tempId` and the same fields. `add` threads `source`/`productType` through both the online `createScoped` path and the offline enqueue path.
- `enqueueLocalConsume` — decrements locally (or archives to zero), clears history, enqueues `.consume`.
- `enqueueLocalUpdate` — PATCH-style merge (`nil` = untouched) via `InventoryItem.merging`, re-sorts, enqueues `.update`.
- `enqueueLocalDelete` — removes locally + history/archived cleanup, enqueues `.delete`.

Each enqueue calls `triggerReplayIfOnline()` (covers the "classified offline but path still satisfied" case where no connectivity flip will arrive).

## replayOutbox: FIFO Last-Write-Wins

`replayOutbox()` drains [`outbox.entries`](../concepts/ios-offline-outbox.md) in FIFO order on the entry's own `pantryId` (not the current selection — the user may have switched pantries mid-queue):

- Success → `remove(id:)`; for `.create`, `remapTempId(tempId → serverId)` rewrites later entries referencing the temp-id (e.g. consume-on-offline-created-item), then continue. Create replay re-sends `source`/`productType` (plus `offTags`/`storageLocation`) via `createScoped`; optimistic `InventoryItem.replacing`/`merging` preserve `source`/`productType` so snapshots keep them.
- `OutboxStore.decision(for:)` → `.drop` (server wins: `.notFound`, HTTP 404/409 and other 4xx except 401/403/408/429, `.decoding`) logs and discards; `.stop` (HTTP 401/403/408/429, `.transport`, `.offline`, `.invalidURL`, 5xx) halts and retries on the next online event. Unknown `catch` also halts.
- Never sets `store.error` (state is already reflected in the UI; a banner would mislead). After processing anything, reconciles via `refresh()` — or `fetchPantries()` when `pantries` is empty (cold-start offline gate).
- Single-flight via `isReplayingOutbox` + `replayRequested` coalescing (one extra pass, only if still online).

`OutboxStore` I/O is best-effort atomic JSON; missing/corrupt files reset to empty (corrupt removed). It lives in Application Support (never Caches — the queue is the only copy of unsynced mutations). `LocalInventoryCache` lives in Caches (regenerable, system-purgeable).

Online recovery is driven by `startOnlineWatch()` (`withObservationTracking` on `connectivity.isOnline`, self re-arming, `weak self`): on flip to online, `fetchPantries()` if the list is empty (cold-start offline), then `replayOutbox()` if the queue is non-empty.

## Provisioning (Single-Flight)

`fetchPantries()` on empty list + `isAuthFailure` (401/403), or on empty list at all, delegates to `ensureProvisionedThenResync()`:

- Guard `isProvisioning` (single-flight: one `POST /pantries` per token) and `provisionAttemptedToken == PantryToken.value` (sticky per-token: no fake pantries, state reflects absence).
- Creates `"Dispensa"`, re-lists, selects first if needed, then `refresh()`.
- On failure: transient errors (`isTransientProvisionError`) clear `provisionAttemptedToken` so the next fetch retries; `.offline` stays silent (pill); real errors go to the banner. Never fabricates a pantry (B2).

## Sorting Behavior

Ascending `expirationDate`, `nil` last (`.distantFuture`). Applied after `refresh`, `add`/`addManual`, `update`, and all optimistic enqueues. `refresh` replaces the array wholesale.

## Threading Guarantee

`InventoryStore` and `APIClient` are `@MainActor`; `ConnectivityMonitor.start()` and the online watch run on the main actor. No `DispatchQueue.main.async` wrappers needed. `OutboxStore` / `LocalInventoryCache` are plain value types with injectable `directory` for tests.
