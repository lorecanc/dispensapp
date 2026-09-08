---
title: "Pantries API"
description: "Pantry lifecycle, invite creation/acceptance, and member management endpoints"
category: "api"
source_files:
  - "backend/routes/pantries.py"
  - "backend/main.py"
created: "2026-09-05"
last_updated: "2026-09-06"
---

# Pantries API

## Endpoints

All routes require the `X-Pantry-Token` header (UUID v4) via `get_pantry_context` or `get_current_pantry` (see [Pantry Sharing](../concepts/pantry-sharing.md)). Missing or malformed header returns `401`; unknown pantry returns `404`; valid token that is not owner/member returns `403` (intentional, not anti-enumeration). Owner-only actions (delete pantry, create invites, remove members) return `403` for non-owners. Invite tokens are never logged. Request/response shapes are defined in [Backend Schemas](../modules/backend-schemas.md). Validation (`422`) bodies use the uniform `{"detail": str, "message": str}` shape from `validation_exception_handler` in `backend/main.py` for iOS `[String: String]` compatibility.

### GET /api/pantries

**Description**: List pantries where the caller token is owner (`owner_token`) or member (`PantryMember.member_token`), ordered by id ascending.

**Request**: Header `X-Pantry-Token`. No body.

**Response**: `200` `list[PantryOut]`. `401` on missing/malformed header.

**Source**: `backend/routes/pantries.py:30-52`

### POST /api/pantries

**Description**: Create a pantry named by `PantryCreate.name` (stripped, 1-100 chars) and register the caller as `owner` member. Idempotent: an existing pantry with the same `name + owner_token` is returned with `200` instead of `201`; an `IntegrityError` retry covers concurrent double-POST.

**Request**: Header `X-Pantry-Token`. Body `PantryCreate` (`name`).

**Response**: `201` `PantryOut` on create; `200` `PantryOut` on idempotent reuse. `422` on empty/invalid name. `500` on persistence failure.

**Source**: `backend/routes/pantries.py:55-102`

### GET /api/pantries/{pantry_id}

**Description**: Return a single pantry for members only (`get_current_pantry`).

**Request**: Path `pantry_id: int`. Header `X-Pantry-Token`.

**Response**: `200` `PantryOut`. `401` on missing/malformed header. `404` `{"detail": "Pantry non trovata"}` when the pantry does not exist. `403` `{"detail": "Non membro della pantry"}` for non-members.

**Source**: `backend/routes/pantries.py:105-112`

### DELETE /api/pantries/{pantry_id}

**Description**: Delete a pantry with an explicit 6-table cascade. Owner only via `_is_owner`. Deletes child rows before `db.delete(pantry)` in order `ShoppingListItem` → `ShoppingList` → `InventoryItem` → `ConsumptionEvent` → `Invite` → `PantryMember` → `Pantry` (all with `synchronize_session=False` in a single transaction). Explicit deletes are required because SQLite has no `PRAGMA foreign_keys=ON`, so DB-level `ondelete=CASCADE` is inert; previously orphans survived delete and broke recreate via rowid reuse. Verified by `backend/tests/test_pantry_delete_cleanup.py` (zero orphans, recreate same name returns `201`).

**Request**: Path `pantry_id: int`. Header `X-Pantry-Token`.

**Response**: `204` empty body. `403` `{"detail": "Solo l'owner può eliminare la pantry"}` for non-owners. `404` when the pantry does not exist. `500` on persistence failure.

**Source**: `backend/routes/pantries.py:123-169`

### POST /api/pantries/{pantry_id}/invites

**Description**: Create a pending invite (`secrets.token_urlsafe(32)`, `created_by_token` = caller, 7-day `expires_at`; created from the [Invite Members Sheet](../components/ios-invite-members-sheet.md)). Owner only. The optional `InviteCreate.token` body field is ignored here; the server always generates the token.

**Request**: Path `pantry_id: int`. Header `X-Pantry-Token`. Optional body `InviteCreate` (ignored).

**Response**: `201` `InviteOut` (`token`, `status="pending"`, `expires_at`). `403` `{"detail": "Solo l'owner può creare inviti"}` for non-owners. `500` on persistence failure.

**Source**: `backend/routes/pantries.py:139-168`

### POST /api/invites/accept

**Description**: Accept an invite via body token. Atomically flips `pending` to `accepted` (`UPDATE ... WHERE status == "pending" AND expires_at > now`), records `accepted_by_token`, and grants the `editor` role (no-op if already a member). Only one concurrent accept wins; losers see `404`.

**Request**: Header `X-Pantry-Token`. Body `InviteCreate` (`token` required).

**Response**: `200` `InviteOut` (`status="accepted"`). `422` `{"detail": "token mancante"}` when the body token is absent. `404` `{"detail": "Invito non trovato"}` for unknown/consumed/expired invites. `500` on persistence failure.

**Source**: `backend/routes/pantries.py:224-232`

### POST /api/invites/{token}/accept

**Description**: Legacy path-param accept form. When both forms are present, `body.token` wins over the path `token`. Same atomic claim semantics as the body form.

**Request**: Path `token: str`. Header `X-Pantry-Token`. Optional body `InviteCreate` (`token` overrides path when present).

**Response**: `200` `InviteOut`. `404` `{"detail": "Invito non trovato"}` for unknown/consumed/expired invites. `500` on persistence failure.

**Source**: `backend/routes/pantries.py:235-244`

### GET /api/pantries/{pantry_id}/members

**Description**: List members of a pantry ordered by `joined_at` ascending. Any member may read.

**Request**: Path `pantry_id: int`. Header `X-Pantry-Token`.

**Response**: `200` `list[MemberOut]` (`pantry_id`, `role`, `joined_at`; no actor token exposed). `403` for non-members. `404` when the pantry does not exist.

**Source**: `backend/routes/pantries.py:247-259`

### DELETE /api/pantries/{pantry_id}/members/{member_token}

**Description**: Remove a member. Owner only; the owner row can never be removed (self-removal and owner-role removal both return `403`).

**Request**: Path `pantry_id: int`, `member_token: str`. Header `X-Pantry-Token`.

**Response**: `204` empty body. `403` `{"detail": "Solo l'owner può rimuovere membri"}` for non-owners, or `{"detail": "L'owner non può rimuovere se stesso"}` when targeting the owner. `404` `{"detail": "Membro non trovato"}` for unknown members. `500` on persistence failure.

**Source**: `backend/routes/pantries.py:262-302`
