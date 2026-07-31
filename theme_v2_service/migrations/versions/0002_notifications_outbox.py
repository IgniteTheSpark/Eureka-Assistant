"""Add persistent notifications and the transactional outbox.

Revision ID: 0002_notifications_outbox
Revises: 0001_foundation
Create Date: 2026-07-31
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0002_notifications_outbox"
down_revision = "0001_foundation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "notifications",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("type", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("link", sa.String(length=255), nullable=True),
        sa.Column("read", sa.Boolean(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_notifications_user_created",
        "notifications",
        ["user_id", "created_at"],
    )
    op.create_index(
        "ix_notifications_user_read_created",
        "notifications",
        ["user_id", "read", "created_at"],
    )

    op.create_table(
        "outbox_events",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("event_type", sa.String(length=100), nullable=False),
        sa.Column("aggregate_type", sa.String(length=100), nullable=False),
        sa.Column("aggregate_id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("payload_json", mysql.JSON(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("available_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("attempt", sa.Integer(), nullable=False),
        sa.Column("published_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("last_error", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_outbox_events_publish",
        "outbox_events",
        ["published_at", "available_at", "id"],
    )


def downgrade() -> None:
    op.drop_index("ix_outbox_events_publish", table_name="outbox_events")
    op.drop_table("outbox_events")
    op.drop_index(
        "ix_notifications_user_read_created",
        table_name="notifications",
    )
    op.drop_index("ix_notifications_user_created", table_name="notifications")
    op.drop_table("notifications")
