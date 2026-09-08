"""Regression tests per gap upload OpenFoodFacts (implementati, verdi).

Tutti i test mockano httpx.AsyncClient: mai rete reale.
- T2a: part multipart deve chiamarsi imgupload_{imagefield}
- T2b: lang=it-IT deve inviare lc=it & lang=it (2 lettere), senza cc spurio
- T2c: risposta OFF {"status": "status ok"} (stringa) deve valere successo (status=1)
"""

from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest

import backend.services.off as off_module
from backend.services.off import contribute_product, upload_product_image

CODE = "8076809514381"
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 100


def _make_post_patcher(monkeypatch, response_data: dict, capture: dict):
    """Patcha backend.services.off.httpx.AsyncClient catturando url/data/files/headers."""
    monkeypatch.setattr(off_module, "OFF_USER", "testuser")
    monkeypatch.setattr(off_module, "OFF_PASS", "s3cret-test-pw")
    monkeypatch.setattr(off_module, "OFF_WRITE_BASE_URL", "https://world.openfoodfacts.net/cgi")
    monkeypatch.setattr(off_module, "OFF_APP_NAME", "DispensApp")
    monkeypatch.setattr(off_module, "OFF_APP_VERSION", "0.1.0")

    resp = Mock(spec=httpx.Response)
    resp.raise_for_status.return_value = None
    resp.json.return_value = response_data

    client_mock = AsyncMock(spec=httpx.AsyncClient)

    async def _post(url, data=None, files=None, headers=None, **kwargs):
        capture.update(url=url, data=data, files=files, headers=headers)
        return resp

    client_mock.post.side_effect = _post

    async def aenter(*args, **kwargs):
        return client_mock

    cm = Mock()
    cm.__aenter__ = aenter
    cm.__aexit__ = AsyncMock(return_value=False)
    return patch("backend.services.off.httpx.AsyncClient", return_value=cm)


@pytest.mark.asyncio
async def test_image_part_name_imgupload_field(monkeypatch):
    """upload_product_image deve inviare part imgupload_{imagefield}."""
    capture: dict = {}
    patcher = _make_post_patcher(monkeypatch, {"status": 1}, capture)
    with patcher:
        await upload_product_image(
            code=CODE,
            image_bytes=JPEG_BYTES,
            filename="nutrition.jpg",
            mime="image/jpeg",
            imagefield="nutrition_it",
        )
    # Spec OFF: il campo file si chiama imgupload_{imagefield}
    assert "imgupload_nutrition_it" in capture["files"], (
        f"atteso part 'imgupload_nutrition_it', trovate chiavi: {sorted(capture['files'].keys())}"
    )


@pytest.mark.asyncio
async def test_lang_truncates_to_2_letters(monkeypatch):
    """contribute con lang=it-IT deve inviare lc=it & lang=it, senza cc spurio."""
    capture: dict = {}
    patcher = _make_post_patcher(monkeypatch, {"status": 1}, capture)
    with patcher:
        await contribute_product(code=CODE, product_name="Spaghetti", lang="it-IT")
    form = capture["data"]
    assert form.get("lc") == "it", f"atteso lc='it', got {form.get('lc')!r}"
    assert form.get("lang") == "it", f"atteso lang='it', got {form.get('lang')!r}"
    assert "cc" not in form, f"cc spurio non deve essere inviato, got cc={form.get('cc')!r}"


@pytest.mark.asyncio
async def test_upload_parses_string_status_ok(monkeypatch):
    """Risposta OFF {'status': 'status ok'} (stringa) deve valere successo."""
    capture: dict = {}
    patcher = _make_post_patcher(monkeypatch, {"status": "status ok"}, capture)
    with patcher:
        result = await upload_product_image(
            code=CODE,
            image_bytes=JPEG_BYTES,
            filename="front.jpg",
            mime="image/jpeg",
            imagefield="front_it",
        )
    assert result["status"] == 1, (
        f"atteso status=1 per 'status ok', got {result['status']!r} (reason={result.get('reason')!r})"
    )
