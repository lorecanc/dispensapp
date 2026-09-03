import logging
import time
from typing import Optional

import httpx
from fastapi import APIRouter, Request
from fastapi import HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator

import backend.config as config
from backend.schemas import BARCODE_PATTERN
from backend.services.off import contribute_product

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["contribute"])

LANG_PATTERN = r"^[a-z]{2}(-[A-Z]{2})?$"

# Mitigazione abuse leggera senza nuove dipendenze (H1): rate limit
# in-memory per IP su POST /api/scan/contribute. Soglia: 10 req/min.
# TODO(prod): sostituire con slowapi/auth persistente (Redis) prima del go-live.
_RATE_LIMIT: dict[str, list[float]] = {}
_RATE_LIMIT_MAX = 10
_RATE_LIMIT_WINDOW = 60.0


def _check_rate_limit(ip: str) -> None:
    now = time.monotonic()
    hits = [t for t in _RATE_LIMIT.get(ip, []) if now - t < _RATE_LIMIT_WINDOW]
    if len(hits) >= _RATE_LIMIT_MAX:
        _RATE_LIMIT[ip] = hits
        raise HTTPException(status_code=429, detail="Troppe richieste, riprova tra poco")
    hits.append(now)
    _RATE_LIMIT[ip] = hits


class ContributeRequest(BaseModel):
    code: str = Field(pattern=BARCODE_PATTERN)
    product_name: Optional[str] = Field(default=None, max_length=200)
    brands: Optional[str] = Field(default=None, max_length=200)
    quantity: Optional[str] = Field(default=None, max_length=64)
    categories: Optional[str] = Field(default=None, max_length=500)
    consent_cc_bysa: bool
    lang: str = Field(default="it", max_length=8, pattern=LANG_PATTERN)

    @field_validator("lang", mode="before")
    @classmethod
    def normalize_lang(cls, v: object) -> object:
        if v is None or (isinstance(v, str) and not v.strip()):
            return "it"
        if not isinstance(v, str):
            return v
        s = v.strip()
        parts = s.split("-")
        return parts[0].lower() + (f"-{parts[1].upper()}" if len(parts) > 1 else "")

    @field_validator("product_name", "brands", "quantity", "categories")
    @classmethod
    def strip_optional(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None

    @model_validator(mode="after")
    def at_least_one_field(self):
        fields = (self.product_name, self.brands, self.quantity, self.categories)
        if all(f is None or not f.strip() for f in fields):
            raise ValueError("Almeno un campo da contribuire")
        return self


class ContributeResponse(BaseModel):
    ok: bool
    code: str
    message: Optional[str] = None


@router.post("/scan/contribute", response_model=ContributeResponse)
async def contribute_scan(body: ContributeRequest, request: Request):
    ip = request.client.host if request.client else "unknown"
    _check_rate_limit(ip)
    if not body.consent_cc_bysa:
        raise HTTPException(
            status_code=400,
            detail="Consenso CC BY-SA obbligatorio per contribuire a Open Food Facts",
        )
    if not config.OFF_WRITE_ENABLED:
        raise HTTPException(
            status_code=403,
            detail="Contribuzione a Open Food Facts disabilitata sul server",
        )
    try:
        result = await contribute_product(
            code=body.code,
            product_name=body.product_name,
            brands=body.brands,
            categories=body.categories,
            quantity=body.quantity,
            lang=body.lang,
        )
    except (httpx.HTTPError, ValueError):
        logger.warning("Contribuzione OFF fallita per %s: errore trasporto", body.code)
        raise HTTPException(
            status_code=502,
            detail="Errore durante la comunicazione con Open Food Facts",
        )
    if not isinstance(result, dict) or result.get("status") != 1:
        reason = result.get("reason") if isinstance(result, dict) else None
        logger.info("OFF ha rifiutato contributo per %s: %s", body.code, reason)
        raise HTTPException(
            status_code=502,
            detail="Open Food Facts ha rifiutato il contributo",
        )
    return ContributeResponse(ok=True, code=body.code, message="Contributo inviato a Open Food Facts")
