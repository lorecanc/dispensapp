"""inventory_items source + product_type

Revision ID: d5e6f7a8b9c0
Revises: c4d5e6f7a8b9
Create Date: 2026-09-06

Add columns source and product_type VARCHAR to inventory_items if not exists
(idempotent). Entrambe nullable per non rompere dati legacy, nessun backfill.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "d5e6f7a8b9c0"
down_revision: Union[str, Sequence[str], None] = "c4d5e6f7a8b9"
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
    if not _has_column(inspector, "inventory_items", "source"):
        with op.batch_alter_table("inventory_items") as batch_op:
            batch_op.add_column(sa.Column("source", sa.String(), nullable=True))
    inspector = sa.inspect(bind)
    if not _has_column(inspector, "inventory_items", "product_type"):
        with op.batch_alter_table("inventory_items") as batch_op:
            batch_op.add_column(sa.Column("product_type", sa.String(), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, "inventory_items"):
        return
    if _has_column(inspector, "inventory_items", "product_type"):
        with op.batch_alter_table("inventory_items") as batch_op:
            try:
                batch_op.drop_column("product_type")
            except Exception:
                pass
    inspector = sa.inspect(bind)
    if _has_column(inspector, "inventory_items", "source"):
        with op.batch_alter_table("inventory_items") as batch_op:
            try:
                batch_op.drop_column("source")
            except Exception:
                pass
