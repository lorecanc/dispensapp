"""fix yogurt alias to yogurts

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-09-01

Normalize legacy category 'yogurt' to canonical 'yogurts' (idempotent).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, Sequence[str], None] = "a1b2c3d4e5f6"
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
    if not _has_column(inspector, "inventory_items", "category"):
        return
    try:
        bind.execute(sa.text("UPDATE inventory_items SET category='yogurts' WHERE category='yogurt'"))
    except Exception:
        pass


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, "inventory_items"):
        return
    if not _has_column(inspector, "inventory_items", "category"):
        return
    # Best-effort revert (downgrade non deve bloccare)
    try:
        bind.execute(sa.text("UPDATE inventory_items SET category='yogurt' WHERE category='yogurts'"))
    except Exception:
        pass
