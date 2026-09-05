---
title: "Backend Configuration"
description: "Configuration values for the Inventario FastAPI backend"
category: "config"
source_files:
  - "backend/config.py"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# Backend Configuration

## Overview

Environment-driven configuration for the FastAPI backend. All values are defined in [`backend/config.py`](../modules/backend-config.md) and imported directly by backend modules. Copy `.env.example` to `.env` for local development; never commit real credentials. See the module reference for code-level constant and helper details.

## Configuration Table

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `DATABASE_URL` | `str` | `sqlite:///<repo>/inventory.db` | [SQLite](../modules/backend-database.md) connection string. Default is an absolute path resolved relative to `backend/config.py`, not CWD. Override via env. |
| `OFF_BASE_URL` | `str` | `"https://world.openfoodfacts.org/api/v0/product"` | Read-only base URL for the [Open Food Facts API](../concepts/off-integration.md). Product code appended as `{base}/{barcode}.json`. Not env-configurable. |
| `OFF_WRITE_ENABLED` | `bool` | `false` | Master write gate for `POST /api/scan/contribute` and `/photo` (see [Contribute](../api/contribute.md)). Truthy values: `1/true/yes/on`. Effective `true` only when credentials are set AND the write base URL passes host/scheme validation. See [OFF integration](../concepts/off-integration.md) and [scan API](../api/scan.md). |
| `OFF_WRITE_BASE_URL` | `str` | `"https://world.openfoodfacts.net/cgi"` | OFF write endpoint (staging `.net` by default; production `.org` only via explicit env). Host outside `openfoodfacts.org`/`.net` or non-https scheme falls back to staging default with a warning (`http` allowed only for `localhost`/`127.0.0.1`). |
| `OFF_USER` | `str` | `""` | Personal OFF account for writes. Never logged. On staging use a staging-created account, not production. |
| `OFF_PASS` | `str` | `""` | OFF password. Never logged. |
| `OFF_STAGING_BASIC_USER` | `str` | `"off"` | HTTP Basic user for the protected staging host `world.openfoodfacts.net`. Sent only on staging hosts via `off_basic_auth()`. |
| `OFF_STAGING_BASIC_PASS` | `str` | `"off"` | HTTP Basic password for staging (`off:off` default). |
| `OFF_APP_NAME` | `str` | `"DispensApp"` | Client name sent in `comment`, `app_name`, and `User-Agent` via `off_user_agent()`. |
| `OFF_APP_VERSION` | `str` | `"0.1.0"` | Client version sent in `comment`, `app_version`, and `User-Agent`. |
| `OFF_CONTACT_EMAIL` | `str` | `""` | Optional contact appended to the user agent as `Name/Version (email)`. |
| `CORS_ORIGINS` | `list[str]` | 6 localhost origins + env extras | Restricted allowlist for `CORSMiddleware` (no wildcard). Defaults: `http://localhost|127.0.0.1:3000|5173|8000`. Extra origins via comma-separated `CORS_ORIGINS` env, e.g. `CORS_ORIGINS="https://app.example.com,https://admin.example.com"`. |
| `EXPIRING_SOON_DAYS` | `int` | `3` | Days within which an item is "[expiring soon](../concepts/item-status.md)". Not env-configurable. |
| `ESTIMATED_NOTE` | `str` | `"⚠️ Scadenza stimata, potrebbe scadere prima"` | Warning appended to markdown export rows with estimated dates (Italian: "Estimated expiry, may expire earlier"). Not env-configurable. |
| `DEFAULT_SHELF_LIFE` | `dict[str, int]` | See table below | Category slug -> shelf-life days. Used to [estimate](../concepts/expiration-estimation.md) missing expiration dates. Not env-configurable. |

## DEFAULT_SHELF_LIFE

Default shelf life values in days, keyed by canonical category:

| Category | Days |
|----------|------|
| `yogurts` | 14 |
| `fresh-milk` | 7 |
| `pasta` | 365 |
| `canned-vegetables` | 730 |
| `rice` | 365 |
| `cheeses` | 30 |
| `eggs` | 21 |
| `fresh-fruits` | 7 |
| `fresh-vegetables` | 7 |
| `frozen-foods` | 90 |
| `legumes` | 365 |
| `uht-milk` | 90 |
| `cold-cuts` | 14 |
| `meat` | 4 |
| `fish` | 2 |
| `canned-fish` | 730 |
| `bread-bakery` | 5 |
| `flours` | 180 |
| `sauces-condiments` | 365 |
| `oils-vinegars` | 540 |
| `sweets-snacks` | 180 |
| `beverages-water` | 365 |
| `beverages-juices` | 30 |
| `coffee-tea` | 365 |
| `alcoholic-beverages` | 1095 |
| `cleaning-hygiene` | 730 |
| `default` | 30 |

The `default` key is the fallback for unmatched categories after `normalize_category()` (alias + OFF-tag mapping).

## `.env.example`

```env
OFF_WRITE_ENABLED=false
OFF_WRITE_BASE_URL=https://world.openfoodfacts.net/cgi
OFF_USER=
OFF_PASS=
OFF_STAGING_BASIC_USER=off
OFF_STAGING_BASIC_PASS=off
OFF_APP_NAME=DispensApp
OFF_APP_VERSION=0.1.0
OFF_CONTACT_EMAIL=
```

`DATABASE_URL` and `CORS_ORIGINS` are also read from the environment but intentionally left out of the example defaults (database falls back to the repo-local `inventory.db`; CORS falls back to localhost dev origins).

## Usage

Modules import these values directly from `config`:

```python
from config import DATABASE_URL, OFF_BASE_URL, EXPIRING_SOON_DAYS
```

- `DATABASE_URL` is consumed by the SQLAlchemy engine in the database initialization module.
- `OFF_BASE_URL` is used by the barcode lookup service when querying Open Food Facts.
- `OFF_WRITE_ENABLED`, `off_basic_auth()`, and `off_user_agent()` gate and authenticate the contribute/photo write path.
- `CORS_ORIGINS` is passed to FastAPI's `CORSMiddleware`.
- `EXPIRING_SOON_DAYS` is used by inventory queries that filter for items near their expiration date.
- `ESTIMATED_NOTE` is appended during markdown export generation for rows with estimated dates.
- `DEFAULT_SHELF_LIFE` is used when creating or updating inventory items that lack a concrete expiration date.
