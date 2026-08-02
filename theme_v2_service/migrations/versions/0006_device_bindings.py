"""Add Theme V2 device binding persistence.

Revision ID: 0006_device_bindings
Revises: 0005_report_share
Create Date: 2026-08-02
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0006_device_bindings"
down_revision = "0005_report_share"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "cards",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("card_sn", sa.String(length=160), nullable=False),
        sa.Column("card_device_uuid", sa.String(length=255), nullable=False),
        sa.Column("card_mac", sa.String(length=64), nullable=True),
        sa.Column("card_mac_from", sa.String(length=64), nullable=True),
        sa.Column("card_name", sa.String(length=160), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("card_sn", name="uq_cards_card_sn"),
        mysql_charset="utf8mb4",
    )
    op.create_table(
        "card_bindings",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("card_id", sa.CHAR(length=36), nullable=False),
        sa.Column("active_card_id", sa.CHAR(length=36), nullable=True),
        sa.Column("card_nick", sa.String(length=160), nullable=True),
        sa.Column("card_app_uuid", sa.String(length=255), nullable=False),
        sa.Column("bind_status", sa.String(length=32), nullable=False),
        sa.Column("bind_time", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("unbind_time", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint(
            "bind_status IN ('bound', 'unbound')",
            name="ck_card_bindings_status",
        ),
        sa.ForeignKeyConstraint(
            ["active_card_id"],
            ["cards.id"],
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(["card_id"], ["cards.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "active_card_id",
            name="uq_card_bindings_active_card_id",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_card_bindings_user_status",
        "card_bindings",
        ["user_id", "bind_status", "bind_time"],
    )
    op.create_index(
        "ix_card_bindings_card_created",
        "card_bindings",
        ["card_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_table("card_bindings")
    op.drop_table("cards")
