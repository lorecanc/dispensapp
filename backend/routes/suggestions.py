from fastapi import APIRouter, Depends, Query
from sqlalchemy import and_, or_
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.dependencies.pantry import require_known_token
from backend.models import InventoryItem, Pantry, PantryMember, ScanHistory

router = APIRouter(prefix="/api", tags=["suggestions"])


def _escape_like(value: str) -> str:
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


@router.get("/suggestions")
def list_suggestions(
    q: str = Query(default="", description="prefix filter case-insensitive"),
    scope: str = Query(default="shopping", description="shopping (default) o pantry"),
    db: Session = Depends(get_db),
    current_token: str = Depends(require_known_token),
):
    prefix = q.strip().lower() if q and q.strip() else ""
    if scope == "pantry":
        return _pantry_suggestions(db, current_token, prefix)
    query = db.query(ScanHistory)
    if prefix:
        # prefix case-insensitive: ilike
        query = query.filter(ScanHistory.name.ilike(f"{_escape_like(prefix)}%", escape="\\"))
    items = (
        query.order_by(ScanHistory.times_scanned.desc(), ScanHistory.last_scanned_at.desc())
        .limit(10)
        .all()
    )
    # Return minimal fields for suggestions
    return [
        {
            "barcode": s.barcode,
            "name": s.name,
            "category": s.category,
            "times_scanned": s.times_scanned,
        }
        for s in items
    ]


def _pantry_suggestions(db: Session, token: str, prefix: str):
    # YAGNI: consumption_events omessi, inventory_items copre gia le
    # immissioni passate senza join aggiuntivi.
    owned = [r[0] for r in db.query(Pantry.id).filter(Pantry.owner_token == token).all()]
    membered = [
        r[0]
        for r in db.query(PantryMember.pantry_id)
        .filter(PantryMember.member_token == token)
        .all()
    ]
    pantry_ids = set(owned) | set(membered)
    if not pantry_ids:
        return []
    inv_query = db.query(InventoryItem).filter(
        or_(
            InventoryItem.pantry_id.in_(pantry_ids),
            and_(
                InventoryItem.pantry_id.is_(None),
                InventoryItem.created_by_token == token,
            ),
        )
    )
    if prefix:
        inv_query = inv_query.filter(InventoryItem.name.ilike(f"{_escape_like(prefix)}%", escape="\\"))
    # I 200 più recenti, non i più vecchi: con ordine ascendente i nuovi
    # inserimenti oltre il limit resterebbero esclusi dai suggerimenti.
    inv_rows = inv_query.order_by(InventoryItem.id.desc()).limit(200).all()

    merged: dict[str, dict] = {}
    for item in inv_rows:
        key = (item.name or "").lower()
        if not key:
            continue
        entry = merged.get(key)
        if entry is None:
            merged[key] = {
                "barcode": item.barcode or "",
                "name": item.name,
                "category": item.category,
                "times_scanned": 1,
            }
        else:
            entry["times_scanned"] += 1
            if not entry["barcode"] and item.barcode is not None:
                entry["barcode"] = item.barcode
            if entry["category"] is None and item.category is not None:
                entry["category"] = item.category

    hist_query = db.query(ScanHistory)
    if prefix:
        hist_query = hist_query.filter(ScanHistory.name.ilike(f"{_escape_like(prefix)}%", escape="\\"))
    for s in (
        hist_query.order_by(ScanHistory.times_scanned.desc(), ScanHistory.last_scanned_at.desc())
        .limit(10)
        .all()
    ):
        key = (s.name or "").lower()
        entry = merged.get(key)
        if entry is None:
            merged[key] = {
                "barcode": s.barcode or "",
                "name": s.name,
                "category": s.category,
                "times_scanned": s.times_scanned,
            }
        else:
            entry["times_scanned"] += s.times_scanned

    ranked = sorted(merged.values(), key=lambda e: e["times_scanned"], reverse=True)
    return ranked[:10]
