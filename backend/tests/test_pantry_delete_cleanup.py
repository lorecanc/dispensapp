"""Red test (A1): DELETE /api/pantries/{id} must clean up all child rows.

Bug: backend/routes/pantries.py delete_pantry only deletes the pantry row.
SQLite has no PRAGMA foreign_keys=ON so ondelete=CASCADE is inert, leaving
orphans in inventory_items, shopping_lists(+items), pantry_members, invites,
consumption_events. Rowid reuse then resurrects them / breaks recreate (500).
"""

from backend.models import (
    ConsumptionEvent,
    InventoryItem,
    Invite,
    PantryMember,
    ShoppingList,
    ShoppingListItem,
)

OWNER_TOKEN = "00000000-0000-0000-0000-000000000000"
EDITOR_TOKEN = "11111111-1111-1111-1111-111111111111"
OWNER_HEADERS = {"X-Pantry-Token": OWNER_TOKEN}
PANTRY_NAME = "Dispensa"


def _seed_full_pantry(client, db_session):
    """Create pantry via API + all child rows. Returns (pantry_id, list_id)."""
    resp = client.post("/api/pantries", json={"name": PANTRY_NAME}, headers=OWNER_HEADERS)
    assert resp.status_code == 201, resp.text
    pantry_id = resp.json()["id"]

    # 2 inventory items (direct DB insert)
    items = [
        InventoryItem(name="Latte", quantity=1, pantry_id=pantry_id, created_by_token=OWNER_TOKEN),
        InventoryItem(name="Pane", quantity=2, pantry_id=pantry_id, created_by_token=OWNER_TOKEN),
    ]
    db_session.add_all(items)
    db_session.commit()

    # 1 shopping list with 1 item (via API)
    resp = client.post(
        f"/api/pantries/{pantry_id}/shopping-lists", json={"name": "Spesa"}, headers=OWNER_HEADERS
    )
    assert resp.status_code == 201, resp.text
    list_id = resp.json()["id"]
    resp = client.post(
        f"/api/pantries/{pantry_id}/shopping-lists/{list_id}/items",
        json={"name": "Burro", "quantity": 1},
        headers=OWNER_HEADERS,
    )
    assert resp.status_code == 201, resp.text

    # 1 extra member row (direct DB insert)
    db_session.add(PantryMember(pantry_id=pantry_id, member_token=EDITOR_TOKEN, role="editor"))
    db_session.commit()

    # 1 invite (via API)
    resp = client.post(f"/api/pantries/{pantry_id}/invites", json={}, headers=OWNER_HEADERS)
    assert resp.status_code == 201, resp.text

    # 1 consumption event (direct DB insert)
    db_session.add(
        ConsumptionEvent(
            pantry_id=pantry_id,
            item_id=items[0].id,
            name_snapshot="Latte",
            delta=-1,
        )
    )
    db_session.commit()

    return pantry_id, list_id


def _orphan_counts(db_session, pantry_id, list_id):
    db_session.expire_all()
    return {
        "inventory_items": db_session.query(InventoryItem)
        .filter(InventoryItem.pantry_id == pantry_id)
        .count(),
        "shopping_lists": db_session.query(ShoppingList)
        .filter(ShoppingList.pantry_id == pantry_id)
        .count(),
        "shopping_list_items": db_session.query(ShoppingListItem)
        .filter(ShoppingListItem.shopping_list_id == list_id)
        .count(),
        "pantry_members": db_session.query(PantryMember)
        .filter(PantryMember.pantry_id == pantry_id)
        .count(),
        "invites": db_session.query(Invite).filter(Invite.pantry_id == pantry_id).count(),
        "consumption_events": db_session.query(ConsumptionEvent)
        .filter(ConsumptionEvent.pantry_id == pantry_id)
        .count(),
    }


def test_delete_pantry_cleans_all_child_tables(client, db_session):
    pantry_id, list_id = _seed_full_pantry(client, db_session)

    resp = client.delete(f"/api/pantries/{pantry_id}", headers=OWNER_HEADERS)
    assert resp.status_code == 204, resp.text

    orphans = _orphan_counts(db_session, pantry_id, list_id)
    assert orphans == {
        "inventory_items": 0,
        "shopping_lists": 0,
        "shopping_list_items": 0,
        "pantry_members": 0,
        "invites": 0,
        "consumption_events": 0,
    }, f"orphan rows left after DELETE: {orphans}"


def test_recreate_pantry_same_name_after_delete_returns_201(client, db_session):
    pantry_id, _ = _seed_full_pantry(client, db_session)

    resp = client.delete(f"/api/pantries/{pantry_id}", headers=OWNER_HEADERS)
    assert resp.status_code == 204, resp.text

    recreate = client.post("/api/pantries", json={"name": PANTRY_NAME}, headers=OWNER_HEADERS)
    assert recreate.status_code == 201, (
        f"recreate after delete failed: status={recreate.status_code} body={recreate.text}"
    )
