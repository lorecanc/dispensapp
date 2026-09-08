import logging
import re
import time
from typing import Optional

import httpx
from fastapi import APIRouter, File, Form, Request, UploadFile
from fastapi import HTTPException
from pydantic import BaseModel, Field, field_validator, model_validator

import backend.config as config
from backend.schemas import BARCODE_PATTERN
from backend.services.off import contribute_product, upload_product_image

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api", tags=["contribute"])

LANG_PATTERN = r"^[a-z]{2}(-[A-Z]{2})?$"

# Tipi scrittura OFF ammessi (T5): default food per retrocompatibilità.
_WRITE_PRODUCT_TYPES = frozenset({"food", "beauty", "petfood", "product"})


def _normalize_product_type(v: object) -> str:
    if v is None or (isinstance(v, str) and not v.strip()):
        return "food"
    if not isinstance(v, str):
        raise ValueError("product_type non valido")
    pt = v.strip().lower()
    if pt not in _WRITE_PRODUCT_TYPES:
        raise ValueError("product_type non valido")
    return pt

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
    labels: Optional[str] = Field(default=None, max_length=500)
    generic_name: Optional[str] = Field(default=None, max_length=200)
    comment: Optional[str] = Field(default=None, max_length=500)
    app_uuid: Optional[str] = Field(default=None, max_length=64)
    consent_cc_bysa: bool
    lang: str = Field(default="it", max_length=8, pattern=LANG_PATTERN)
    product_type: str = Field(default="food", max_length=16)

    @field_validator("product_type", mode="before")
    @classmethod
    def normalize_product_type(cls, v: object) -> object:
        return _normalize_product_type(v)

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

    @field_validator(
        "product_name", "brands", "quantity", "categories",
        "labels", "generic_name", "comment", "app_uuid",
    )
    @classmethod
    def strip_optional(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None

    @model_validator(mode="after")
    def at_least_one_field(self):
        # Solo campi prodotto; comment/app_uuid sono metadati e non bastano.
        fields = (
            self.product_name,
            self.generic_name,
            self.brands,
            self.quantity,
            self.categories,
            self.labels,
        )
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
            detail="Consenso CC BY-SA obbligatorio per contribuire a Open Facts",
        )
    if not config.OFF_WRITE_ENABLED:
        raise HTTPException(
            status_code=403,
            detail="Contribuzione a Open Facts disabilitata sul server",
        )
    try:
        result = await contribute_product(
            code=body.code,
            product_name=body.product_name,
            brands=body.brands,
            categories=body.categories,
            labels=body.labels,
            quantity=body.quantity,
            generic_name=body.generic_name,
            lang=body.lang,
            comment=body.comment,
            app_uuid=body.app_uuid,
            product_type=body.product_type,
        )
    except (httpx.HTTPError, ValueError):
        logger.warning("Contribuzione OFF fallita per %s: errore trasporto", body.code)
        raise HTTPException(
            status_code=502,
            detail="Errore durante la comunicazione con Open Facts",
        )
    if not isinstance(result, dict) or result.get("status") != 1:
        reason = result.get("reason") if isinstance(result, dict) else None
        logger.info("OFF ha rifiutato contributo per %s: %s", body.code, reason)
        raise HTTPException(
            status_code=502,
            detail="Open Facts ha rifiutato il contributo",
        )
    return ContributeResponse(ok=True, code=body.code, message="Contributo inviato a Open Facts")


# Viste OFF ammesse con suffisso lingua opzionale (_lc, 2 lettere minuscole)
# e forme senza suffisso per retrocompatibilità (es. front, front_it,
# front_en, other, other_it). Fail-closed: tutto il resto -> 422.
_PHOTO_IMAGEFIELD_RE = re.compile(r"^(?:front|ingredients|nutrition|packaging|other)(?:_[a-z]{2})?$")


def _is_valid_imagefield(v: str) -> bool:
    return bool(_PHOTO_IMAGEFIELD_RE.match(v or ""))


def _safe_filename(raw: str | None, fallback: str) -> str:
    if not raw:
        return fallback
    cleaned = raw.replace("\r", "").replace("\n", "").replace('"', "").replace("'", "")
    cleaned = re.sub(r"[^A-Za-z0-9._-]", "_", cleaned)[:128]
    return cleaned or fallback


def _photo_dimensions(data: bytes, kind: str) -> Optional[tuple[int, int]]:
    if kind == "png":
        if len(data) < 24 or data[12:16] != b"IHDR":
            return None
        w = int.from_bytes(data[16:20], "big")
        h = int.from_bytes(data[20:24], "big")
        return (w, h)
    if kind == "jpeg":
        # Scansione marker JPEG fino al primo SOF con dimensioni.
        pos = 2
        n = len(data)
        while pos + 4 <= n:
            if data[pos] != 0xFF:
                return None
            marker = data[pos + 1]
            pos += 2
            if marker in (0xD8, 0xD9, 0x01) or 0xD0 <= marker <= 0xD7:
                continue
            if pos + 2 > n:
                return None
            seg_len = int.from_bytes(data[pos : pos + 2], "big")
            if seg_len < 2 or pos + seg_len > n:
                return None
            if marker in (
                0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
            ):
                if seg_len >= 7:
                    h = int.from_bytes(data[pos + 3 : pos + 5], "big")
                    w = int.from_bytes(data[pos + 5 : pos + 7], "big")
                    return (w, h)
                return None
            pos += seg_len
        return None
    # HEIC: box ispe/ispe richiederebbe parsing meta completo; senza
    # dipendenze esterne si accetta senza controllo dimensioni.
    return None


_MIN_PHOTO_WIDTH = 640
_MIN_PHOTO_HEIGHT = 160
MAX_PHOTO_BYTES = 5 * 1024 * 1024
_PHOTO_CONTENT_TYPES = {
    "image/jpeg": "jpeg",
    "image/png": "png",
    "image/heic": "heic",
    "image/heif": "heic",
}
# Brand HEIC restrittivi: mif1/msf1 (container HEIF generici) esclusi di proposito.
# Un generico verrebbe comunque rifiutato da OFF dopo l'upload: meglio 415
# fail-closed subito, senza traffico verso OFF.
_HEIC_BRANDS = frozenset(
    {b"heic", b"heix", b"hevc", b"hevx", b"heim", b"heis", b"hevm", b"hevs"}
)


def _detect_photo_kind(data: bytes) -> Optional[str]:
    if data.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        if data[8:12] in _HEIC_BRANDS:
            return "heic"
        # Compatible brands dopo minor version (offset 16), entry da 4B.
        # Cap ai primi 32B di compat list (8 brand): fail-closed oltre.
        end = min(len(data), 16 + 32)
        offset = 16
        while offset + 4 <= end:
            if data[offset : offset + 4] in _HEIC_BRANDS:
                return "heic"
            offset += 4
    return None


@router.post("/scan/contribute/photo", response_model=ContributeResponse)
async def contribute_scan_photo(
    request: Request,
    code: str = Form(...),
    imagefield: str = Form(...),
    consent_cc_bysa: bool = Form(...),
    image: UploadFile = File(...),
    product_type: str = Form(default="food"),
):
    ip = request.client.host if request.client else "unknown"
    _check_rate_limit(ip)
    # Pre-check fail-fast sul Content-Length dichiarato (include overhead
    # multipart: +1KB di tolleranza) prima di leggere il body in memoria.
    # Prioritario su validazione product_type: 413 senza leggere il body.
    declared_length = request.headers.get("content-length", "")
    if declared_length.isdigit() and int(declared_length) > MAX_PHOTO_BYTES + 1024:
        raise HTTPException(status_code=413, detail="Immagine troppo grande (max 5MB)")
    try:
        pt = _normalize_product_type(product_type)
    except ValueError:
        raise HTTPException(status_code=422, detail="product_type non valido")
    if not consent_cc_bysa:
        raise HTTPException(
            status_code=400,
            detail="Consenso CC BY-SA obbligatorio per contribuire a Open Facts",
        )
    if not config.OFF_WRITE_ENABLED:
        raise HTTPException(
            status_code=403,
            detail="Contribuzione a Open Facts disabilitata sul server",
        )
    if not re.match(BARCODE_PATTERN, code or ""):
        raise HTTPException(status_code=422, detail="code non valido")
    if not _is_valid_imagefield(imagefield):
        raise HTTPException(status_code=422, detail="imagefield non valido")
    content = await image.read()
    if len(content) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=413, detail="Immagine troppo grande (max 5MB)")
    if not content:
        raise HTTPException(status_code=415, detail="Tipo immagine non consentito (JPEG/PNG/HEIC)")
    declared = (image.content_type or "").lower().split(";")[0].strip()
    expected_kind = _PHOTO_CONTENT_TYPES.get(declared)
    detected_kind = _detect_photo_kind(content)
    if expected_kind is None or detected_kind is None or expected_kind != detected_kind:
        raise HTTPException(
            status_code=415,
            detail="Tipo immagine non consentito (JPEG/PNG/HEIC)",
        )
    mime = {"jpeg": "image/jpeg", "png": "image/png"}.get(
        detected_kind,
        declared if declared in ("image/heic", "image/heif") else "image/heic",
    )
    dims = _photo_dimensions(content, detected_kind)
    if dims is not None and (dims[0] < _MIN_PHOTO_WIDTH or dims[1] < _MIN_PHOTO_HEIGHT):
        raise HTTPException(
            status_code=422,
            detail="Immagine troppo piccola (minimo 640x160 px)",
        )
    try:
        result = await upload_product_image(
            code=code,
            image_bytes=content,
            filename=_safe_filename(image.filename, f"{code}_{imagefield}"),
            mime=mime,
            imagefield=imagefield,
            product_type=pt,
        )
    except (httpx.HTTPError, ValueError):
        logger.warning("Contribuzione foto OFF fallita per %s: errore trasporto", code)
        raise HTTPException(
            status_code=502,
            detail="Errore durante la comunicazione con Open Facts",
        )
    if not isinstance(result, dict) or result.get("status") != 1:
        reason = result.get("reason") if isinstance(result, dict) else None
        logger.info("OFF ha rifiutato foto per %s: %s", code, reason)
        raise HTTPException(
            status_code=502,
            detail="Open Facts ha rifiutato il contributo",
        )
    return ContributeResponse(ok=True, code=code, message="Foto inviata a Open Facts")
