import asyncio
import logging
import re
from typing import Optional

import httpx

from backend.config import (
    OFF_APP_NAME,
    OFF_APP_VERSION,
    OFF_CONTACT_EMAIL,
    OFF_PASS,
    OFF_PRODUCT_TYPE_DEFAULT,
    OFF_USER,
    OFF_V3_BASE_URL,
    OFF_V3_HOSTS,
    OFF_WRITE_BASE_URL,
    is_off_staging_base_url,
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
        norm = status.strip().lower()
        if norm in ("ok", "status ok", "success"):
            return 1
        if norm == "failure":
            return 0
        result = data.get("result")
        if isinstance(result, dict):
            rid = result.get("id")
            if isinstance(rid, str) and rid.strip().lower() == "product_found":
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
        _read_client = httpx.AsyncClient(timeout=10.0, headers={"User-Agent": off_user_agent()})
    return _read_client


def _resolve_product_source(data: dict, requested: str) -> str:
    """Deriva source/product_type da payload v3 o dal tipo richiesto.

    Cerca product_type/istanza nel payload (top-level o product); mappa
    host/istanze contenenti food/beauty/petfood/productsfacts al gemello
    corrispondente. Fallback al tipo richiesto se specifico, altrimenti
    "product" (mai "all").
    """
    candidates: list[str] = []
    if isinstance(data, dict):
        for key in ("product_type", "instance", "source"):
            val = data.get(key)
            if isinstance(val, str) and val.strip():
                candidates.append(val.strip().lower())
        product = data.get("product")
        if isinstance(product, dict):
            for key in ("product_type", "instance"):
                val = product.get(key)
                if isinstance(val, str) and val.strip():
                    candidates.append(val.strip().lower())
    for cand in candidates:
        if "beauty" in cand:
            return "beauty"
        if "petfood" in cand or "pet-food" in cand or "pet_food" in cand:
            return "petfood"
        if "productsfacts" in cand or cand == "product":
            return "product"
        if "food" in cand:
            return "food"
    if requested in ("food", "beauty", "petfood", "product"):
        return requested
    return "product"


async def _fetch_single_v3(url: str, params: dict, barcode: str) -> Optional[dict]:
    """Singolo GET v3 con max 1 retry su timeout/5xx/trasporto (~300ms)."""
    response: Optional[httpx.Response] = None
    for attempt in range(2):
        try:
            response = await _get_client().get(url, params=params)
        except httpx.HTTPError as exc:
            if attempt == 0:
                await asyncio.sleep(0.3)
                continue
            logger.warning("OFF fetch failed for %s: %s", barcode, exc)
            return None
        if response.status_code >= 500:
            if attempt == 0:
                await asyncio.sleep(0.3)
                continue
            logger.warning("OFF fetch failed for %s: 5xx %s", barcode, response.status_code)
            return None
        break
    if response is None:
        return None
    if response.status_code == 404:
        return {"found": False}
    try:
        response.raise_for_status()
        data = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("OFF fetch failed for %s: %s", barcode, exc)
        return None
    if not isinstance(data, dict):
        return None

    product = data.get("product")
    if _parse_off_status(data) != 1 or not isinstance(product, dict):
        return {"found": False}

    # pnns_groups_1: testo libero ("Milk and dairy products") o tag "en:…";
    # normalizziamo a slug lowercase con trattini per combaciare con le chiavi
    # di PNNS_TO_INTERNAL (config). Le enumerazioni con virgola ("Fish, meat
    # and eggs") perdono virgole e connettore "and": la tassonomia OFF live
    # canonizza quel gruppo come "Fish Meat Eggs" -> slug "fish-meat-eggs".
    # None se assente/vuoto/non stringa (atteso per non-food).
    raw_pnns = product.get("pnns_groups_1")
    pnns_group = None
    if isinstance(raw_pnns, str):
        slug = raw_pnns.split(":")[-1].strip().lower()
        if "," in slug:
            slug = slug.replace(",", "").replace(" and ", " ")
        pnns_group = slug.replace(" ", "-") or None

    requested = str(params.get("product_type", "all")).strip().lower() or "all"
    resolved = _resolve_product_source(data, requested)
    logger.info("OFF fetch %s requested=%s resolved=%s", barcode, requested, resolved)
    tags = product.get("categories_tags") or []
    if not isinstance(tags, list):
        tags = []
    return {
        "barcode": barcode,
        "name": product.get("product_name", ""),
        "brand": product.get("brands") or None,
        "categories": [c.split(":")[-1] for c in tags if isinstance(c, str)],
        "pnns_group": pnns_group,
        "image_url": product.get("image_front_small_url") or None,
        "source": resolved,
        "product_type": resolved,
    }


async def fetch_product(
    barcode: str, product_type: str = OFF_PRODUCT_TYPE_DEFAULT
) -> Optional[dict]:
    """Lettura v3 universale: singolo GET product_type=all (default).

    Il fallback per-host (OFF_V3_HOSTS) è usato solo con product_type
    esplicito != all e solo su fallimento trasporto/5xx del primo GET,
    mai su 404 o found=False e mai con fan-out parallelo.
    """
    if not re.fullmatch(r"^\d{8,14}$", barcode or ""):
        logger.warning("OFF fetch skipped for invalid barcode %s", barcode)
        return None
    requested = (product_type or OFF_PRODUCT_TYPE_DEFAULT).strip().lower() or "all"
    params = {"product_type": requested}
    result = await _fetch_single_v3(f"{OFF_V3_BASE_URL}/{barcode}", params, barcode)
    if result is not None:
        return result
    if requested != "all" and requested in OFF_V3_HOSTS:
        host = OFF_V3_HOSTS[requested]
        fallback_url = f"https://{host}/api/v3/product/{barcode}"
        return await _fetch_single_v3(fallback_url, params, barcode)
    return None


def resolve_write_url(product_type: Optional[str], base: str = OFF_WRITE_BASE_URL) -> str:
    pt = (product_type or "food").strip().lower() or "food"
    if is_off_staging_base_url(base):
        if pt in ("beauty", "petfood", "product"):
            # TODO(staging-twins): gemelli .net non verificati, per ora tutto a food staging.
            logger.warning(
                "OFF staging non-food POST a food staging con product_type=%s (gemelli .net non verificati)",
                pt,
            )
        return "https://world.openfoodfacts.net/cgi"
    host = {
        "food": "world.openfoodfacts.org",
        "beauty": "world.openbeautyfacts.org",
        "petfood": "world.openpetfoodfacts.org",
        "product": "world.openproductsfacts.org",
    }.get(pt, "world.openfoodfacts.org")
    return f"https://{host}/cgi"


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
    product_type: str = "food",
) -> dict:
    """Invia metadati a OFF (staging di default) via product_jqm2.pl.

    Usa solo campi add_* per brands/categories/labels, mai quelli nudi.
    Non logga mai la password. Ritorna {"status": int, "reason": str | None}.
    Solleva httpx.HTTPError su errori di trasporto (il chiamante mappa a 502).
    """
    base_url = resolve_write_url(product_type)
    pt = (product_type or "food").strip().lower() or "food"
    url = f"{base_url}/product_jqm2.pl"
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
        "product_type": pt,
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
    basic_auth = off_basic_auth(base_url)
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
    product_type: str = "food",
) -> dict:
    """Invia una foto a OFF (staging di default) via product_image_upload.pl.

    Riusa credenziali OFF_USER/OFF_PASS e User-Agent app. Non logga mai
    la password né i bytes dell'immagine. Ritorna {"status": int, "reason": str | None}.
    Solleva httpx.HTTPError su errori di trasporto (il chiamante mappa a 502).
    """
    base_url = resolve_write_url(product_type)
    url = f"{base_url}/product_image_upload.pl"
    form: dict[str, str] = {
        "code": code,
        "imagefield": imagefield,
        "user_id": OFF_USER,
        "password": OFF_PASS,
    }
    user_agent = off_user_agent()
    files = {f"imgupload_{imagefield}": (filename or "upload", image_bytes, mime)}
    basic_auth = off_basic_auth(base_url)
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
