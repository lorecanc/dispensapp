from datetime import date, timedelta
from typing import Optional

from backend.config import DEFAULT_SHELF_LIFE


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
            normalized = tag.split(":")[-1]
            for key, days in DEFAULT_SHELF_LIFE.items():
                if key != "default" and key in normalized:
                    matched_days = days
                    break
            if matched_days != DEFAULT_SHELF_LIFE["default"]:
                break

    return reference_date + timedelta(days=matched_days)
