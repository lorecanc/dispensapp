---
title: "Backend Configuration"
description: "Configuration values for the Inventario FastAPI backend"
category: "config"
source_files:
  - "backend/config.py"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Backend Configuration

## Overview

Application-level constants for the FastAPI backend. All values are defined in [`backend/config.py`](../modules/backend-config.md) as module-level variables and imported directly by the rest of the backend.

## Configuration Table

| Key | Type | Value | Description |
|-----|------|-------|-------------|
| `DATABASE_URL` | `str` | `"sqlite:///./inventory.db"` | [SQLite](../modules/backend-database.md) connection string. The database file is created in the project root directory. |
| `OFF_BASE_URL` | `str` | `"https://world.openfoodfacts.org/api/v0/product"` | Base URL for the [Open Food Facts API](../concepts/off-integration.md). Used to look up product information by barcode. The product code is appended to this URL when making requests. |
| `OFF_WRITE_ENABLED` | `bool` | `false` (da `OFF_WRITE_ENABLED` env) | Abilita `POST /api/scan/contribute` e `/photo`. Resta `false` se `OFF_USER`/`OFF_PASS` mancano o la base URL non è valida/sicura. Vedi [OFF integration](../concepts/off-integration.md) e [scan API](../api/scan.md). |
| `OFF_WRITE_BASE_URL` | `str` | `"https://world.openfoodfacts.net/cgi"` (da `OFF_WRITE_BASE_URL` env) | Staging OFF per la scrittura (`product_jqm2.pl`, `product_image_upload.pl`). Prod `https://world.openfoodfacts.org/cgi` solo via env esplicito. Host fuori `openfoodfacts.org`/`.net` o scheme non-https → fallback a staging con warning (http solo per `localhost`/`127.0.0.1`). |
| `OFF_USER` | `str` | `""` (env) | Account OFF personale per la scrittura (mai nei log). |
| `OFF_PASS` | `str` | `""` (env) | Password OFF (mai nei log). |
| `OFF_APP_NAME` | `str` | `"DispensApp"` (env) | Nome client in `comment`, `app_name` e `User-Agent`. |
| `OFF_APP_VERSION` | `str` | `"0.1.0"` (env) | Versione client in `comment`, `app_version` e `User-Agent`. |
| `OFF_CONTACT_EMAIL` | `str` | `""` (env) | Contatto opzionale accodato allo `User-Agent` (`Nome/Versione (email)`). |
| `CORS_ORIGINS` | `list[str]` | `["*"]` | Allowed origins for CORS middleware. Currently set to wildcard for development convenience. |
| `EXPIRING_SOON_DAYS` | `int` | `3` | Number of days within which an item is considered "[expiring soon](../concepts/item-status.md)". Items whose expiration date falls within this window from today trigger the expiring-soon status. |
| `ESTIMATED_NOTE` | `str` | `"⚠️ Scadenza stimata, potrebbe scadere prima"` | Warning text appended to markdown export rows that have an estimated expiration date (as opposed to a manufacturer-provided one). Written in Italian: "Estimated expiry, may expire earlier." |
| `DEFAULT_SHELF_LIFE` | `dict[str, int]` | See table below | Maps product category slugs to default shelf life in days. Used when a product has no explicit expiration date — the system calculates an [estimated date](../concepts/expiration-estimation.md) from the current date plus the category's shelf life. |

## DEFAULT_SHELF_LIFE

Default shelf life values in days, keyed by product category:

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
| `default` | 30 |

The `default` key serves as a fallback when a product's category does not match any specific entry.

## Usage

Modules import these values directly from `config`:

```python
from config import DATABASE_URL, OFF_BASE_URL, EXPIRING_SOON_DAYS
```

- `DATABASE_URL` is consumed by the SQLAlchemy engine in the database initialization module.
- `OFF_BASE_URL` is used by the barcode lookup service when querying Open Food Facts.
- `CORS_ORIGINS` is passed to FastAPI's `CORSMiddleware`.
- `EXPIRING_SOON_DAYS` is used by inventory queries that filter for items near their expiration date.
- `ESTIMATED_NOTE` is appended during markdown export generation for rows with estimated dates.
- `DEFAULT_SHELF_LIFE` is used when creating or updating inventory items that lack a concrete expiration date.
