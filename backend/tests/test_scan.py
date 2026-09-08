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
    assert "database" in body.get("message", "").lower()


def test_scan_network_error():
    """fetch_product returns None → 502 Bad Gateway."""
    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = None
        resp = _call_scan()

    assert resp.status_code == 502
    body = resp.json()
    assert "comunicazione" in body.get("message", "").lower()
    assert "database" in body.get("message", "").lower()


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


def test_scan_suggested_category_from_pnns_group():
    """Tag non mappabili + pnns_group latte/dairy → suggested_category fresh-milk."""
    payload = {
        "barcode": "8076809514381",
        "name": "Latte Intero",
        "brand": None,
        "categories": ["organic", "vegan"],  # nessun tag mappa a categoria interna
        "pnns_group": "milk-and-dairy-products",
        "image_url": None,
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["suggested_category"] == "fresh-milk"


def test_scan_suggested_category_null_when_nothing_maps():
    """Nessun tag mappabile e nessun pnns_group → suggested_category null."""
    payload = {
        "barcode": "8076809514381",
        "name": "Prodotto Ignoto",
        "brand": None,
        "categories": ["organic", "vegan"],
        "image_url": None,
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["suggested_category"] is None


def test_scan_not_found_suggested_category_null():
    """Ramo found=false → campo suggested_category presente e null."""
    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = {"found": False}
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is False
    assert "suggested_category" in body
    assert body["suggested_category"] is None


def test_scan_propagates_source_product_type():
    """source/product_type da fetch_product propagati in ScanResponse."""
    payload = {
        "barcode": "3560070791460",
        "name": "Cream",
        "brand": None,
        "categories": ["makeup"],
        "image_url": None,
        "source": "beauty",
        "product_type": "beauty",
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan(barcode="3560070791460")

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["source"] == "beauty"
    assert body["product_type"] == "beauty"
    mock_fetch.assert_called_once_with("3560070791460")


def test_scan_non_food_without_pnns():
    """Non-food (beauty) senza pnns → found true, source beauty, nessun crash."""
    payload = {
        "barcode": "3560070791460",
        "name": "Cream",
        "brand": None,
        "categories": ["makeup"],
        "pnns_group": None,
        "image_url": None,
        "source": "beauty",
        "product_type": "beauty",
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan(barcode="3560070791460")

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["source"] == "beauty"
    assert body["product_type"] == "beauty"


# --- T1 RED: scan deve inoltrare source a suggest_category -------------------
# scan.py oggi chiama suggest_category(categories, pnns_group) ignorando
# source: i test sotto falliscono finché la produzione non propaga source.

def test_scan_makeup_beauty_suggests_cleaning_hygiene():
    """source=beauty + makeup → suggested cleaning-hygiene (oggi None)."""
    payload = {
        "barcode": "3560070791460",
        "name": "Cream",
        "brand": None,
        "categories": ["makeup"],
        "pnns_group": None,
        "image_url": None,
        "source": "beauty",
        "product_type": "beauty",
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan(barcode="3560070791460")

    assert resp.status_code == 200
    assert resp.json()["suggested_category"] == "cleaning-hygiene"


def test_scan_tuna_petfood_defers_none():
    """source=petfood + tonno → suggested None (oggi canned-fish)."""
    payload = {
        "barcode": "1234567890123",
        "name": "Tonno per gatti",
        "brand": None,
        "categories": ["tuna"],
        "pnns_group": None,
        "image_url": None,
        "source": "petfood",
        "product_type": "petfood",
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan(barcode="1234567890123")

    assert resp.status_code == 200
    assert resp.json()["suggested_category"] is None


def test_scan_propagates_pnns_group():
    """pnns_group da fetch_product esposto in ScanResponse."""
    payload = {
        "barcode": "8076809514381",
        "name": "Latte Intero",
        "brand": None,
        "categories": ["organic", "vegan"],
        "pnns_group": "milk-and-dairy-products",
        "image_url": None,
    }

    with patch("backend.routes.scan.fetch_product") as mock_fetch:
        mock_fetch.return_value = payload
        resp = _call_scan()

    assert resp.status_code == 200
    body = resp.json()
    assert body["found"] is True
    assert body["pnns_group"] == "milk-and-dairy-products"


def test_scan_forwards_source_to_suggest_category():
    """Wiring: scan inoltra source a suggest_category (oggi chiamata a 2 args)."""
    payload = {
        "barcode": "3560070791460",
        "name": "Cream",
        "brand": None,
        "categories": ["makeup"],
        "pnns_group": None,
        "image_url": None,
        "source": "beauty",
        "product_type": "beauty",
    }

    with (
        patch("backend.routes.scan.fetch_product") as mock_fetch,
        patch("backend.routes.scan.suggest_category") as mock_suggest,
    ):
        mock_fetch.return_value = payload
        mock_suggest.return_value = None
        resp = _call_scan(barcode="3560070791460")

    assert resp.status_code == 200
    mock_suggest.assert_called_once_with(
        ["makeup"], None, source="beauty", product_type="beauty"
    )
