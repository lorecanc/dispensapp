"""add storage_location to inventory_items

Revision ID: b3c4d5e6f7a8
Revises: a2b3c4d5e6f7
Create Date: 2026-09-05

Add column storage_location VARCHAR(16) to inventory_items if not exists
(idempotent). Nessun backfill: NULL = "derivato dalla categoria" by design.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "b3c4d5e6f7a8"
down_revision: Union[str, Sequence[str], None] = "a2b3c4d5e6f7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_table(inspector, name: str) -> bool:
    try:
        return inspector.has_table(name)
    except Exception:
        return False


def _has_column(inspector, table: str, col: str) -> bool:
    try:
        cols = [c["name"] for c in inspector.get_columns(table)]
        return col in cols
    except Exception:
        return False


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, "inventory_items"):
        return
    if _has_column(inspector, "inventory_items", "storage_location"):
        return
    with op.batch_alter_table("inventory_items") as batch_op:
        batch_op.add_column(
            sa.Column("storage_location", sa.String(length=16), nullable=True)
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, "inventory_items"):
        return
    if not _has_column(inspector, "inventory_items", "storage_location"):
        return
    with op.batch_alter_table("inventory_items") as batch_op:
        try:
            batch_op.drop_column("storage_location")
        except Exception:
            pass
