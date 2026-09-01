from __future__ import annotations

from backend.config import (
    CATEGORY_ALIASES,
    COMPARTMENT_MAP,
    OFF_TO_INTERNAL,
    SUPER_MARKET_COMPARTMENTS,
)

# Ordine supermercato per ordinamento sezioni markdown
SUPERMARKET_ORDER: list[str] = list(SUPER_MARKET_COMPARTMENTS)

DEFAULT_COMPARTMENT = "Dispensa Secca"

# Keyword fallback su nome prodotto (lower)
_KEYWORD_MAP: list[tuple[list[str], str]] = [
    (["mela", "pera", "banana", "frutta", "verdura", "insalata", "pomodoro", "zucchina", "carota", "patata", "cipolla", "agrumi", "kiwi", "uva"], "Ortofrutta"),
    (["latte", "yogurt", "uovo", "uova", "burro", "panna"], "Latticini e Uova"),
    (["formaggio", "parmigiano", "mozzarella", "salame", "prosciutto", "affettato", "salumi"], "Salumi e Formaggi"),
    (["pollo", "manzo", "maiale", "carne", "bistecca", "salsiccia", "pesce", "salmone", "tonno fresco", "merluzzo", "gamber"], "Carne e Pesce"),
    (["surgelat", "gelato", "bastoncini", "piselli surgelati"], "Surgelati"),
    (["pane", "panino", "brioche", "cornetto", "focaccia", "baguette", "forno", "pasticceria"], "Forno e Panetteria"),
    (["acqua", "succo", "bevanda", "bibita", "cola", "aranciata", "caffè", "caffe", "tè", "the", "tisana"], "Bevande"),
    (["vino", "birra", "prosecco", "champagne", "whisky", "vodka", "liquore", "alcol"], "Cantina"),
    (["detersivo", "sapone", "shampoo", "bagnoschiuma", "dentifricio", "candeggina", "igiene", "puliz"], "Igiene e Casa"),
]


def _normalize_tag(tag: str) -> str | None:
    if not tag:
        return None
    k = tag.strip().lower()
    if not k:
        return None
    k = k.split(":")[-1].strip().lower()
    # OFF_TO_INTERNAL prima, poi alias
    k = OFF_TO_INTERNAL.get(k, k)
    k = CATEGORY_ALIASES.get(k, k)
    return k or None


def infer_compartment(
    name: str | None = None,
    category: str | None = None,
    off_category_tags: list[str] | None = None,
) -> str:
    """Inferisci comparto supermercato.

    Cascata:
    1) match OFF tags -> categoria interna -> COMPARTMENT_MAP
    2) category esplicita -> COMPARTMENT_MAP
    3) keyword su name
    4) default Dispensa Secca
    """
    # 1) OFF tags hanno priorità
    if off_category_tags:
        for tag in off_category_tags:
            norm = _normalize_tag(tag)
            if norm and norm in COMPARTMENT_MAP:
                return COMPARTMENT_MAP[norm]

    # 2) categoria interna esplicita
    if category:
        norm = _normalize_tag(category)
        if norm and norm in COMPARTMENT_MAP:
            return COMPARTMENT_MAP[norm]

    # 3) keyword su nome
    if name:
        low = name.strip().lower()
        if low:
            for keywords, compartment in _KEYWORD_MAP:
                for kw in keywords:
                    if kw in low:
                        return compartment

    # 4) default
    return DEFAULT_COMPARTMENT
