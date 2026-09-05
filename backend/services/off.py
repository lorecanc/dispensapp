import logging
from typing import Optional

import httpx

from backend.config import (
    OFF_APP_NAME,
    OFF_APP_VERSION,
    OFF_BASE_URL,
    OFF_CONTACT_EMAIL,
    OFF_PASS,
    OFF_USER,
    OFF_WRITE_BASE_URL,
    off_basic_auth,
    off_user_agent,
)

logger = logging.getLogger(__name__)


def _normalize_lang(lang: str) -> str:
    raw = (lang or "it").strip().lower().replace("_", "-") or "it"
    return (raw.split("-")[0][:2] or "it")


def _parse_off_status(data: dict) -> int:
    status = data.get("status", 0)
    if isinstance(status, str):
        if status.strip().lower() in ("ok", "status ok"):
            return 1
    try:
        return int(status)
    except (TypeError, ValueError):
        return 0


_read_client: Optional[httpx.AsyncClient] = None


def _get_client() -> httpx.AsyncClient:
    """Client httpx condiviso per le letture OFF, creato alla prima richiesta."""
    global _read_client
    if _read_client is None:
        _read_client = httpx.AsyncClient(timeout=10.0)
    return _read_client


async def fetch_product(barcode: str) -> Optional[dict]:
    url = f"{OFF_BASE_URL}/{barcode}.json"
    try:
        response = await _get_client().get(url)
        response.raise_for_status()
        data = response.json()
    except (httpx.HTTPError, httpx.TimeoutException, ValueError) as exc:
        logger.warning("OFF fetch failed for %s: %s", barcode, exc)
        return None

    product = data.get("product")
    status = data.get("status")
    if status != 1 or product is None:
        return {"found": False}

    # pnns_groups_1: testo libero ("Milk and dairy products") o tag "en:…";
    # normalizziamo a slug lowercase con trattini per combaciare con le chiavi
    # di PNNS_TO_INTERNAL (config). Le enumerazioni con virgola ("Fish, meat
    # and eggs") perdono virgole e connettore "and": la tassonomia OFF live
    # canonizza quel gruppo come "Fish Meat Eggs" -> slug "fish-meat-eggs".
    # None se assente/vuoto/non stringa.
    raw_pnns = product.get("pnns_groups_1")
    pnns_group = None
    if isinstance(raw_pnns, str):
        slug = raw_pnns.split(":")[-1].strip().lower()
        if "," in slug:
            slug = slug.replace(",", "").replace(" and ", " ")
        pnns_group = slug.replace(" ", "-") or None

    return {
        "barcode": barcode,
        "name": product.get("product_name", ""),
        "brand": product.get("brands") or None,
        "categories": [c.split(":")[-1] for c in product.get("categories_tags", [])],
        "pnns_group": pnns_group,
        "image_url": product.get("image_front_small_url") or None,
    }


async def contribute_product(
    code: str,
    product_name: Optional[str] = None,
    brands: Optional[str] = None,
    categories: Optional[str] = None,
    labels: Optional[str] = None,
    quantity: Optional[str] = None,
    generic_name: Optional[str] = None,
    lang: str = "it",
    comment: Optional[str] = None,
    app_uuid: Optional[str] = None,
) -> dict:
    """Invia metadati a OFF (staging di default) via product_jqm2.pl.

    Usa solo campi add_* per brands/categories/labels, mai quelli nudi.
    Non logga mai la password. Ritorna {"status": int, "reason": str | None}.
    Solleva httpx.HTTPError su errori di trasporto (il chiamante mappa a 502).
    """
    url = f"{OFF_WRITE_BASE_URL}/product_jqm2.pl"
    lang = _normalize_lang(lang)
    form: dict[str, str] = {
        "code": code,
        "user_id": OFF_USER,
        "password": OFF_PASS,
        "lc": lang,
        "lang": lang,
        "comment": comment or f"Contributo via {OFF_APP_NAME} {OFF_APP_VERSION}",
        "app_name": OFF_APP_NAME,
        "app_version": OFF_APP_VERSION,
    }
    if app_uuid:
        form["app_uuid"] = app_uuid
    if product_name:
        form[f"product_name_{lang}"] = product_name
    if generic_name:
        form[f"generic_name_{lang}"] = generic_name
    if brands:
        form["add_brands"] = brands
    if categories:
        form["add_categories"] = categories
    if labels:
        form["add_labels"] = labels
    if quantity:
        form["quantity"] = quantity
    user_agent = off_user_agent()
    basic_auth = off_basic_auth(OFF_WRITE_BASE_URL)
    post_kwargs: dict = {"headers": {"User-Agent": user_agent}}
    if basic_auth is not None:
        post_kwargs["auth"] = basic_auth
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(url, data=form, **post_kwargs)
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, dict):
                raise ValueError("OFF unexpected response")
    except (httpx.HTTPError, ValueError) as exc:
        # Mai includere la password nei log
        logger.warning("OFF contribute failed for %s: %s", code, exc)
        raise
    status = _parse_off_status(data)
    reason = data.get("status_verbose") or data.get("reason")
    logger.info("OFF contribute for %s: status=%s", code, status)
    return {"status": status, "reason": reason}


async def upload_product_image(
    code: str,
    image_bytes: bytes,
    filename: str,
    mime: str,
    imagefield: str,
) -> dict:
    """Invia una foto a OFF (staging di default) via product_image_upload.pl.

    Riusa credenziali OFF_USER/OFF_PASS e User-Agent app. Non logga mai
    la password né i bytes dell'immagine. Ritorna {"status": int, "reason": str | None}.
    Solleva httpx.HTTPError su errori di trasporto (il chiamante mappa a 502).
    """
    url = f"{OFF_WRITE_BASE_URL}/product_image_upload.pl"
    form: dict[str, str] = {
        "code": code,
        "imagefield": imagefield,
        "user_id": OFF_USER,
        "password": OFF_PASS,
    }
    user_agent = off_user_agent()
    files = {f"imgupload_{imagefield}": (filename or "upload", image_bytes, mime)}
    basic_auth = off_basic_auth(OFF_WRITE_BASE_URL)
    post_kwargs = {"data": form, "files": files, "headers": {"User-Agent": user_agent}}
    if basic_auth is not None:
        post_kwargs["auth"] = basic_auth
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(url, **post_kwargs)
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, dict):
                raise ValueError("OFF unexpected response")
    except (httpx.HTTPError, ValueError) as exc:
        # Mai includere password o bytes nei log
        logger.warning("OFF image upload failed for %s (%s): %s", code, imagefield, exc)
        raise
    status = _parse_off_status(data)
    reason = data.get("status_verbose") or data.get("reason")
    logger.info("OFF image upload for %s (%s): status=%s", code, imagefield, status)
    return {"status": status, "reason": reason}
