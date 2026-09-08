---
title: "Python Dependencies"
description: "Python packages used by the Inventario backend and their roles"
category: "dependencies"
source_files:
  - "requirements.txt"
  - "Dockerfile"
  - ".github/workflows/alembic-heads.yml"
  - "backend/routes/scan.py"
  - "backend/services/off.py"
  - "backend/routes/contribute.py"
created: "2026-06-24"
last_updated: "2026-09-06"
---

# Python Dependencies

## Overview

The Inventario backend is a Python application using FastAPI. Dependencies are managed via `requirements.txt` and split into production and development/test groups. There are no image-processing third-party packages: photo validation is stdlib-only.

## Production Dependencies

### fastapi

Web framework used to build the [REST API](../modules/backend-api.md). Provides request routing, dependency injection, input validation via Pydantic models, and automatic OpenAPI documentation generation.

Used in: all route handlers, middleware, and the application factory. `UploadFile` / `File` / `Form` in `backend/routes/contribute.py` handle `multipart/form-data` photo uploads.

### uvicorn[standard]

ASGI server that runs the FastAPI application. The `[standard]` extra includes `uvloop` and `httptools` for better performance on supported platforms.

Used in: the `server.py` entrypoint and `make run` / `dev` commands.

### sqlalchemy

Object Relational Mapper (ORM) for all [database operations](../modules/backend-database.md). Handles schema definition via the declarative base, query construction, session management, and migrations.

Used in: all model definitions, repository/data-access layer, and database setup. Sessions are synchronous, so blocking DB work is offloaded via `anyio.to_thread` (see below).

### httpx

Async HTTP client used to communicate with the Open Food Facts API. Provides native `async`/`await` support, connection pooling, timeout handling, and automatic content negotiation.

Usage pattern in `backend/services/off.py` is split by operation:

- **Reads** (`fetch_product`): one shared module-level `httpx.AsyncClient(timeout=10.0)` created lazily by `_get_client()` and reused across requests (connection reuse, no per-request construction cost).
- **Writes** (`contribute_product`, `upload_product_image`): short-lived `async with httpx.AsyncClient(...)` per call with longer timeouts (15s for metadata `product_jqm2.pl`, 30s for `product_image_upload.pl` multipart upload), because writes carry auth headers, form fields, and file payloads that must not share the read client's lifecycle.

Used in: the Open Food Facts integration module for barcode lookups, metadata contributions, and product-image uploads.

### pydantic

Data validation and schema definition library (v2). FastAPI uses Pydantic models for request/response serialization and validation. Also used for internal data transfer objects and configuration schemas.

Used in: request bodies, response models, query parameters, and internal data structures.

### python-multipart

Multipart parser Starlette requires for `Form` / `File` / `UploadFile` (`multipart/form-data`). Pinned explicitly in `requirements.txt` so production installs (Render, Docker) include it; without it the photo-upload form parsing in `backend/routes/contribute.py` fails at runtime.

Used in: `POST /api/scan/contribute/photo` and any `Form`-based endpoint.

### anyio (transitive, not pinned)

`anyio` is **not** listed in `requirements.txt`; it arrives transitively via FastAPI / Starlette. It is imported directly in exactly one place: `backend/routes/scan.py` (`import anyio.to_thread`).

`POST /api/scan` runs its synchronous SQLAlchemy `persist_history()` closure via `await anyio.to_thread.run_sync(persist_history)` so the blocking session work executes in a worker thread and never stalls the event loop. No ORM objects cross the thread boundary.

## Photo Dependencies (none — stdlib only)

Photo contribution (`POST /api/scan/contribute/photo`) deliberately adds **no** third-party image dependency (no Pillow, no libheif bindings):

- Type detection in `backend/routes/contribute.py:_detect_photo_kind` uses magic bytes only: JPEG (`FF D8 FF`), PNG (`89 50 4E 47 0D 0A 1A 0A`), HEIC via `ftyp` box brand allowlist (`heic`, `heix`, `hevc`, `hevx`, `heim`, `heis`, `hevm`, `hevs` plus an 8-entry compatible-brand scan). Declared `Content-Type` vs detected kind mismatch is rejected with `415`.
- Dimension check in `_photo_dimensions` parses headers manually: PNG `IHDR` width/height via `int.from_bytes`, JPEG SOF-marker scan for the first Start-Of-Frame segment. Minimum 640x160 px applies only when dimensions are determinable; HEIC is accepted without a dimension check (full `ispe` box parsing would require external deps). Violations return `422`.
- Size enforcement is a plain length check against `MAX_PHOTO_BYTES` (5 MB) plus a fail-fast `Content-Length` pre-check; `imagefield` is validated fail-closed by regex. The raw bytes are forwarded unchanged to `upload_product_image`, which posts them as `imgupload_{imagefield}` multipart via httpx.

## Development / Test Dependencies

### pytest

Test framework used for all [backend tests](../modules/backend-tests.md). Provides test discovery, fixtures, assertions, and reporting.

Used in: all test files under `tests/`.

### pytest-asyncio

Async test support for pytest. Enables `async def` test functions so that async endpoint handlers and database operations can be tested directly without extra boilerplate.

Used in: async test cases in the test suite.

## Production Install & Migration Notes

The `Dockerfile` installs `requirements.txt` first (layer cache), then adds `alembic` + `psycopg2-binary` via a separate `pip install` — they are intentionally not in `requirements.txt`. `alembic` is needed because the lifespan in `backend/main.py` runs `alembic upgrade head` at startup; `psycopg2-binary` is needed for Postgres `DATABASE_URL`s. `.dockerignore` keeps `ios/`, `wiki/`, and local DB files out of the image.

CI (`.github/workflows/alembic-heads.yml`) installs `alembic` + `sqlalchemy` and fails the build unless `alembic heads` reports exactly one head, so divergent migrations must be merged before push.
