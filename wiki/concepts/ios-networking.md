---
title: "iOS Networking"
description: "Pantry-scoped HTTP client, Keychain token auth, and connectivity for the Inventario iOS app"
category: "concepts"
source_files:
  - "ios/Inventario/Networking/APIClient.swift"
  - "ios/Inventario/Networking/APIConfig.swift"
  - "ios/Inventario/Networking/APIError.swift"
  - "ios/Inventario/Networking/PantryToken.swift"
  - "ios/Inventario/Networking/ConnectivityMonitor.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# iOS Networking

## Purpose

The iOS networking layer is a pantry-scoped, type-safe HTTP client for the backend API (see [Pantry Sharing](../concepts/pantry-sharing.md)). Every `/api/*` request carries per-install `X-Pantry-Token` auth (Keychain-backed), targets pantry-nested routes (`/api/pantries/{id}/...`), and funnels through one shared `Sendable` `APIClient`. `ConnectivityMonitor` provides reactive online/offline state; `APIError` maps transport, HTTP, decoding, and offline failures to Italian user-facing messages.

## Architecture

`APIClient` (shared singleton, `Sendable`, **not** MainActor-isolated) runs requests off the main thread; callers hop to MainActor only when assigning results to UI state. Shared `JSONDecoder` (`.inventoryDate` strategy) and `JSONEncoder`/`DateFormatter` are read-only after setup.

- `APIClient` — all endpoints; injects auth via `decorated(_:)`; central `perform(_:)` + `sendInventory` / `deleteItem` / `fetchMarkdown` helpers.
- `PantryToken` — `X-Pantry-Token` value in Keychain (`Inventario` / `pantryToken`, `accessibleAfterFirstUnlockThisDeviceOnly`); one-time legacy `UserDefaults` migration; per-install `UUID` generation; no zero-UUID fallback; never logged.
- `APIConfig` — server base URL in `UserDefaults` (`apiBaseURL`, default `http://127.0.0.1:8000`); validated optional `baseURL` (nil on malformed input, throws `APIError.invalidURL`); `isValidURL` + `fallbackURL` for display.
- `APIError` — `invalidURL / transport / decoding / http / notFound / offline` with Italian descriptions; 401/403 get pantry-specific messages.
- `ConnectivityMonitor` — `@Observable` `@MainActor` wrapper over `NWPathMonitor`; publishes `isOnline`; injectable monitor for tests.

No request deduplication/inflight coalescing: the previous dedup layer (~120 lines) was removed; concurrent identical calls each hit the network.

## Auth: PantryToken + decorated(_:)

`PantryToken.value` reads Keychain first; if empty, migrates the legacy `UserDefaults("pantryToken")` value once (then deletes the defaults key); otherwise generates and stores `UUID().uuidString`. `PantryToken.pantryToken` is a spec alias for `value`; `reset()` clears Keychain + defaults (tests/debug).

`APIClient.decorated(_:)` attaches the header to every request whose URL path contains `/api/` when the header is not already set. Invite/member tokens are never printed to logs.

Note: the client does not auto-provision a pantry on first 401/403 — the backend must provision the pantry for the presented token.

## APIClient Endpoints

All methods are `async throws`. Bodies use `JSONSerialization` with nil-values filtered out; dates serialize as `yyyy-MM-dd` (UTC, `en_US_POSIX`).

### Scan / contribute / suggestions / categories

| Method | HTTP | Path |
|--------|------|------|
| `scan(barcode:)` | POST | `/api/scan` (10s timeout) |
| `contribute(code:productName:brands:quantity:categories:labels:genericName:comment:appUUID:lang:consent:)` | POST | `/api/scan/contribute` (15s timeout) |
| `uploadPhoto(code:imageData:filename:mimeType:imagefield:consent:)` | POST multipart | `/api/scan/contribute/photo` (fail-fast 413 over 5 MB) |
| `fetchSuggestions(q:)` | GET | `/api/suggestions?q=` (see [Suggestions](../api/suggestions.md)) |
| `fetchCategories()` | GET | `/api/categories` → `CategoriesResponse` (registry of categories, shelf life, compartments) |

### Pantries / invites / members

| Method | HTTP | Path |
|--------|------|------|
| `listPantries()` | GET | `/api/pantries` (see [Pantries API](../api/pantries.md)) → `[Pantry]` |
| `createPantry(name:)` | POST | `/api/pantries` → `Pantry` |
| `deletePantry(id:)` | DELETE | `/api/pantries/{id}` (200/204) |
| `acceptInvite(token:)` | POST | `/api/invites/accept` + `{token}` body; falls back to legacy `/api/invites/{token}/accept` on 404 |
| `createInvite(pantryId:)` | POST | `/api/pantries/{id}/invites` → `Invite` (owner-only server-side) |
| `listMembers(pantryId:)` | GET | `/api/pantries/{id}/members` → `[PantryMember]` |
| `removeMember(pantryId:memberToken:)` | DELETE | `/api/pantries/{id}/members/{token}` (200/204) |

### Pantry-scoped inventory

| Method | HTTP | Path |
|--------|------|------|
| `listScoped(pantryId:)` | GET | `/api/pantries/{id}/inventory` |
| `createScoped(pantryId:barcode:name:brand:expirationDate:category:imageURL:quantity:)` | POST | `/api/pantries/{id}/inventory` |
| `createManualScoped(pantryId:name:brand:expirationDate:category:quantity:)` | POST | `/api/pantries/{id}/inventory/manual` |
| `updateScoped(pantryId:id:name:brand:expirationDate:category:quantity:)` | PATCH | `/api/pantries/{id}/inventory/{item}` |
| `deleteScoped(pantryId:id:)` | DELETE | `/api/pantries/{id}/inventory/{item}` (200/204) |
| `consume(pantryId:itemId:delta:reason:)` | POST | `/api/pantries/{id}/inventory/{item}/consume` (atomic server-side; 409 on insufficient quantity; see [Inventory Consume & History](../concepts/inventory-consume-history.md)) |
| `history(pantryId:itemId:limit:)` | GET | `/api/pantries/{id}/inventory/{item}/history?limit=` (default 50) → `[ConsumptionEvent]` |
| `exportScoped(pantryId:)` | GET | `/api/pantries/{id}/inventory/export` (markdown) |

Legacy unscoped `list / create / createManual / update / delete / exportMarkdown` variants remain for backwards compatibility.

### Shopping lists (pantry-scoped)

| Method | HTTP | Path |
|--------|------|------|
| `listShoppingLists(pantryId:)` | GET | `/api/pantries/{id}/shopping-lists` |
| `createShoppingList(pantryId:name:)` | POST | `/api/pantries/{id}/shopping-lists` |
| `getShoppingList(pantryId:listId:)` | GET | `/api/pantries/{id}/shopping-lists/{list}` |
| `addShoppingItem(pantryId:listId:name:quantity:compartment:)` | POST | `.../shopping-lists/{list}/items` |
| `toggleShoppingItem(pantryId:listId:itemId:checked:)` | PATCH | `.../items/{item}` |
| `deleteShoppingItem(pantryId:listId:itemId:)` | DELETE | `.../items/{item}` (200/204) |
| `deleteShoppingList(pantryId:listId:)` | DELETE | `.../shopping-lists/{list}` (200/204) |
| `exportShoppingMarkdown(pantryId:listId:)` | GET | `.../shopping-lists/{list}/export` (markdown) |

## Request/Response Cycle

`perform(_:)` (used by all JSON GET/POST/PATCH paths):

1. `decorated(_:)` injects `X-Pantry-Token`.
2. `session.data(for:)`; transport throw → `APIError.transport`.
3. Non-`HTTPURLResponse` → `APIError.transport(.badServerResponse)`.
4. Non-2xx → `404` maps to `APIError.notFound`; else decode `detail`/`message` from body → `APIError.http(status:message:)`.
5. Returns raw `Data`; caller decodes with the shared decoder.

Specialized helpers bypass `perform(_:)` but apply `decorated(_:)` themselves:

- `sendInventory(method:path:body:)` — JSON POST/PATCH returning one `InventoryItem`; backs `createScoped / createManualScoped / updateScoped` with bodies built by `inventoryBody(...)` (nil fields omitted).
- `deleteItem(at:)` — DELETE expecting 200/204; backs `deleteScoped`; `deletePantry` / `removeMember` / `deleteShopping*` duplicate the pattern inline.
- `fetchMarkdown(from:)` — GET with `Accept: text/markdown`, raw UTF-8 → `String` (failure → `APIError.decoding`); backs `exportScoped`.

## APIError

`enum APIError: LocalizedError, Equatable`. Equality: `.transport` / `.decoding` never equal (wrapped errors not `Equatable`); `.http` compares status only.

| Case | When | Italian message |
|------|------|-----------------|
| `invalidURL` | `APIConfig.baseURL` nil | "URL non valido." |
| `transport` | `URLError`, timeout, bad response | `NSURLErrorNotConnectedToInternet` → "Nessuna connessione internet."; else "Errore di rete: …" |
| `decoding` | JSON/markdown decode failure | "Errore durante l'elaborazione dei dati: …" |
| `http(401)` | Missing/invalid pantry token | "Token mancante … (401)." |
| `http(403)` | Token not authorized for pantry | "Accesso negato alla dispensa (403) …" |
| `http(other)` | Other non-2xx | "Errore del server ({status}): {message}" |
| `notFound` | HTTP 404 | "Risorsa non trovata." |
| `offline` | Explicit offline path (store-level mapping of transport-no-connection) | "Nessuna connessione internet." |

## ConnectivityMonitor

```swift
@Observable @MainActor final class ConnectivityMonitor {
    private(set) var isOnline: Bool
    func start(); func stop(); func update(isOnline:)
}
```

`NWPathMonitor` on a dedicated utility queue; `pathUpdateHandler` hops to MainActor to publish. `update(isOnline:)` is a pure seam for tests. Initial value reflects `monitor.currentPath.status`. Consumed by the store layer for offline gating; transport-level no-connection errors surface as `.transport` with the offline message, while explicit offline state maps to `.offline`.

## Date Handling

- Outgoing: static `DateFormatter` (`yyyy-MM-dd`, `en_US_POSIX`, UTC) applied manually in `inventoryBody`; scan/contribute encode via `JSONEncoder`.
- Incoming: shared `JSONDecoder.dateDecodingStrategy = .inventoryDate`, tried in order: ISO 8601 with fractional seconds → ISO 8601 plain → SQLite-style `yyyy-MM-dd'T'HH:mm:ss.SSSSSS` (UTC) → date-only `yyyy-MM-dd`; else `dataCorruptedError`.
- File-scope models: `Pantry`, `Invite`, `PantryMember`, `ConsumptionEvent`, `CategoriesResponse` (snake_case keys).

## Gotchas

- Every `/api/*` call needs the Keychain token — missing header yields 401; wrong pantry yields 403. Check `PantryToken.value` before blaming routes.
- `APIConfig.baseURL` is optional now (no force-unwrap): validate `isValidURL` and surface `APIError.invalidURL` for bad Settings input.
- No dedup: rapid double-taps (e.g. consume) send two requests; debounce in UI/store, not in the client.
- `consume` 409 means insufficient quantity — refresh the item rather than retrying blindly.
- Never log `PantryToken.value` or invite/member tokens.
