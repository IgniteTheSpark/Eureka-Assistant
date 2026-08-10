"""Add persisted lifecycle and Rhythm profiles for Theme V2 Reka signals.

Revision ID: 0019_reka_overdue_rhythm
Revises: 0018_report_plan_draft
Create Date: 2026-08-10
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0019_reka_overdue_rhythm"
down_revision = "0018_report_plan_draft"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "nudges",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("natural_key", sa.String(length=255), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("ref", sa.String(length=255), nullable=False),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default="delivered",
        ),
        sa.Column("delivered_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("acted_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("dismissed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("expires_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column(
            "created_at",
            mysql.DATETIME(fsp=6),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP(6)"),
        ),
        sa.Column(
            "updated_at",
            mysql.DATETIME(fsp=6),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP(6)"),
        ),
        sa.CheckConstraint(
            "status IN ('delivered', 'seen', 'acted', 'dismissed', 'expired')",
            name="ck_nudges_status",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "natural_key",
            name="uq_nudges_user_natural_key",
        ),
    )
    op.create_index(
        "ix_nudges_user_status",
        "nudges",
        ["user_id", "status"],
        unique=False,
    )
    op.create_index(
        "ix_nudges_user_kind_ref",
        "nudges",
        ["user_id", "kind", "ref"],
        unique=False,
    )
    op.create_index(
        "ix_nudges_expiry",
        "nudges",
        ["expires_at"],
        unique=False,
    )

    op.create_table(
        "rhythm_profiles",
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("skill", sa.String(length=100), nullable=False),
        sa.Column("timezone_name", sa.String(length=64), nullable=False),
        sa.Column("patterns_json", mysql.JSON(), nullable=False),
        sa.Column("computed_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("user_id", "skill"),
    )
    op.create_index(
        "ix_rhythm_profiles_user_computed",
        "rhythm_profiles",
        ["user_id", "computed_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_rhythm_profiles_user_computed",
        table_name="rhythm_profiles",
    )
    op.drop_table("rhythm_profiles")
    op.drop_index("ix_nudges_expiry", table_name="nudges")
    op.drop_index("ix_nudges_user_kind_ref", table_name="nudges")
    op.drop_index("ix_nudges_user_status", table_name="nudges")
    op.drop_table("nudges")
