from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest

from backend.services.off import fetch_product


def _mock_response(data: dict, status_code: int = 200) -> Mock:
    """Build a synchronous mock httpx.Response."""
    resp = Mock(spec=httpx.Response)
    resp.status_code = status_code
    resp.raise_for_status.return_value = None
    resp.json.return_value = data
    return resp


def _patch_client(resp: Mock):
    """Return a patched `httpx.AsyncClient` whose `.get()` returns *resp*."""
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.return_value = resp

    async def aenter(*args, **kwargs):
        return client_mock

    cm = Mock()
    cm.__aenter__ = aenter
    cm.__aexit__ = AsyncMock(return_value=False)

    patcher = patch("httpx.AsyncClient", return_value=cm)
    return patcher


@pytest.mark.asyncio
async def test_fetch_product_valid():
    """Valid product returns name, brand, categories, image_url."""
    data = {
        "status": 1,
        "product": {
            "product_name": "Spaghetti",
            "brands": "Barilla",
            "categories_tags": ["en:pasta", "en:italian-cuisine"],
            "image_front_small_url": "https://example.com/pic.jpg",
        },
    }
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("8076809514381")

    assert result == {
        "barcode": "8076809514381",
        "name": "Spaghetti",
        "brand": "Barilla",
        "categories": ["pasta", "italian-cuisine"],
        "image_url": "https://example.com/pic.jpg",
    }


@pytest.mark.asyncio
async def test_fetch_product_not_found():
    """Product missing from OFF (status 0) returns {'found': False}."""
    data = {"status": 0, "product": None}
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("0000000000000")

    assert result == {"found": False}


@pytest.mark.asyncio
async def test_fetch_product_not_found_no_product():
    """Product key missing / product is None returns {'found': False}."""
    data = {"status": 1, "product": None}
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("0000000000000")

    assert result == {"found": False}


@pytest.mark.asyncio
async def test_fetch_product_network_error():
    """Network/HTTP error returns None."""
    client_mock = AsyncMock()
    client_mock.get.side_effect = httpx.HTTPError("connection failed")

    async def aenter(*args, **kwargs):
        return client_mock

    cm = Mock()
    cm.__aenter__ = aenter
    cm.__aexit__ = AsyncMock(return_value=False)

    with patch("httpx.AsyncClient", return_value=cm):
        result = await fetch_product("8076809514381")

    assert result is None


@pytest.mark.asyncio
async def test_fetch_product_categories_normalization():
    """Categories have 'en:' prefix stripped."""
    data = {
        "status": 1,
        "product": {
            "product_name": "Penne",
            "categories_tags": ["en:pasta", "en:tomato-sauce"],
            "brands": "",
            "image_front_small_url": None,
        },
    }
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("1234567890123")

    assert result["categories"] == ["pasta", "tomato-sauce"]
