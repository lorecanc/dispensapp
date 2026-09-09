# Handoff — Migrazione Auth: da X-Pantry-Token a WorkOS AuthKit

> **Stato:** decisione presa, implementazione NON iniziata.
> **Data:** 2026-09-09 · **Branch:** `main` (nessun branch auth aperto)
> **Contesto discussione:** thread su open-sourcability → decisione di passare a login veri post-POC.

## 1. Decisioni già prese (non ridiscutere)

| # | Decisione | Dettaglio |
|---|-----------|-----------|
| 1 | **Repo resta open source** | Auth attuale non espone segreti: nessun hardcoded, `.env`/`*.db` in `.gitignore` e non tracciati (verificato via `git ls-files`). |
| 2 | **IdP: WorkOS AuthKit** | Metodi: **Sign in with Apple + Google OAuth + Email OTP**. Niente password proprie, niente UI login custom. |
| 3 | **Modello condivisione: identità WorkOS + membership propria** | `Pantry` + `PantryMember(user_id, role)` con chiave = WorkOS `user_id` (`user_xxx`). **NO WorkOS Organizations per-pantry** (semantica B2B, overkill per app famiglia; vedi §5). |
| 4 | **Migrazione: fresh start** | Nessun import/mapping `token → user_id`. Vecchie pantry del POC si abbandonano. Nessun periodo di doppia auth. |
| 5 | **Colonna `organization_id` riservata** | Aggiungere `organization_id Nullable` su membership fin da subito, non usata. Serve per futuro B2B (mense/condomini) senza riscritture. |

## 2. Stato attuale (punto di partenza)

**Auth odierna — bearer token anonimo per-installazione:**

- `backend/dependencies/pantry.py` — tre dependency:
  - `get_pantry_context` → 401 se header `X-Pantry-Token` mancante/malformato (non-UUID);
  - `require_known_token` → +401 se token sconosciuto (usata da inventory/shopping/scan);
  - `get_current_pantry(pantry_id)` → 401 → 404 pantry ignota → 403 non-membro, ritorna `PantryContext`.
- `backend/models.py` — `Pantry.owner_token: String(36)`, `PantryMember(pantry_id, member_token, role)`, `Invite.token = secrets.token_urlsafe(32)`, TTL 7gg, claim atomico in `_claim_invite` (`routes/pantries.py:204`).
- `ios/.../Networking/PantryToken.swift` — token = `UUID().uuidString` per-installazione in Keychain (`accessibleAfterFirstUnlockThisDeviceOnly`), migrazione legacy da UserDefaults. **È la causa del limite "no multi-device":** due device = due UUID = due identità diverse.
- Limiti noti (accettati nel POC, da chiudere con WorkOS): nessun rate-limit globale auth, `403` vs `404` permette enumerazione pantry-id (`pantry.py:139-142`), rate-limit contribute solo in-memory (`routes/contribute.py:37` → `TODO(prod)` slowapi/Redis).

**File da toccare (inventario):**

| Area | File |
|------|------|
| Modelli | `backend/models.py`, nuova migration in `backend/alembic/versions/` |
| Auth BE | `backend/dependencies/pantry.py` (da sostituire), nuovo `backend/auth/workos.py` + `backend/auth/dependencies.py` |
| Route BE | `backend/routes/pantries.py`, poi `inventory.py`, `shopping.py`, `scan.py`, `contribute.py`, `suggestions.py`, `categories.py` |
| Config | `backend/config.py`, `.env.example`, `requirements.txt` (`+ workos`, `PyJWT[crypto]`) |
| iOS | `Networking/PantryToken.swift` (da cancellare), `Networking/APIClient.swift`, `Networking/APIConfig.swift`, nuovo `Auth/AuthSession.swift`, `InventarioApp.swift` (deep-link `auth/callback`), `Info.plist` (URL scheme) |
| Deploy | `HF_DEPLOY.md` (nuovi secrets), HF Space Settings |
| Docs | `wiki/concepts/pantry-sharing.md` (da riscrivere), nuovo `SECURITY.md` |

**Segreti (tutti runtime, mai nel repo):**

| Nome | Dove vive | Note |
|------|-----------|------|
| `WORKOS_API_KEY` | HF Secrets / env locale | Solo server, MAI nel binary iOS |
| `WORKOS_CLIENT_ID` | env + binary iOS | Pubblico per design (PKCE) |
| `WORKOS_COOKIE_PASSWORD` | HF Secrets (32+ byte random) | Solo se si usano sealed-session cookie (web); per iOS Bearer non strettamente necessario |
| `DATABASE_URL` (Neon) | HF Secrets | Già così oggi |
| `OFF_USER`/`OFF_PASS` | HF Secrets | Già così oggi |

## 3. Architettura target

```
iOS (PublicClient, PKCE, solo client_id)
  │  ASWebAuthenticationSession → AuthKit (Apple/Google/Email OTP)
  │  access_token + refresh_token in Keychain
  ▼
FastAPI: Authorization: Bearer <access_token>
  │  get_current_user: verifica firma via JWKS
  │  https://api.workos.com/sso/jwks/{client_id} (cache ~5 min)
  │  valida iss/exp (+ aud solo se JWT template configurato —
  │  i session token AuthKit NON hanno aud di default)
  ▼
get_current_pantry_v2 / require_role("owner"|"editor")
  │  PantryMember(pantry_id, user_id) / Pantry.owner_user_id
  ▼
Stesse tabelle dominio (inventory, shopping, consumption_events)
```

**Mapping identità → dati (breaking, ok perché fresh start):**

| Prima (`*_token: String(36)`) | Dopo (`*_user_id: String`) |
|---|---|
| `Pantry.owner_token` | `Pantry.owner_user_id` |
| `PantryMember.member_token` (PK) | `PantryMember.user_id` (PK) |
| `Invite.created_by_token` / `accepted_by_token` | `created_by_user_id` / `accepted_by_user_id` |
| `InventoryItem.created_by_token`, `ShoppingList.created_by_token`, `ShoppingListItem.added_by_token` | `created_by_user_id` / `added_by_user_id` (o drop dove non serve) |
| **Nuovo** | `PantryMember.organization_id Nullable` (riservato, non usato) |

**Flusso inviti invariato nella UX, nuova chiave:** `inventario://invite?token=` → `POST /api/invites/accept` → `_claim_invite` atomico (già single-winner) ma inserisce `user_id` invece di `member_token`.

**Error mapping BE (da implementare in `get_current_user`):**

| Caso | HTTP | Azione client |
|------|------|---------------|
| header mancante / firma invalida / malformato | 401 `invalid_token` | logout → AuthKit |
| token scaduto valido | 401 `token_expired` | refresh silenzioso → retry singolo |
| JWKS non raggiungibile (timeout) | 503 + `Retry-After` | retry, MAI logout (non è colpa dell'utente) |

## 4. Sequenza esecutiva proposta (per il futuro)

1. **Branch `auth/workos`** — `pip install workos "PyJWT[crypto]"`, `backend/auth/workos.py` (JWKS verify + cache), 1 route pilota protetta. Test con `get_current_user` mockato.
2. **Migration Alembic breaking** — nuove colonne `*_user_id` + `organization_id Nullable`, drop colonne `*_token`. (Fresh start: nessuna migrazione dati.)
3. **Rewrite auth BE** — `backend/auth/dependencies.py` (`get_current_user`, `get_current_pantry_v2`, `require_role`); porting `pantries.py` → inventory/shopping/scan/contribute/suggestions.
4. **iOS** — SPM `workos/workos-ios`, `Auth/AuthSession.swift` (`@Observable`, PKCE + `ASWebAuthenticationSession` + state check + Keychain), `APIClient` → `Authorization: Bearer`, deep-link `inventario://auth/callback` in `Info.plist` + `InventarioApp.onOpenURL`. Cancellare `PantryToken.swift`.
5. **Chiusura** — `404` uniforme anti-enumerazione, rate-limit persistente (chiude `TODO(prod)`), `SECURITY.md`, secrets su HF, riscrittura `wiki/concepts/pantry-sharing.md`, `gitleaks` prima del push.
6. **Verifica** — `pytest`, `xcodebuild test`, test segregazione (A non legge pantry di B), test claim invito concorrente.

## 5. Perché non Organizations-per-pantry (promemoria decisione §1.3)

WorkOS Organizations modella **tenant B2B** (SSO, directory sync, seat billing, ruoli org). Applicarlo a "la dispensa di casa" trascina dentro inviti org, ruoli org e complessità di fatturazione senza benefici. Il modello `user_id + membership propria` dà già multi-device (stesso `user_id` su N device) e condivisione (invite → riga `editor`), e lascia la porta B2B aperta via `organization_id` riservato.

## 6. Questioni aperte (da decidere alla ripresa)

- [ ] Redirect URI prod esatto (dipende da URL HF Space finale) + registrazione in dashboard WorkOS.
- [ ] JWT template custom per `aud` dedicato (`https://api.<tuodominio>`) — consigliato ma opzionale al primo giro.
- [ ] `DEVELOPMENT_TEAM = 4YK6GDPC39` committato in `ios/project.yml:25` + `project.pbxproj` — rimuovere dal repo pubblico (xcconfig locale o CI secret) prima/durante il branch auth.
- [ ] `.dockerignore` oggi esclude `*.db` ma non `.env` — aggiungere.
- [ ] Access token lifetime + strategia refresh (default WorkOS vs custom).
- [ ] `MemberOut` oggi non espone identità (lista membri anonima) — con login veri decidere cosa mostrare (email mascherata? nome?).

## 7. Riferimenti

- WorkOS: `workos.com/blog/securing-a-fastapi-server-with-workos-authkit` (pattern FastAPI + sealed session), `workos.com/blog/verify-workos-access-tokens-in-your-own-api` (verifica Bearer via JWKS — **il pattern giusto per iOS**), `workos.com/blog/ios-sdk-authkit-sign-in-tutorial` + `github.com/workos/workos-ios` (PublicClient PKCE + `ASWebAuthenticationSession`), `workos.com/blog/rbac-authorization-python-apis-workos` (pattern `require_permission` → analogo a `require_role`).
- JWKS: `https://api.workos.com/sso/jwks/{client_id}` · Docs: `workos.com/docs/reference/authkit/session-tokens/jwks`, `/access-token`, `workos.com/docs/sdks/ios`.
- Repo: `HF_DEPLOY.md` (deploy), `wiki/concepts/pantry-sharing.md` (share model attuale), `backend/dependencies/pantry.py`, `backend/routes/pantries.py`, `ios/.../Networking/PantryToken.swift`.
