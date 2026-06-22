from datetime import datetime, timezone

from sqlalchemy import Boolean, Column, Date, DateTime, Integer, String

from backend.database import Base


class InventoryItem(Base):
    __tablename__ = "inventory_items"

    id = Column(Integer, primary_key=True, index=True)
    barcode = Column(String, nullable=True, index=True)
    name = Column(String, nullable=False)
    brand = Column(String, nullable=True)
    expiration_date = Column(Date, nullable=True)
    is_estimated = Column(Boolean, default=False)
    category = Column(String, nullable=True)
    image_url = Column(String, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
