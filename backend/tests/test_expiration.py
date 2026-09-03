from datetime import date, timedelta
from backend.services.expiration import estimate_expiration, resolve_expiration
from backend.config import DEFAULT_SHELF_LIFE


def test_resolve_with_expiration_date_returns_not_estimated():
    d = date(2026, 5, 1)
    exp, is_est = resolve_expiration(expiration_date=d, category="yogurts")
    assert exp == d
    assert is_est is False


def test_estimate_known_category_yogurts():
    ref = date(2026, 1, 1)
    est = estimate_expiration(category_tags=["yogurts"], reference_date=ref)
    assert est == ref + timedelta(days=DEFAULT_SHELF_LIFE["yogurts"])
    assert DEFAULT_SHELF_LIFE["yogurts"] == 14


def test_resolve_category_case_insensitive_and_prefix():
    ref = date(2026, 1, 1)
    exp, is_est = resolve_expiration(category="  YoGurts ", reference_date=ref)
    assert exp == ref + timedelta(days=14)
    assert is_est is True
    # with en: prefix via off_category_tags
    exp2, _ = resolve_expiration(off_category_tags=["en:pasta"], reference_date=ref)
    assert exp2 == ref + timedelta(days=365)


def test_resolve_combined_category_and_off_tags_dedup():
    ref = date(2026, 1, 1)
    # category pasta + off tag pasta (dup) should not double
    exp, _ = resolve_expiration(category="pasta", off_category_tags=["EN:PASTA", "pasta"], reference_date=ref)
    assert exp == ref + timedelta(days=365)
    # off tags with whitespace and empty strings filtered
    exp2, _ = resolve_expiration(off_category_tags=["  ", "en:eggs", ""], reference_date=ref)
    assert exp2 == ref + timedelta(days=DEFAULT_SHELF_LIFE["eggs"])


def test_resolve_unknown_category_fallback_default():
    ref = date(2026, 1, 1)
    exp, is_est = resolve_expiration(category="unknown-category", reference_date=ref)
    assert exp == ref + timedelta(days=DEFAULT_SHELF_LIFE["default"])
    assert is_est is True
    # also estimate
    est = estimate_expiration(category_tags=["unknown"], reference_date=ref)
    assert est == ref + timedelta(days=DEFAULT_SHELF_LIFE["default"])


def test_resolve_empty_tags_fallback_default_estimated():
    ref = date(2026, 1, 1)
    exp, is_est = resolve_expiration(category=None, off_category_tags=None, reference_date=ref)
    assert exp == ref + timedelta(days=DEFAULT_SHELF_LIFE["default"])
    assert is_est is True
    # empty string category treated as empty
    exp2, _ = resolve_expiration(category="   ", off_category_tags=[], reference_date=ref)
    assert exp2 == ref + timedelta(days=30)


def test_resolve_normalizes_and_strips():
    ref = date(2026, 1, 1)
    # " fresh-milk " stripped lower and matched
    exp, _ = resolve_expiration(category=" fresh-milk ", reference_date=ref)
    assert exp == ref + timedelta(days=DEFAULT_SHELF_LIFE["fresh-milk"])
    assert DEFAULT_SHELF_LIFE["fresh-milk"] == 7
    # off tag with colon split: "en:fresh-milk" -> fresh-milk
    exp2, _ = resolve_expiration(off_category_tags=["en:fresh-milk"], reference_date=ref)
    assert exp2 == ref + timedelta(days=7)


def test_estimate_empty_tags_uses_default():
    ref = date(2026, 6, 15)
    est = estimate_expiration(category_tags=None, reference_date=ref)
    assert est == ref + timedelta(days=DEFAULT_SHELF_LIFE["default"])
    est2 = estimate_expiration(category_tags=[], reference_date=ref)
    assert est2 == ref + timedelta(days=30)
    est3 = estimate_expiration(category_tags=["   "], reference_date=ref)
    assert est3 == ref + timedelta(days=30)


def test_resolve_centralizzata_integration_via_api(client, db_session):
    from backend.models import Pantry

    p = Pantry(id=1, name="La mia dispensa", owner_token="00000000-0000-0000-0000-000000000000")
    db_session.add(p)
    db_session.commit()
    headers = {"X-Pantry-Token": "00000000-0000-0000-0000-000000000000"}
    # senza expiration_date ma con categoria yogurts -> scadenza stimata 14 giorni da oggi
    today = date.today()
    resp = client.post(
        "/api/inventory",
        json={"barcode": "12345678", "name": "Yogurt Test", "category": "yogurts", "quantity": 1},
        headers=headers,
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["is_estimated"] is True
    exp = date.fromisoformat(body["expiration_date"])
    expected = today + timedelta(days=14)
    assert exp == expected

    # con expiration_date esplicita -> non stimata
    explicit = (today + timedelta(days=10)).isoformat()
    resp2 = client.post(
        "/api/inventory/manual",
        json={"name": "Manual Test", "expiration_date": explicit, "category": "pasta", "quantity": 1},
        headers=headers,
    )
    assert resp2.status_code == 201
    body2 = resp2.json()
    assert body2["is_estimated"] is False
    assert body2["expiration_date"] == explicit
