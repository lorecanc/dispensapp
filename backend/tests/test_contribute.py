"""Tests for POST /api/scan/contribute.

All Open Food Facts network calls are mocked (httpx.AsyncClient or the
service layer). These tests never touch the production network.
"""

import logging
from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest
from fastapi.testclient import TestClient

import backend.config as config
from backend.main import app
from backend.services.off import contribute_product

client = TestClient(app)

VALID_BODY = {
    "code": "8076809514381",
    "product_name": "Spaghetti",
    "brands": "Barilla",
    "quantity": "500g",
    "categories": "Pasta",
    "consent_cc_bysa": True,
    "lang": "it",
}


def _enable_write(monkeypatch, enabled=True):
    monkeypatch.setattr(config, "OFF_WRITE_ENABLED", enabled)


def test_contribute_disabled_returns_403_without_calling_off(monkeypatch):
    """OFF_WRITE_ENABLED=false -> 403 e contribute_product mai invocato."""
    _enable_write(monkeypatch, False)
    with patch(
        "backend.routes.contribute.contribute_product", new=AsyncMock()
    ) as mock_contrib:
        resp = client.post("/api/scan/contribute", json=VALID_BODY)
    assert resp.status_code == 403
    mock_contrib.assert_not_called()


def test_contribute_consent_false_returns_400_without_calling_off(monkeypatch):
    """consent_cc_bysa=false -> 400 prima di qualsiasi chiamata OFF."""
    _enable_write(monkeypatch, True)
    body = dict(VALID_BODY, consent_cc_bysa=False)
    with patch(
        "backend.routes.contribute.contribute_product", new=AsyncMock()
    ) as mock_contrib:
        resp = client.post("/api/scan/contribute", json=body)
    assert resp.status_code == 400
    mock_contrib.assert_not_called()


def test_contribute_success_returns_200(monkeypatch):
    """OFF accetta (status=1) -> 200 con ok=true."""
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.contribute_product",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ) as mock_contrib:
        resp = client.post("/api/scan/contribute", json=VALID_BODY)
    assert resp.status_code == 200
    body = resp.json()
    assert body["ok"] is True
    assert body["code"] == VALID_BODY["code"]
    mock_contrib.assert_awaited_once()


def test_contribute_off_rejection_returns_502(monkeypatch):
    """OFF rifiuta (status=0) -> 502."""
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.contribute_product",
        new=AsyncMock(return_value={"status": 0, "reason": "missing code"}),
    ):
        resp = client.post("/api/scan/contribute", json=VALID_BODY)
    assert resp.status_code == 502


def test_contribute_transport_error_returns_502(monkeypatch):
    """Errore di trasporto httpx -> 502 (mai 500)."""
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.contribute_product",
        new=AsyncMock(side_effect=httpx.ConnectError("conn refused")),
    ):
        resp = client.post("/api/scan/contribute", json=VALID_BODY)
    assert resp.status_code == 502


def test_contribute_invalid_barcode_returns_422(monkeypatch):
    """Barcode non numerico -> 422 di validazione, OFF mai chiamato."""
    _enable_write(monkeypatch, True)
    body = dict(VALID_BODY, code="not-a-barcode!")
    with patch(
        "backend.routes.contribute.contribute_product", new=AsyncMock()
    ) as mock_contrib:
        resp = client.post("/api/scan/contribute", json=body)
    assert resp.status_code == 422
    mock_contrib.assert_not_called()


def _patch_post_client(monkeypatch, response_data, capture):
    """Patch httpx.AsyncClient: cattura url/data/headers del POST e rende response_data."""
    resp = Mock(spec=httpx.Response)
    resp.raise_for_status.return_value = None
    resp.json.return_value = response_data

    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.post.return_value = resp

    async def _post(url, data=None, headers=None, **kwargs):
        capture.update(url=url, data=data, headers=headers)
        return resp

    client_mock.post.side_effect = _post

    async def aenter(*args, **kwargs):
        return client_mock

    cm = Mock()
    cm.__aenter__ = aenter
    cm.__aexit__ = AsyncMock(return_value=False)
    return patch("backend.services.off.httpx.AsyncClient", return_value=cm)


@pytest.mark.asyncio
async def test_contribute_product_sends_add_fields_and_user_agent(monkeypatch):
    """Il POST a product_jqm2.pl usa solo add_* e User-Agent con nome/versione app."""
    import backend.services.off as off_module

    monkeypatch.setattr(off_module, "OFF_USER", "testuser")
    monkeypatch.setattr(off_module, "OFF_PASS", "s3cret-test-pw")
    monkeypatch.setattr(
        off_module, "OFF_WRITE_BASE_URL", "https://world.openfoodfacts.net/cgi"
    )
    monkeypatch.setattr(off_module, "OFF_APP_NAME", "DispensApp")
    monkeypatch.setattr(off_module, "OFF_APP_VERSION", "0.1.0")
    monkeypatch.setattr(off_module, "OFF_CONTACT_EMAIL", "test@example.com")

    capture = {}
    patcher = _patch_post_client(capture, {"status": 1}, capture)
    with patcher:
        result = await contribute_product(
            code="8076809514381",
            product_name="Spaghetti",
            brands="Barilla",
            categories="Pasta",
            quantity="500g",
        )

    assert result == {"status": 1, "reason": None}
    assert capture["url"].endswith("/product_jqm2.pl")
    form = capture["data"]
    # solo campi add_* per brands/categories, mai quelli nudi
    assert form["add_brands"] == "Barilla"
    assert form["add_categories"] == "Pasta"
    assert "brands" not in form
    assert "categories" not in form
    assert form["product_name_it"] == "Spaghetti"
    assert form["quantity"] == "500g"
    assert form["code"] == "8076809514381"
    ua = capture["headers"]["User-Agent"]
    assert "DispensApp/0.1.0" in ua


@pytest.mark.asyncio
async def test_contribute_product_never_logs_password(monkeypatch, caplog):
    """Su errore di trasporto i log non devono contenere la password OFF."""
    import backend.services.off as off_module

    fake_pw = "pw-super-segreta-xyz-123"
    monkeypatch.setattr(off_module, "OFF_USER", "testuser")
    monkeypatch.setattr(off_module, "OFF_PASS", fake_pw)
    monkeypatch.setattr(
        off_module, "OFF_WRITE_BASE_URL", "https://world.openfoodfacts.net/cgi"
    )

    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.post.side_effect = httpx.ConnectError("conn refused")

    async def aenter(*args, **kwargs):
        return client_mock

    cm = Mock()
    cm.__aenter__ = aenter
    cm.__aexit__ = AsyncMock(return_value=False)

    with patch("backend.services.off.httpx.AsyncClient", return_value=cm):
        with caplog.at_level(logging.WARNING, logger="backend.services.off"):
            with pytest.raises(httpx.HTTPError):
                await contribute_product(code="8076809514381", product_name="X")

    assert fake_pw not in caplog.text
