from backend.models import Pantry

VALID_TOKEN = "00000000-0000-0000-0000-000000000000"
HEADERS = {"X-Pantry-Token": VALID_TOKEN}


def _create_pantry(db_session):
    p = Pantry(id=1, name="La mia dispensa", owner_token=VALID_TOKEN)
    db_session.add(p)
    db_session.commit()
    return p


def test_inventory_create_quantity_zero_422(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/inventory",
        json={"barcode": "12345678", "name": "Latte", "quantity": 0},
        headers=HEADERS,
    )
    assert resp.status_code == 422


def test_inventory_create_quantity_1000_422(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/inventory",
        json={"barcode": "12345678", "name": "Latte", "quantity": 1000},
        headers=HEADERS,
    )
    assert resp.status_code == 422


def test_inventory_create_quantity_negative_422(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/inventory",
        json={"barcode": "12345678", "name": "Latte", "quantity": -5},
        headers=HEADERS,
    )
    assert resp.status_code == 422


def test_inventory_manual_quantity_out_of_range_422(client, db_session):
    _create_pantry(db_session)
    for q in [0, 1000, -1]:
        resp = client.post("/api/inventory/manual", json={"name": "Latte", "quantity": q}, headers=HEADERS)
        assert resp.status_code == 422, f"quantity {q} should be 422"


def test_inventory_create_quantity_valid_boundaries():
    from backend.schemas import InventoryCreate
    import pytest

    # valid
    InventoryCreate(barcode="12345678", name="Latte", quantity=1)
    InventoryCreate(barcode="12345678", name="Latte", quantity=999)
    # invalid via schema should raise
    with pytest.raises(Exception):
        InventoryCreate(barcode="12345678", name="Latte", quantity=0)
    with pytest.raises(Exception):
        InventoryCreate(barcode="12345678", name="Latte", quantity=1000)


def test_barcode_invalid_short_422_scan(client):
    resp = client.post("/api/scan", json={"barcode": "1234567"})
    assert resp.status_code == 422


def test_barcode_invalid_long_422_scan(client):
    resp = client.post("/api/scan", json={"barcode": "123456789012345"})
    assert resp.status_code == 422


def test_barcode_invalid_alpha_422_scan(client):
    resp = client.post("/api/scan", json={"barcode": "ABC12345"})
    assert resp.status_code == 422


def test_barcode_invalid_inventory_create_422(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/inventory",
        json={"barcode": "123", "name": "Latte", "quantity": 1},
        headers=HEADERS,
    )
    assert resp.status_code == 422
    resp2 = client.post(
        "/api/inventory",
        json={"barcode": "abcdefgh", "name": "Latte", "quantity": 1},
        headers=HEADERS,
    )
    assert resp2.status_code == 422


def test_name_empty_422_inventory(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/inventory",
        json={"barcode": "12345678", "name": "", "quantity": 1},
        headers=HEADERS,
    )
    assert resp.status_code == 422
    resp2 = client.post(
        "/api/inventory",
        json={"barcode": "12345678", "name": "   ", "quantity": 1},
        headers=HEADERS,
    )
    assert resp2.status_code == 422


def test_name_empty_422_manual(client, db_session):
    _create_pantry(db_session)
    resp = client.post("/api/inventory/manual", json={"name": "", "quantity": 1}, headers=HEADERS)
    assert resp.status_code == 422
    resp2 = client.post("/api/inventory/manual", json={"name": "   ", "quantity": 1}, headers=HEADERS)
    assert resp2.status_code == 422


def test_name_missing_422(client, db_session):
    _create_pantry(db_session)
    resp = client.post("/api/inventory/manual", json={"quantity": 1}, headers=HEADERS)
    assert resp.status_code == 422


def test_shopping_list_name_empty_422(client, db_session):
    # create pantry first
    from backend.models import Pantry

    p = Pantry(id=1, name="La mia dispensa", owner_token="00000000-0000-0000-0000-000000000000")
    db_session.add(p)
    db_session.commit()
    headers = {"X-Pantry-Token": "00000000-0000-0000-0000-000000000000"}
    resp = client.post("/api/pantries/1/shopping-lists", json={"name": ""}, headers=headers)
    assert resp.status_code == 422
    resp2 = client.post("/api/pantries/1/shopping-lists", json={"name": "   "}, headers=headers)
    assert resp2.status_code == 422
