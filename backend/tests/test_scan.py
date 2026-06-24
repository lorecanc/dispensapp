from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from backend.main import app

client = TestClient(app)


def _call_scan(barcode: str = "8076809514381"):
    return client.post("/api/scan", json={"barcode": barcode})


def test_scan_found_all_fields():
    """Product found with all fields → returns found: true."""
    payload = {
        "barcode": "8076809514381",
        "name": "Spaghetti",
        "brand": "Barilla",
        "categories": ["pasta", "italian-cuisine"],
        "image_url": "https://example.com/pic.jpg",
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["name"] == "Spaghetti"
    assert body["brand"] == "Barilla"
    assert body["categories"] == ["pasta", "italian-cuisine"]
    assert body["image_url"] == "https://example.com/pic.jpg"


def test_scan_found_empty_name_but_has_brands():
    """Product found with empty name but has brand → returns found: true (not false)."""
    payload = {
        "barcode": "8076809514381",
        "name": "",
        "brand": "Barilla",
        "categories": ["pasta"],
        "image_url": None,
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["name"] == ""
    assert body["brand"] == "Barilla"
    # The "found": True path was taken — name is empty but that's OK


def test_scan_not_found():
    """Product genuinely not in OFF → returns found: false."""
    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = {"found": False}
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is False
    assert "non trovato" in body.get("message", "").lower()


def test_scan_network_error():
    """fetch_product returns None → 502 Bad Gateway."""
    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = None
        resp = _call_scan()

    assert resp.status_code == 502
    body = resp.json()
    assert "comunicazione" in body.get("message", "").lower()


def test_scan_category_normalization():
    """Categories come pre-normalized from fetch_product (no en: prefix)."""
    payload = {
        "barcode": "1234567890123",
        "name": "Penne",
        "brand": None,
        "categories": ["pasta", "tomato-sauce"],
        "image_url": None,
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan(barcode="1234567890123")

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert "en:" not in " ".join(body["categories"])
