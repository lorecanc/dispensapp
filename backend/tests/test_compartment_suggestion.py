"""Test per le funzioni pure di suggerimento in backend/services/compartment.py."""

from backend.services.compartment import storage_for_category, suggest_category


# --- storage_for_category --------------------------------------------------

def test_storage_yogurts_frigo():
    assert storage_for_category("yogurts") == "frigo"


def test_storage_frozen_freezer():
    assert storage_for_category("frozen-foods") == "freezer"


def test_storage_pasta_dispensa():
    assert storage_for_category("pasta") == "dispensa"


def test_storage_none_fallback_dispensa():
    assert storage_for_category(None) == "dispensa"


def test_storage_unknown_fallback_dispensa():
    assert storage_for_category("sconosciuta") == "dispensa"


# --- suggest_category ------------------------------------------------------

def test_suggest_frozen_override_wins_even_if_canned_first():
    # "frozen-foods" normalizza da OFF_TO_INTERNAL; l'override freezer deve
    # vincere anche se il tag canned appare prima nella lista
    assert suggest_category(["en:canned-vegetables", "en:frozen-foods"]) == "frozen-foods"


def test_suggest_canned_without_frozen():
    assert suggest_category(["en:canned-vegetables"]) == "canned-vegetables"


def test_suggest_first_tag_in_compartment_map():
    # "italian-cuisine" non è una categoria nota: va saltato, "pasta" vince
    assert suggest_category(["en:italian-cuisine", "en:pasta"]) == "pasta"


def test_suggest_tags_win_over_pnns():
    assert suggest_category(["en:pasta"], "milk-and-dairy-products") == "pasta"


def test_suggest_pnns_fallback_milk():
    assert suggest_category(None, "milk-and-dairy-products") == "fresh-milk"


def test_suggest_pnns_fallback_fish_meat_eggs():
    assert suggest_category(None, "fish-meat-eggs") == "meat"


def test_suggest_nothing_matches_returns_none():
    # "composite-foods" è escluso intenzionalmente da PNNS_TO_INTERNAL
    assert suggest_category(["en:italian-cuisine"], "composite-foods") is None


def test_suggest_ignores_non_string_tags():
    # signature tipa list[str], ma il runtime deve essere difensivo
    assert suggest_category([None, 42, "en:pasta"]) == "pasta"  # type: ignore[list-item]


def test_suggest_empty_pnns_skipped():
    assert suggest_category([], "") is None
