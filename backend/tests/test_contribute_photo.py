"""Tests for POST /api/scan/contribute/photo.

All Open Food Facts network calls are mocked (service layer or
httpx.AsyncClient). These tests never touch the production network.
"""

import logging
from unittest.mock import AsyncMock, Mock, patch

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.requests import Request

import backend.config as config
import backend.routes.contribute as contribute_module
from backend.main import app
from backend.services.off import upload_product_image

client = TestClient(app)

CODE = "8076809514381"
JPEG_BYTES = b"\xff\xd8\xff\xe0" + b"\x00" * 100
PNG_BYTES = b"\x89PNG\r\n\x1a\n" + b"\x00" * 100
HEIC_BYTES = b"\x00\x00\x00\x18ftypheic\x00\x00\x00\x00" + b"\x00" * 100


@pytest.fixture(autouse=True)
def _clean_rate_limit():
    contribute_module._RATE_LIMIT.clear()
    yield
    contribute_module._RATE_LIMIT.clear()


def _enable_write(monkeypatch, enabled=True):
    monkeypatch.setattr(config, "OFF_WRITE_ENABLED", enabled)


def _post_photo(code=CODE, imagefield="front_it", consent="true",
                filename="front.jpg", content=JPEG_BYTES, mime="image/jpeg"):
    return client.post(
        "/api/scan/contribute/photo",
        data={"code": code, "imagefield": imagefield, "consent_cc_bysa": consent},
        files={"image": (filename, content, mime)},
    )


def test_photo_disabled_returns_403_without_calling_off(monkeypatch):
    _enable_write(monkeypatch, False)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo()
    assert resp.status_code == 403
    mock_upload.assert_not_called()


def test_photo_consent_false_returns_400_without_calling_off(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(consent="false")
    assert resp.status_code == 400
    mock_upload.assert_not_called()


def test_photo_invalid_imagefield_returns_422(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(imagefield="face")
    assert resp.status_code == 422
    mock_upload.assert_not_called()


def test_photo_invalid_code_returns_422(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(code="not-a-barcode!")
    assert resp.status_code == 422
    mock_upload.assert_not_called()


def test_photo_too_large_returns_413(monkeypatch):
    _enable_write(monkeypatch, True)
    big = b"\xff\xd8\xff" + b"\x00" * (5 * 1024 * 1024 + 1)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(content=big)
    assert resp.status_code == 413
    mock_upload.assert_not_called()


@pytest.mark.asyncio
async def test_photo_declared_content_length_oversize_returns_413_without_reading_body(
    monkeypatch,
):
    _enable_write(monkeypatch, True)
    # Test diretto del pre-check fail-fast senza TestClient: evita il
    # ricalcolo automatico dell'header content-length.
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/api/scan/contribute/photo",
        "headers": [(b"content-length", str(6 * 1024 * 1024).encode())],
        "client": ("testclient", 50000),
    }
    request = Request(scope)
    read_mock = AsyncMock(side_effect=AssertionError("body must not be read"))
    image = Mock(content_type="image/jpeg", filename="front.jpg")
    image.read = read_mock
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        with pytest.raises(HTTPException) as exc_info:
            await contribute_module.contribute_scan_photo(
                request,
                code=CODE,
                imagefield="front_it",
                consent_cc_bysa=True,
                image=image,
            )
    assert exc_info.value.status_code == 413
    mock_upload.assert_not_called()
    read_mock.assert_not_called()


def test_photo_unsupported_type_returns_415(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(
            filename="note.txt", content=b"hello world", mime="text/plain"
        )
    assert resp.status_code == 415
    mock_upload.assert_not_called()


def test_photo_content_type_magic_mismatch_returns_415(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        # dichiarato PNG ma bytes JPEG
        resp = _post_photo(
            filename="front.png", content=JPEG_BYTES, mime="image/png"
        )
    assert resp.status_code == 415
    mock_upload.assert_not_called()


def test_photo_success_returns_200(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ) as mock_upload:
        resp = _post_photo()
    assert resp.status_code == 200
    assert resp.json()["ok"] is True
    assert resp.json()["code"] == CODE
    mock_upload.assert_awaited_once()


def test_photo_success_png_returns_200(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ) as mock_upload:
        resp = _post_photo(filename="front.png", content=PNG_BYTES, mime="image/png")
    assert resp.status_code == 200
    assert resp.json()["ok"] is True
    mock_upload.assert_awaited_once()


def test_photo_success_heic_returns_200(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ) as mock_upload:
        resp = _post_photo(filename="front.heic", content=HEIC_BYTES, mime="image/heic")
    assert resp.status_code == 200
    mock_upload.assert_awaited_once()


def test_photo_heif_alias_returns_200(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ) as mock_upload:
        resp = _post_photo(filename="front.heif", content=HEIC_BYTES, mime="image/heif")
    assert resp.status_code == 200
    mock_upload.assert_awaited_once()


def test_photo_mif1_major_with_heic_compat_returns_200(monkeypatch):
    _enable_write(monkeypatch, True)
    content = b"\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00heic" + b"\x00" * 100
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ) as mock_upload:
        resp = _post_photo(filename="front.heic", content=content, mime="image/heic")
    assert resp.status_code == 200
    mock_upload.assert_awaited_once()


def test_photo_mif1_major_without_heic_compat_returns_415(monkeypatch):
    _enable_write(monkeypatch, True)
    content = b"\x00\x00\x00\x18ftypmif1\x00\x00\x00\x00mif1" + b"\x00" * 100
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(filename="front.heic", content=content, mime="image/heic")
    assert resp.status_code == 415
    mock_upload.assert_not_called()


def test_photo_empty_file_returns_415(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image", new=AsyncMock()
    ) as mock_upload:
        resp = _post_photo(filename="front.jpg", content=b"", mime="image/jpeg")
    assert resp.status_code == 415
    mock_upload.assert_not_called()


def test_photo_off_rejection_returns_502(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 0, "reason": "no code"}),
    ):
        resp = _post_photo()
    assert resp.status_code == 502


def test_photo_transport_error_returns_502(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(side_effect=httpx.ConnectError("conn refused")),
    ):
        resp = _post_photo()
    assert resp.status_code == 502


def test_photo_rate_limited_returns_429(monkeypatch):
    _enable_write(monkeypatch, True)
    with patch(
        "backend.routes.contribute.upload_product_image",
        new=AsyncMock(return_value={"status": 1, "reason": None}),
    ):
        for _ in range(10):
            assert _post_photo().status_code == 200
        resp = _post_photo()
    assert resp.status_code == 429


@pytest.mark.asyncio
async def test_upload_product_image_posts_multipart(monkeypatch):
    import backend.services.off as off_module

    monkeypatch.setattr(off_module, "OFF_USER", "testuser")
    monkeypatch.setattr(off_module, "OFF_PASS", "s3cret-test-pw")
    monkeypatch.setattr(
        off_module, "OFF_WRITE_BASE_URL", "https://world.openfoodfacts.net/cgi"
    )
    monkeypatch.setattr(off_module, "OFF_APP_NAME", "DispensApp")
    monkeypatch.setattr(off_module, "OFF_APP_VERSION", "0.1.0")
    monkeypatch.setattr(off_module, "OFF_CONTACT_EMAIL", "test@example.com")

    resp = Mock(spec=httpx.Response)
    resp.raise_for_status.return_value = None
    resp.json.return_value = {"status": 1}
    capture = {}

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

    with patch("backend.services.off.httpx.AsyncClient", return_value=cm):
        result = await upload_product_image(
            code=CODE,
            image_bytes=JPEG_BYTES,
            filename="front.jpg",
            mime="image/jpeg",
            imagefield="front_it",
        )

    assert result == {"status": 1, "reason": None}
    assert capture["url"].endswith("/product_image_upload.pl")
    assert capture["data"]["code"] == CODE
    assert capture["data"]["imagefield"] == "front_it"
    assert capture["data"]["user_id"] == "testuser"
    assert capture["data"]["password"] == "s3cret-test-pw"
    assert "DispensApp/0.1.0" in capture["headers"]["User-Agent"]
    name, payload, mime = capture["files"]["imgupload_front_it"]
    assert name == "front.jpg"
    assert payload == JPEG_BYTES
    assert mime == "image/jpeg"


@pytest.mark.asyncio
async def test_upload_product_image_never_logs_password(monkeypatch, caplog):
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
                await upload_product_image(
                    code=CODE,
                    image_bytes=JPEG_BYTES,
                    filename="front.jpg",
                    mime="image/jpeg",
                    imagefield="front_it",
                )

    assert fake_pw not in caplog.text
