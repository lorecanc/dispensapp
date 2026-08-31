import logging
from typing import Optional

import httpx

from backend.config import OFF_BASE_URL

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
