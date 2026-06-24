# Inventario

Pantry inventory management app — scan barcodes, track expiration dates, reduce food waste.

A SwiftUI iOS client communicates with a FastAPI backend over HTTP REST. Barcodes are resolved via the [Open Food Facts](https://world.openfoodfacts.org/) public database; expiration dates are auto-estimated from category shelf-life defaults when not provided.

## Architecture

```
iOS App (SwiftUI)  ──HTTP──>  FastAPI Backend  ──httpx──>  Open Food Facts
                                        │
                                     SQLite
```

| Layer | Technology |
|-------|-----------|
| Backend | Python, FastAPI, SQLAlchemy, SQLite, httpx |
| iOS | Swift 5.9, SwiftUI, VisionKit, URLSession async/await |

## Project Structure

```
Inventario/
├── backend/                    # FastAPI backend
│   ├── main.py                 # App entry point, CORS, lifespan
│   ├── config.py               # Shelf-life mapping, OFF URL, constants
│   ├── database.py             # SQLAlchemy engine & session
│   ├── models.py               # ORM model (InventoryItem)
│   ├── schemas.py              # Pydantic v2 request/response schemas
│   ├── routes/
│   │   ├── scan.py             # POST /api/scan
│   │   └── inventory.py        # CRUD /api/inventory
│   ├── services/
│   │   ├── off.py              # Open Food Facts async client
│   │   ├── expiration.py       # Expiration date estimation
│   │   └── markdown_export.py  # Markdown table generation
│   └── tests/                  # pytest suite
├── ios/
│   ├── Inventario/             # SwiftUI app source
│   │   ├── State/InventoryStore.swift
│   │   ├── Models/
│   │   ├── Networking/APIClient.swift
│   │   ├── Features/           # Scan, Inventory, ManualEntry, Settings
│   │   └── Components/         # Shared UI components
│   └── project.yml             # XcodeGen project spec
├── wiki/                       # Project documentation
├── requirements.txt
└── inventory.db                # SQLite database (generated)
```

## Getting Started

### Backend

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

### iOS

```bash
cd ios
xcodegen generate
open Inventario.xcodeproj
```

The app defaults to `http://127.0.0.1:8000` — configure in Settings.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/scan` | Lookup barcode via Open Food Facts |
| POST | `/api/inventory` | Create item from scan |
| POST | `/api/inventory/manual` | Create item manually |
| GET | `/api/inventory` | List all items |
| PATCH | `/api/inventory/{id}` | Update item |
| DELETE | `/api/inventory/{id}` | Delete item |
| GET | `/api/inventory/export` | Export as Markdown |

## Documentation

See the [wiki](./wiki/index.md) for architecture, component details, concepts, and configuration.

## Notes

- All iOS UI text is in Italian.
- Barcode scanning supports EAN-13, EAN-8, UPC-E, and Code 128 via VisionKit.
- Expiration dates are auto-estimated from product category when not provided (marked with a warning).
