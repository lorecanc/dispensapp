import anyio.to_thread
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.models import ScanHistory
from backend.schemas import ScanRequest, ScanResponse
from backend.services.compartment import suggest_category
from backend.services.off import fetch_product

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["scan"])


@router.post("/scan", response_model=ScanResponse)
async def scan_barcode(body: ScanRequest, db: Session = Depends(get_db)):
    result = await fetch_product(body.barcode)

    if result is None:
        raise HTTPException(
            status_code=502,
            detail="Errore durante la comunicazione con Open Food Facts",
        )

    if result.get("found") is False:
        return ScanResponse(
            found=False,
            barcode=body.barcode,
            message="Prodotto non trovato nel database Open Food Facts",
        )

    # Hook ScanHistory: increment times_scanned or create
    def persist_history() -> None:
        try:
            barcode = result.get("barcode") or body.barcode
            name = result.get("name") or ""
            categories = result.get("categories") or []
            category = categories[0] if categories else None
            existing = db.query(ScanHistory).filter(ScanHistory.barcode == barcode).first()
            now = datetime.now(timezone.utc)
            if existing:
                existing.times_scanned = (existing.times_scanned or 0) + 1
                # update name/category to latest OFF data if provided
                if name:
                    existing.name = name
                if category:
                    existing.category = category
                existing.last_scanned_at = now
            else:
                # ensure name not empty for NOT NULL constraint; fallback to barcode
                hist = ScanHistory(
                    barcode=barcode,
                    name=name or barcode,
                    category=category,
                    times_scanned=1,
                    last_scanned_at=now,
                )
                db.add(hist)
            db.commit()
        except Exception:
            # ScanHistory non deve bloccare la scansione
            try:
                db.rollback()
            except Exception:
                pass
            logger.exception("Errore salvataggio ScanHistory per %s", body.barcode)

    # Session SQLAlchemy sincrona: eseguita in un worker thread per non
    # bloccare l'event loop; nessun oggetto ORM esce dal thread.
    await anyio.to_thread.run_sync(persist_history)

    # Suggerimento categoria interna (tag OFF + gruppo PNNS); None-safe:
    # suggest_category tollera input mancanti e ritorna None senza match.
    suggested = suggest_category(result.get("categories"), result.get("pnns_group"))

    return ScanResponse(
        found=True,
        barcode=result["barcode"],
        name=result.get("name", ""),
        brand=result.get("brand"),
        categories=result.get("categories", []),
        image_url=result.get("image_url"),
        suggested_category=suggested,
    )
