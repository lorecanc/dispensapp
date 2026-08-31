import os
from pathlib import Path

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

# Registry etichette IT allineato a ios CategoryRegistry (chiavi = DEFAULT_SHELF_LIFE senza "default")
CATEGORY_LABELS = {
    "yogurts": "Yogurt",
    "fresh-milk": "Latte fresco",
    "pasta": "Pasta",
    "canned-vegetables": "Verdure in scatola",
    "rice": "Riso",
    "cheeses": "Formaggi",
    "eggs": "Uova",
    "fresh-fruits": "Frutta fresca",
    "fresh-vegetables": "Verdura fresca",
    "frozen-foods": "Surgelati",
}

# Alias legacy -> canonico (normalizzazione categorie)
# es. OFF o dati legacy possono contenere "yogurt" singolare; canonical è "yogurts"
CATEGORY_ALIASES: dict[str, str] = {
    "yogurt": "yogurts",
}


def normalize_category(key: str | None) -> str | None:
    """Normalizza chiave categoria a forma canonica (lower, alias)."""
    if key is None:
        return None
    k = key.strip().lower()
    if not k:
        return None
    # gestisce prefisso lingua tipo "en:yogurt" già splittato altrove, ma per sicurezza
    k = k.split(":")[-1].strip().lower()
    return CATEGORY_ALIASES.get(k, k)

# DATABASE_URL configurabile via env var; default risolto come path assoluto
# rispetto al file (non CWD) per evitare file sparsi in directory diverse.
_DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "inventory.db"
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{_DEFAULT_DB_PATH}")
OFF_BASE_URL = "https://world.openfoodfacts.org/api/v0/product"
# CORS allowlist ristretta: solo localhost per sviluppo + domini da env var.
# Imposta CORS_ORIGINS come lista comma-separated, es:
#   CORS_ORIGINS="https://app.example.com,https://admin.example.com"
# Se non impostata, sono permessi solo gli origin di sviluppo.
_env_origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
CORS_ORIGINS = [
    "http://localhost:3000",
    "http://localhost:5173",
    "http://localhost:8000",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:5173",
    "http://127.0.0.1:8000",
] + _env_origins
EXPIRING_SOON_DAYS = 3
ESTIMATED_NOTE = "⚠️ Scadenza stimata, potrebbe scadere prima"
