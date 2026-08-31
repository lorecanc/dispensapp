from datetime import date, datetime, timedelta, timezone

from backend.models import InventoryItem, Pantry

VALID_TOKEN = "00000000-0000-0000-0000-000000000000"
OTHER_TOKEN = "11111111-1111-1111-1111-111111111111"
HEADERS = {"X-Pantry-Token": VALID_TOKEN}
OTHER_HEADERS = {"X-Pantry-Token": OTHER_TOKEN}
BAD_HEADERS = {"X-Pantry-Token": "not-a-uuid"}


def _create_pantry(db_session, pid=1):
    p = Pantry(id=pid, name="La mia dispensa", owner_token=VALID_TOKEN)
    db_session.add(p)
    db_session.commit()
    return p


def test_shopping_crud_and_toggle(client, db_session):
    _create_pantry(db_session)
    # create list
    resp = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa Test"}, headers=HEADERS)
    assert resp.status_code == 201
    lst = resp.json()
    assert lst["name"] == "Spesa Test"
    assert lst["pantry_id"] == 1
    list_id = lst["id"]

    # list all contains it
    resp2 = client.get("/api/pantries/1/shopping-lists", headers=HEADERS)
    assert resp2.status_code == 200
    assert any(l["id"] == list_id for l in resp2.json())

    # get single
    resp3 = client.get(f"/api/pantries/1/shopping-lists/{list_id}", headers=HEADERS)
    assert resp3.status_code == 200
    assert resp3.json()["items"] == []

    # add item
    resp4 = client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items",
        json={"name": "Latte", "quantity": 2, "compartment": "frigo"},
        headers=HEADERS,
    )
    assert resp4.status_code == 201
    item = resp4.json()
    assert item["name"] == "Latte"
    assert item["quantity"] == 2
    assert item["compartment"] == "frigo"
    assert item["checked"] is False
    item_id = item["id"]

    # add second item without compartment defaults to dispensa in export but stored None
    resp5 = client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "Pane", "quantity": 1}, headers=HEADERS
    )
    assert resp5.status_code == 201

    # patch toggle checked true
    resp6 = client.patch(
        f"/api/pantries/1/shopping-lists/{list_id}/items/{item_id}", json={"checked": True}, headers=HEADERS
    )
    assert resp6.status_code == 200
    assert resp6.json()["checked"] is True

    # toggle back false
    resp7 = client.patch(
        f"/api/pantries/1/shopping-lists/{list_id}/items/{item_id}", json={"checked": False}, headers=HEADERS
    )
    assert resp7.status_code == 200
    assert resp7.json()["checked"] is False

    # delete item
    resp8 = client.delete(f"/api/pantries/1/shopping-lists/{list_id}/items/{item_id}", headers=HEADERS)
    assert resp8.status_code == 204
    # verify removed
    resp9 = client.get(f"/api/pantries/1/shopping-lists/{list_id}", headers=HEADERS)
    ids = [i["id"] for i in resp9.json()["items"]]
    assert item_id not in ids


def test_shopping_validation(client, db_session):
    _create_pantry(db_session)
    resp = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa"}, headers=HEADERS)
    list_id = resp.json()["id"]
    # name empty
    resp2 = client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "", "quantity": 1}, headers=HEADERS
    )
    assert resp2.status_code == 422
    # quantity 0
    resp3 = client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "Latte", "quantity": 0}, headers=HEADERS
    )
    assert resp3.status_code == 422
    # quantity 1000
    resp4 = client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "Latte", "quantity": 1000}, headers=HEADERS
    )
    assert resp4.status_code == 422


def test_shopping_export_markdown(client, db_session):
    _create_pantry(db_session)
    resp = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa|Pipe"}, headers=HEADERS)
    list_id = resp.json()["id"]
    client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items",
        json={"name": "Latte|Fresco", "quantity": 1, "compartment": "frigo"},
        headers=HEADERS,
    )
    client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items",
        json={"name": "Vino", "quantity": 2, "compartment": "cantina"},
        headers=HEADERS,
    )
    client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items",
        json={"name": "Pane", "quantity": 1, "compartment": "dispensa"},
        headers=HEADERS,
    )
    # check one
    client.patch(f"/api/pantries/1/shopping-lists/{list_id}/items/1", json={"checked": True}, headers=HEADERS)
    resp2 = client.get(f"/api/pantries/1/shopping-lists/{list_id}/export", headers=HEADERS)
    assert resp2.status_code == 200
    md = resp2.text
    assert "Spesa\\|Pipe" in md or "Spesa" in md
    assert "Latte\\|Fresco" in md
    assert "- [x]" in md
    assert "- [ ]" in md
    # groups
    assert "Frigo" in md
    assert "Cantina" in md
    assert "Dispensa" in md


def test_shopping_check_incrocciato(client, db_session):
    _create_pantry(db_session)
    today = date.today()
    # inventory: Latte expired, Pane ok, Yogurt expiring_soon
    for name, delta in [("Latte", -1), ("Pane", 10), ("Yogurt", 1)]:
        it = InventoryItem(
            barcode=None,
            name=name,
            brand=None,
            expiration_date=today + timedelta(days=delta),
            is_estimated=False,
            quantity=1,
            pantry_id=1,
            created_at=datetime.now(timezone.utc),
        )
        db_session.add(it)
    db_session.commit()

    resp = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa"}, headers=HEADERS)
    list_id = resp.json()["id"]
    # add items: one matching Latte (case-insensitive), one missing
    client.post(f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "latte", "quantity": 1}, headers=HEADERS)
    client.post(f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "Burro", "quantity": 1}, headers=HEADERS)
    client.post(f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "YOGURT", "quantity": 1}, headers=HEADERS)

    resp2 = client.get(f"/api/pantries/1/shopping-lists/{list_id}/check", headers=HEADERS)
    assert resp2.status_code == 200
    items = resp2.json()["items"]
    by_name = {i["name"].lower(): i for i in items}
    # latte in pantry expired
    assert by_name["latte"]["inPantry"] is True
    assert by_name["latte"]["status"] == "expired"
    # burro missing
    assert by_name["burro"]["inPantry"] is False
    assert by_name["burro"]["status"] == "missing"
    # yogurt expiring_soon (delta 1 within EXPIRING_SOON_DAYS=3)
    assert by_name["yogurt"]["inPantry"] is True
    assert by_name["yogurt"]["status"] == "expiring_soon"


def test_shopping_404_pantry_not_found(client):
    resp = client.get("/api/pantries/999/shopping-lists", headers=HEADERS)
    assert resp.status_code == 404
    resp2 = client.post("/api/pantries/999/shopping-lists", json={"name": "Spesa"}, headers=HEADERS)
    assert resp2.status_code == 404


def test_shopping_401_missing_token(client, db_session):
    _create_pantry(db_session)
    resp = client.get("/api/pantries/1/shopping-lists")
    assert resp.status_code == 401
    resp2 = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa"})
    assert resp2.status_code == 401
    # export without token also 401
    resp3 = client.get("/api/pantries/1/shopping-lists/1/export")
    assert resp3.status_code == 401


def test_shopping_401_malformed_token(client, db_session):
    _create_pantry(db_session)
    resp = client.get("/api/pantries/1/shopping-lists", headers=BAD_HEADERS)
    assert resp.status_code == 401
    resp2 = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa"}, headers=BAD_HEADERS)
    assert resp2.status_code == 401
    resp3 = client.post("/api/pantries/1/shopping-lists", json={"name": "   "}, headers={"X-Pantry-Token": "123"})
    assert resp3.status_code == 401


def test_shopping_403_forbidden(client, db_session):
    _create_pantry(db_session)
    resp = client.get("/api/pantries/1/shopping-lists", headers=OTHER_HEADERS)
    assert resp.status_code == 403
    resp2 = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa"}, headers=OTHER_HEADERS)
    assert resp2.status_code == 403
    # create list as owner then try to access as non-member
    resp3 = client.post("/api/pantries/1/shopping-lists", json={"name": "Spesa"}, headers=HEADERS)
    list_id = resp3.json()["id"]
    resp4 = client.get(f"/api/pantries/1/shopping-lists/{list_id}", headers=OTHER_HEADERS)
    assert resp4.status_code == 403
    resp5 = client.post(
        f"/api/pantries/1/shopping-lists/{list_id}/items", json={"name": "Latte", "quantity": 1}, headers=OTHER_HEADERS
    )
    assert resp5.status_code == 403
