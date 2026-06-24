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

Tables are created automatically on first startup. The database file is `inventory.db` in the project root.

## Configuration

All constants in [`config.py`](./config.py):

| Key | Default | Description |
|-----|---------|-------------|
| `DEFAULT_SHELF_LIFE` | (per category map) | Shelf life in days by product category |
| `OFF_BASE_URL` | `https://world.openfoodfacts.org/api/v0/product` | Open Food Facts API endpoint |
| `CORS_ORIGINS` | `["*"]` | Allowed CORS origins |
| `EXPIRING_SOON_DAYS` | `3` | Days before expiration to flag as "expiring soon" |
| `ESTIMATED_NOTE` | `⚠️ Scadenza stimata...` | Warning for auto-estimated dates |

## Project Layout

```
backend/
├── main.py              # App factory, lifespan (create_all), CORS, router registration
├── config.py            # Constants: shelf life, OFF URL, CORS
├── database.py          # SQLAlchemy engine, SessionLocal, get_db dependency
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
