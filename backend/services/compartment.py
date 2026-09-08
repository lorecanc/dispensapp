from __future__ import annotations

import logging
import re

from backend.config import (
    CATEGORY_ALIASES,
    CATEGORY_STORAGE_DEFAULT,
    COMPARTMENT_MAP,
    DEFAULT_STORAGE,
    GENERIC_OPF,
    HUMAN_FOOD_ONLY,
    OFF_TO_INTERNAL,
    PNNS_TO_INTERNAL,
    SUPER_MARKET_COMPARTMENTS,
    normalize_category,
)

logger = logging.getLogger(__name__)

# Ordine supermercato per ordinamento sezioni markdown
SUPERMARKET_ORDER: list[str] = list(SUPER_MARKET_COMPARTMENTS)

DEFAULT_COMPARTMENT = "Dispensa Secca"


def _log_safe(v: object, limit: int = 64) -> str:
    return re.sub(r"[\r\n]+", " ", str(v))[:limit]

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
    (["crocchette", "pet-food", "dog-food", "cat-food"], "Animali"),
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


def _normalize_source(value: str | None) -> str | None:
    if not isinstance(value, str):
        return None
    v = value.strip().lower()
    return v or None


def _is_generic_opf(norm: str) -> bool:
    if norm in GENERIC_OPF:
        return True
    # regola substring "productsfacts" senza qualificatore (vive qui, non in config)
    compact = norm.replace("-", "").replace("_", "")
    return "productsfacts" in compact


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
    source: str | None = None,
    product_type: str | None = None,
) -> str | None:
    """Proponi categoria interna da tag OFF e gruppo PNNS.

    Cascata:
    1) tag filtrati (via GENERIC_OPF) + source-guard petfood
    2) override conservazione: frozen-foods vince su canned-vegetables/canned-fish
    3) primo tag filtrato che mappa a una chiave di COMPARTMENT_MAP
    4) PNNS_TO_INTERNAL su pnns_group (con guard petfood)
    5) None se nulla matcha (defer, mai default di categoria)

    DEBT: pnns-forward-ios-mancante, GENERIC_OPF parziale,
    keyword-pet senza categoria.
    """
    raw_tags = list(off_category_tags or []) if off_category_tags else []
    normalized = [
        norm
        for tag in raw_tags
        if isinstance(tag, str) and (norm := _normalize_tag(tag))
    ]
    # C2: filtra tag generici OPF prima del match
    filtered = [n for n in normalized if not _is_generic_opf(n)]

    src = _normalize_source(source)
    ptype = _normalize_source(product_type)
    is_petfood = src == "petfood" or ptype == "petfood"
    is_product = src == "product" or ptype == "product"

    # C3a/C4a: petfood esclude HUMAN_FOOD_ONLY; soli tag pet/food -> defer
    if is_petfood:
        filtered = [n for n in filtered if n not in HUMAN_FOOD_ONLY]

    def _defer(reason: str) -> str | None:
        # C7a: warning con source/tags/pnns/esito, nessun PII oltre barcode (non disponibile qui)
        logger.warning(
            "suggest_category defer (%s): source=%s product_type=%s tags=%s pnns=%s esito=None",
            _log_safe(reason, 64),
            _log_safe(src, 32),
            _log_safe(ptype, 32),
            [_log_safe(t, 200) for t in raw_tags[:50]],
            _log_safe(pnns_group, 64),
        )
        return None

    # 2) override conservazione sui tag filtrati
    if "frozen-foods" in filtered:
        return "frozen-foods"
    for norm in filtered:
        if norm in ("canned-vegetables", "canned-fish"):
            return norm

    # 3) primo tag filtrato che mappa a categoria nota
    for norm in filtered:
        if norm in COMPARTMENT_MAP:
            # C2c: cleaning-hygiene mai da source==product da solo
            if norm == "cleaning-hygiene" and is_product:
                return _defer("cleaning-bloccato-per-product")
            return norm

    # 4) fallback PNNS (con guard petfood su HUMAN_FOOD_ONLY)
    if isinstance(pnns_group, str) and pnns_group:
        if is_petfood and pnns_group in HUMAN_FOOD_ONLY:
            return _defer("pnns-human-food-escluso-per-petfood")
        mapped = PNNS_TO_INTERNAL.get(pnns_group)
        if mapped is not None:
            if mapped == "cleaning-hygiene" and is_product:
                return _defer("cleaning-bloccato-per-product")
            return mapped

    # 5) nessun suggerimento
    return _defer("nessun-match")
