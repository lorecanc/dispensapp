"""invite token 64 + backfill pantry NULL

Revision ID: f1a2b3c4d5e6
Revises: e5f6a7b8c9d0
Create Date: 2026-09-04

- allarga invites.token a String(64): secrets.token_urlsafe(32) produce
  ~43 caratteri e troncava/violava String(36)
- backfill idempotente: righe inventory_items con pantry_id NULL -> pantry
  di default (MIN(id) esistente, o creata "La mia dispensa" se assente)
"""

from datetime import datetime, timezone
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "f1a2b3c4d5e6"
down_revision: Union[str, Sequence[str], None] = "e5f6a7b8c9d0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

DEFAULT_PANTRY_OWNER = "00000000-0000-0000-0000-000000000000"
DEFAULT_PANTRY_NAME = "La mia dispensa"


def _has_table(inspector, name: str) -> bool:
    try:
        return inspector.has_table(name)
    except Exception:
        return False


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    # --- invites.token -> String(64) (idempotente) ---
    if _has_table(inspector, "invites"):
        try:
            cols = {c["name"]: c for c in inspector.get_columns("invites")}
            current_len = getattr(cols.get("token", {}).get("type"), "length", None)
        except Exception:
            current_len = None
        if current_len is None or current_len < 64:
            try:
                with op.batch_alter_table("invites") as batch_op:
                    batch_op.alter_column(
                        "token",
                        existing_type=sa.String(length=36),
                        type_=sa.String(length=64),
                        existing_nullable=False,
                    )
            except Exception:
                pass

    # --- backfill pantry_id NULL -> default pantry (idempotente) ---
    try:
        inspector2 = sa.inspect(bind)
        if _has_table(inspector2, "inventory_items") and _has_table(
            inspector2, "pantries"
        ):
            null_count = bind.execute(
                sa.text("SELECT COUNT(*) FROM inventory_items WHERE pantry_id IS NULL")
            ).scalar()
            if null_count:
                pantry_id = bind.execute(
                    sa.text("SELECT MIN(id) FROM pantries")
                ).scalar()
                if pantry_id is None:
                    now = datetime.now(timezone.utc)
                    bind.execute(
                        sa.text(
                            "INSERT INTO pantries (name, owner_token, created_at)"
                            " VALUES (:n, :o, :c)"
                        ),
                        {"n": DEFAULT_PANTRY_NAME, "o": DEFAULT_PANTRY_OWNER, "c": now},
                    )
                    pantry_id = bind.execute(
                        sa.text("SELECT MIN(id) FROM pantries")
                    ).scalar()
                if pantry_id is not None:
                    bind.execute(
                        sa.text(
                            "UPDATE inventory_items SET pantry_id = :pid"
                            " WHERE pantry_id IS NULL"
                        ),
                        {"pid": pantry_id},
                    )
    except Exception:
        # Backfill non deve bloccare upgrade
        pass


def downgrade() -> None:
    # Backfill non reversibile (dati preservati); restringimento colonna
    # best-effort solo se nessun token eccede 36 caratteri.
    try:
        bind = op.get_bind()
        inspector = sa.inspect(bind)
        if _has_table(inspector, "invites"):
            long_count = bind.execute(
                sa.text("SELECT COUNT(*) FROM invites WHERE LENGTH(token) > 36")
            ).scalar()
            if not long_count:
                with op.batch_alter_table("invites") as batch_op:
                    batch_op.alter_column(
                        "token",
                        existing_type=sa.String(length=64),
                        type_=sa.String(length=36),
                        existing_nullable=False,
                    )
    except Exception:
        pass
