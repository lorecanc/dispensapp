"""Casi T9: comparti non-food e persistenza source/product_type (solo test)."""

from backend.models import Pantry
from backend.services.compartment import infer_compartment

VALID_TOKEN = "00000000-0000-0000-0000-000000000000"
HEADERS = {"X-Pantry-Token": VALID_TOKEN}


def _create_pantry(db_session):
    p = Pantry(id=1, name="La mia dispensa", owner_token=VALID_TOKEN)
    db_session.add(p)
    db_session.commit()
    return p


def test_infer_shampoos_to_igiene_casa():
    assert infer_compartment(off_category_tags=["en:shampoos"]) == "Igiene e Casa"


def test_infer_dog_food_to_dispensa_secca():
    assert infer_compartment(off_category_tags=["en:dog-food"]) == "Animali"
    assert infer_compartment(name="Crocchette dog-food") == "Animali"


def test_inventory_source_product_type_persisted(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/pantries/1/inventory",
        json={
            "barcode": "3560070791460",
            "name": "Cream",
            "source": "beauty",
            "product_type": "beauty",
        },
        headers=HEADERS,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["source"] == "beauty"
    assert data["product_type"] == "beauty"
    got = client.get(
        f"/api/pantries/1/inventory/{data['id']}", headers=HEADERS
    )
    assert got.status_code == 200
    assert got.json()["source"] == "beauty"
    assert got.json()["product_type"] == "beauty"
