"""create_initial_tables

Revision ID: afda9b92019f
Revises: 
Create Date: 2026-08-31 22:46:30.290442

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'afda9b92019f'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create inventory_items baseline (idempotent — non distruttivo)."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if inspector.has_table("inventory_items"):
        return
    op.create_table(
        "inventory_items",
        sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
        sa.Column("barcode", sa.String(), nullable=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("brand", sa.String(), nullable=True),
        sa.Column("expiration_date", sa.Date(), nullable=True),
        sa.Column("is_estimated", sa.Boolean(), nullable=True),
        sa.Column("category", sa.String(), nullable=True),
        sa.Column("image_url", sa.String(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=True),
        sa.Column("quantity", sa.Integer(), server_default="1", nullable=False),
    )
    # indici idempotenti (has_table già garantisce tabella nuova, ma per sicurezza verifica)
    try:
        op.create_index("ix_inventory_items_barcode", "inventory_items", ["barcode"])
    except Exception:
        pass
    try:
        op.create_index("ix_inventory_items_id", "inventory_items", ["id"])
    except Exception:
        pass


def downgrade() -> None:
    """Drop inventory_items (idempotent)."""
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if not inspector.has_table("inventory_items"):
        return
    # drop indici se esistono (SQLite li droppa con tabella, ma per idempotenza)
    try:
        op.drop_index("ix_inventory_items_barcode", table_name="inventory_items")
    except Exception:
        pass
    try:
        op.drop_index("ix_inventory_items_id", table_name="inventory_items")
    except Exception:
        pass
    op.drop_table("inventory_items")
