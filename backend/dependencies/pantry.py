"""Pantry context dependency (T3 placeholder).

Non applicato globalmente alle route esistenti per non rompere iOS attuale.
Le future route /api/pantries e inventari filtrati useranno questo Depends.

Header:
  X-Pantry-Token: UUID v4/qualsiasi (String 36)

Comportamento:
  - 401 se header mancante
  - 401 se malformato (non UUID)
"""

import uuid

from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from backend.database import get_db
from backend.models import Pantry, PantryMember


class PantryContext(str):
    """Str compatibile che espone anche dict/context con pantry e token.

    - Si comporta come str (token) per compatibilità con route esistenti
      che fanno `created_by_token=current_token`.
    - Espone `ctx.pantry`, `ctx.token`, `ctx["pantry"]`, `ctx["token"]`
      per il nuovo contratto dict/context.
    """

    _token: str
    _pantry: object
    token: str  # alias pubblico
    pantry: object  # alias pubblico

    def __new__(cls, token: str, pantry):
        obj = super().__new__(cls, token)
        object.__setattr__(obj, "_token", token)
        object.__setattr__(obj, "_pantry", pantry)
        object.__setattr__(obj, "token", token)
        object.__setattr__(obj, "pantry", pantry)
        return obj

    def __getitem__(self, key):  # type: ignore[override]
        if key == "token":
            return self._token
        if key == "pantry":
            return self._pantry
        if isinstance(key, int):
            return super().__getitem__(key)
        if isinstance(key, slice):
            return super().__getitem__(key)
        raise KeyError(key)

    def get(self, key, default=None):  # type: ignore[override]
        if key == "token":
            return self._token
        if key == "pantry":
            return self._pantry
        return default

    def __contains__(self, key):  # type: ignore[override]
        if key in ("token", "pantry"):
            return True
        return super().__contains__(key)


def get_pantry_context(
    x_pantry_token: str | None = Header(default=None, alias="X-Pantry-Token"),
) -> str:
    if not x_pantry_token:
        raise HTTPException(status_code=401, detail="X-Pantry-Token header mancante")
    try:
        uuid.UUID(x_pantry_token)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=401, detail="X-Pantry-Token malformato")
    return x_pantry_token


def get_current_pantry(
    pantry_id: int,
    x_pantry_token: str | None = Header(default=None, alias="X-Pantry-Token"),
    db: Session = Depends(get_db),
) -> PantryContext:
    """Valida header, verifica membership e ritorna context.

    - 401 se header mancante o malformato (non UUID)
    - 404 se pantry non esiste
    - 403 se token non è owner né in pantry_members
    - ritorna PantryContext (str + dict/context con pantry e token)
    """
    if not x_pantry_token:
        raise HTTPException(status_code=401, detail="X-Pantry-Token header mancante")
    try:
        uuid.UUID(x_pantry_token)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=401, detail="X-Pantry-Token malformato")

    pantry = db.query(Pantry).filter(Pantry.id == pantry_id).first()
    if not pantry:
        raise HTTPException(status_code=404, detail="Pantry non trovata")

    if getattr(pantry, "owner_token") == x_pantry_token:  # type: ignore[comparison-overlap]
        return PantryContext(x_pantry_token, pantry)

    member = (
        db.query(PantryMember)
        .filter(
            PantryMember.pantry_id == pantry_id,
            PantryMember.member_token == x_pantry_token,
        )
        .first()
    )
    if member:
        return PantryContext(x_pantry_token, pantry)

    # 403 (non 404 uniforme): distingue "pantry inesistente" da "non membro"
    # per compatibilità con iOS e test esistenti; il 404 uniforme anti-enumerazione
    # resta una opzione futura se il client verrà aggiornato.
    raise HTTPException(status_code=403, detail="Non membro della pantry")
