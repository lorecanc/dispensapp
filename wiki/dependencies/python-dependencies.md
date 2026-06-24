---
title: "Python Dependencies"
description: "Python packages used by the Inventario backend and their roles"
category: "dependencies"
source_files:
  - "requirements.txt"
created: "2026-06-24"
last_updated: "2026-06-24"
---

# Python Dependencies

## Overview

The Inventario backend is a Python application using FastAPI. Dependencies are managed via `requirements.txt` and split into production and development/test groups.

## Production Dependencies

### fastapi

Web framework used to build the [REST API](../modules/backend-api.md). Provides request routing, dependency injection, input validation via Pydantic models, and automatic OpenAPI documentation generation.

Used in: all route handlers, middleware, and the application factory.

### uvicorn[standard]

ASGI server that runs the FastAPI application. The `[standard]` extra includes `uvloop` and `httptools` for better performance on supported platforms.

Used in: the `server.py` entrypoint and `make run` / `dev` commands.

### sqlalchemy

Object Relational Mapper (ORM) for all [database operations](../modules/backend-database.md). Handles schema definition via the declarative base, query construction, session management, and migrations.

Used in: all model definitions, repository/data-access layer, and database setup.

### httpx

Async HTTP client used to communicate with the Open Food Facts API. Provides native `async`/`await` support, connection pooling, timeout handling, and automatic content negotiation.

Used in: the Open Food Facts integration module for barcode lookups and product data fetching.

### pydantic

Data validation and schema definition library (v2). FastAPI uses Pydantic models for request/response serialization and validation. Also used for internal data transfer objects and configuration schemas.

Used in: request bodies, response models, query parameters, and internal data structures.

## Development / Test Dependencies

### pytest

Test framework used for all [backend tests](../modules/backend-tests.md). Provides test discovery, fixtures, assertions, and reporting.

Used in: all test files under `tests/`.

### pytest-asyncio

Async test support for pytest. Enables `async def` test functions so that async endpoint handlers and database operations can be tested directly without extra boilerplate.

Used in: async test cases in the test suite.
