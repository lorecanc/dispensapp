from backend.models import Pantry

VALID_TOKEN = "00000000-0000-0000-0000-000000000000"
HEADERS = {"X-Pantry-Token": VALID_TOKEN}


def _create_pantry(db_session):
    p = Pantry(id=1, name="La mia dispensa", owner_token=VALID_TOKEN)
    db_session.add(p)
    db_session.commit()
    return p


# --- Contratto create: auto-assegnazione categoria dai tag OFF ---


def test_create_auto_assigns_category_from_off_tags(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/pantries/1/inventory",
        json={
            "barcode": "12345678",
            "name": "Yogurt bianco",
            "off_category_tags": ["en:yogurts"],
        },
        headers=HEADERS,
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["category"] == "yogurts"
    # conferma via GET sul singolo elemento
    resp2 = client.get(f"/api/pantries/1/inventory/{data['id']}", headers=HEADERS)
    assert resp2.status_code == 200
    assert resp2.json()["category"] == "yogurts"


def test_create_explicit_category_wins_over_off_tags(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/pantries/1/inventory",
        json={
            "barcode": "12345678",
            "name": "Pasta",
            "category": "pasta",
            "off_category_tags": ["en:yogurts"],
        },
        headers=HEADERS,
    )
    assert resp.status_code == 201
    assert resp.json()["category"] == "pasta"


# --- Contratto create/update: storage_location ---


def test_create_storage_location_echo(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/pantries/1/inventory",
        json={
            "barcode": "12345678",
            "name": "Gelato",
            "storage_location": "freezer",
        },
        headers=HEADERS,
    )
    assert resp.status_code == 201
    assert resp.json()["storage_location"] == "freezer"
    # senza campo -> NULL (derivazione lasciata al client, by design)
    resp2 = client.post(
        "/api/pantries/1/inventory",
        json={"barcode": "87654321", "name": "Acqua"},
        headers=HEADERS,
    )
    assert resp2.status_code == 201
    assert resp2.json()["storage_location"] is None


def test_patch_storage_location_not_reset_by_later_patch(client, db_session):
    _create_pantry(db_session)
    resp = client.post(
        "/api/pantries/1/inventory/manual",
        json={"name": "Affettato"},
        headers=HEADERS,
    )
    assert resp.status_code == 201
    item_id = resp.json()["id"]
    assert resp.json()["storage_location"] is None
    patch = client.patch(
        f"/api/pantries/1/inventory/{item_id}",
        json={"storage_location": "frigo"},
        headers=HEADERS,
    )
    assert patch.status_code == 200
    assert patch.json()["storage_location"] == "frigo"
    # PATCH successivo senza il campo non deve azzerarlo (exclude_unset)
    patch2 = client.patch(
        f"/api/pantries/1/inventory/{item_id}",
        json={"quantity": 3},
        headers=HEADERS,
    )
    assert patch2.status_code == 200
    assert patch2.json()["storage_location"] == "frigo"


# --- Boundary 422 off_category_tags su entrambi gli endpoint create ---


def test_off_category_tags_too_many_422(client, db_session):
    _create_pantry(db_session)
    tags = [f"en:tag{i}" for i in range(51)]
    resp = client.post(
        "/api/pantries/1/inventory",
        json={"barcode": "12345678", "name": "Prodotto", "off_category_tags": tags},
        headers=HEADERS,
    )
    assert resp.status_code == 422
    resp2 = client.post(
        "/api/pantries/1/inventory/manual",
        json={"name": "Prodotto", "off_category_tags": tags},
        headers=HEADERS,
    )
    assert resp2.status_code == 422


def test_off_category_tag_too_long_422(client, db_session):
    _create_pantry(db_session)
    long_tag = "x" * 201
    resp = client.post(
        "/api/pantries/1/inventory",
        json={"barcode": "12345678", "name": "Prodotto", "off_category_tags": [long_tag]},
        headers=HEADERS,
    )
    assert resp.status_code == 422
    resp2 = client.post(
        "/api/pantries/1/inventory/manual",
        json={"name": "Prodotto", "off_category_tags": [long_tag]},
        headers=HEADERS,
    )
    assert resp2.status_code == 422
