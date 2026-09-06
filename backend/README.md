# Inventario Backend

FastAPI-based backend for the Inventario pantry management app.

Handles barcode lookup (via Open Food Facts), inventory CRUD, expiration date estimation, and markdown export. Persists to SQLite via SQLAlchemy.

## Stack

| Component | Library |
|-----------|---------|
| Framework | FastAPI |
| Server | uvicorn |
| ORM | SQLAlchemy (declarative) |
| Database | SQLite |
| Validation | Pydantic v2 |
| HTTP client | httpx (async) |
| Tests | pytest, pytest-asyncio |

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r ../requirements.txt
```

## Run

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

Tables are created via Alembic migrations on startup (`alembic upgrade head` in `lifespan`), with `Base.metadata.create_all` as fallback if Alembic is unavailable. The database file is `inventory.db` in the project root (absolute path resolved from `config.py`).

### Database & Migrations (Alembic)

```bash
# from backend/
alembic upgrade head      # apply all migrations
alembic downgrade base    # revert all (drops tables — destructive)
alembic revision --autogenerate -m "add_xxx"  # new migration (env.py uses Base.metadata)
# override DB for one-off runs:
DATABASE_URL=sqlite:////tmp/test.db alembic upgrade head
DATABASE_URL=sqlite:////tmp/test.db alembic downgrade base
```

- Config: `backend/alembic.ini` + `backend/alembic/env.py` (loads `Base` from `database.py` and `DATABASE_URL` from `config.py`/`DATABASE_URL` env).
- Baseline: `alembic/versions/*_create_initial_tables.py` creates `inventory_items` (idempotent — skips if table exists, does not drop data on upgrade).

## Configuration

All constants in [`config.py`](./config.py). `DATABASE_URL` is env-configurable.

| Key | Default | Description |
|-----|---------|-------------|
| `DATABASE_URL` | `sqlite:///<project_root>/inventory.db` (absolute, from `DATABASE_URL` env) | SQLAlchemy URL. Override with `DATABASE_URL` env var, e.g. `sqlite:////tmp/test.db` or `postgresql://user:pass@host/db`. Default is resolved as absolute path relative to `config.py` (not CWD) |
| `DEFAULT_SHELF_LIFE` | (per category map) | Shelf life in days by product category |
| `OFF_V3_BASE_URL` | `https://world.openfoodfacts.org/api/v3/product` (`OFF_V3_BASE_URL` env) | Open Food Facts API v3 universale (sola lettura). Solo `https` con host in `world.openfoodfacts.org` / `world.openbeautyfacts.org` / `world.openpetfoodfacts.org` / `world.openproductsfacts.org`, altrimenti fallback al default con warning |
| `OFF_PRODUCT_TYPE_DEFAULT` | `all` (`OFF_PRODUCT_TYPE_DEFAULT` env) | `product_type` di default per la lettura v3 (`all` interroga tutti i progetti; fallback per-host `OFF_V3_HOSTS` solo con tipo esplicito) |
| `OFF_WRITE_ENABLED` | `false` (`OFF_WRITE_ENABLED` env) | Abilita `POST /api/scan/contribute` e `/photo`. Resta `false` senza `OFF_USER`/`OFF_PASS` |
| `OFF_WRITE_BASE_URL` | `https://world.openfoodfacts.net/cgi` (`OFF_WRITE_BASE_URL` env) | Staging OFF per scrittura; prod `https://world.openfoodfacts.org/cgi` solo via env |
| `OFF_USER` / `OFF_PASS` | `""` (env, mai loggata) | Credenziali account OFF personale per la scrittura. Su staging usare un account creato sullo staging, non quello di produzione |
| `OFF_STAGING_BASIC_USER` / `OFF_STAGING_BASIC_PASS` | `off` / `off` (env) | Basic auth dell'host staging `world.openfoodfacts.net` (protetto da `off:off`): inviata solo su host `*.openfoodfacts.net`, mai su produzione |
| `OFF_APP_NAME` / `OFF_APP_VERSION` | `DispensApp` / `0.1.0` (env) | Identificano il client in `comment` e `User-Agent` |
| `OFF_CONTACT_EMAIL` | `""` (env) | Contatto opzionale aggiunto allo `User-Agent` |
| `CORS_ORIGINS` | localhost dev origins + `CORS_ORIGINS` env (comma-separated) | Allowed CORS origins |
| `EXPIRING_SOON_DAYS` | `3` | Days before expiration to flag as "expiring soon" |
| `ESTIMATED_NOTE` | `⚠️ Scadenza stimata...` | Warning for auto-estimated dates |

`database.py` also reads `DATABASE_URL` via `os.getenv("DATABASE_URL", ...)` with the same absolute-path default, so setting the env var is enough for both modules.

### Scrittura Open Food Facts (OFF_WRITE)

Contributi disabilitati di default. Copia `.env.example` (root) in `.env` e imposta `OFF_WRITE_ENABLED=true` + `OFF_USER`/`OFF_PASS` (account OFF personale; su staging un account creato sullo staging). Base di default: staging `https://world.openfoodfacts.net/cgi`; prod `https://world.openfoodfacts.org/cgi` solo via env esplicito. Host non `openfoodfacts.org`/`.net` o scheme non-https → fallback a staging con warning. Lo staging è protetto da Basic auth `off:off` (env `OFF_STAGING_BASIC_USER`/`OFF_STAGING_BASIC_PASS`), inviata solo su host `*.openfoodfacts.net`. Ogni richiesta OFF usa `User-Agent: OFF_APP_NAME/OFF_APP_VERSION (OFF_CONTACT_EMAIL)` (contatto omesso se vuoto). Esempio staging in `.env.example`, modulo iOS: `APIClient.contribute` / `APIClient.uploadPhoto`.

Metadati via `POST {base}/product_jqm2.pl` (form: `code`, `user_id`, `password`, `lc`/`lang` a 2 lettere, `comment`, `app_name`, `app_version`, `app_uuid` opzionale persistita dal client, `product_name_{lc}`/`generic_name_{lc}`, solo campi `add_brands`/`add_categories`/`add_labels` mai quelli nudi, `quantity`). Foto via `POST {base}/product_image_upload.pl` (form `code`/`imagefield`/`user_id`/`password` + file `imgupload_{imagefield}`). Il consenso `consent_cc_bysa=true` è obbligatorio: le foto inviate a OFF sono pubblicate con licenza CC BY-SA irrevocabile.

## Project Layout

```
backend/
├── main.py              # App factory, lifespan (alembic upgrade + create_all fallback), CORS, router registration
├── config.py            # Constants: shelf life, OFF URL, CORS, DATABASE_URL (env + absolute default)
├── database.py          # SQLAlchemy engine, SessionLocal, get_db, DATABASE_URL (env + absolute default)
├── alembic.ini          # Alembic config (sqlalchemy.url overridden by env.py)
├── alembic/
│   ├── env.py           # Uses Base from database.py + DATABASE_URL from config
│   └── versions/*_create_initial_tables.py  # Baseline: inventory_items
├── models.py            # InventoryItem ORM model
├── schemas.py           # Pydantic v2 schemas (ScanRequest/Response, InventoryCreate/Out/Update)
├── routes/
│   ├── scan.py          # POST /api/scan — barcode lookup via OFF
│   └── inventory.py     # CRUD + export endpoints
├── services/
│   ├── off.py           # fetch_product(barcode) — async OFF client
│   ├── expiration.py    # estimate_expiration(category) — shelf-life logic
│   └── markdown_export.py  # to_markdown(items) — table generation
├── tests/
│   ├── test_off.py      # OFF service unit tests (httpx mock)
│   └── test_scan.py     # Scan endpoint integration tests (TestClient)
└── README.md
```

## API Reference

### `POST /api/scan`

Lookup a barcode via Open Food Facts.

**Request:** `{"barcode": "8000500310427"}`

**Response (200):** `{"found": true, "name": "...", "brand": "...", "categories": "...", "image_url": "...", "barcode": "..."}`

**Response (404):** `{"found": false, "message": "Prodotto non trovato"}`

**Response (502):** `{"detail": "Impossibile contattare Open Food Facts"}`

### `POST /api/scan/contribute` + `POST /api/scan/contribute/photo`

Invio metadati/foto a OFF (staging di default) via `backend/routes/contribute.py` → `services/off.py` (`product_jqm2.pl` / `product_image_upload.pl`). Richiedono `consent_cc_bysa=true` (licenza CC BY-SA) e `OFF_WRITE_ENABLED=true`, altrimenti `400` (consenso) / `403` (disabilitata). Barcode `^\d{8,14}$`, rate-limit in-memory 10 req/min per IP (`429`).

| Method | Path | Content-Type | Parametri | Risposta ok |
|--------|------|--------------|-----------|-------------|
| POST | `/api/scan/contribute` | `application/json` | `code`, `consent_cc_bysa`, `lang` (2 lettere, default `it`; `it-IT` normalizzato a `it`), almeno uno tra `product_name`/`brands`/`quantity`/`categories` (+ `labels`/`generic_name`/`comment`/`app_uuid` opzionali) | `200 {"ok": true, "code", "message"}` |
| POST | `/api/scan/contribute/photo` | `multipart/form-data` | `code`, `imagefield` (`front`/`ingredients`/`nutrition`/`packaging`/`other` + suffisso opzionale `_<lc>` a 2 lettere, es. `front_it`), `consent_cc_bysa`, `image` (JPEG/PNG/HEIC, max 5MB, magic-byte verificati) | `200 {"ok": true, "code", "message"}` |

Limiti foto: `imagefield` fail-closed via regex `^(front|ingredients|nutrition|packaging|other)(_[a-z]{2})?$`, non validi → `422`; max 5MB (`413`, con pre-check sul `Content-Length` dichiarato); tipi JPEG/PNG/HEIC con mismatch dichiarato/rilevato → `415`; minimo 640x160 px solo per JPEG/PNG con dimensioni determinabili (`422`), HEIC accettato senza check dimensioni (niente dipendenze esterne); `code` non valido → `422`, rifiuto OFF → `502`. iOS: `APIClient.contribute(code:productName:brands:quantity:categories:lang:consent:)` e `APIClient.uploadPhoto(code:imageData:filename:mimeType:imagefield:consent:)` (timeout 15s/30s).

### `POST /api/inventory`

Create an inventory item from a scan. If `expiration_date` is omitted, it is estimated from the category.

### `POST /api/inventory/manual`

Same as above but without a barcode.

### `GET /api/inventory`

List all items ordered by expiration date (nulls last). Each item includes a computed `status` field: `"ok"`, `"expiring_soon"`, or `"expired"`.

### `PATCH /api/inventory/{item_id}`

Partial update. At least one field is required.

### `DELETE /api/inventory/{item_id}`

Delete an item by ID.

### `GET /api/inventory/export`

Returns `text/markdown` — a table of all items with status indicators and estimated-date warnings.

## Testing

```bash
# from project root
pytest backend/tests/ -v
```

Tests use `httpx` mock for OFF calls and FastAPI `TestClient` for endpoint integration.
