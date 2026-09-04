from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import PlainTextResponse, Response
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.dependencies.pantry import get_current_pantry
from backend.services.expiration import get_status
from backend.models import InventoryItem, Pantry, ShoppingList, ShoppingListItem
from backend.schemas import (
    ShoppingListCreate,
    ShoppingListItemCheckedUpdate,
    ShoppingListItemCreate,
    ShoppingListItemOut,
    ShoppingListOut,
)
from backend.services.compartment import infer_compartment
from backend.services.shopping_markdown import to_shopping_markdown

router = APIRouter(prefix="/api/pantries/{pantry_id}/shopping-lists", tags=["shopping"])


def _get_pantry_or_404(db: Session, pantry_id: int) -> Pantry:
    pantry = db.query(Pantry).filter(Pantry.id == pantry_id).first()
    if not pantry:
        raise HTTPException(status_code=404, detail="Pantry non trovata")
    return pantry


def _get_list_or_404(db: Session, pantry_id: int, list_id: int) -> ShoppingList:
    lst = (
        db.query(ShoppingList)
        .filter(ShoppingList.id == list_id, ShoppingList.pantry_id == pantry_id)
        .first()
    )
    if not lst:
        raise HTTPException(status_code=404, detail="Shopping list non trovata")
    return lst


def _inventory_status(item: InventoryItem) -> str:
    return get_status(item.expiration_date)


@router.post("", response_model=ShoppingListOut, status_code=201)
def create_shopping_list(
    pantry_id: int,
    body: ShoppingListCreate,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    sl = ShoppingList(
        pantry_id=pantry_id,
        name=body.name,
        created_by_token=current_token,
    )
    db.add(sl)
    db.commit()
    db.refresh(sl)
    return ShoppingListOut(
        id=sl.id,
        pantry_id=sl.pantry_id,
        name=sl.name,
        created_at=sl.created_at,
        items=[],
    )


@router.get("", response_model=list[ShoppingListOut])
def list_shopping_lists(
    pantry_id: int,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lists = db.query(ShoppingList).filter(ShoppingList.pantry_id == pantry_id).all()
    result = []
    for lst in lists:
        items = (
            db.query(ShoppingListItem)
            .filter(ShoppingListItem.shopping_list_id == lst.id)
            .order_by(ShoppingListItem.id.asc())
            .all()
        )
        result.append(
            ShoppingListOut(
                id=lst.id,
                pantry_id=lst.pantry_id,
                name=lst.name,
                created_at=lst.created_at,
                items=items,
            )
        )
    return result


@router.get("/{list_id}", response_model=ShoppingListOut)
def get_shopping_list(
    pantry_id: int,
    list_id: int,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    items = (
        db.query(ShoppingListItem)
        .filter(ShoppingListItem.shopping_list_id == lst.id)
        .order_by(ShoppingListItem.id.asc())
        .all()
    )
    return ShoppingListOut(
        id=lst.id,
        pantry_id=lst.pantry_id,
        name=lst.name,
        created_at=lst.created_at,
        items=items,
    )


@router.delete("/{list_id}", status_code=204)
def delete_shopping_list(
    pantry_id: int,
    list_id: int,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    db.delete(lst)
    db.commit()
    return Response(status_code=204)


@router.post("/{list_id}/items", response_model=ShoppingListItemOut, status_code=201)
def add_item(
    pantry_id: int,
    list_id: int,
    body: ShoppingListItemCreate,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    compartment = body.compartment
    if not compartment:
        compartment = infer_compartment(name=body.name)
    item = ShoppingListItem(
        shopping_list_id=lst.id,
        name=body.name,
        quantity=body.quantity,
        compartment=compartment,
        checked=False,
        added_by_token=current_token,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.patch("/{list_id}/items/{item_id}", response_model=ShoppingListItemOut)
def patch_item(
    pantry_id: int,
    list_id: int,
    item_id: int,
    body: ShoppingListItemCheckedUpdate,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    item = (
        db.query(ShoppingListItem)
        .filter(
            ShoppingListItem.id == item_id,
            ShoppingListItem.shopping_list_id == lst.id,
        )
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item non trovato")
    item.checked = body.checked
    db.commit()
    db.refresh(item)
    return item


@router.delete("/{list_id}/items/{item_id}", status_code=204)
def delete_item(
    pantry_id: int,
    list_id: int,
    item_id: int,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    item = (
        db.query(ShoppingListItem)
        .filter(
            ShoppingListItem.id == item_id,
            ShoppingListItem.shopping_list_id == lst.id,
        )
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Item non trovato")
    db.delete(item)
    db.commit()
    return Response(status_code=204)


@router.get("/{list_id}/export")
def export_shopping_list(
    pantry_id: int,
    list_id: int,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    items = (
        db.query(ShoppingListItem)
        .filter(ShoppingListItem.shopping_list_id == lst.id)
        .order_by(ShoppingListItem.id.asc())
        .all()
    )
    md = to_shopping_markdown(lst, items)
    return PlainTextResponse(content=md, media_type="text/markdown")


@router.get("/{list_id}/check")
def check_shopping_list(
    pantry_id: int,
    list_id: int,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_current_pantry),
):
    _get_pantry_or_404(db, pantry_id)
    lst = _get_list_or_404(db, pantry_id, list_id)
    items = (
        db.query(ShoppingListItem)
        .filter(ShoppingListItem.shopping_list_id == lst.id)
        .order_by(ShoppingListItem.id.asc())
        .all()
    )
    pantry_items = (
        db.query(InventoryItem)
        .filter(InventoryItem.pantry_id == pantry_id)
        .all()
    )
    # mappa nome normalizzato -> inventory item (primo match) per status
    norm_map: dict[str, InventoryItem] = {}
    for pi in pantry_items:
        if not pi.name:
            continue
        norm = pi.name.strip().lower()
        if norm not in norm_map:
            norm_map[norm] = pi

    results = []
    for it in items:
        norm = (it.name or "").strip().lower()
        inv = norm_map.get(norm)
        in_pantry = inv is not None
        if in_pantry:
            status = _inventory_status(inv)
        else:
            status = "missing"
        results.append(
            {
                "id": it.id,
                "name": it.name,
                "inPantry": in_pantry,
                "status": status,
            }
        )
    return {"items": results}
