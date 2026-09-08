import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy import or_
from sqlalchemy.orm import Session

from backend.config import COMPARTMENT_MAP, normalize_category
from backend.database import get_db
from backend.dependencies.pantry import PantryContext, get_current_pantry
from backend.models import ConsumptionEvent, InventoryItem
from backend.schemas import (
    ConsumptionEventOut,
    InventoryConsume,
    InventoryCreate,
    InventoryCreateManual,
    InventoryOut,
    InventoryUpdate,
)
from backend.services.compartment import _log_safe, infer_compartment, suggest_category
from backend.services.expiration import resolve_expiration
from backend.services.markdown_export import to_markdown

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["inventory"])

# Pantry di default per gli shim legacy /api/inventory*.
# Shim deprecato: i client nuovi usano /api/pantries/{id}/inventory.
# Il backfill (migration f1a2b3c4d5e6) mappa i NULL su MIN(id) esistente;
# ID=1 vale solo per seed legacy, nessun cambio semantica scoped.
DEFAULT_PANTRY_ID = 1


def _default_pantry_ctx(
    x_pantry_token: str | None = Header(default=None, alias="X-Pantry-Token"),
    db: Session = Depends(get_db),
) -> PantryContext:
    # Shim legacy: valida il token contro la pantry di default.
    return get_current_pantry(
        pantry_id=DEFAULT_PANTRY_ID, x_pantry_token=x_pantry_token, db=db
    )


def _pantry_filter(pantry_id: int, allow_null: bool = False):
    # Fallback legacy: le righe pre-T3 hanno pantry_id NULL; backfill su
    # MIN(id) via migration, ma gli shim legacy includono anche NULL.
    # Le route scoped passano allow_null=False (nessun cambio semantica).
    if allow_null:
        return or_(
            InventoryItem.pantry_id == pantry_id,
            InventoryItem.pantry_id.is_(None),
        )
    return InventoryItem.pantry_id == pantry_id


def _create_scoped_item(
    db: Session,
    pantry_id: int,
    token: str,
    body: InventoryCreate | InventoryCreateManual,
    *,
    manual: bool,
    source: str | None = None,
    product_type: str | None = None,
) -> InventoryItem:
    # Priorità categoria persistita: explicit valida > suggest > None.
    # Explicit spuria (non in COMPARTMENT_MAP) vale come None e prosegue cascata.
    explicit = normalize_category(body.category)
    if explicit is not None and explicit not in COMPARTMENT_MAP:
        explicit = None
    resolved_source = source if source is not None else getattr(body, "source", None)
    resolved_product_type = (
        product_type if product_type is not None else getattr(body, "product_type", None)
    )
    pnns_group = getattr(body, "pnns_group", None)
    if explicit is not None:
        category = explicit
    else:
        category = suggest_category(
            body.off_category_tags, pnns_group, resolved_source, resolved_product_type
        )
    if category is None:
        logger.warning(
            "inventory category fallback None barcode=%s source=%s product_type=%s tags=%s pnns=%s esito=None",
            _log_safe(getattr(body, "barcode", None), 32),
            _log_safe(resolved_source, 32),
            _log_safe(resolved_product_type, 32),
            [_log_safe(t, 200) for t in (body.off_category_tags or [])[:50]],
            _log_safe(pnns_group, 64),
        )
    expiration_date, is_estimated = resolve_expiration(
        expiration_date=body.expiration_date,
        category=body.category,
        off_category_tags=body.off_category_tags,
        allow_none=manual,
    )
    compartment = body.compartment
    if not compartment:
        compartment = infer_compartment(
            name=body.name,
            category=category,
            off_category_tags=body.off_category_tags,
        )
    item = InventoryItem(
        barcode=None if manual else body.barcode,  # type: ignore[attr-defined]
        name=body.name,
        brand=body.brand,
        expiration_date=expiration_date,
        is_estimated=is_estimated,
        category=category,
        image_url=str(body.image_url) if body.image_url else None,
        quantity=body.quantity,
        compartment=compartment,
        # storage_location: NULL = derivato dal client via categoria (by design).
        storage_location=body.storage_location,
        # T8b: param esplicito vince, fallback al body; NULL = non impostato.
        source=resolved_source,
        product_type=resolved_product_type,
        pantry_id=pantry_id,
        created_by_token=token,
    )
    try:
        db.add(item)
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        logger.exception("Errore creazione inventario pantry %s", pantry_id)
        raise HTTPException(status_code=500, detail="Errore interno durante la creazione")
    return item


def _get_scoped_item(
    db: Session, pantry_id: int, item_id: int, allow_null: bool = False
) -> InventoryItem:
    item = (
        db.query(InventoryItem)
        .filter(InventoryItem.id == item_id, _pantry_filter(pantry_id, allow_null))
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Elemento non trovato")
    return item


def _list_scoped_items(
    db: Session, pantry_id: int, limit: int, offset: int, allow_null: bool = False
) -> list[InventoryItem]:
    return (
        db.query(InventoryItem)
        .filter(_pantry_filter(pantry_id, allow_null), InventoryItem.quantity > 0)
        .order_by(InventoryItem.expiration_date.asc().nulls_last())
        .offset(offset)
        .limit(limit)
        .all()
    )


def _update_scoped_item(
    db: Session, pantry_id: int, item_id: int, body: InventoryUpdate, allow_null: bool = False
) -> InventoryItem:
    item = _get_scoped_item(db, pantry_id, item_id, allow_null)
    data = body.model_dump(exclude_unset=True)
    if "image_url" in data and data["image_url"] is not None:
        data["image_url"] = str(data["image_url"])
    if "category" in data and data["category"] is not None:
        data["category"] = normalize_category(data["category"])
        if data["category"] is not None and data["category"] not in COMPARTMENT_MAP:
            data["category"] = None
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


def _delete_scoped_item(
    db: Session, pantry_id: int, item_id: int, allow_null: bool = False
) -> None:
    item = _get_scoped_item(db, pantry_id, item_id, allow_null)
    try:
        db.delete(item)
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("Errore cancellazione inventario %s", item_id)
        raise HTTPException(status_code=500, detail="Errore interno durante la cancellazione")


def _consume_scoped_item(
    db: Session,
    pantry_id: int,
    item_id: int,
    delta: int,
    reason: str | None,
    allow_null: bool = False,
) -> InventoryItem:
    pantry_filter = _pantry_filter(pantry_id, allow_null)
    try:
        updated = (
            db.query(InventoryItem)
            .filter(
                InventoryItem.id == item_id,
                pantry_filter,
                InventoryItem.quantity >= delta,
            )
            .update(
                {InventoryItem.quantity: InventoryItem.quantity - delta},
                synchronize_session=False,
            )
        )
        if updated == 0:
            db.rollback()
            exists = (
                db.query(InventoryItem.id)
                .filter(
                    InventoryItem.id == item_id,
                    pantry_filter,
                )
                .first()
            )
            if not exists:
                raise HTTPException(status_code=404, detail="Elemento non trovato")
            raise HTTPException(status_code=409, detail="Quantità insufficiente")
        item = (
            db.query(InventoryItem)
            .filter(
                InventoryItem.id == item_id,
                pantry_filter,
            )
            .first()
        )
        if not item:
            db.rollback()
            raise HTTPException(status_code=404, detail="Elemento non trovato")
        event = ConsumptionEvent(
            pantry_id=item.pantry_id if item.pantry_id is not None else pantry_id,
            item_id=item.id,
            name_snapshot=item.name,
            barcode=item.barcode,
            delta=-delta,
            reason=reason,
            # Privacy: token non persistito (colonna actor_token rimossa).
        )
        remaining = getattr(item, "quantity", 0) or 0
        if remaining == 0:
            # Contratto A: a zero la riga è cancellata; la history resta
            # interrogabile su pantry+item_id senza richiedere la riga.
            snapshot = InventoryItem(
                barcode=item.barcode,
                name=item.name,
                brand=item.brand,
                expiration_date=item.expiration_date,
                is_estimated=item.is_estimated,
                category=item.category,
                image_url=item.image_url,
                quantity=0,
                pantry_id=item.pantry_id,
                compartment=item.compartment,
            )
            snapshot.id = item.id
            snapshot.created_at = item.created_at
            db.delete(item)
            db.add(event)
            db.commit()
            return snapshot
        db.add(event)
        db.commit()
        db.refresh(item)
    except HTTPException:
        raise
    except Exception:
        db.rollback()
        logger.exception("Errore consumo inventario %s", item_id)
        raise HTTPException(status_code=500, detail="Errore interno durante il consumo")
    return item


def _history_scoped_items(
    db: Session, pantry_id: int, item_id: int, limit: int, offset: int
) -> list[ConsumptionEvent]:
    # Contratto A: la history è su pantry+item_id e non richiede la riga
    # (cancellata quando il consumo arriva a zero). Auth resta stretta su
    # get_current_pantry (401/403, nessun mask server).
    return (
        db.query(ConsumptionEvent)
        .filter(
            ConsumptionEvent.pantry_id == pantry_id,
            ConsumptionEvent.item_id == item_id,
        )
        .order_by(ConsumptionEvent.created_at.desc(), ConsumptionEvent.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )


# --- T3: route pantry-scoped ---


@router.get("/pantries/{pantry_id}/inventory", response_model=list[InventoryOut])
def list_scoped_inventory(
    pantry_id: int,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _list_scoped_items(db, pantry_id, limit, offset)


@router.post(
    "/pantries/{pantry_id}/inventory", response_model=InventoryOut, status_code=201
)
def create_scoped_inventory(
    pantry_id: int,
    body: InventoryCreate,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _create_scoped_item(db, pantry_id, ctx.token, body, manual=False)


@router.post(
    "/pantries/{pantry_id}/inventory/manual",
    response_model=InventoryOut,
    status_code=201,
)
def create_scoped_inventory_manual(
    pantry_id: int,
    body: InventoryCreateManual,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _create_scoped_item(db, pantry_id, ctx.token, body, manual=True)


@router.get("/pantries/{pantry_id}/inventory/export")
def export_scoped_inventory(
    pantry_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    items = (
        db.query(InventoryItem)
        .filter(
            InventoryItem.pantry_id == pantry_id,
            InventoryItem.quantity > 0,
        )
        .order_by(InventoryItem.expiration_date.asc().nulls_last())
        .all()
    )
    md = to_markdown(items)
    return PlainTextResponse(content=md, media_type="text/markdown")


@router.get("/pantries/{pantry_id}/inventory/{item_id}", response_model=InventoryOut)
def get_scoped_inventory(
    pantry_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _get_scoped_item(db, pantry_id, item_id)


@router.patch("/pantries/{pantry_id}/inventory/{item_id}", response_model=InventoryOut)
def update_scoped_inventory(
    pantry_id: int,
    item_id: int,
    body: InventoryUpdate,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _update_scoped_item(db, pantry_id, item_id, body)


@router.delete("/pantries/{pantry_id}/inventory/{item_id}", status_code=204)
def delete_scoped_inventory(
    pantry_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    _delete_scoped_item(db, pantry_id, item_id)
    return Response(status_code=204)


# --- T3: shim legacy su pantry di default ---


@router.post("/inventory", response_model=InventoryOut, status_code=201)
def create_inventory(
    body: InventoryCreate,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _create_scoped_item(db, DEFAULT_PANTRY_ID, ctx.token, body, manual=False)


@router.post("/inventory/manual", response_model=InventoryOut, status_code=201)
def create_inventory_manual(
    body: InventoryCreateManual,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _create_scoped_item(db, DEFAULT_PANTRY_ID, ctx.token, body, manual=True)


@router.get("/inventory", response_model=list[InventoryOut])
def list_inventory(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _list_scoped_items(db, DEFAULT_PANTRY_ID, limit, offset, allow_null=True)


@router.get("/inventory/export")
def export_inventory(
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    items = (
        db.query(InventoryItem)
        .filter(
            _pantry_filter(DEFAULT_PANTRY_ID, allow_null=True),
            InventoryItem.quantity > 0,
        )
        .order_by(InventoryItem.expiration_date.asc().nulls_last())
        .all()
    )
    md = to_markdown(items)
    return PlainTextResponse(content=md, media_type="text/markdown")


@router.get("/inventory/{item_id}", response_model=InventoryOut)
def get_inventory(
    item_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _get_scoped_item(db, DEFAULT_PANTRY_ID, item_id, allow_null=True)


@router.patch("/inventory/{item_id}", response_model=InventoryOut)
def update_inventory(
    item_id: int,
    body: InventoryUpdate,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _update_scoped_item(db, DEFAULT_PANTRY_ID, item_id, body, allow_null=True)


@router.delete("/inventory/{item_id}", status_code=204)
def delete_inventory(
    item_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    _delete_scoped_item(db, DEFAULT_PANTRY_ID, item_id, allow_null=True)
    return Response(status_code=204)


# --- T4: consumo atomico + history (scoped) ---


@router.post(
    "/pantries/{pantry_id}/inventory/{item_id}/consume",
    response_model=InventoryOut,
)
def consume_scoped_inventory(
    pantry_id: int,
    item_id: int,
    body: InventoryConsume,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _consume_scoped_item(
        db, pantry_id, item_id, body.delta, body.reason
    )


@router.get(
    "/pantries/{pantry_id}/inventory/{item_id}/history",
    response_model=list[ConsumptionEventOut],
)
def history_scoped_inventory(
    pantry_id: int,
    item_id: int,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    return _history_scoped_items(db, pantry_id, item_id, limit, offset)


# --- T4: shim legacy consume/history su pantry di default ---


@router.post("/inventory/{item_id}/consume", response_model=InventoryOut)
def consume_inventory(
    item_id: int,
    body: InventoryConsume,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _consume_scoped_item(
        db, DEFAULT_PANTRY_ID, item_id, body.delta, body.reason,
        allow_null=True,
    )


@router.get("/inventory/{item_id}/history", response_model=list[ConsumptionEventOut])
def history_inventory(
    item_id: int,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(_default_pantry_ctx),
):
    return _history_scoped_items(db, DEFAULT_PANTRY_ID, item_id, limit, offset)
