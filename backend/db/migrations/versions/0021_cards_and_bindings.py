"""cards + user binding history

Separate physical card identity from per-user binding history:
- cards: stable BLE card metadata, unique by card_sn.
- card_bindings: user/card bind-unbind records. active_card_id is non-null only
  for the current binding, and a unique index on it enforces one active owner.

Revision ID: 0021_cards_and_bindings
Revises: 0020_chat_starters
Create Date: 2026-06-12
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0021_cards_and_bindings"
down_revision = "0020_chat_starters"
branch_labels = None
depends_on = None


def _dt():
    return sa.DateTime(timezone=True).with_variant(mysql.DATETIME(fsp=6), "mysql")


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    if not insp.has_table("cards"):
        op.create_table(
            "cards",
            sa.Column("id", sa.CHAR(36), primary_key=True),
            sa.Column("card_sn", sa.String(100), nullable=False),
            sa.Column("card_device_uuid", sa.String(100), nullable=False),
            sa.Column("card_mac", sa.String(100), nullable=True),
            sa.Column("card_mac_from", sa.String(20), nullable=True),
            sa.Column("card_name", sa.String(100), nullable=True),
            sa.Column("created_at", _dt(), nullable=False),
            sa.Column("updated_at", _dt(), nullable=False),
            sa.UniqueConstraint("card_sn", name="uq_cards_card_sn"),
        )
        op.create_index("idx_cards_device_uuid", "cards", ["card_device_uuid"])
        op.create_index("idx_cards_mac", "cards", ["card_mac"])

    if not insp.has_table("card_bindings"):
        op.create_table(
            "card_bindings",
            sa.Column("id", sa.CHAR(36), primary_key=True),
            sa.Column("user_id", sa.String(50), nullable=False),
            sa.Column("card_id", sa.CHAR(36), nullable=False),
            sa.Column("card_nick", sa.String(100), nullable=True),
            sa.Column("card_app_uuid", sa.String(100), nullable=False),
            sa.Column("bind_status", sa.String(20), nullable=False, server_default="bound"),
            sa.Column("bind_time", _dt(), nullable=False),
            sa.Column("unbind_time", _dt(), nullable=True),
            sa.Column("active_card_id", sa.CHAR(36), nullable=True),
            sa.Column("created_at", _dt(), nullable=False),
            sa.Column("updated_at", _dt(), nullable=False),
            sa.ForeignKeyConstraint(["card_id"], ["cards.id"], name="fk_card_bindings_card_id"),
            sa.ForeignKeyConstraint(
                ["active_card_id"],
                ["cards.id"],
                name="fk_card_bindings_active_card_id",
            ),
        )
        op.create_index(
            "idx_card_bindings_user_status",
            "card_bindings",
            ["user_id", "bind_status", "bind_time"],
        )
        op.create_index(
            "idx_card_bindings_card",
            "card_bindings",
            ["card_id", "bind_time"],
        )
        op.create_index(
            "idx_card_bindings_user_card",
            "card_bindings",
            ["user_id", "card_id"],
        )
        op.create_index(
            "uq_card_bindings_active_card",
            "card_bindings",
            ["active_card_id"],
            unique=True,
        )


def downgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    if insp.has_table("card_bindings"):
        op.drop_table("card_bindings")
    if insp.has_table("cards"):
        op.drop_table("cards")
