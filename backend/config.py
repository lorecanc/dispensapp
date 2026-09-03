import logging
import os
from pathlib import Path
from urllib.parse import urlparse

logger = logging.getLogger(__name__)

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
    # nuove 16 categorie allineate OFF
    "legumes": 365,
    "uht-milk": 90,
    "cold-cuts": 14,
    "meat": 4,
    "fish": 2,
    "canned-fish": 730,
    "bread-bakery": 5,
    "flours": 180,
    "sauces-condiments": 365,
    "oils-vinegars": 540,
    "sweets-snacks": 180,
    "beverages-water": 365,
    "beverages-juices": 30,
    "coffee-tea": 365,
    "alcoholic-beverages": 1095,
    "cleaning-hygiene": 730,
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
    "legumes": "Legumi",
    "uht-milk": "Latte UHT",
    "cold-cuts": "Salumi e affettati",
    "meat": "Carne",
    "fish": "Pesce fresco",
    "canned-fish": "Pesce in scatola",
    "bread-bakery": "Pane e prodotti da forno",
    "flours": "Farine",
    "sauces-condiments": "Salse e condimenti",
    "oils-vinegars": "Oli e aceti",
    "sweets-snacks": "Dolci e snack",
    "beverages-water": "Acqua",
    "beverages-juices": "Succhi e bevande",
    "coffee-tea": "Caffè e tè",
    "alcoholic-beverages": "Bevande alcoliche",
    "cleaning-hygiene": "Igiene e pulizia",
}

# Alias legacy -> canonico (normalizzazione categorie)
# es. OFF o dati legacy possono contenere "yogurt" singolare; canonical è "yogurts"
CATEGORY_ALIASES: dict[str, str] = {
    "yogurt": "yogurts",
    "yogurts": "yogurts",
    "cheese": "cheeses",
    "milk": "fresh-milk",
    "uht-milks": "uht-milk",
    "legume": "legumes",
    "cold-cut": "cold-cuts",
    "canned-fishs": "canned-fish",
    "bread": "bread-bakery",
    "flour": "flours",
    "sauce": "sauces-condiments",
    "oil": "oils-vinegars",
    "sweet": "sweets-snacks",
    "snack": "sweets-snacks",
    "water": "beverages-water",
    "juice": "beverages-juices",
    "coffee": "coffee-tea",
    "tea": "coffee-tea",
    "alcohol": "alcoholic-beverages",
    "cleaning": "cleaning-hygiene",
    "hygiene": "cleaning-hygiene",
}

# Mapping OFF tags -> categoria interna canonica (normalizzazione ampia OFF)
OFF_TO_INTERNAL: dict[str, str] = {
    # latticini / uova
    "yogurts": "yogurts",
    "yogurt": "yogurts",
    "fresh-milk": "fresh-milk",
    "milk": "fresh-milk",
    "milks": "fresh-milk",
    "pasteurized-milk": "fresh-milk",
    "uht-milk": "uht-milk",
    "uht-milks": "uht-milk",
    "cheeses": "cheeses",
    "cheese": "cheeses",
    "eggs": "eggs",
    # ortofrutta / legumi
    "fresh-fruits": "fresh-fruits",
    "fruits": "fresh-fruits",
    "fresh-vegetables": "fresh-vegetables",
    "vegetables": "fresh-vegetables",
    "legumes": "legumes",
    "pulses": "legumes",
    "lentils": "legumes",
    # dispensa secca
    "pasta": "pasta",
    "pastas": "pasta",
    "rice": "rice",
    "canned-vegetables": "canned-vegetables",
    "flours": "flours",
    "flour": "flours",
    "sauces-condiments": "sauces-condiments",
    "sauces": "sauces-condiments",
    "condiments": "sauces-condiments",
    "oils-vinegars": "oils-vinegars",
    "oils": "oils-vinegars",
    "vinegars": "oils-vinegars",
    "sweets-snacks": "sweets-snacks",
    "sweets": "sweets-snacks",
    "snacks": "sweets-snacks",
    "biscuits": "sweets-snacks",
    "chocolate": "sweets-snacks",
    # salumi / carne / pesce
    "cold-cuts": "cold-cuts",
    "charcuterie": "cold-cuts",
    "hams": "cold-cuts",
    "salamis": "cold-cuts",
    "meat": "meat",
    "meats": "meat",
    "fish": "fish",
    "fishes": "fish",
    "canned-fish": "canned-fish",
    "tuna": "canned-fish",
    "sardines": "canned-fish",
    # forno
    "bread-bakery": "bread-bakery",
    "breads": "bread-bakery",
    "bakery": "bread-bakery",
    "pastries": "bread-bakery",
    # surgelati
    "frozen-foods": "frozen-foods",
    "frozen-food": "frozen-foods",
    # bevande
    "beverages-water": "beverages-water",
    "waters": "beverages-water",
    "water": "beverages-water",
    "beverages-juices": "beverages-juices",
    "juices": "beverages-juices",
    "juice": "beverages-juices",
    "coffee-tea": "coffee-tea",
    "coffees": "coffee-tea",
    "teas": "coffee-tea",
    "coffee": "coffee-tea",
    "tea": "coffee-tea",
    "alcoholic-beverages": "alcoholic-beverages",
    "alcohol": "alcoholic-beverages",
    "wines": "alcoholic-beverages",
    "beers": "alcoholic-beverages",
    "spirits": "alcoholic-beverages",
    # igiene
    "cleaning-hygiene": "cleaning-hygiene",
    "cleaning": "cleaning-hygiene",
    "hygiene": "cleaning-hygiene",
    "detergents": "cleaning-hygiene",
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
    # prima OFF_TO_INTERNAL, poi CATEGORY_ALIASES
    k = OFF_TO_INTERNAL.get(k, k)
    return CATEGORY_ALIASES.get(k, k)


# Comparti supermercato — ordine di percorrenza corsie
SUPER_MARKET_COMPARTMENTS: list[str] = [
    "Ortofrutta",
    "Latticini e Uova",
    "Salumi e Formaggi",
    "Carne e Pesce",
    "Surgelati",
    "Dispensa Secca",
    "Bevande",
    "Cantina",
    "Forno e Panetteria",
    "Igiene e Casa",
]

# Categoria interna -> comparto
COMPARTMENT_MAP: dict[str, str] = {
    "fresh-fruits": "Ortofrutta",
    "fresh-vegetables": "Ortofrutta",
    "yogurts": "Latticini e Uova",
    "fresh-milk": "Latticini e Uova",
    "uht-milk": "Latticini e Uova",
    "eggs": "Latticini e Uova",
    "cheeses": "Salumi e Formaggi",
    "cold-cuts": "Salumi e Formaggi",
    "meat": "Carne e Pesce",
    "fish": "Carne e Pesce",
    "canned-fish": "Dispensa Secca",
    "frozen-foods": "Surgelati",
    "pasta": "Dispensa Secca",
    "rice": "Dispensa Secca",
    "legumes": "Dispensa Secca",
    "canned-vegetables": "Dispensa Secca",
    "flours": "Dispensa Secca",
    "sauces-condiments": "Dispensa Secca",
    "oils-vinegars": "Dispensa Secca",
    "sweets-snacks": "Dispensa Secca",
    "beverages-water": "Bevande",
    "beverages-juices": "Bevande",
    "coffee-tea": "Bevande",
    "alcoholic-beverages": "Cantina",
    "bread-bakery": "Forno e Panetteria",
    "cleaning-hygiene": "Igiene e Casa",
}

# DATABASE_URL configurabile via env var; default risolto come path assoluto
# rispetto al file (non CWD) per evitare file sparsi in directory diverse.
_DEFAULT_DB_PATH = Path(__file__).resolve().parent.parent / "inventory.db"
DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{_DEFAULT_DB_PATH}")
OFF_BASE_URL = "https://world.openfoodfacts.org/api/v0/product"
# Scrittura OFF (contribuzione metadati): default staging .net, prod .org solo via env.
_off_write_default = "https://world.openfoodfacts.net/cgi"
_off_write_requested = os.getenv("OFF_WRITE_ENABLED", "false").lower() in ("1", "true", "yes", "on")
_raw_off_write_base_url = os.getenv("OFF_WRITE_BASE_URL", _off_write_default).rstrip("/")
_parsed = urlparse(_raw_off_write_base_url)
_host = (_parsed.hostname or "").lower()
_host_ok = _host.endswith("openfoodfacts.org") or _host.endswith("openfoodfacts.net")
_scheme_ok = _parsed.scheme == "https" or (
    _parsed.scheme == "http" and _host in ("localhost", "127.0.0.1")
)
_off_write_valid = _host_ok and _scheme_ok
if not _off_write_valid:
    logger.warning(
        "OFF_WRITE_BASE_URL non valido o insicuro (%s): fallback a staging default",
        _raw_off_write_base_url,
    )
OFF_WRITE_BASE_URL = _raw_off_write_base_url if _off_write_valid else _off_write_default
_off_write_insecure = not _off_write_valid
OFF_USER = os.getenv("OFF_USER", "")
OFF_PASS = os.getenv("OFF_PASS", "")
OFF_APP_NAME = os.getenv("OFF_APP_NAME", "DispensApp")
OFF_APP_VERSION = os.getenv("OFF_APP_VERSION", "0.1.0")
OFF_CONTACT_EMAIL = os.getenv("OFF_CONTACT_EMAIL", "")
if _off_write_requested and (not OFF_USER or not OFF_PASS):
    logger.warning("OFF_WRITE_ENABLED ma credenziali OFF_USER/OFF_PASS mancanti: scrittura disabilitata")
OFF_WRITE_ENABLED = _off_write_requested and bool(OFF_USER and OFF_PASS) and not _off_write_insecure
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
