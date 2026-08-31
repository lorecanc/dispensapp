from datetime import date, timedelta, datetime, timezone
from backend.models import InventoryItem


def _seed_inventory(db_session, count=5):
    today = date.today()
    for i in range(count):
        item = InventoryItem(
            barcode=f"80000000000{i}",
            name=f"Prodotto {i}",
            brand="Brand",
            expiration_date=today + timedelta(days=i),
            is_estimated=False,
            quantity=1,
            created_at=datetime.now(timezone.utc),
        )
        db_session.add(item)
    db_session.commit()
    return count


def test_pagination_limit_offset(client, db_session):
    _seed_inventory(db_session, count=5)
    # limit 2 offset 0
    resp = client.get("/api/inventory?limit=2&offset=0")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data) == 2
    # should be sorted by expiration_date asc
    dates = [d["expiration_date"] for d in data]
    assert dates == sorted(dates)

    # offset 2
    resp2 = client.get("/api/inventory?limit=2&offset=2")
    assert resp2.status_code == 200
    data2 = resp2.json()
    assert len(data2) == 2
    # no overlap with first page
    ids1 = {x["id"] for x in data}
    ids2 = {x["id"] for x in data2}
    assert ids1.isdisjoint(ids2)

    # last page partial
    resp3 = client.get("/api/inventory?limit=2&offset=4")
    assert resp3.status_code == 200
    assert len(resp3.json()) == 1

    # beyond total
    resp4 = client.get("/api/inventory?limit=10&offset=10")
    assert resp4.status_code == 200
    assert resp4.json() == []


def test_pagination_validation(client):
    # limit 0 => 422
    resp = client.get("/api/inventory?limit=0&offset=0")
    assert resp.status_code == 422
    # limit 101 => 422 (le=100)
    resp2 = client.get("/api/inventory?limit=101&offset=0")
    assert resp2.status_code == 422
    # offset negative => 422
    resp3 = client.get("/api/inventory?limit=10&offset=-1")
    assert resp3.status_code == 422


def test_pagination_default_limit(client, db_session):
    _seed_inventory(db_session, count=3)
    resp = client.get("/api/inventory")
    assert resp.status_code == 200
    # default 50, should return all 3
    assert len(resp.json()) == 3


def test_pagination_limit_exceeds_total(client, db_session):
    _seed_inventory(db_session, count=2)
    resp = client.get("/api/inventory?limit=100&offset=0")
    assert resp.status_code == 200
    assert len(resp.json()) == 2
