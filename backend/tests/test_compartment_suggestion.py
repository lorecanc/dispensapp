"""Test per le funzioni pure di suggerimento in backend/services/compartment.py."""

from backend.services.compartment import infer_compartment, storage_for_category, suggest_category


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


# --- T1 RED: smistamento automatico categorie dispensa (source-aware) --------
# suggest_category oggi ignora `source`: questi test usano il parametro
# `source` desiderato e falliscono (TypeError) finché la produzione non lo
# accetta. Non toccare produzione in T1.

def test_makeup_maps_cleaning_hygiene_via_source():
    assert suggest_category(["en:makeup"], source="beauty") == "cleaning-hygiene"


def test_petfood_defers_none_not_cleaning():
    assert suggest_category(["en:pet-food", "en:dog-food"], source="petfood") is None
    assert infer_compartment(off_category_tags=["en:dog-food"]) == "Dispensa Secca"


def test_tuna_source_guard_food_vs_petfood():
    assert suggest_category(["en:tuna"], source="food") == "canned-fish"
    assert suggest_category(["en:tuna"], source="petfood") is None


def test_product_empty_tags_escapes():
    assert suggest_category(["en:product", "en:electronics", "en:cable"], source="product") is None


def test_pnns_transits_through_create():
    assert suggest_category(["en:organic"], "milk-and-dairy-products", source="food") == "fresh-milk"
    assert suggest_category(["en:organic"], None, source="food") is None


# --- T1 RED falsificanti C7c -------------------------------------------------

def test_explicit_spuria_pippo_pasta():
    assert suggest_category(["en:pippo", "en:pasta"], source="food") == "pasta"


def test_product_laptop_defers_none():
    assert suggest_category(["en:product", "en:laptop"], source="product") is None


def test_petfood_chicken_defers_none():
    assert suggest_category(["en:petfood", "en:chicken"], source="petfood") is None


def test_beauty_empty_defers_none():
    assert suggest_category([], None, source="beauty") is None


def test_pnns_composite_foods_defers_none():
    assert suggest_category(["en:italian-cuisine"], "composite-foods", source="food") is None
