"""Add precise and fuzzy occurrence time to assets.

Revision ID: 0012_asset_temporal
Revises: 0011_report_actions
Create Date: 2026-08-05
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0012_asset_temporal"
down_revision = "0011_report_actions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "assets",
        sa.Column("period", sa.String(length=8), nullable=True),
    )
    op.add_column(
        "assets",
        sa.Column("occurred_at", mysql.DATETIME(fsp=6), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("assets", "occurred_at")
    op.drop_column("assets", "period")
