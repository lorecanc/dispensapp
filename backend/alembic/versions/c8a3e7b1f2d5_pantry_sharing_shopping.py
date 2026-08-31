"""pantry sharing shopping

Revision ID: c8a3e7b1f2d5
Revises: afda9b92019f
Create Date: 2026-08-31

Schema:
- pantries, pantry_members, invites, shopping_lists, shopping_list_items
- extend inventory_items with pantry_id, created_by_token, compartment + indexes
- backfill default pantry "La mia dispensa" if legacy data exists
"""

from datetime import datetime, timedelta, timezone
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "c8a3e7b1f2d5"
down_revision: Union[str, Sequence[str], None] = "afda9b92019f"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

DEFAULT_PANTRY_OWNER = "00000000-0000-0000-0000-000000000000"
DEFAULT_PANTRY_NAME = "La mia dispensa"


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


def _has_index(inspector, table: str, index_name: str) -> bool:
    try:
        return any(idx["name"] == index_name for idx in inspector.get_indexes(table))
    except Exception:
        return False


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    # --- pantries ---
    if not _has_table(inspector, "pantries"):
        op.create_table(
            "pantries",
            sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
            sa.Column("name", sa.String(length=100), nullable=False),
            sa.Column("owner_token", sa.String(length=36), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=True),
        )
        try:
            op.create_index("ix_pantries_owner_token", "pantries", ["owner_token"])
        except Exception:
            pass
        try:
            op.create_index("ix_pantries_id", "pantries", ["id"])
        except Exception:
            pass
    else:
        if not _has_index(inspector, "pantries", "ix_pantries_owner_token"):
            try:
                op.create_index("ix_pantries_owner_token", "pantries", ["owner_token"])
            except Exception:
                pass

    # --- pantry_members ---
    if not _has_table(inspector, "pantry_members"):
        op.create_table(
            "pantry_members",
            sa.Column("pantry_id", sa.Integer(), nullable=False),
            sa.Column("member_token", sa.String(length=36), nullable=False),
            sa.Column("role", sa.String(length=10), nullable=False),
            sa.Column("joined_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(["pantry_id"], ["pantries.id"], ondelete="CASCADE"),
            sa.PrimaryKeyConstraint("pantry_id", "member_token"),
        )
        try:
            op.create_index(
                "ix_pantry_members_member_token", "pantry_members", ["member_token"]
            )
        except Exception:
            pass
    else:
        if not _has_index(inspector, "pantry_members", "ix_pantry_members_member_token"):
            try:
                op.create_index(
                    "ix_pantry_members_member_token", "pantry_members", ["member_token"]
                )
            except Exception:
                pass

    # --- invites ---
    if not _has_table(inspector, "invites"):
        op.create_table(
            "invites",
            sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
            sa.Column("pantry_id", sa.Integer(), nullable=False),
            sa.Column("token", sa.String(length=36), nullable=False),
            sa.Column("created_by_token", sa.String(length=36), nullable=False),
            sa.Column("status", sa.String(length=10), nullable=False, server_default="pending"),
            sa.Column("expires_at", sa.DateTime(), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.Column("accepted_by_token", sa.String(length=36), nullable=True),
            sa.ForeignKeyConstraint(["pantry_id"], ["pantries.id"], ondelete="CASCADE"),
            sa.UniqueConstraint("token", name="uq_invites_token"),
        )
        for idx, cols in [
            ("ix_invites_pantry_id", ["pantry_id"]),
            ("ix_invites_token", ["token"]),
            ("ix_invites_id", ["id"]),
        ]:
            try:
                op.create_index(idx, "invites", cols)
            except Exception:
                pass
    else:
        for idx, cols in [
            ("ix_invites_pantry_id", ["pantry_id"]),
            ("ix_invites_token", ["token"]),
        ]:
            if not _has_index(inspector, "invites", idx):
                try:
                    op.create_index(idx, "invites", cols)
                except Exception:
                    pass

    # --- shopping_lists ---
    if not _has_table(inspector, "shopping_lists"):
        op.create_table(
            "shopping_lists",
            sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
            sa.Column("pantry_id", sa.Integer(), nullable=False),
            sa.Column("name", sa.String(length=100), nullable=False, server_default="Spesa"),
            sa.Column("created_by_token", sa.String(length=36), nullable=False),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(["pantry_id"], ["pantries.id"], ondelete="CASCADE"),
        )
        try:
            op.create_index("ix_shopping_lists_pantry_id", "shopping_lists", ["pantry_id"])
        except Exception:
            pass
        try:
            op.create_index("ix_shopping_lists_id", "shopping_lists", ["id"])
        except Exception:
            pass
    else:
        if not _has_index(inspector, "shopping_lists", "ix_shopping_lists_pantry_id"):
            try:
                op.create_index("ix_shopping_lists_pantry_id", "shopping_lists", ["pantry_id"])
            except Exception:
                pass

    # --- shopping_list_items ---
    if not _has_table(inspector, "shopping_list_items"):
        op.create_table(
            "shopping_list_items",
            sa.Column("id", sa.Integer(), primary_key=True, nullable=False),
            sa.Column("shopping_list_id", sa.Integer(), nullable=False),
            sa.Column("name", sa.String(length=200), nullable=False),
            sa.Column("quantity", sa.Integer(), nullable=False, server_default="1"),
            sa.Column("checked", sa.Boolean(), nullable=False, server_default="0"),
            sa.Column("added_by_token", sa.String(length=36), nullable=True),
            sa.Column("created_at", sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(
                ["shopping_list_id"], ["shopping_lists.id"], ondelete="CASCADE"
            ),
        )
        try:
            op.create_index(
                "ix_shopping_list_items_shopping_list_id",
                "shopping_list_items",
                ["shopping_list_id"],
            )
        except Exception:
            pass
        try:
            op.create_index("ix_shopping_list_items_id", "shopping_list_items", ["id"])
        except Exception:
            pass
    else:
        if not _has_index(
            inspector, "shopping_list_items", "ix_shopping_list_items_shopping_list_id"
        ):
            try:
                op.create_index(
                    "ix_shopping_list_items_shopping_list_id",
                    "shopping_list_items",
                    ["shopping_list_id"],
                )
            except Exception:
                pass

    # --- extend inventory_items (nullable, idempotente) ---
    if _has_table(inspector, "inventory_items"):
        # Use batch mode for SQLite FK support
        with op.batch_alter_table("inventory_items") as batch_op:
            if not _has_column(inspector, "inventory_items", "pantry_id"):
                batch_op.add_column(
                    sa.Column(
                        "pantry_id",
                        sa.Integer(),
                        nullable=True,
                    ),
                )
                # FK added via create_foreign_key to satisfy batch naming requirement
                try:
                    batch_op.create_foreign_key(
                        "fk_inventory_items_pantry_id",
                        "pantries",
                        ["pantry_id"],
                        ["id"],
                        ondelete="CASCADE",
                    )
                except Exception:
                    pass
            if not _has_column(inspector, "inventory_items", "created_by_token"):
                batch_op.add_column(
                    sa.Column("created_by_token", sa.String(length=36), nullable=True),
                )
            if not _has_column(inspector, "inventory_items", "compartment"):
                batch_op.add_column(
                    sa.Column("compartment", sa.String(length=32), nullable=True),
                )
        # indici compositi
        if not _has_index(inspector, "inventory_items", "ix_inventory_items_pantry_expiration"):
            try:
                op.create_index(
                    "ix_inventory_items_pantry_expiration",
                    "inventory_items",
                    ["pantry_id", "expiration_date"],
                )
            except Exception:
                pass
        if not _has_index(inspector, "inventory_items", "ix_inventory_items_pantry_created"):
            try:
                op.create_index(
                    "ix_inventory_items_pantry_created",
                    "inventory_items",
                    ["pantry_id", "created_at"],
                )
            except Exception:
                pass
        # index singolo pantry_id se non già creato da add_column
        if not _has_index(inspector, "inventory_items", "ix_inventory_items_pantry_id"):
            try:
                op.create_index(
                    "ix_inventory_items_pantry_id", "inventory_items", ["pantry_id"]
                )
            except Exception:
                pass

    # --- backfill: se inventory_items ha dati e pantries vuota, crea default pantry ---
    # Eseguito solo se entrambe le tabelle esistono (re-inspect per cache)
    try:
        inspector2 = sa.inspect(bind)
        if _has_table(inspector2, "inventory_items") and _has_table(inspector2, "pantries"):
            inv_count = bind.execute(sa.text("SELECT COUNT(*) FROM inventory_items")).scalar()
            pantry_count = bind.execute(sa.text("SELECT COUNT(*) FROM pantries")).scalar()
            if inv_count and inv_count > 0 and (pantry_count == 0 or pantry_count is None):
                now = datetime.now(timezone.utc)
                # Evita duplicati se owner già esistente (idempotente)
                exists = bind.execute(
                    sa.text("SELECT id FROM pantries WHERE owner_token = :o LIMIT 1"),
                    {"o": DEFAULT_PANTRY_OWNER},
                ).scalar()
                if not exists:
                    bind.execute(
                        sa.text(
                            "INSERT INTO pantries (name, owner_token, created_at) VALUES (:n, :o, :c)"
                        ),
                        {"n": DEFAULT_PANTRY_NAME, "o": DEFAULT_PANTRY_OWNER, "c": now},
                    )
                pantry_id = bind.execute(
                    sa.text("SELECT id FROM pantries WHERE owner_token = :o LIMIT 1"),
                    {"o": DEFAULT_PANTRY_OWNER},
                ).scalar()
                if pantry_id is not None:
                    bind.execute(
                        sa.text(
                            "UPDATE inventory_items SET pantry_id = :pid WHERE pantry_id IS NULL"
                        ),
                        {"pid": pantry_id},
                    )
    except Exception:
        # Backfill non deve bloccare upgrade
        pass


def downgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    # Rimuovi backfill? No: downgrade non cancella dati pantry se usata; ma idempotente drop tabelle/colonne.

    # Drop indici inventory_items compositi
    if _has_table(inspector, "inventory_items"):
        for idx in [
            "ix_inventory_items_pantry_expiration",
            "ix_inventory_items_pantry_created",
            "ix_inventory_items_pantry_id",
        ]:
            if _has_index(inspector, "inventory_items", idx):
                try:
                    op.drop_index(idx, table_name="inventory_items")
                except Exception:
                    pass
        # Drop colonne se esistono (batch mode per SQLite)
        cols_to_drop = [c for c in ["pantry_id", "created_by_token", "compartment"] if _has_column(inspector, "inventory_items", c)]
        if cols_to_drop:
            try:
                with op.batch_alter_table("inventory_items") as batch_op:
                    # drop FK if present
                    if "pantry_id" in cols_to_drop:
                        try:
                            batch_op.drop_constraint("fk_inventory_items_pantry_id", type_="foreignkey")
                        except Exception:
                            pass
                    for col in cols_to_drop:
                        try:
                            batch_op.drop_column(col)
                        except Exception:
                            pass
            except Exception:
                pass

    # Drop tabelle in ordine inverso (idempotente)
    for tbl in ["shopping_list_items", "shopping_lists", "invites", "pantry_members", "pantries"]:
        if _has_table(inspector, tbl):
            # drop indici prima (alcuni DB li droppano con tabella)
            try:
                idxs = inspector.get_indexes(tbl)
                for idx in idxs:
                    try:
                        op.drop_index(idx["name"], table_name=tbl)
                    except Exception:
                        pass
            except Exception:
                pass
            try:
                op.drop_table(tbl)
            except Exception:
                pass
