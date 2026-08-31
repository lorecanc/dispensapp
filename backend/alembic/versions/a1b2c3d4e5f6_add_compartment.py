"""add compartment to shopping_list_items

Revision ID: a1b2c3d4e5f6
Revises: d4e5f6a7b8c9
Create Date: 2026-09-01

Add column compartment VARCHAR(32) to shopping_list_items if not exists (idempotent).
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "a1b2c3d4e5f6"
down_revision: Union[str, Sequence[str], None] = "d4e5f6a7b8c9"
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
    if not _has_table(inspector, "shopping_list_items"):
        return
    if _has_column(inspector, "shopping_list_items", "compartment"):
        return
    with op.batch_alter_table("shopping_list_items") as batch_op:
        batch_op.add_column(sa.Column("compartment", sa.String(length=32), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, "shopping_list_items"):
        return
    if not _has_column(inspector, "shopping_list_items", "compartment"):
        return
    with op.batch_alter_table("shopping_list_items") as batch_op:
        try:
            batch_op.drop_column("compartment")
        except Exception:
            pass
