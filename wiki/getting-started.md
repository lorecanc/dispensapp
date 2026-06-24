---
title: "Getting Started"
description: "Setup instructions for backend (FastAPI) and iOS (SwiftUI) development"
category: "root"
source_files:
  - "requirements.txt"
  - "ios/project.yml"
  - "ios/README.md"
  - "ios/Inventario/Networking/APIConfig.swift"
  - "backend/main.py"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Getting Started

## Prerequisites

- **[Python 3](../dependencies/python-dependencies.md)** — for the FastAPI backend
- **Xcode 15.0+** — for the iOS app
- **iOS 17.0+** — deployment target
- **[XcodeGen](../dependencies/apple-dependencies.md)** — install via Homebrew: `brew install xcodegen`

## Backend Setup

The backend is a [Python/FastAPI application](../overview.md) backed by SQLite.

```bash
# Navigate to the project root
cd /path/to/Inventario

# Create a virtual environment
python3 -m venv .venv

# Activate it
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
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

### Running the Backend

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

The server starts on `http://127.0.0.1:8000` with auto-reload enabled. On first startup the database tables are created automatically via SQLAlchemy's `create_all` — no manual migration step is required.

The database file is `inventory.db` at the project root (SQLite, configured in [`backend/config.py`](../config/backend-config.md)).

## iOS Setup

### Generate the Xcode Project

The iOS project uses [XcodeGen](../config/ios-config.md). The project specification is in `ios/project.yml`.

```bash
cd ios
xcodegen generate
open Inventario.xcodeproj
```

### Configure the API URL

The iOS app communicates with the backend at `http://127.0.0.1:8000` by default. The base URL is defined in [`APIConfig.swift`](../config/ios-config.md):

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

See the [Architecture](../architecture.md) page for a detailed breakdown of system components and data flow.

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/scan` | Lookup a barcode |
| POST | `/api/inventory` | Create an inventory item from a scan |
| POST | `/api/inventory/manual` | Create an inventory item manually |
| GET | `/api/inventory` | List all inventory items |
| PATCH | `/api/inventory/{id}` | Update an item |
| DELETE | `/api/inventory/{id}` | Delete an item |
| GET | `/api/inventory/export` | Export inventory as Markdown |

## Project Conventions

- **UI language** — all iOS UI text is in Italian.
- **Barcode scanning** — supports EAN-13, EAN-8, UPC-E, and Code 128 via VisionKit.
- **CORS** — the backend allows all origins during development (`CORS_ORIGINS = ["*"]` in [`backend/config.py`](../config/backend-config.md)).
- **Shelf life estimation** — the backend assigns default expiration dates based on product category. Items marked with a warning note (⚠️) have estimated rather than scanned expiration dates.
