---
title: "Backend Configuration"
description: "Configuration values for the Inventario FastAPI backend"
category: "config"
source_files:
  - "backend/config.py"
created: "2026-06-24"
last_updated: "2026-09-09"
---

# Backend Configuration

## Overview

Environment-driven configuration for the FastAPI backend. All values are defined in [`backend/config.py`](../modules/backend-config.md) and imported directly by backend modules. Copy `.env.example` to `.env` for local development; never commit real credentials. See the module reference for code-level constant and helper details.

## Configuration Table

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `DATABASE_URL` | `str` | `sqlite:///<repo>/inventory.db` | [SQLite](../modules/backend-database.md) connection string. Default is an absolute path resolved relative to `backend/config.py`, not CWD. Override via env. |
| `OFF_V3_BASE_URL` | `str` | `"https://world.openfoodfacts.org/api/v3/product"` (via `OFF_V3_BASE_URL` env) | Universal read-only base URL for the [OFF service](../modules/backend-service-off.md) (food + twin projects via `product_type`). Only `https` with host in `world.openfoodfacts.org` / `world.openbeautyfacts.org` / `world.openpetfoodfacts.org` / `world.openproductsfacts.org`; otherwise falls back to default with a warning. See [OFF integration](../concepts/off-integration.md). |
| `OFF_PRODUCT_TYPE_DEFAULT` | `str` | `"all"` (via `OFF_PRODUCT_TYPE_DEFAULT` env) | Default `product_type` for v3 reads (`all` queries every project). |
| `OFF_V3_HOSTS` | `dict[str, str]` | `food`/`beauty`/`petfood`/`product` -> world hosts | Per-`product_type` fallback hosts used by the [OFF service](../modules/backend-service-off.md) when the first v3 `GET` fails with an explicit type. Not env-configurable. |
| `OFF_WRITE_ENABLED` | `bool` | `false` | Master write gate for `POST /api/scan/contribute` and `/photo` (see [Contribute](../api/contribute.md)). Truthy values: `1/true/yes/on`. Effective `true` only when credentials are set AND the write base URL passes host/scheme validation. See [OFF integration](../concepts/off-integration.md) and [scan API](../api/scan.md). |
| `OFF_WRITE_BASE_URL` | `str` | `"https://world.openfoodfacts.net/cgi"` | OFF write endpoint (staging `.net` by default; production `.org` only via explicit env). Host outside `openfoodfacts.org`/`.net` (incl. `openbeautyfacts.org`, `openpetfoodfacts.org`, `openproductsfacts.org` and subdomains) or non-https scheme falls back to staging default with a warning (`http` allowed only for `localhost`/`127.0.0.1`). |
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
| `animali` | 365 |
| `default` | 30 |

The `default` key is the fallback for unmatched categories after `normalize_category()` (alias + OFF-tag mapping).

## Category Mapping and Compartments

Canonical category `animali` ("Animali", shelf life 365 days, default storage `dispensa`) covers pet food. Labels and storage defaults are defined alongside `DEFAULT_SHELF_LIFE` in [`backend/config.py`](../modules/backend-config.md): `CATEGORY_LABELS` holds the Italian UI labels and `CATEGORY_STORAGE_DEFAULT` holds the per-category storage location (unknown keys fall back to `DEFAULT_STORAGE`, `"dispensa"`).

`OFF_TO_INTERNAL` normalizes Open Food Facts tags before alias resolution in `normalize_category()`. Recent additions map `cosmetic -> cleaning-hygiene`, the beauty cluster (`makeup`, `make-up`, `makeups`, `skincare`, `skin-care`, `hair-care`, `haircare`, `personal-care -> cleaning-hygiene`), and the pet-food cluster (`dog-food`, `dog-foods`, `cat-food`, `cat-foods`, `pet-food`, `pet-foods`, `petfood -> animali`).

Two reserved tag sets support future disambiguation (not yet applied by `normalize_category()`): `GENERIC_OPF` (`product`, `products`, `open-products-facts`, `openproductsfacts` — generic Open Products Facts tags meaning "no category") and `HUMAN_FOOD_ONLY` (`tuna`, `sardines`, `canned-fish`, `fish`, `meat`, `fish-meat-eggs` — human-food-only tags for human-food vs pet-food disambiguation).

Supermarket layout uses 11 walk-order aisles in `SUPER_MARKET_COMPARTMENTS` (`Ortofrutta` … `Igiene e Casa`, plus `Animali`), with `COMPARTMENT_MAP` assigning `animali -> Animali` and `cleaning-hygiene -> Igiene e Casa`.

## `.env.example`

```env
OFF_V3_BASE_URL=https://world.openfoodfacts.org/api/v3/product
OFF_PRODUCT_TYPE_DEFAULT=all
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
from config import DATABASE_URL, OFF_V3_BASE_URL, EXPIRING_SOON_DAYS
```

- `DATABASE_URL` is consumed by the SQLAlchemy engine in the database initialization module.
- `OFF_V3_BASE_URL` is used by the [OFF service](../modules/backend-service-off.md) when querying Open Food Facts (API v3, `?product_type=` from `OFF_PRODUCT_TYPE_DEFAULT`).
- `OFF_WRITE_ENABLED`, `off_basic_auth()`, and `off_user_agent()` gate and authenticate the contribute/photo write path.
- `CORS_ORIGINS` is passed to FastAPI's `CORSMiddleware`.
- `EXPIRING_SOON_DAYS` is used by inventory queries that filter for items near their expiration date.
- `ESTIMATED_NOTE` is appended during markdown export generation for rows with estimated dates.
- `DEFAULT_SHELF_LIFE` is used when creating or updating inventory items that lack a concrete expiration date.
