from fastapi import APIRouter

from backend.config import (
    CATEGORY_LABELS,
    COMPARTMENT_MAP,
    DEFAULT_SHELF_LIFE,
    STORAGE_LOCATION_LABELS,
    SUPER_MARKET_COMPARTMENTS,
)
from backend.services.compartment import storage_for_category

router = APIRouter(prefix="/api", tags=["categories"])


@router.get("/categories")
def list_categories():
    """Registry pubblico categorie + shelf life + comparti supermercato."""
    categories = [
        {
            "key": key,
            "label": CATEGORY_LABELS.get(key, key),
            "shelf_life_days": days,
            "compartment": COMPARTMENT_MAP.get(key),
            "storage_location": storage_for_category(key),
        }
        for key, days in DEFAULT_SHELF_LIFE.items()
        if key != "default"
    ]
    return {
        "categories": categories,
        "default_shelf_life_days": DEFAULT_SHELF_LIFE["default"],
        "labels": CATEGORY_LABELS,
        "compartments": SUPER_MARKET_COMPARTMENTS,
        "compartment_map": COMPARTMENT_MAP,
        "storage_location_labels": STORAGE_LOCATION_LABELS,
    }


@router.get("/compartments")
def list_compartments():
    """Lista comparti supermercato ordinata."""
    return {
        "compartments": SUPER_MARKET_COMPARTMENTS,
        "compartment_map": COMPARTMENT_MAP,
    }
