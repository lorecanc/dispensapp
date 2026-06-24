from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import JSONResponse, PlainTextResponse, Response
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.models import InventoryItem
from backend.schemas import (
    InventoryCreate,
    InventoryCreateManual,
    InventoryOut,
    InventoryUpdate,
    MessageResponse,
)
from backend.services.expiration import estimate_expiration
from backend.services.markdown_export import to_markdown

router = APIRouter(prefix="/api", tags=["inventory"])


@router.post("/inventory", response_model=InventoryOut, status_code=201)
def create_inventory(body: InventoryCreate, db: Session = Depends(get_db)):
    if body.expiration_date:
        expiration_date = body.expiration_date
        is_estimated = False
    else:
        category_tags = [body.category] if body.category else None
        expiration_date = estimate_expiration(category_tags=category_tags)
        is_estimated = True

    item = InventoryItem(
        barcode=body.barcode,
        name=body.name,
        brand=body.brand,
        expiration_date=expiration_date,
        is_estimated=is_estimated,
        category=body.category,
        image_url=body.image_url,
        quantity=body.quantity,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.post("/inventory/manual", response_model=InventoryOut, status_code=201)
def create_inventory_manual(
    body: InventoryCreateManual, db: Session = Depends(get_db)
):
    if body.expiration_date:
        expiration_date = body.expiration_date
        is_estimated = False
    elif body.category:
        expiration_date = estimate_expiration(category_tags=[body.category])
        is_estimated = True
    else:
        expiration_date = None
        is_estimated = False

    item = InventoryItem(
        barcode=None,
        name=body.name,
        brand=body.brand,
        expiration_date=expiration_date,
        is_estimated=is_estimated,
        category=body.category,
        quantity=body.quantity,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.patch("/inventory/{item_id}", response_model=InventoryOut)
def update_inventory(item_id: int, body: InventoryUpdate, db: Session = Depends(get_db)):
    item = db.query(InventoryItem).filter(InventoryItem.id == item_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Elemento non trovato")
    data = body.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(item, k, v)
    db.commit()
    db.refresh(item)
    return item


@router.get("/inventory", response_model=list[InventoryOut])
def list_inventory(db: Session = Depends(get_db)):
    items = (
        db.query(InventoryItem)
        .order_by(InventoryItem.expiration_date.asc().nulls_last())
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
        return JSONResponse(
            status_code=404,
            content=MessageResponse(message="Elemento non trovato").model_dump(),
        )
    db.delete(item)
    db.commit()
    return Response(status_code=204)
