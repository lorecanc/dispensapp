from datetime import datetime, timedelta, timezone

from sqlalchemy import Boolean, CheckConstraint, Column, Date, DateTime, ForeignKey, Index, Integer, String, Text

from backend.database import Base


class Pantry(Base):
    __tablename__ = "pantries"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    owner_token = Column(String(36), nullable=False, index=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class PantryMember(Base):
    __tablename__ = "pantry_members"

    pantry_id = Column(
        Integer, ForeignKey("pantries.id", ondelete="CASCADE"), primary_key=True, nullable=False
    )
    member_token = Column(String(36), primary_key=True, nullable=False)
    role = Column(String(10), nullable=False)  # 'owner' | 'editor'
    joined_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("ix_pantry_members_member_token", "member_token"),
    )


class Invite(Base):
    __tablename__ = "invites"

    id = Column(Integer, primary_key=True, index=True)
    pantry_id = Column(
        Integer, ForeignKey("pantries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token = Column(String(64), nullable=False, unique=True, index=True)
    created_by_token = Column(String(36), nullable=False)
    status = Column(String(10), nullable=False, default="pending", server_default="pending")
    expires_at = Column(
        DateTime,
        nullable=False,
        default=lambda: datetime.now(timezone.utc) + timedelta(days=7),
    )
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    accepted_by_token = Column(String(36), nullable=True)


class ShoppingList(Base):
    __tablename__ = "shopping_lists"

    id = Column(Integer, primary_key=True, index=True)
    pantry_id = Column(
        Integer, ForeignKey("pantries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    name = Column(String(100), nullable=False, default="Spesa", server_default="Spesa")
    created_by_token = Column(String(36), nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class ShoppingListItem(Base):
    __tablename__ = "shopping_list_items"

    id = Column(Integer, primary_key=True, index=True)
    shopping_list_id = Column(
        Integer,
        ForeignKey("shopping_lists.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    name = Column(String(200), nullable=False)
    quantity = Column(Integer, nullable=False, default=1, server_default="1")
    checked = Column(Boolean, nullable=False, default=False, server_default="0")
    compartment = Column(String(32), nullable=True)
    added_by_token = Column(String(36), nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


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
    quantity = Column(Integer, nullable=False, default=1, server_default="1")
    # T3: dispensa + ownership + scomparto (NULLABLE per non rompere dati legacy)
    pantry_id = Column(
        Integer, ForeignKey("pantries.id", ondelete="CASCADE"), nullable=True, index=True
    )
    created_by_token = Column(String(36), nullable=True)
    compartment = Column(String(32), nullable=True)

    __table_args__ = (
        Index("ix_inventory_items_pantry_expiration", "pantry_id", "expiration_date"),
        Index("ix_inventory_items_pantry_created", "pantry_id", "created_at"),
        CheckConstraint("quantity >= 0", name="ck_inventory_items_quantity_nonnegative"),
    )


class ScanHistory(Base):
    __tablename__ = "scan_history"

    id = Column(Integer, primary_key=True, index=True)
    barcode = Column(String, nullable=False, unique=True, index=True)
    name = Column(String, nullable=False)
    category = Column(String, nullable=True)
    times_scanned = Column(Integer, nullable=False, default=1, server_default="1")
    last_scanned_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (
        Index("ix_scan_history_times_scanned", "times_scanned"),
        Index("ix_scan_history_name", "name"),
    )


# T1: ledger consumi append-only (no update/delete API); gestione expires a T2.
class ConsumptionEvent(Base):
    __tablename__ = "consumption_events"

    id = Column(Integer, primary_key=True, index=True)
    pantry_id = Column(
        Integer, ForeignKey("pantries.id", ondelete="CASCADE"), nullable=False, index=True
    )
    item_id = Column(
        Integer,
        ForeignKey("inventory_items.id", ondelete="SET NULL"),
        nullable=True,
    )
    name_snapshot = Column(String(200), nullable=False)
    barcode = Column(String, nullable=True)
    delta = Column(Integer, nullable=False)
    reason = Column(Text, nullable=True)
    # Privacy: actor_token non persistito (stop write + colonna rimossa).
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (
        Index("ix_consumption_events_pantry_created", "pantry_id", "created_at"),
    )
