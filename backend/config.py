DEFAULT_SHELF_LIFE = {
    "yogurts": 14,
    "fresh-milk": 7,
    "pasta": 365,
    "canned-vegetables": 730,
    "rice": 365,
    "cheeses": 30,
    "eggs": 21,
    "fresh-fruits": 7,
    "fresh-vegetables": 7,
    "frozen-foods": 90,
    "default": 30,
}

DATABASE_URL = "sqlite:///./inventory.db"
OFF_BASE_URL = "https://world.openfoodfacts.org/api/v0/product"
CORS_ORIGINS = ["*"]
EXPIRING_SOON_DAYS = 3
ESTIMATED_NOTE = "⚠️ Scadenza stimata, potrebbe scadere prima"
