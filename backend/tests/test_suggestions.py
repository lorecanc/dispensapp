import uuid as uuid_mod
from datetime import datetime, timezone, timedelta
import pytest

from backend.models import InventoryItem, Pantry, ScanHistory

VALID_TOKEN = "00000000-0000-0000-0000-000000000000"
HEADERS = {"X-Pantry-Token": VALID_TOKEN}


@pytest.fixture
def owned_pantry(db_session):
    """Associa VALID_TOKEN a una pantry esistente (owner)."""
    db_session.add(Pantry(name="Dispensa test", owner_token=VALID_TOKEN))
    db_session.commit()


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


def test_suggestions_requires_pantry_token(client):
    # B3: /api/suggestions è una route di dati: senza X-Pantry-Token → 401
    resp = client.get("/api/suggestions")
    assert resp.status_code == 401
    resp2 = client.get("/api/suggestions?q=lat")
    assert resp2.status_code == 401
    # token malformato → 401 (stesso comportamento di get_pantry_context)
    resp3 = client.get("/api/suggestions", headers={"X-Pantry-Token": "not-a-uuid"})
    assert resp3.status_code == 401


def test_suggestions_rejects_valid_but_unknown_token(client):
    # CWE-287: UUID ben formato ma non associato ad alcuna pantry (owner o membro) → 401
    resp = client.get("/api/suggestions", headers={"X-Pantry-Token": str(uuid_mod.uuid4())})
    assert resp.status_code == 401


def test_suggestions_accepts_known_pantry_token(client, db_session, owned_pantry):
    # token owner di una pantry esistente → 200
    _seed_histories(db_session)
    resp = client.get("/api/suggestions?q=lat", headers=HEADERS)
    assert resp.status_code == 200
    assert "Latte fresco" in [d["name"] for d in resp.json()]


def test_suggestions_prefix_case_insensitive(client, db_session, owned_pantry):
    _seed_histories(db_session)
    resp = client.get("/api/suggestions?q=lat", headers=HEADERS)
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
    resp2 = client.get("/api/suggestions?q=tte", headers=HEADERS)
    assert resp2.status_code == 200
    assert resp2.json() == []


def test_suggestions_prefix_trim_and_q_empty(client, db_session, owned_pantry):
    _seed_histories(db_session)
    # q with spaces trimmed
    resp = client.get("/api/suggestions?q=  LAT  ", headers=HEADERS)
    assert resp.status_code == 200
    names = [d["name"] for d in resp.json()]
    assert "Latte fresco" in names

    # empty q returns all ordered by times_scanned desc then last_scanned_at desc, limit 10
    resp2 = client.get("/api/suggestions", headers=HEADERS)
    assert resp2.status_code == 200
    data2 = resp2.json()
    # ordered: Pasta 10, latticino 7, Latte fresco 5, Latte scremato 3, Yogurt 2, Latte di soia 1
    assert data2[0]["name"] == "Pasta integrale"
    assert data2[0]["times_scanned"] == 10


def test_suggestions_limit_10(client, db_session, owned_pantry):
    now = datetime.now(timezone.utc)
    for i in range(15):
        h = ScanHistory(barcode=f"b{i:03d}", name=f"Prodotto {i}", category="pasta", times_scanned=i, last_scanned_at=now)
        db_session.add(h)
    db_session.commit()
    resp = client.get("/api/suggestions?q=Prodotto", headers=HEADERS)
    assert resp.status_code == 200
    assert len(resp.json()) <= 10


def test_suggestions_returns_minimal_fields(client, db_session, owned_pantry):
    _seed_histories(db_session)
    resp = client.get("/api/suggestions?q=Latte", headers=HEADERS)
    assert resp.status_code == 200
    for item in resp.json():
        assert "barcode" in item
        assert "name" in item
        assert "category" in item
        assert "times_scanned" in item


TOKEN_A = "11111111-1111-1111-1111-111111111111"
TOKEN_B = "22222222-2222-2222-2222-222222222222"


def _pantry_of(db_session, owner_token):
    db_session.add(Pantry(name=f"Dispensa {owner_token[:8]}", owner_token=owner_token))
    db_session.commit()
    return db_session.query(Pantry).filter(Pantry.owner_token == owner_token).one()


def test_pantry_scope_returns_only_own_and_merges(client, db_session):
    pa = _pantry_of(db_session, TOKEN_A)
    pb = _pantry_of(db_session, TOKEN_B)
    db_session.add_all(
        [
            InventoryItem(name="Latte", barcode=None, category="fresh", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="LATTE", barcode="123", category="fresh", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="Miele", barcode=None, category=None, pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="Pasta", barcode="999", pantry_id=pb.id, created_by_token=TOKEN_B),
        ]
    )
    db_session.commit()
    resp = client.get("/api/suggestions", params={"scope": "pantry"}, headers={"X-Pantry-Token": TOKEN_A})
    assert resp.status_code == 200
    by_name = {(d["name"] or "").lower(): d for d in resp.json()}
    assert "pasta" not in by_name
    assert by_name["latte"]["times_scanned"] == 2
    assert by_name["latte"]["barcode"] == "123"
    assert by_name["miele"]["barcode"] == ""


def test_pantry_scope_empty_pantry_returns_empty(client, db_session):
    _pantry_of(db_session, TOKEN_A)
    resp = client.get("/api/suggestions", params={"scope": "pantry"}, headers={"X-Pantry-Token": TOKEN_A})
    assert resp.status_code == 200
    assert resp.json() == []


def test_pantry_scope_isolation_between_tokens(client, db_session):
    pa = _pantry_of(db_session, TOKEN_A)
    pb = _pantry_of(db_session, TOKEN_B)
    db_session.add_all(
        [
            InventoryItem(name="Mio A", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="Legacy A", pantry_id=None, created_by_token=TOKEN_A),
            InventoryItem(name="Segreto B", pantry_id=pb.id, created_by_token=TOKEN_B),
            InventoryItem(name="Legacy B", pantry_id=None, created_by_token=TOKEN_B),
        ]
    )
    db_session.commit()
    resp = client.get("/api/suggestions", params={"scope": "pantry"}, headers={"X-Pantry-Token": TOKEN_A})
    assert resp.status_code == 200
    names = [(d["name"] or "").lower() for d in resp.json()]
    assert "mio a" in names
    assert "legacy a" in names
    assert "segreto b" not in names
    assert "legacy b" not in names


def test_pantry_scope_prefix_escape(client, db_session):
    pa = _pantry_of(db_session, TOKEN_A)
    db_session.add_all(
        [
            InventoryItem(name="50% Sconto", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="50X Sconto", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="a_b", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="axb", pantry_id=pa.id, created_by_token=TOKEN_A),
            InventoryItem(name="a\\b", pantry_id=pa.id, created_by_token=TOKEN_A),
        ]
    )
    db_session.commit()
    headers = {"X-Pantry-Token": TOKEN_A}
    pct = client.get("/api/suggestions", params={"scope": "pantry", "q": "50%"}, headers=headers).json()
    assert [(d["name"] or "").lower() for d in pct] == ["50% sconto"]
    und = client.get("/api/suggestions", params={"scope": "pantry", "q": "a_"}, headers=headers).json()
    assert [(d["name"] or "").lower() for d in und] == ["a_b"]
    bsl = client.get("/api/suggestions", params={"scope": "pantry", "q": "a\\"}, headers=headers).json()
    assert [(d["name"] or "").lower() for d in bsl] == ["a\\b"]


def test_pantry_scope_limit_10(client, db_session):
    pa = _pantry_of(db_session, TOKEN_A)
    db_session.add_all(
        [InventoryItem(name=f"Prodotto {i}", pantry_id=pa.id, created_by_token=TOKEN_A) for i in range(15)]
    )
    db_session.commit()
    resp = client.get("/api/suggestions", params={"scope": "pantry", "q": "Prodotto"}, headers={"X-Pantry-Token": TOKEN_A})
    assert resp.status_code == 200
    assert len(resp.json()) <= 10
