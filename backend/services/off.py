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
)

logger = logging.getLogger(__name__)


async def fetch_product(barcode: str) -> Optional[dict]:
    url = f"{OFF_BASE_URL}/{barcode}.json"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            data = response.json()
    except (httpx.HTTPError, httpx.TimeoutException, ValueError) as exc:
        logger.warning("OFF fetch failed for %s: %s", barcode, exc)
        return None

    product = data.get("product")
    status = data.get("status")
    if status != 1 or product is None:
        return {"found": False}

    return {
        "barcode": barcode,
        "name": product.get("product_name", ""),
        "brand": product.get("brands") or None,
        "categories": [c.split(":")[-1] for c in product.get("categories_tags", [])],
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
    lang = (lang or "it").strip().lower() or "it"
    form: dict[str, str] = {
        "code": code,
        "user_id": OFF_USER,
        "password": OFF_PASS,
        "lc": lang,
        "cc": lang,
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
    contact = OFF_CONTACT_EMAIL.strip() if OFF_CONTACT_EMAIL else ""
    user_agent = f"{OFF_APP_NAME}/{OFF_APP_VERSION} ({contact})" if contact else f"{OFF_APP_NAME}/{OFF_APP_VERSION}"
    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            response = await client.post(url, data=form, headers={"User-Agent": user_agent})
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, dict):
                raise ValueError("OFF unexpected response")
    except (httpx.HTTPError, ValueError) as exc:
        # Mai includere la password nei log
        logger.warning("OFF contribute failed for %s: %s", code, exc)
        raise
    status = data.get("status", 0)
    try:
        status = int(status)
    except (TypeError, ValueError):
        status = 0
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
    contact = OFF_CONTACT_EMAIL.strip() if OFF_CONTACT_EMAIL else ""
    user_agent = f"{OFF_APP_NAME}/{OFF_APP_VERSION} ({contact})" if contact else f"{OFF_APP_NAME}/{OFF_APP_VERSION}"
    files = {"image": (filename or "upload", image_bytes, mime)}
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(url, data=form, files=files, headers={"User-Agent": user_agent})
            response.raise_for_status()
            data = response.json()
            if not isinstance(data, dict):
                raise ValueError("OFF unexpected response")
    except (httpx.HTTPError, ValueError) as exc:
        # Mai includere password o bytes nei log
        logger.warning("OFF image upload failed for %s (%s): %s", code, imagefield, exc)
        raise
    status = data.get("status", 0)
    try:
        status = int(status)
    except (TypeError, ValueError):
        status = 0
    reason = data.get("status_verbose") or data.get("reason")
    logger.info("OFF image upload for %s (%s): status=%s", code, imagefield, status)
    return {"status": status, "reason": reason}
