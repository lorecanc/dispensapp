from typing import Optional

import httpx

from backend.config import OFF_BASE_URL


async def fetch_product(barcode: str) -> Optional[dict]:
    url = f"{OFF_BASE_URL}/{barcode}.json"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            data = response.json()
    except (httpx.HTTPError, httpx.TimeoutException, ValueError):
        return None

    product = data.get("product")
    status = data.get("status")
    if status != 1 or product is None:
        return None

    return {
        "barcode": barcode,
        "name": product.get("product_name", ""),
        "brand": product.get("brands") or None,
        "categories": product.get("categories_tags", []),
        "image_url": product.get("image_front_small_url") or None,
    }
