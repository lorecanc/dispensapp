from fastapi import APIRouter

from backend.config import CATEGORY_LABELS, DEFAULT_SHELF_LIFE

router = APIRouter(prefix="/api", tags=["categories"])


@router.get("/categories")
def list_categories():
    """Registry pubblico categorie + shelf life."""
    categories = [
        {
            "key": key,
            "label": CATEGORY_LABELS.get(key, key),
            "shelf_life_days": days,
        }
        for key, days in DEFAULT_SHELF_LIFE.items()
        if key != "default"
    ]
    return {
        "categories": categories,
        "default_shelf_life_days": DEFAULT_SHELF_LIFE["default"],
        "labels": CATEGORY_LABELS,
    }
