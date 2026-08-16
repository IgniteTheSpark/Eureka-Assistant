"""Add advance reminder delivery and overdue snooze persistence.

Revision ID: 0024_reka_reminders
Revises: 0023_report_async_illustration
Create Date: 2026-08-14
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0024_reka_reminders"
down_revision = "0023_report_async_illustration"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "events",
        sa.Column("reminder_offsets_json", mysql.JSON(), nullable=True),
    )
    op.add_column(
        "nudges",
        sa.Column("remind_again_at", mysql.DATETIME(fsp=6), nullable=True),
    )
    op.create_index(
        "ix_nudges_remind_again",
        "nudges",
        ["remind_again_at"],
        unique=False,
    )
    op.create_table(
        "reminder_deliveries",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("natural_key", sa.String(length=255), nullable=False),
        sa.Column("record_kind", sa.String(length=16), nullable=False),
        sa.Column("record_id", sa.CHAR(length=36), nullable=False),
        sa.Column("anchor_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("offset_minutes", sa.Integer(), nullable=False),
        sa.Column("notification_id", sa.CHAR(length=36), nullable=True),
        sa.Column(
            "delivered_at",
            mysql.DATETIME(fsp=6),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP(6)"),
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "natural_key",
            name="uq_reminder_deliveries_user_natural_key",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_reminder_deliveries_user_delivered",
        "reminder_deliveries",
        ["user_id", "delivered_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_reminder_deliveries_user_delivered",
        table_name="reminder_deliveries",
    )
    op.drop_table("reminder_deliveries")
    op.drop_index("ix_nudges_remind_again", table_name="nudges")
    op.drop_column("nudges", "remind_again_at")
    op.drop_column("events", "reminder_offsets_json")
