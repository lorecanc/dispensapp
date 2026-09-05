from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.dependencies.pantry import require_known_token
from backend.models import ScanHistory

router = APIRouter(prefix="/api", tags=["suggestions"])


@router.get("/suggestions")
def list_suggestions(
    q: str = Query(default="", description="prefix filter case-insensitive"),
    db: Session = Depends(get_db),
    current_token: str = Depends(require_known_token),
):
    query = db.query(ScanHistory)
    if q and q.strip():
        prefix = q.strip().lower()
        # prefix case-insensitive: ilike
        query = query.filter(ScanHistory.name.ilike(f"{prefix}%"))
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
