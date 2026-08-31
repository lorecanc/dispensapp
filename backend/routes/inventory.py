import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy.orm import Session

from backend.config import normalize_category
from backend.database import get_db
from backend.models import InventoryItem
from backend.schemas import (
    InventoryCreate,
    InventoryCreateManual,
    InventoryOut,
    InventoryUpdate,
)
from backend.services.expiration import resolve_expiration
from backend.services.markdown_export import to_markdown

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["inventory"])


@router.post("/inventory", response_model=InventoryOut, status_code=201)
def create_inventory(body: InventoryCreate, db: Session = Depends(get_db)):
    expiration_date, is_estimated = resolve_expiration(
        expiration_date=body.expiration_date,
        category=body.category,
        off_category_tags=None,
    )

    item = InventoryItem(
        barcode=body.barcode,
        name=body.name,
        brand=body.brand,
        expiration_date=expiration_date,
        is_estimated=is_estimated,
        category=normalize_category(body.category),
        image_url=str(body.image_url) if body.image_url else None,
        quantity=body.quantity,
    )
    try:
        db.add(item)
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        logger.exception("Errore creazione inventario")
        raise HTTPException(status_code=500, detail="Errore interno durante la creazione")
    return item


@router.post("/inventory/manual", response_model=InventoryOut, status_code=201)
def create_inventory_manual(
    body: InventoryCreateManual, db: Session = Depends(get_db)
):
    expiration_date, is_estimated = resolve_expiration(
        expiration_date=body.expiration_date,
        category=body.category,
        off_category_tags=None,
        allow_none=True,
    )

    item = InventoryItem(
        barcode=None,
        name=body.name,
        brand=body.brand,
        expiration_date=expiration_date,
        is_estimated=is_estimated,
        category=normalize_category(body.category),
        image_url=str(body.image_url) if body.image_url else None,
        quantity=body.quantity,
    )
    try:
        db.add(item)
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        logger.exception("Errore creazione manuale inventario")
        raise HTTPException(status_code=500, detail="Errore interno durante la creazione")
    return item


@router.patch("/inventory/{item_id}", response_model=InventoryOut)
def update_inventory(item_id: int, body: InventoryUpdate, db: Session = Depends(get_db)):
    item = db.query(InventoryItem).filter(InventoryItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Elemento non trovato")
    data = body.model_dump(exclude_unset=True)
    # HttpUrl -> str per SQLAlchemy
    if "image_url" in data and data["image_url"] is not None:
        data["image_url"] = str(data["image_url"])
    # Normalizza categoria a forma canonica (alias yogurt -> yogurts)
    if "category" in data and data["category"] is not None:
        data["category"] = normalize_category(data["category"])
    for k, v in data.items():
        setattr(item, k, v)
    try:
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        logger.exception("Errore aggiornamento inventario %s", item_id)
        raise HTTPException(status_code=500, detail="Errore interno durante l'aggiornamento")
    return item


@router.get("/inventory", response_model=list[InventoryOut])
def list_inventory(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    items = (
        db.query(InventoryItem)
        .order_by(InventoryItem.expiration_date.asc().nulls_last())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return items


@router.get("/inventory/export")
def export_inventory(db: Session = Depends(get_db)):
    items = (
        db.query(InventoryItem)
        .order_by(InventoryItem.expiration_date.asc().nulls_last())
        .all()
    )
    md = to_markdown(items)
    return PlainTextResponse(content=md, media_type="text/markdown")


@router.delete("/inventory/{item_id}", status_code=204)
def delete_inventory(item_id: int, db: Session = Depends(get_db)):
    item = db.query(InventoryItem).filter(InventoryItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Elemento non trovato")
    try:
        db.delete(item)
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("Errore cancellazione inventario %s", item_id)
        raise HTTPException(status_code=500, detail="Errore interno durante la cancellazione")
    return Response(status_code=204)
