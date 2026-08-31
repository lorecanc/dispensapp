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
| `OFF_BASE_URL` | `https://world.openfoodfacts.org/api/v0/product` | Open Food Facts API endpoint |
| `CORS_ORIGINS` | localhost dev origins + `CORS_ORIGINS` env (comma-separated) | Allowed CORS origins |
| `EXPIRING_SOON_DAYS` | `3` | Days before expiration to flag as "expiring soon" |
| `ESTIMATED_NOTE` | `⚠️ Scadenza stimata...` | Warning for auto-estimated dates |

`database.py` also reads `DATABASE_URL` via `os.getenv("DATABASE_URL", ...)` with the same absolute-path default, so setting the env var is enough for both modules.

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
