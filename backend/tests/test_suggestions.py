from datetime import datetime, timezone, timedelta
from backend.models import ScanHistory


def _seed_histories(db_session):
    now = datetime.now(timezone.utc)
    entries = [
        ScanHistory(barcode="001", name="Latte fresco", category="fresh-milk", times_scanned=5, last_scanned_at=now - timedelta(days=1)),
        ScanHistory(barcode="002", name="Latte scremato", category="fresh-milk", times_scanned=3, last_scanned_at=now),
        ScanHistory(barcode="003", name="Pasta integrale", category="pasta", times_scanned=10, last_scanned_at=now - timedelta(hours=2)),
        ScanHistory(barcode="004", name="latticino", category="cheeses", times_scanned=7, last_scanned_at=now - timedelta(hours=1)),
        ScanHistory(barcode="005", name="Yogurt", category="yogurts", times_scanned=2, last_scanned_at=now),
        ScanHistory(barcode="006", name="Latte di soia", category="fresh-milk", times_scanned=1, last_scanned_at=now),
    ]
    for e in entries:
        db_session.add(e)
    db_session.commit()


def test_suggestions_prefix_case_insensitive(client, db_session):
    _seed_histories(db_session)
    resp = client.get("/api/suggestions?q=lat")
    assert resp.status_code == 200
    data = resp.json()
    names = [d["name"] for d in data]
    # should match Latte fresco, Latte scremato, latticino, Latte di soia (case-insensitive prefix lat)
    assert "Latte fresco" in names
    assert "Latte scremato" in names
    assert "latticino" in names
    # should not include Pasta or Yogurt
    assert "Pasta integrale" not in names
    assert "Yogurt" not in names
    # only prefix, not substring: "tte" should not match Latte
    resp2 = client.get("/api/suggestions?q=tte")
    assert resp2.status_code == 200
    assert resp2.json() == []


def test_suggestions_prefix_trim_and_q_empty(client, db_session):
    _seed_histories(db_session)
    # q with spaces trimmed
    resp = client.get("/api/suggestions?q=  LAT  ")
    assert resp.status_code == 200
    names = [d["name"] for d in resp.json()]
    assert "Latte fresco" in names

    # empty q returns all ordered by times_scanned desc then last_scanned_at desc, limit 10
    resp2 = client.get("/api/suggestions")
    assert resp2.status_code == 200
    data2 = resp2.json()
    # ordered: Pasta 10, latticino 7, Latte fresco 5, Latte scremato 3, Yogurt 2, Latte di soia 1
    assert data2[0]["name"] == "Pasta integrale"
    assert data2[0]["times_scanned"] == 10


def test_suggestions_limit_10(client, db_session):
    now = datetime.now(timezone.utc)
    for i in range(15):
        h = ScanHistory(barcode=f"b{i:03d}", name=f"Prodotto {i}", category="pasta", times_scanned=i, last_scanned_at=now)
        db_session.add(h)
    db_session.commit()
    resp = client.get("/api/suggestions?q=Prodotto")
    assert resp.status_code == 200
    assert len(resp.json()) <= 10


def test_suggestions_returns_minimal_fields(client, db_session):
    _seed_histories(db_session)
    resp = client.get("/api/suggestions?q=Latte")
    assert resp.status_code == 200
    for item in resp.json():
        assert "barcode" in item
        assert "name" in item
        assert "category" in item
        assert "times_scanned" in item
