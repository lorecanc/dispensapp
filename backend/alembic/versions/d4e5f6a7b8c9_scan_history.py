"""scan history + suggestions

Revision ID: d4e5f6a7b8c9
Revises: c8a3e7b1f2d5
Create Date: 2026-08-31
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, Sequence[str], None] = "c8a3e7b1f2d5"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if inspector.has_table("scan_history"):
        return
    op.create_table(
        "scan_history",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("barcode", sa.String(), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("category", sa.String(), nullable=True),
        sa.Column("times_scanned", sa.Integer(), server_default="1", nullable=False),
        sa.Column("last_scanned_at", sa.DateTime(), nullable=False),
    )
    try:
        op.create_index("ix_scan_history_barcode", "scan_history", ["barcode"], unique=True)
    except Exception:
        pass
    try:
        op.create_index("ix_scan_history_id", "scan_history", ["id"])
    except Exception:
        pass
    try:
        op.create_index("ix_scan_history_times_scanned", "scan_history", ["times_scanned"])
    except Exception:
        pass
    try:
        op.create_index("ix_scan_history_name", "scan_history", ["name"])
    except Exception:
        pass


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("scan_history"):
        return
    for idx in ["ix_scan_history_barcode", "ix_scan_history_name", "ix_scan_history_times_scanned", "ix_scan_history_id"]:
        try:
            op.drop_index(idx, table_name="scan_history")
        except Exception:
            pass
    op.drop_table("scan_history")
