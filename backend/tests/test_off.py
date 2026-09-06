import importlib
import logging
import os
from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest

from backend.services import off
from backend.services.off import fetch_product

# Fixture documentate: gemelli OFF (usate solo come barcode, nessun live call).
OPF_BARCODE = "3760044183738"  # product (Open Products Facts)
OBF_BARCODE = "3560070791460"  # beauty (Open Beauty Facts)


@pytest.fixture(autouse=True)
def _reset_shared_client():
    """Keep tests independent from the module-level cached AsyncClient."""
    off._read_client = None
    yield
    off._read_client = None


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

    return patch("httpx.AsyncClient", return_value=client_mock)


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
        "pnns_group": None,
        "image_url": "https://example.com/pic.jpg",
        "source": "product",
        "product_type": "product",
    }


@pytest.mark.asyncio
async def test_fetch_product_v3_url_and_product_type_all():
    """GET v3 universale: URL /api/v3/product/<barcode> con ?product_type=all."""
    data = {"status": 1, "product": {"product_name": "X"}}
    resp = _mock_response(data)
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.return_value = resp

    with patch("httpx.AsyncClient", return_value=client_mock):
        await fetch_product(OPF_BARCODE)

    args, kwargs = client_mock.get.call_args
    assert f"/api/v3/product/{OPF_BARCODE}" in args[0]
    assert kwargs["params"] == {"product_type": "all"}


@pytest.mark.asyncio
async def test_fetch_product_pnns_free_text():
    """pnns_groups_1 free text is slugified to a PNNS_TO_INTERNAL key."""
    data = {
        "status": 1,
        "product": {
            "product_name": "Yogurt bianco",
            "brands": "",
            "categories_tags": [],
            "pnns_groups_1": "Milk and dairy products",
            "image_front_small_url": None,
        },
    }
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("1234567890123")

    assert result["pnns_group"] == "milk-and-dairy-products"


@pytest.mark.asyncio
async def test_fetch_product_pnns_free_text_with_comma():
    """Comma in free text must not leak into the slug: "Fish, meat and eggs" -> "fish-meat-eggs"."""
    data = {
        "status": 1,
        "product": {
            "product_name": "Pollo intero",
            "brands": "",
            "categories_tags": [],
            "pnns_groups_1": "Fish, meat and eggs",
            "image_front_small_url": None,
        },
    }
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("1234567890123")

    assert result["pnns_group"] == "fish-meat-eggs"


@pytest.mark.asyncio
async def test_fetch_product_pnns_tag_prefix():
    """Tag form "en:sugary-snacks" keeps the "en:" prefix stripped."""
    data = {
        "status": 1,
        "product": {
            "product_name": "Cioccolato",
            "brands": "",
            "categories_tags": [],
            "pnns_groups_1": "en:sugary-snacks",
            "image_front_small_url": None,
        },
    }
    resp = _mock_response(data)
    patcher = _patch_client(resp)

    with patcher:
        result = await fetch_product("1234567890123")

    assert result["pnns_group"] == "sugary-snacks"


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

    with patch("httpx.AsyncClient", return_value=client_mock):
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


@pytest.mark.asyncio
async def test_fetch_product_uses_shared_client():
    """Bug B6: consecutive fetches must reuse one AsyncClient, not rebuild it."""
    data = {
        "status": 1,
        "product": {
            "product_name": "Penne",
            "brands": None,
            "categories_tags": [],
            "image_front_small_url": None,
        },
    }
    resp = _mock_response(data)
    client_mock = AsyncMock()
    client_mock.get.return_value = resp
    # old code used `async with httpx.AsyncClient() as client` -> keep RED assertive
    client_mock.__aenter__ = AsyncMock(return_value=client_mock)
    client_mock.__aexit__ = AsyncMock(return_value=False)

    with patch("httpx.AsyncClient", return_value=client_mock) as ctor:
        await fetch_product("1234567890123")
        await fetch_product("1234567890123")

    assert ctor.call_count <= 1


@pytest.mark.asyncio
async def test_fetch_product_opf_source_product():
    """Fixture OPF: product_type product propagato come source/product_type."""
    data = {
        "status": 1,
        "product_type": "product",
        "product": {"product_name": "Cable", "brands": "", "categories_tags": []},
    }
    with _patch_client(_mock_response(data)):
        result = await fetch_product(OPF_BARCODE)

    assert result["source"] == "product"
    assert result["product_type"] == "product"


@pytest.mark.asyncio
async def test_fetch_product_obf_source_beauty():
    """Fixture OBF: product_type beauty propagato come source/product_type."""
    data = {
        "status": 1,
        "product_type": "beauty",
        "product": {"product_name": "Cream", "brands": "", "categories_tags": []},
    }
    with _patch_client(_mock_response(data)):
        result = await fetch_product(OBF_BARCODE)

    assert result["source"] == "beauty"
    assert result["product_type"] == "beauty"


@pytest.mark.asyncio
async def test_fetch_product_non_food_no_pnns():
    """Non-food (beauty) senza pnns_groups_1: pnns_group None."""
    data = {
        "status": 1,
        "product_type": "beauty",
        "product": {"product_name": "Cream", "brands": "", "categories_tags": []},
    }
    with _patch_client(_mock_response(data)):
        result = await fetch_product(OBF_BARCODE)

    assert result["pnns_group"] is None


@pytest.mark.asyncio
async def test_fetch_product_retry_once_on_500_then_none():
    """500 persistente: esattamente 1 retry (2 GET) poi None."""
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.side_effect = [_mock_response({}, 500), _mock_response({}, 500)]

    with (
        patch("httpx.AsyncClient", return_value=client_mock),
        patch("backend.services.off.asyncio.sleep", new=AsyncMock()),
    ):
        result = await fetch_product(OPF_BARCODE)

    assert result is None
    assert client_mock.get.call_count == 2


@pytest.mark.asyncio
async def test_fetch_product_retry_once_on_timeout_then_none():
    """Timeout persistente: esattamente 1 retry (2 GET) poi None."""
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.side_effect = httpx.TimeoutException("timeout")

    with (
        patch("httpx.AsyncClient", return_value=client_mock),
        patch("backend.services.off.asyncio.sleep", new=AsyncMock()),
    ):
        result = await fetch_product(OPF_BARCODE)

    assert result is None
    assert client_mock.get.call_count == 2


@pytest.mark.asyncio
async def test_fetch_product_no_retry_on_404():
    """404: nessun retry (1 solo GET), ritorna found False."""
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.return_value = _mock_response({}, 404)

    with patch("httpx.AsyncClient", return_value=client_mock):
        result = await fetch_product(OPF_BARCODE)

    assert result == {"found": False}
    assert client_mock.get.call_count == 1


@pytest.mark.asyncio
async def test_fetch_product_no_retry_on_found_false():
    """status 0: nessun retry (1 solo GET), ritorna found False."""
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.return_value = _mock_response({"status": 0, "product": None})

    with patch("httpx.AsyncClient", return_value=client_mock):
        result = await fetch_product(OPF_BARCODE)

    assert result == {"found": False}
    assert client_mock.get.call_count == 1


@pytest.mark.asyncio
async def test_fetch_product_url_v3_without_v0():
    """URL v3 universale senza alcun segmento v0."""
    data = {"status": 1, "product": {"product_name": "X"}}
    resp = _mock_response(data)
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.return_value = resp

    with patch("httpx.AsyncClient", return_value=client_mock):
        await fetch_product(OPF_BARCODE)

    args, _ = client_mock.get.call_args
    url = args[0]
    assert "/api/v3/product/" in url
    assert "v0" not in url


@pytest.mark.asyncio
async def test_fetch_product_read_user_agent_present():
    """Il client di lettura invia User-Agent con nome/versione app."""
    data = {"status": 1, "product": {"product_name": "X"}}
    resp = _mock_response(data)
    client_mock = AsyncMock(spec=httpx.AsyncClient)
    client_mock.get.return_value = resp

    with patch("httpx.AsyncClient", return_value=client_mock) as ctor:
        await fetch_product(OPF_BARCODE)

    _, kwargs = ctor.call_args
    ua = (kwargs.get("headers") or {}).get("User-Agent", "")
    assert off.OFF_APP_NAME in ua
    assert off.OFF_APP_VERSION in ua


@pytest.mark.asyncio
@pytest.mark.parametrize("bad", ["123", "1234567", "ABC12345", "", "12-34-56"])
async def test_fetch_product_invalid_barcode_no_network(bad):
    """Barcode corto/non-digit: None senza alcuna chiamata di rete."""
    with patch("httpx.AsyncClient") as ctor:
        result = await fetch_product(bad)

    assert result is None
    ctor.assert_not_called()


@pytest.mark.asyncio
async def test_fetch_product_categories_tags_none():
    """categories_tags None -> categories []."""
    data = {
        "status": 1,
        "product": {"product_name": "X", "categories_tags": None},
    }
    with _patch_client(_mock_response(data)):
        result = await fetch_product(OPF_BARCODE)

    assert result["categories"] == []


@pytest.mark.asyncio
async def test_fetch_product_categories_tags_string():
    """categories_tags stringa (non lista) -> categories [], mai crash."""
    data = {
        "status": 1,
        "product": {"product_name": "X", "categories_tags": "en:pasta"},
    }
    with _patch_client(_mock_response(data)):
        result = await fetch_product(OPF_BARCODE)

    assert result["categories"] == []


@pytest.mark.asyncio
async def test_fetch_product_categories_tags_mixed():
    """categories_tags mista: solo stringhe, prefisso lingua rimosso."""
    data = {
        "status": 1,
        "product": {
            "product_name": "X",
            "categories_tags": ["en:pasta", 42, None, "fr:riz"],
        },
    }
    with _patch_client(_mock_response(data)):
        result = await fetch_product(OPF_BARCODE)

    assert result["categories"] == ["pasta", "riz"]


@pytest.mark.asyncio
async def test_fetch_product_logs_requested_vs_resolved(caplog):
    """Il log distingue product_type richiesto da quello risolto."""
    data = {
        "status": 1,
        "product_type": "beauty",
        "product": {"product_name": "Cream"},
    }
    with _patch_client(_mock_response(data)):
        with caplog.at_level(logging.INFO, logger="backend.services.off"):
            await fetch_product(OBF_BARCODE)

    assert "requested=" in caplog.text
    assert "resolved=" in caplog.text
    assert "resolved=beauty" in caplog.text


def test_off_v3_base_url_allowlist_reject():
    """OFF_V3_BASE_URL non allowlist (o http) -> fallback al default."""
    import backend.config as cfg

    default = "https://world.openfoodfacts.org/api/v3/product"
    old = os.environ.get("OFF_V3_BASE_URL")
    try:
        os.environ["OFF_V3_BASE_URL"] = "https://evil.example.com/api/v3/product"
        importlib.reload(cfg)
        assert cfg.OFF_V3_BASE_URL == default
        os.environ["OFF_V3_BASE_URL"] = "http://world.openfoodfacts.org/api/v3/product"
        importlib.reload(cfg)
        assert cfg.OFF_V3_BASE_URL == default
    finally:
        if old is None:
            os.environ.pop("OFF_V3_BASE_URL", None)
        else:
            os.environ["OFF_V3_BASE_URL"] = old
        importlib.reload(cfg)
