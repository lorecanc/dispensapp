---
title: "Getting Started"
description: "Setup instructions for backend (FastAPI) and iOS (SwiftUI) development"
category: "root"
source_files:
  - "requirements.txt"
  - ".env.example"
  - "backend/config.py"
  - "backend/main.py"
  - "ios/project.yml"
  - "ios/README.md"
  - "ios/Inventario/Networking/APIConfig.swift"
created: "2026-06-24"
last_updated: "2026-09-05"
---

# Getting Started

## Prerequisites

- **[Python 3](./dependencies/python-dependencies.md)** — for the FastAPI backend
- **Xcode** — for the iOS app (no pinned `xcodeVersion`; requires a toolchain supporting `nonisolated(unsafe)`, i.e. Swift 5.10+ / Xcode 26.x)
- **iOS 17.0+** — deployment target
- **[XcodeGen](./dependencies/apple-dependencies.md)** — install via Homebrew: `brew install xcodegen`

## Backend Setup

The backend is a [Python/FastAPI application](./overview.md) backed by SQLite.

```bash
# Navigate to the project root
cd /path/to/Inventario

# Create a virtual environment
python3 -m venv .venv

# Activate it
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy the example environment file
cp .env.example .env
```

Contents of `requirements.txt`:

| Package | Purpose |
|---------|---------|
| `fastapi` | Web framework |
| `uvicorn[standard]` | ASGI server for development |
| `sqlalchemy` | ORM and database access |
| `httpx` | HTTP client (used for Open Food Facts lookups) |
| `pydantic` | Request/response validation |
| `pytest` | Test runner |
| `pytest-asyncio` | Async test support |

### Environment Configuration (.env)

Configuration lives in [`backend/config.py`](./config/backend-config.md) and is overridden via environment variables (see `.env.example` and `backend/README.md`). Never commit real credentials.

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite:///<project_root>/inventory.db` (absolute, resolved from `config.py`, not CWD) | SQLAlchemy URL. E.g. `sqlite:////tmp/test.db` |
| `OFF_WRITE_ENABLED` | `false` | Enables `POST /api/scan/contribute` and photo upload. Stays `false` without `OFF_USER`/`OFF_PASS` |
| `OFF_WRITE_BASE_URL` | `https://world.openfoodfacts.net/cgi` | Staging OFF for writes; prod `https://world.openfoodfacts.org/cgi` only via explicit env. Non-OFF hosts or insecure schemes fall back to staging with a warning |
| `OFF_USER` / `OFF_PASS` | `""` | Personal OFF account for writes. On staging use an account created on staging, not production |
| `OFF_STAGING_BASIC_USER` / `OFF_STAGING_BASIC_PASS` | `off` / `off` | Host basic-auth for staging `world.openfoodfacts.net`; sent only on `*.openfoodfacts.net`, never on production |
| `OFF_APP_NAME` / `OFF_APP_VERSION` | `DispensApp` / `0.1.0` | Client identity sent in `User-Agent` and `comment` |
| `OFF_CONTACT_EMAIL` | `""` | Optional contact appended to `User-Agent` |
| `CORS_ORIGINS` | localhost dev origins + comma-separated env list | Extra allowed origins, e.g. `CORS_ORIGINS="https://app.example.com,https://admin.example.com"` |

For local development the defaults work as-is (writes disabled, staging base URL, localhost CORS origins).

### Running the Backend

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

The server starts on `http://127.0.0.1:8000` with auto-reload enabled. On startup Alembic migrations run (`alembic upgrade head`), with SQLAlchemy `create_all` as fallback — no manual migration step is required.

The database file is `inventory.db` at the project root (SQLite, absolute path resolved in [`backend/config.py`](./config/backend-config.md), overridable via `DATABASE_URL`).

## iOS Setup

### Generate the Xcode Project

The iOS project uses [XcodeGen](./config/ios-config.md). The project specification is in `ios/project.yml`.

```bash
cd ios
xcodegen generate
open Inventario.xcodeproj
```

XcodeGen notes (`ios/project.yml`):

- No `xcodeVersion` pin — the old `15.0` value was inconsistent with features in use (`nonisolated(unsafe)` requires toolchain 5.10+, here 26.x).
- `SWIFT_VERSION: "5"` is set for both the `Inventario` app and `InventarioTests` targets.
- `Inventario/Info.plist` is hand-maintained (orientations, `CFBundleURLTypes`). Do not add an `info:` block — XcodeGen would regenerate and clobber that file.
- `InventarioTests` uses `GENERATE_INFOPLIST_FILE: "YES"`.

### Configure the API URL

The iOS app communicates with the backend at `http://127.0.0.1:8000` by default. The base URL is defined in [`APIConfig.swift`](./config/ios-config.md):

```swift
struct APIConfig {
    static var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8000" }
        set { UserDefaults.standard.set(newValue, forKey: "apiBaseURL") }
    }
    static var baseURL: URL { URL(string: baseURLString)! }
}
```

The URL can be changed in-app via the Settings screen — the value is persisted in `UserDefaults`. This allows pointing the app at a different host (e.g. a local network IP or a deployed instance) without rebuilding.

### Build and Run

After generating the project, select an iOS 17.0+ simulator or a physical device running iOS 17.0+ and run from Xcode.

See the [Architecture](./architecture.md) page for a detailed breakdown of system components and data flow.

## API Endpoints

All pantry-scoped routes require the `X-Pantry-Token` header (see [Pantry Sharing](./concepts/pantry-sharing.md)). Legacy unscoped `/api/inventory...` aliases still exist alongside the canonical `/api/pantries/{pantry_id}/inventory...` paths.

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/scan` | Lookup a barcode via Open Food Facts |
| POST | `/api/scan/contribute` | Contribute missing metadata to OFF (opt-in, rate-limited) |
| POST | `/api/scan/contribute/photo` | Upload a product photo to OFF (JPEG/PNG/HEIC, ≤ 5 MB) |
| GET/POST/DELETE | `/api/pantries...` | Pantry lifecycle, invites, members (see [Pantries API](./api/pantries.md)) |
| GET | `/api/pantries/{pantry_id}/inventory` | List pantry items (paginated) |
| POST | `/api/pantries/{pantry_id}/inventory` | Create an inventory item from a scan |
| POST | `/api/pantries/{pantry_id}/inventory/manual` | Create an inventory item manually |
| GET/PATCH/DELETE | `/api/pantries/{pantry_id}/inventory/{id}` | Read, update, or delete an item |
| POST | `/api/inventory/{id}/consume` | Atomically decrement quantity (409 if over-drawn) |
| GET | `/api/inventory/{id}/history` | Consumption history ledger |
| GET | `/api/pantries/{pantry_id}/inventory/export` | Export inventory as Markdown |
| GET | `/api/categories`, `/api/compartments` | Server-driven category/compartment taxonomy |
| GET | `/api/suggestions` | Scan-history autocomplete (prefix search) |
| * | `/api/pantries/{pantry_id}/shopping-lists...` | Shopping-list CRUD, check/uncheck, markdown export |

## Project Conventions

- **UI language** — all iOS UI text is in Italian.
- **Barcode scanning** — supports EAN-13, EAN-8, UPC-E, and Code 128 via VisionKit.
- **CORS** — the backend allows only localhost dev origins plus `CORS_ORIGINS` env entries (see [`backend/config.py`](./config/backend-config.md)).
- **Shelf life estimation** — the backend assigns default expiration dates based on product category. Items marked with a warning note (⚠️) have estimated rather than scanned expiration dates.
