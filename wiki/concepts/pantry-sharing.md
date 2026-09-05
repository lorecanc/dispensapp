---
title: "Pantry Sharing"
description: "Multi-pantry share model, X-Pantry-Token auth, invite deep-links, and idempotent provisioning"
category: "concepts"
source_files:
  - "backend/dependencies/pantry.py"
  - "backend/routes/pantries.py"
  - "ios/Inventario/Networking/PantryToken.swift"
  - "ios/Inventario/InventarioApp.swift"
  - "ios/Inventario/Features/Inventory/InviteMembersSheet.swift"
created: "2026-09-05"
last_updated: "2026-09-05"
---

# Pantry Sharing

## Purpose

Multi-pantry collaboration keyed by per-install `X-Pantry-Token`. Owners create `inventario://` invite links (7-day expiry); joiners claim them via `acceptInviteToken` and gain `editor` membership. No accounts, no passwords — the Keychain token is the identity. Route details: [Backend Routes — Pantries](../modules/backend-routes-pantries.md).

## Share Model

- `Pantry.owner_token` — creator identity; owner-only ops (`DELETE /pantries/{id}`, `POST .../invites`, `DELETE .../members/{token}`) checked via `_is_owner` (owner_token match or `PantryMember.role == "owner"`).
- `PantryMember(pantry_id, member_token, role)` — `owner` row auto-created on `POST /api/pantries`; `editor` row added on invite accept (skipped if already member).
- `Invite(pantry_id, token, created_by_token, status, expires_at)` — `secrets.token_urlsafe(32)`, `pending` → `accepted`, 7-day TTL. Token shape `[A-Za-z0-9_-]{20,64}` validated client-side before accept.
- `GET /api/pantries` unions owner pantries + member pantries, ordered by id.

## Auth: X-Pantry-Token

`PantryToken` (`ios/Inventario/Networking/PantryToken.swift`) stores the token in Keychain (`Inventario` / `pantryToken`, `accessibleAfterFirstUnlockThisDeviceOnly`). First launch migrates the legacy `UserDefaults("pantryToken")` value once, otherwise generates `UUID().uuidString`. No zero-UUID / hardcoded fallbacks; tokens never logged, never in `UserDefaults` after migration.

Three backend dependencies (`backend/dependencies/pantry.py`):

| Dependency | Checks | Used by |
|------------|--------|---------|
| `get_pantry_context` | 401 missing / malformed (non-UUID) | `list/create pantries`, `accept invites` — new tokens must pass here |
| `require_known_token` | `get_pantry_context` + 401 if token owns/joins no pantry | Item/shopping routes (not pantries/invites) |
| `get_current_pantry(pantry_id)` | 401 bad header → 404 unknown pantry → 403 non-member; returns `PantryContext` (str + `.pantry` / `.token`) | All `{pantry_id}`-scoped routes |

## 401 vs 403 Semantics

- **401** — missing/malformed `X-Pantry-Token`, or valid-but-unknown token on `require_known_token` routes. Client response: single-flight provisioning (`ensureProvisionedThenResync`) when list is empty.
- **403** — known token, wrong pantry (`get_current_pantry`) or non-owner attempting owner-only op. Client surfaces "Solo l'owner può invitare/rimuovere." No auto-retry.
- **404** — pantry doesn't exist, or invite claim found no `pending` unexpired row (atomic `_claim_invite` UPDATE returns 0). Deliberately not unified 404 anti-enumeration, for iOS/test compatibility.

## Invite Flow

1. Owner taps "Crea link invito" in `InviteMembersSheet` → `store.createInvite(pantryId:)` → `POST /api/pantries/{id}/invites` → `inviteLink = "inventario://invite?token=\(token)"` with `ShareLink` / copy.
2. Joiner opens `inventario://invite?token=...` (or `inventario://invite/<token>` path form) → `InventarioApp.onOpenURL` parses via `inviteToken(from:)` (scheme + regex gate) → confirmation dialog → `store.acceptInviteToken(token)`.
3. Manual path: paste token into `InviteMembersSheet` accept section → confirm dialog → same `acceptInviteToken`.
4. `acceptInviteToken` trims, calls `POST /api/invites/accept` (+ legacy path-param fallback on 404), then `fetchPantries()` to verify and reload. Local var zeroed via `defer`; invite tokens never persisted or logged.
5. Server `_claim_invite` atomically flips one `pending` row to `accepted` (single winner on races), inserts `editor` membership, commits.

## Provisioning & Idempotency

- **Single-flight provisioning** — `InventoryStore.ensureProvisionedThenResync`: guarded by `isProvisioning` + sticky `provisionAttemptedToken`. One `POST /api/pantries` ("Dispensa") per token; transients (transport/offline/429/5xx) clear the sticky flag for retry, non-transients stay sticky. Never creates fake local pantries.
- **Idempotent create** — `POST /api/pantries` returns **201** new / **200** existing on same `name + owner_token` (SELECT-first + `IntegrityError` retry for the future UNIQUE constraint). Concurrent double-POST can still race (documented TODO).
- **Invite claim** — idempotent-safe: re-accept by an existing member skips the insert; second claim on a consumed invite yields 404 ("Link scaduto, chiedine uno nuovo").

## Gotchas

- New installs get a fresh UUID — they see an empty list until provisioned or invited; don't confuse 401 (unknown token) with 403 (wrong pantry).
- `InviteMembersSheet` member list is read-only (`MemberOut` exposes no token); removal UI is owner-note only.
- Invite error mapping: 401/403 → owner-only, 404/410 → expired link, 409 → already member.
