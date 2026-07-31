"""Add durable trigger trackers and executions.

Revision ID: 0003_triggers
Revises: 0002_notifications_outbox
Create Date: 2026-07-31
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0003_triggers"
down_revision = "0002_notifications_outbox"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "trigger_trackers",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("trigger_type", sa.String(length=32), nullable=False),
        sa.Column("scope_type", sa.String(length=32), nullable=False),
        sa.Column("scope_id", sa.CHAR(length=36), nullable=False),
        sa.Column("cycle_started_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("new_asset_count", sa.Integer(), nullable=False),
        sa.Column("active_execution_id", sa.CHAR(length=36), nullable=True),
        sa.Column("last_notified_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("last_notified_local_date", sa.Date(), nullable=True),
        sa.Column("dismissed_until", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column(
            "proactive_suppressed_until",
            mysql.DATETIME(fsp=6),
            nullable=True,
        ),
        sa.Column("last_consumed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("metadata_json", mysql.JSON(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint(
            "new_asset_count >= 0",
            name="ck_trigger_trackers_asset_count_nonnegative",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "trigger_type",
            "scope_type",
            "scope_id",
            name="uq_trigger_trackers_scope",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_trigger_trackers_active_execution",
        "trigger_trackers",
        ["active_execution_id"],
    )
    op.create_index(
        "ix_trigger_trackers_dismissed_until",
        "trigger_trackers",
        ["dismissed_until"],
    )

    op.create_table(
        "trigger_counted_assets",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("tracker_id", sa.CHAR(length=36), nullable=False),
        sa.Column("asset_id", sa.CHAR(length=36), nullable=False),
        sa.Column("counted_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(
            ["tracker_id"],
            ["trigger_trackers.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "tracker_id",
            "asset_id",
            name="uq_trigger_counted_assets_tracker_asset",
        ),
        mysql_charset="utf8mb4",
    )

    op.create_table(
        "trigger_executions",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("trigger_type", sa.String(length=32), nullable=False),
        sa.Column("workflow_type", sa.String(length=100), nullable=False),
        sa.Column("tracker_id", sa.CHAR(length=36), nullable=True),
        sa.Column("scope_type", sa.String(length=32), nullable=False),
        sa.Column("scope_id", sa.CHAR(length=36), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("dedupe_key", sa.String(length=255), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("payload_json", mysql.JSON(), nullable=False),
        sa.Column("first_fired_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("last_fired_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("last_notified_revision", sa.Integer(), nullable=True),
        sa.Column("consumed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("expires_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("workflow_run_id", sa.CHAR(length=36), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint(
            "revision > 0",
            name="ck_trigger_executions_revision_positive",
        ),
        sa.CheckConstraint(
            "status IN ('available', 'consumed', 'expired')",
            name="ck_trigger_executions_status",
        ),
        sa.ForeignKeyConstraint(
            ["tracker_id"],
            ["trigger_trackers.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "dedupe_key",
            name="uq_trigger_executions_dedupe_key",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_trigger_executions_user_status_created",
        "trigger_executions",
        ["user_id", "status", "created_at"],
    )
    op.create_index(
        "ix_trigger_executions_tracker_status",
        "trigger_executions",
        ["tracker_id", "status"],
    )


def downgrade() -> None:
    op.drop_table("trigger_executions")
    op.drop_table("trigger_counted_assets")
    op.drop_table("trigger_trackers")
