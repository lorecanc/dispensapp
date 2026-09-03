"""remove consumption_events.actor_token (privacy)

Revision ID: a2b3c4d5e6f7
Revises: f1a2b3c4d5e6
Create Date: 2026-09-04

- stop write già applicato in _consume_scoped_item (token non persistito);
- rimuove la colonna actor_token da consumption_events (best-effort,
  idempotente): nessun cambio semantica API, ConsumptionEventOut non
  esponeva già il campo.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "a2b3c4d5e6f7"
down_revision: Union[str, Sequence[str], None] = "f1a2b3c4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _has_table(inspector, name: str) -> bool:
    try:
        return inspector.has_table(name)
    except Exception:
        return False


def _has_column(inspector, table: str, column: str) -> bool:
    try:
        return any(c["name"] == column for c in inspector.get_columns(table))
    except Exception:
        return False


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if _has_table(inspector, "consumption_events") and _has_column(
        inspector, "consumption_events", "actor_token"
    ):
        try:
            with op.batch_alter_table("consumption_events") as batch_op:
                batch_op.drop_column("actor_token")
        except Exception:
            pass


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if _has_table(inspector, "consumption_events") and not _has_column(
        inspector, "consumption_events", "actor_token"
    ):
        try:
            with op.batch_alter_table("consumption_events") as batch_op:
                batch_op.add_column(
                    sa.Column("actor_token", sa.String(length=36), nullable=True)
                )
        except Exception:
            pass
