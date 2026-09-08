"""Test per GET /api/categories (registry pubblico categorie)."""

from backend.config import (
    CATEGORY_LABELS,
    DEFAULT_SHELF_LIFE,
    STORAGE_LOCATION_LABELS,
    SUPER_MARKET_COMPARTMENTS,
)

EXPECTED_ENTRY_KEYS = {
    "key",
    "label",
    "shelf_life_days",
    "compartment",
    "storage_location",
}


def _get_categories(client):
    resp = client.get("/api/categories")
    assert resp.status_code == 200
    return resp.json()


def test_categories_storage_location_non_null_for_every_entry(client):
    """Ogni entry espone storage_location non-null tra i valori ammessi."""
    body = _get_categories(client)
    allowed = set(STORAGE_LOCATION_LABELS.keys())
    assert allowed  # guardia: lista non vuota
    for entry in body["categories"]:
        assert entry["storage_location"] is not None
        assert entry["storage_location"] in allowed, entry["key"]


def test_categories_storage_location_coherent(client):
    """Coerenza sui casi noti: yogurts→frigo, frozen-foods→freezer, pasta→dispensa."""
    body = _get_categories(client)
    by_key = {e["key"]: e for e in body["categories"]}
    assert by_key["yogurts"]["storage_location"] == "frigo"
    assert by_key["frozen-foods"]["storage_location"] == "freezer"
    assert by_key["pasta"]["storage_location"] == "dispensa"


def test_categories_storage_location_labels_top_level(client):
    """Top-level storage_location_labels presente con le 3 chiavi note."""
    body = _get_categories(client)
    labels = body["storage_location_labels"]
    assert set(labels.keys()) == {"frigo", "freezer", "dispensa"}
    assert labels == STORAGE_LOCATION_LABELS


def test_categories_preexisting_fields_unchanged(client):
    """Campi preesistenti (chiavi entry e payload) invariati dopo l'aggiunta."""
    body = _get_categories(client)
    # chiavi top-level storiche ancora presenti
    assert body["default_shelf_life_days"] == DEFAULT_SHELF_LIFE["default"]
    assert body["labels"] == CATEGORY_LABELS
    assert body["compartments"] == SUPER_MARKET_COMPARTMENTS
    assert "compartment_map" in body
    # una entry per categoria del registry, senza "default"
    assert len(body["categories"]) == len(CATEGORY_LABELS)
    for entry in body["categories"]:
        assert set(entry.keys()) == EXPECTED_ENTRY_KEYS
        assert entry["key"] != "default"
    # spot-check su pasta: etichetta, shelf life e comparto invariati
    pasta = next(e for e in body["categories"] if e["key"] == "pasta")
    assert pasta["label"] == "Pasta"
    assert pasta["shelf_life_days"] == 365
    assert pasta["compartment"] == "Dispensa Secca"
    # spot-check first-class Animali
    animali = next(e for e in body["categories"] if e["key"] == "animali")
    assert animali["label"] == "Animali"
    assert animali["shelf_life_days"] == 365
    assert animali["compartment"] == "Animali"
    assert animali["storage_location"] == "dispensa"
