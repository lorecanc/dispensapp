from datetime import date, datetime, timedelta, timezone
from typing import Annotated, Optional

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, PlainSerializer, computed_field, field_validator, model_validator

from backend.services.expiration import get_status

# EAN-8 / UPC-A / EAN-13 / EAN-14
BARCODE_PATTERN = r"^\d{8,14}$"

# Storage resta UTC naive; la serializzazione aggiunge il suffisso +00:00
# richiesto dal decoder iOS. Pydantic 2 emette "Z" per datetime UTC aware nel
# JSON, quindi si formatta con isoformat() e si mantiene lo schema date-time.
UtcDatetime = Annotated[
    datetime,
    PlainSerializer(
        lambda dt: (dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt).isoformat(),
        return_type=Annotated[str, Field(json_schema_extra={"format": "date-time"})],
    ),
]


def _validate_expiration(v: Optional[date]) -> Optional[date]:
    if v is None:
        return v
    today = date.today()
    # rifiuta date assurde: >2 anni nel passato o >10 anni nel futuro
    if v < today - timedelta(days=730):
        raise ValueError("expiration_date troppo nel passato")
    if v > today + timedelta(days=3650):
        raise ValueError("expiration_date troppo nel futuro")
    return v


def _strip_not_empty(v: Optional[str], field_name: str = "campo") -> Optional[str]:
    if v is None:
        return v
    stripped = v.strip()
    if not stripped:
        raise ValueError(f"{field_name} non può essere vuoto")
    return stripped


def _validate_off_tags(v: Optional[list[str]]) -> Optional[list[str]]:
    # Lunghezza max lista (50) delegata a Field(max_length=...); qui max 200/tag.
    if v is None:
        return v
    for tag in v:
        if len(tag) > 200:
            raise ValueError("tag off_category_tags troppo lungo (max 200 caratteri)")
    return v


class ScanRequest(BaseModel):
    barcode: str = Field(pattern=BARCODE_PATTERN)


class ScanResponse(BaseModel):
    barcode: str
    name: Optional[str] = None
    brand: Optional[str] = None
    categories: list[str] = []
    suggested_category: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    found: bool
    message: Optional[str] = None
    source: Optional[str] = None
    product_type: Optional[str] = None
    pnns_group: Optional[str] = Field(default=None, max_length=64)


class InventoryCreate(BaseModel):
    barcode: str = Field(pattern=BARCODE_PATTERN)
    name: str = Field(min_length=1)
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    category: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    quantity: int = Field(default=1, ge=1, le=999)
    compartment: Optional[str] = Field(default=None, max_length=32)
    off_category_tags: Optional[list[str]] = Field(default=None, max_length=50)
    storage_location: Optional[str] = Field(default=None, max_length=16)
    source: Optional[str] = Field(default=None, max_length=32)
    product_type: Optional[str] = Field(default=None, max_length=32)
    pnns_group: Optional[str] = Field(default=None, max_length=64)

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name non può essere vuoto")
        return stripped

    @field_validator("brand", "category", "compartment", "storage_location", "source", "product_type", "pnns_group")
    @classmethod
    def strip_optional(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None

    @field_validator("off_category_tags")
    @classmethod
    def validate_off_tags(cls, v: Optional[list[str]]) -> Optional[list[str]]:
        return _validate_off_tags(v)

    @field_validator("expiration_date")
    @classmethod
    def validate_expiration(cls, v: Optional[date]) -> Optional[date]:
        return _validate_expiration(v)


class InventoryCreateManual(BaseModel):
    name: str = Field(min_length=1)
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    category: Optional[str] = None
    quantity: int = Field(default=1, ge=1, le=999)
    image_url: Optional[HttpUrl] = None
    compartment: Optional[str] = Field(default=None, max_length=32)
    off_category_tags: Optional[list[str]] = Field(default=None, max_length=50)
    storage_location: Optional[str] = Field(default=None, max_length=16)
    source: Optional[str] = Field(default=None, max_length=32)
    product_type: Optional[str] = Field(default=None, max_length=32)
    pnns_group: Optional[str] = Field(default=None, max_length=64)

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name non può essere vuoto")
        return stripped

    @field_validator("brand", "category", "compartment", "storage_location", "source", "product_type", "pnns_group")
    @classmethod
    def strip_optional(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None

    @field_validator("off_category_tags")
    @classmethod
    def validate_off_tags(cls, v: Optional[list[str]]) -> Optional[list[str]]:
        return _validate_off_tags(v)

    @field_validator("expiration_date")
    @classmethod
    def validate_expiration(cls, v: Optional[date]) -> Optional[date]:
        return _validate_expiration(v)


class InventoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    barcode: Optional[str] = None
    name: str
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    is_estimated: bool = False
    category: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    created_at: UtcDatetime
    quantity: int = 1
    compartment: Optional[str] = None
    pantry_id: Optional[int] = None
    # Raw dal DB: NULL = non impostato, il client deriva il luogo dalla categoria.
    storage_location: Optional[str] = None
    source: Optional[str] = None
    product_type: Optional[str] = None

    @computed_field
    @property
    def status(self) -> str:
        return get_status(self.expiration_date)


class InventoryUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1)
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    category: Optional[str] = None
    image_url: Optional[HttpUrl] = None
    quantity: Optional[int] = Field(default=None, ge=1, le=999)
    compartment: Optional[str] = Field(default=None, max_length=32)
    storage_location: Optional[str] = Field(default=None, max_length=16)

    @field_validator("name", "brand", "category", "compartment", "storage_location")
    @classmethod
    def strip_optional_fields(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        if v is not None and not stripped:
            raise ValueError("campo non può essere vuoto o solo spazi")
        return stripped

    @field_validator("expiration_date")
    @classmethod
    def validate_expiration(cls, v: Optional[date]) -> Optional[date]:
        return _validate_expiration(v)

    @model_validator(mode="after")
    def at_least_one_field(self):
        if not self.model_fields_set:
            raise ValueError("Almeno un campo da aggiornare")
        return self


class InventoryConsume(BaseModel):
    delta: int = Field(ge=1, le=999)
    reason: Optional[str] = Field(default=None, max_length=500)

    @field_validator("reason")
    @classmethod
    def strip_reason(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None


class ConsumptionEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    pantry_id: int
    item_id: Optional[int] = None
    name_snapshot: str
    barcode: Optional[str] = None
    delta: int
    reason: Optional[str] = None
    created_at: UtcDatetime


# --- Pantry / Invites / Members (T2) ---


class PantryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name non può essere vuoto")
        return stripped


class PantryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    created_at: UtcDatetime


class InviteCreate(BaseModel):
    # Token opzionale: ignorato su create (server genera), usato solo per
    # accept-by-body POST /invites/accept {token}.
    token: Optional[str] = Field(default=None, max_length=64)

    @field_validator("token")
    @classmethod
    def strip_token(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None


class InviteOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    pantry_id: int
    token: str
    status: str
    expires_at: UtcDatetime
    created_at: UtcDatetime


class MemberOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    pantry_id: int
    role: str
    joined_at: UtcDatetime


class MessageResponse(BaseModel):
    message: str


# --- ShoppingList (T4) ---


class ShoppingListCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name non può essere vuoto")
        return stripped


class ShoppingListItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    quantity: int = Field(default=1, ge=1, le=999)
    compartment: Optional[str] = Field(default=None, max_length=32)

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        stripped = v.strip()
        if not stripped:
            raise ValueError("name non può essere vuoto")
        return stripped

    @field_validator("compartment")
    @classmethod
    def validate_compartment(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return v
        stripped = v.strip()
        return stripped or None


class ShoppingListItemCheckedUpdate(BaseModel):
    checked: bool


class ShoppingListItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    shopping_list_id: int
    name: str
    quantity: int
    checked: bool
    compartment: Optional[str] = None
    created_at: UtcDatetime


class ShoppingListOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    pantry_id: int
    name: str
    created_at: UtcDatetime
    items: list[ShoppingListItemOut] = []
