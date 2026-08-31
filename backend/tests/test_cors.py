from fastapi.testclient import TestClient
from backend.main import app
from backend.config import CORS_ORIGINS


def test_cors_allowlist_not_wildcard():
    assert "*" not in CORS_ORIGINS
    # ensure only localhost origins plus env; no wildcard
    for o in CORS_ORIGINS:
        assert o != "*"
        assert "://" in o


def test_cors_allowed_origin_returns_specific_not_star():
    client = TestClient(app)
    headers = {"Origin": "http://localhost:3000"}
    resp = client.get("/api/inventory", headers=headers)
    # CORSMiddleware should echo allowed origin
    acao = resp.headers.get("access-control-allow-origin")
    assert acao == "http://localhost:3000"
    assert acao != "*"


def test_cors_disallowed_origin_not_star():
    client = TestClient(app)
    headers = {"Origin": "https://evil.com"}
    resp = client.get("/api/inventory", headers=headers)
    acao = resp.headers.get("access-control-allow-origin")
    # disallowed should not be echoed; either absent or not evil, never "*"
    assert acao != "*"
    if acao is not None:
        assert acao != "https://evil.com"


def test_cors_preflight_allowed():
    client = TestClient(app)
    headers = {
        "Origin": "http://localhost:3000",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "Content-Type",
    }
    resp = client.options("/api/inventory", headers=headers)
    # preflight should succeed for allowed origin
    assert resp.status_code in (200, 204)
    acao = resp.headers.get("access-control-allow-origin")
    assert acao == "http://localhost:3000"


def test_cors_credentials_false():
    # main.py sets allow_credentials=False, ensure header not allow-credentials true for wildcard
    # Starlette's CORSMiddleware when allow_credentials False should not send allow-credentials:true
    client = TestClient(app)
    headers = {"Origin": "http://localhost:3000"}
    resp = client.get("/api/inventory", headers=headers)
    # should not have allow-credentials: true when credentials disabled
    cred = resp.headers.get("access-control-allow-credentials")
    # allow_credentials=False means header absent or "false"
    assert cred is None or cred.lower() == "false"
