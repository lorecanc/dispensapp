from __future__ import annotations

from backend.config import (
    CATEGORY_ALIASES,
    CATEGORY_STORAGE_DEFAULT,
    COMPARTMENT_MAP,
    DEFAULT_STORAGE,
    OFF_TO_INTERNAL,
    PNNS_TO_INTERNAL,
    SUPER_MARKET_COMPARTMENTS,
    normalize_category,
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
    (["pasta", "spaghetti", "riso", "farina", "olio", "passata", "pelati", "legumi", "ceci", "lenticchie", "fagioli", "biscotti", "cioccolato", "marmellata", "sale", "zucchero", "scatolame", "tonno"], "Dispensa Secca"),
    (["crocchette", "pet-food", "dog-food", "cat-food"], "Dispensa Secca"),
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


def storage_for_category(category: str | None) -> str:
    """Luogo di conservazione predefinito per categoria interna (fallback: DEFAULT_STORAGE)."""
    norm = normalize_category(category)
    if norm is None:
        return DEFAULT_STORAGE
    return CATEGORY_STORAGE_DEFAULT.get(norm, DEFAULT_STORAGE)


def suggest_category(
    off_category_tags: list[str] | None = None,
    pnns_group: str | None = None,
) -> str | None:
    """Proponi categoria interna da tag OFF e gruppo PNNS.

    Cascata:
    1) override conservazione: frozen-foods vince su canned-vegetables/canned-fish
    2) primo tag che normalizza a una chiave di COMPARTMENT_MAP
    3) PNNS_TO_INTERNAL su pnns_group (slug lowercase già normalizzato)
    4) None se nulla matcha
    """
    normalized = [
        norm
        for tag in (off_category_tags or [])
        if isinstance(tag, str) and (norm := _normalize_tag(tag))
    ]

    # 1) override conservazione (freezer prima dello scatolame)
    if "frozen-foods" in normalized:
        return "frozen-foods"
    for norm in normalized:
        if norm in ("canned-vegetables", "canned-fish"):
            return norm

    # 2) primo tag che mappa a una categoria nota
    for norm in normalized:
        if norm in COMPARTMENT_MAP:
            return norm

    # 3) fallback PNNS
    if isinstance(pnns_group, str) and pnns_group:
        return PNNS_TO_INTERNAL.get(pnns_group)

    # 4) nessun suggerimento
    return None
