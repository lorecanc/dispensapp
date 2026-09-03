import logging
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.dependencies.pantry import PantryContext, get_current_pantry, get_pantry_context
from backend.models import Invite, Pantry, PantryMember
from backend.schemas import InviteCreate, InviteOut, MemberOut, PantryCreate, PantryOut

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["pantries"])


def _is_owner(db: Session, pantry: Pantry, token: str) -> bool:
    if pantry.owner_token == token:
        return True
    m = (
        db.query(PantryMember)
        .filter(PantryMember.pantry_id == pantry.id, PantryMember.member_token == token)
        .first()
    )
    return bool(m and m.role == "owner")


@router.get("/pantries", response_model=list[PantryOut])
def list_pantries(
    db: Session = Depends(get_db),
    current_token: str = Depends(get_pantry_context),
):
    member_ids = (
        db.query(PantryMember.pantry_id)
        .filter(PantryMember.member_token == current_token)
        .all()
    )
    ids = {r[0] for r in member_ids}
    q = db.query(Pantry)
    if ids:
        pantries = (
            q.filter((Pantry.owner_token == current_token) | (Pantry.id.in_(ids)))
            .order_by(Pantry.id.asc())
            .all()
        )
    else:
        pantries = (
            q.filter(Pantry.owner_token == current_token).order_by(Pantry.id.asc()).all()
        )
    return pantries


@router.post("/pantries", response_model=PantryOut, status_code=201)
def create_pantry(
    body: PantryCreate,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_pantry_context),
):
    pantry = Pantry(name=body.name, owner_token=current_token)
    try:
        db.add(pantry)
        db.flush()
        db.add(
            PantryMember(
                pantry_id=pantry.id, member_token=current_token, role="owner"
            )
        )
        db.commit()
        db.refresh(pantry)
    except Exception:
        db.rollback()
        logger.exception("Errore creazione pantry")
        raise HTTPException(status_code=500, detail="Errore interno durante la creazione")
    return pantry


@router.get("/pantries/{pantry_id}", response_model=PantryOut)
def get_pantry(
    pantry_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    pantry = ctx.pantry
    return pantry


@router.post("/pantries/{pantry_id}/invites", response_model=InviteOut, status_code=201)
def create_invite(
    pantry_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
    body: InviteCreate | None = None,
):
    pantry = ctx.pantry
    token = ctx.token
    if not _is_owner(db, pantry, token):
        raise HTTPException(
            status_code=403, detail="Solo l'owner può creare inviti"
        )
    invite = Invite(
        pantry_id=pantry.id,
        token=secrets.token_urlsafe(32),
        created_by_token=token,
        status="pending",
        expires_at=datetime.now(timezone.utc) + timedelta(days=7),
    )
    try:
        db.add(invite)
        db.commit()
        db.refresh(invite)
    except Exception:
        db.rollback()
        logger.exception("Errore creazione invito pantry %s", pantry_id)
        raise HTTPException(status_code=500, detail="Errore interno durante la creazione")
    return invite


@router.post("/invites/{token}/accept", response_model=InviteOut)
def accept_invite(
    token: str,
    db: Session = Depends(get_db),
    current_token: str = Depends(get_pantry_context),
):
    # Claim atomico: un solo accept vince; gli altri (scaduto, usato,
    # doppio click) vedono rowcount 0 -> 404 uniforme.
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    try:
        updated = (
            db.query(Invite)
            .filter(
                Invite.token == token,
                Invite.status == "pending",
                Invite.expires_at > now,
            )
            .update(
                {"status": "accepted", "accepted_by_token": current_token},
                synchronize_session=False,
            )
        )
        if updated == 0:
            db.rollback()
            raise HTTPException(status_code=404, detail="Invito non trovato")
        invite = db.query(Invite).filter(Invite.token == token).first()
        if not invite:
            db.rollback()
            raise HTTPException(status_code=404, detail="Invito non trovato")
        existing = (
            db.query(PantryMember)
            .filter(
                PantryMember.pantry_id == invite.pantry_id,
                PantryMember.member_token == current_token,
            )
            .first()
        )
        if not existing:
            db.add(
                PantryMember(
                    pantry_id=invite.pantry_id,
                    member_token=current_token,
                    role="editor",
                )
            )
        db.commit()
        db.refresh(invite)
    except HTTPException:
        raise
    except Exception:
        db.rollback()
        logger.exception("Errore accettazione invito")
        raise HTTPException(
            status_code=500, detail="Errore interno durante l'accettazione"
        )
    return invite


@router.get("/pantries/{pantry_id}/members", response_model=list[MemberOut])
def list_members(
    pantry_id: int,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    members = (
        db.query(PantryMember)
        .filter(PantryMember.pantry_id == pantry_id)
        .order_by(PantryMember.joined_at.asc())
        .all()
    )
    return members


@router.delete("/pantries/{pantry_id}/members/{member_token}", status_code=204)
def delete_member(
    pantry_id: int,
    member_token: str,
    db: Session = Depends(get_db),
    ctx: PantryContext = Depends(get_current_pantry),
):
    pantry = ctx.pantry
    token = ctx.token
    if not _is_owner(db, pantry, token):
        raise HTTPException(
            status_code=403, detail="Solo l'owner può rimuovere membri"
        )
    if member_token == pantry.owner_token:
        raise HTTPException(
            status_code=403, detail="L'owner non può rimuovere se stesso"
        )
    member = (
        db.query(PantryMember)
        .filter(
            PantryMember.pantry_id == pantry_id,
            PantryMember.member_token == member_token,
        )
        .first()
    )
    if not member:
        raise HTTPException(status_code=404, detail="Membro non trovato")
    if member.role == "owner":
        raise HTTPException(
            status_code=403, detail="L'owner non può rimuovere se stesso"
        )
    try:
        db.delete(member)
        db.commit()
    except Exception:
        db.rollback()
        logger.exception("Errore rimozione membro pantry %s", pantry_id)
        raise HTTPException(
            status_code=500, detail="Errore interno durante la cancellazione"
        )
    return Response(status_code=204)
