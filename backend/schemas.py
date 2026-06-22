from datetime import date, datetime, timedelta
from typing import Optional

from pydantic import BaseModel, ConfigDict, computed_field

from backend.config import EXPIRING_SOON_DAYS


class ScanRequest(BaseModel):
    barcode: str


class ScanResponse(BaseModel):
    barcode: str
    name: Optional[str] = None
    brand: Optional[str] = None
    categories: list[str] = []
    image_url: Optional[str] = None
    found: bool
    message: Optional[str] = None


class InventoryCreate(BaseModel):
    barcode: str
    name: str
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    category: Optional[str] = None
    image_url: Optional[str] = None


class InventoryCreateManual(BaseModel):
    name: str
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    category: Optional[str] = None


class InventoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    barcode: Optional[str] = None
    name: str
    brand: Optional[str] = None
    expiration_date: Optional[date] = None
    is_estimated: bool = False
    category: Optional[str] = None
    image_url: Optional[str] = None
    created_at: datetime

    @computed_field
    @property
    def status(self) -> str:
        if self.expiration_date is None:
            return "ok"
        today = date.today()
        if self.expiration_date < today:
            return "expired"
        if self.expiration_date <= today + timedelta(days=EXPIRING_SOON_DAYS):
            return "expiring_soon"
        return "ok"


class MessageResponse(BaseModel):
    message: str
