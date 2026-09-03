"""consumption events + inventory quantity check

Revision ID: e5f6a7b8c9d0
Revises: b2c3d4e5f6a7
Create Date: 2026-09-03

- crea consumption_events (append-only, gestione expires a T2):
  id PK, pantry_id FK CASCADE NOT NULL, item_id FK SET NULL nullable,
  name_snapshot NOT NULL, barcode nullable, delta NOT NULL,
  reason, actor_token(36), created_at UTC default,
  INDEX pantry_id e INDEX (pantry_id, created_at)
- garantisce CHECK quantity >= 0 su inventory_items se manca
- garantisce indice pantry_id su inventory_items se manca
- Pantry/Member/Invite esistono già: solo FK, nessuna tabella duplicata
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "e5f6a7b8c9d0"
down_revision: Union[str, Sequence[str], None] = "b2c3d4e5f6a7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

CK_INVENTORY_QTY = "ck_inventory_items_quantity_nonnegative"


def _has_table(inspector, name: str) -> bool:
    try:
        return inspector.has_table(name)
    except Exception:
        return False


def _has_index(inspector, table: str, index_name: str) -> bool:
    try:
        return any(idx["name"] == index_name for idx in inspector.get_indexes(table))
    except Exception:
        return False


def _has_check(inspector, table: str, name: str) -> bool:
    try:
        return any(c.get("name") == name for c in inspector.get_check_constraints(table))
    except Exception:
        return False


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if not _has_table(inspector, "consumption_events"):
        op.create_table(
            "consumption_events",
            sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
            sa.Column("pantry_id", sa.Integer(), nullable=False),
            sa.Column("item_id", sa.Integer(), nullable=True),
            sa.Column("name_snapshot", sa.String(length=200), nullable=False),
            sa.Column("barcode", sa.String(), nullable=True),
            sa.Column("delta", sa.Integer(), nullable=False),
            sa.Column("reason", sa.Text(), nullable=True),
            sa.Column("actor_token", sa.String(length=36), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(["pantry_id"], ["pantries.id"], ondelete="CASCADE"),
            sa.ForeignKeyConstraint(
                ["item_id"], ["inventory_items.id"], ondelete="SET NULL"
            ),
        )
    # Indici pantry_id (idempotenti)
    inspector = sa.inspect(bind)
    if _has_table(inspector, "consumption_events"):
        if not _has_index(inspector, "consumption_events", "ix_consumption_events_pantry_id"):
            try:
                op.create_index(
                    "ix_consumption_events_pantry_id", "consumption_events", ["pantry_id"]
                )
            except Exception:
                pass
        if not _has_index(
            inspector, "consumption_events", "ix_consumption_events_pantry_created"
        ):
            try:
                op.create_index(
                    "ix_consumption_events_pantry_created",
                    "consumption_events",
                    ["pantry_id", "created_at"],
                )
            except Exception:
                pass
        if not _has_index(inspector, "consumption_events", "ix_consumption_events_id"):
            try:
                op.create_index("ix_consumption_events_id", "consumption_events", ["id"])
            except Exception:
                pass

    # CHECK quantity >= 0 su inventory_items se manca + indice pantry_id se manca
    inspector = sa.inspect(bind)
    if _has_table(inspector, "inventory_items"):
        if not _has_index(
            inspector, "inventory_items", "ix_inventory_items_pantry_id"
        ):
            try:
                op.create_index(
                    "ix_inventory_items_pantry_id", "inventory_items", ["pantry_id"]
                )
            except Exception:
                pass
        if not _has_check(inspector, "inventory_items", CK_INVENTORY_QTY):
            try:
                with op.batch_alter_table("inventory_items") as batch_op:
                    batch_op.create_check_constraint(
                        CK_INVENTORY_QTY, "quantity >= 0"
                    )
            except Exception:
                pass


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    if _has_table(inspector, "consumption_events"):
        for idx in [
            "ix_consumption_events_pantry_created",
            "ix_consumption_events_pantry_id",
            "ix_consumption_events_id",
        ]:
            if _has_index(inspector, "consumption_events", idx):
                try:
                    op.drop_index(idx, table_name="consumption_events")
                except Exception:
                    pass
        try:
            op.drop_table("consumption_events")
        except Exception:
            pass

    # Revert CHECK su inventory_items (best-effort, lascia dati intatti)
    try:
        inspector = sa.inspect(bind)
        if _has_table(inspector, "inventory_items") and _has_check(
            inspector, "inventory_items", CK_INVENTORY_QTY
        ):
            with op.batch_alter_table("inventory_items") as batch_op:
                batch_op.drop_constraint(CK_INVENTORY_QTY, type_="check")
    except Exception:
        pass
