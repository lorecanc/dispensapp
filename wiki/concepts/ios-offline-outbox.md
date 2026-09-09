---
title: "iOS Offline Outbox"
description: "OutboxStore FIFO queue, LocalInventoryCache snapshots, connectivity gating, and offline replay for the Inventario iOS app"
category: "concepts"
source_files:
  - "ios/Inventario/State/OutboxStore.swift"
  - "ios/Inventario/State/LocalInventoryCache.swift"
  - "ios/Inventario/State/InventoryStore.swift"
  - "ios/Inventario/Networking/ConnectivityMonitor.swift"
  - "ios/Inventario/Networking/APIError.swift"
  - "ios/Inventario/Components/ErrorBanner.swift"
created: "2026-09-05"
last_updated: "2026-09-09"
---

# iOS Offline Outbox

## Purpose

The iOS app stays usable without connectivity: mutations made offline are applied optimistically to the UI, persisted to a FIFO outbox queue, and replayed last-write-wins when the network returns. A per-pantry disk snapshot provides instant cold-start with possibly stale data, while [`ConnectivityMonitor`](../concepts/ios-networking.md) drives offline gating and the `OfflinePill` indicator.

## OutboxStore

`OutboxStore` (`ios/Inventario/State/OutboxStore.swift`) is a pure, testable value type with no network or MainActor dependencies. Queue persisted as JSON (`outbox.json`) under `InventarioOutbox` in **Application Support** — never `Caches`, since the queue is the only copy of unsynced mutations and a purgeable directory would lose them silently. Writes are `.atomic` and best-effort: disk failure never breaks the data flow. Missing or corrupt file → empty queue (corrupt file is removed). Dates use `secondsSince1970`.

### Mutations

Four cases (`Mutation`, `Codable + Equatable`):

- `create(Create)` — add/addManual; `barcode == nil` means manual create; carries `barcode`, `name`, `brand`, `expirationDate`, `category`, `imageURL`, `quantity`, `tempId` (negative local id), plus additive `offTags`, `storageLocation`, `source`, `productType`, `pnnsGroup` (missing keys on old disk entries decode as `nil`).
- `consume(Consume)` — `itemId`, `delta`, `reason` (see [Inventory Consume & History](../concepts/inventory-consume-history.md)).
- `update(Update)` — PATCH semantics: `nil` fields are untouched (same as `APIClient.updateScoped`).
- `delete(Delete)` — `itemId`.

Each queued `Entry` (`Identifiable`, `Codable`) holds `id: UUID`, `createdAt`, `pantryId` (replay uses this id, not the currently selected pantry — the user may switch pantries between mutation and sync), and `mutation`.

### Temp-id allocation and remap

- `nextTempId()` allocates the next negative id (-1, -2, …) from a persisted monotonic counter, saved immediately so an app restart never reissues an id.
- Offline creates insert an `InventoryItem` with the temp id into the visible list right away (sorted, snapshot saved).
- `remapTempId(_:to:)` rewrites later queue entries referencing the temp id (e.g. consume on an offline-created item) with the server id after a successful create replay. The create entry itself is already removed by the caller.

### ReplayDecision

Pure static policy mapping `APIError` to queue behavior:

| Error | Decision | Rationale |
|-------|----------|-----------|
| `.notFound`, HTTP 404/409 and other 4xx except 401/403/408/429, `.decoding` | `drop` | Server state wins; the request would never succeed; reconciliation via `refresh()` overrides the local entry |
| HTTP 401/403 (auth), 408/429 (transient), `.transport`, `.offline`, `.invalidURL`, 5xx / other | `stop` | Auth needs re-login/permission refresh, transient needs retry: halt replay, keep the entry, retry on the next online event |

## Replay in InventoryStore

`InventoryStore` owns `outbox: OutboxStore` and `cache: LocalInventoryCache` plus `connectivity: ConnectivityMonitor` (see [iOS State Management](../concepts/ios-state-management.md) for store ownership and replay orchestration):

- Every mutating action (`add`, `addManual`, `update`, `delete`, `consume`) first checks `isOffline` (`!connectivity.isOnline`); if offline it applies the change optimistically and enqueues. If online but the request throws a `.offline`-classified error mid-flight, it falls back to the same enqueue path — no error banner.
- `replayOutbox()` processes `outbox.entries.first` in FIFO order: success → remove entry (+ remap temp-id for creates); `drop` → discard; `stop` → halt, retry later. Create replay re-sends `source`/`productType`/`pnnsGroup` (plus `offTags`/`storageLocation`) via `createScoped`. Reentrancy is coalesced (`isReplayingOutbox` + `replayRequested` triggers one extra pass). It never sets `store.error` — state is already reflected in the UI, a banner would mislead; after real work it calls `refresh()` to reconcile with the server.
- Triggering: `triggerReplayIfOnline()` covers the race where classification says offline but the path is still satisfied; `startOnlineWatch()` uses `withObservationTracking` on `connectivity.isOnline`, re-arming on every change so no online transition is lost. On flip to online with empty pantries (offline cold-start), it runs `fetchPantries()` first because `refresh()` is inert without verified pantries.

## LocalInventoryCache

`LocalInventoryCache` (`ios/Inventario/State/LocalInventoryCache.swift`) stores one JSON snapshot per pantry (`pantry-{id}.json`) under `InventarioSnapshots` in **Caches** — content is regenerable from the server, so system eviction is harmless. Pure value type, injectable `directory` for tests, best-effort I/O.

- `save(_:pantryId:savedAt:)` replaces the snapshot; `load(pantryId:)` returns `nil` on missing/corrupt/mismatched-pantry file (corrupt removed); `remove(pantryId:)` clears ghost data when a pantry is deleted.
- `refresh()` loads the snapshot into `items` immediately when the in-memory list is empty (stale-acceptable cold-start), then hits the network; on success it re-sorts by expiration and re-saves the snapshot.
- Every optimistic offline mutation also re-saves the snapshot, so the queued state survives restarts.

## Connectivity and offline UI

- `ConnectivityMonitor` — `@Observable` `@MainActor` wrapper over `NWPathMonitor` on a dedicated utility queue; publishes `isOnline`; `pathUpdateHandler` hops to MainActor. Initial value reflects `currentPath.status`; `update(isOnline:)` is a pure seam for tests/previews.
- `.offline` classification (`InventoryStore.classify`): `APIError.transport` wrapping a `URLError` with code in `{notConnectedToInternet, timedOut, cannotConnectToHost, cannotFindHost, networkConnectionLost, dataNotAllowed}` is remapped to `APIError.offline` ("Nessuna connessione internet."). `APIError` itself is `Equatable` (`.offline == .offline`; `.transport`/`.decoding` never equal).
- UI contract: `setError(from:)` drops `.offline` silently — the only offline signal is `isOffline` state rendered as `OfflinePill` ("Offline — dati non aggiornati", `wifi.slash`, capsule style) in `InventoryListView`. Real errors go to auto-dismissing `BannerView(.error)`; `OfflinePill` never uses the banner path.

## Gotchas

- Outbox must stay in Application Support; moving it to Caches risks silent mutation loss on system purge.
- Replay uses each entry's own `pantryId` — never the current selection.
- `OutboxStore.decision`: drop on 404/409/other 4xx and decode; stop on 401/403/408/429, transport/offline, and 5xx. A 409 on consume (insufficient quantity) during live use still surfaces a banner, but during replay it drops in favor of server state.
- No request dedup anywhere: debounce rapid double-taps in UI/store.
- Snapshot staleness is by design (cold-start); `refresh()` + post-replay `refresh()` are the reconciliation points.
