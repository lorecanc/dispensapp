"""scan_history source + product_type

Revision ID: c4d5e6f7a8b9
Revises: b3c4d5e6f7a8
Create Date: 2026-09-06

Add columns source and product_type VARCHAR to scan_history if not exists
(idempotent). Entrambe nullable per non rompere dati legacy.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "c4d5e6f7a8b9"
down_revision: Union[str, Sequence[str], None] = "b3c4d5e6f7a8"
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
    if not _has_table(inspector, "scan_history"):
        return
    if not _has_column(inspector, "scan_history", "source"):
        with op.batch_alter_table("scan_history") as batch_op:
            batch_op.add_column(sa.Column("source", sa.String(), nullable=True))
    inspector = sa.inspect(bind)
    if not _has_column(inspector, "scan_history", "product_type"):
        with op.batch_alter_table("scan_history") as batch_op:
            batch_op.add_column(sa.Column("product_type", sa.String(), nullable=True))


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not _has_table(inspector, "scan_history"):
        return
    if _has_column(inspector, "scan_history", "product_type"):
        with op.batch_alter_table("scan_history") as batch_op:
            try:
                batch_op.drop_column("product_type")
            except Exception:
                pass
    inspector = sa.inspect(bind)
    if _has_column(inspector, "scan_history", "source"):
        with op.batch_alter_table("scan_history") as batch_op:
            try:
                batch_op.drop_column("source")
            except Exception:
                pass
