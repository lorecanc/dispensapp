from datetime import date, timedelta
from typing import Optional

from backend.config import CATEGORY_ALIASES, DEFAULT_SHELF_LIFE, EXPIRING_SOON_DAYS, OFF_TO_INTERNAL


def get_status(expiration_date: Optional[date]) -> str:
    """Ritorna status centrale: ok | expiring_soon | expired."""
    if expiration_date is None:
        return "ok"
    today = date.today()
    if expiration_date < today:
        return "expired"
    if expiration_date <= today + timedelta(days=EXPIRING_SOON_DAYS):
        return "expiring_soon"
    return "ok"


def estimate_expiration(
    category_tags: Optional[list[str]] = None,
    reference_date: Optional[date] = None,
) -> date:
    if reference_date is None:
        reference_date = date.today()

    matched_days = DEFAULT_SHELF_LIFE["default"]

    if category_tags:
        # Strip whitespace and discard empty/whitespace-only entries
        category_tags = [t.strip() for t in category_tags if t.strip()]
        for tag in category_tags:
            # Strip language prefix (e.g. "en:pasta" -> "pasta") before matching
            normalized = tag.split(":")[-1].lower().strip()
            # stesso path di normalize_category: prima OFF_TO_INTERNAL, poi CATEGORY_ALIASES
            normalized = OFF_TO_INTERNAL.get(normalized, normalized)
            normalized = CATEGORY_ALIASES.get(normalized, normalized)
            for key, days in DEFAULT_SHELF_LIFE.items():
                if key != "default" and key == normalized:
                    matched_days = days
                    break
            if matched_days != DEFAULT_SHELF_LIFE["default"]:
                break

    return reference_date + timedelta(days=matched_days)


def resolve_expiration(
    expiration_date: Optional[date] = None,
    category: Optional[str] = None,
    off_category_tags: Optional[list[str]] = None,
    reference_date: Optional[date] = None,
    allow_none: bool = False,
) -> tuple[Optional[date], bool]:
    """Centralizza logica scadenza per create_inventory / create_manual.

    - Se expiration_date è fornita -> ritorna (date, False).
    - Altrimenti normalizza tags (lower, strip, split :, dedup, alias) unendo
      category + off_category_tags e stima con DEFAULT_SHELF_LIFE (fallback default).
    - Se nessun tag utile e allow_none True -> ritorna (None, False) per manual
      senza categoria; altrimenti fallback default stimato.
    """
    if expiration_date is not None:
        return expiration_date, False

    # Collect raw tags
    raw_tags: list[str] = []
    if category and category.strip():
        raw_tags.append(category)
    if off_category_tags:
        raw_tags.extend([t for t in off_category_tags if t and t.strip()])

    # Normalizza: lower, strip, split ":", alias, dedup preservando ordine
    seen: set[str] = set()
    normalized_tags: list[str] = []
    for t in raw_tags:
        stripped = t.strip().lower()
        if not stripped:
            continue
        norm = stripped.split(":")[-1].strip().lower()
        # stesso path di normalize_category: prima OFF_TO_INTERNAL, poi CATEGORY_ALIASES
        norm = OFF_TO_INTERNAL.get(norm, norm)
        norm = CATEGORY_ALIASES.get(norm, norm)
        if not norm or norm in seen:
            continue
        seen.add(norm)
        normalized_tags.append(norm)

    # Se nessun tag: allow_none -> None, altrimenti fallback default stimato
    if not normalized_tags:
        if allow_none:
            return None, False
        if reference_date is None:
            reference_date = date.today()
        return reference_date + timedelta(days=DEFAULT_SHELF_LIFE["default"]), True

    # Usa estimate_expiration con tags normalizzati (già alias-normalizzati, match ==)
    estimated = estimate_expiration(category_tags=normalized_tags, reference_date=reference_date)
    return estimated, True
