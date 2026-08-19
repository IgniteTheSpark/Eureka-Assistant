"""Add onboarding asset-result idempotency markers (§6.9).

Revision ID: 0025_onboarding_asset_results
Revises: 0024_account_onboarding
Create Date: 2026-08-13
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0026_onboarding_asset_results"
down_revision = "0025_account_onboarding"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "onboarding_asset_results",
        sa.Column("id", sa.CHAR(length=36), primary_key=True),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("idempotency_key", sa.String(length=255), nullable=False),
        sa.Column("asset_id", sa.CHAR(length=36), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
    )
    op.create_unique_constraint(
        "uq_onboarding_asset_results_key",
        "onboarding_asset_results",
        ["idempotency_key"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_onboarding_asset_results_key",
        "onboarding_asset_results",
        type_="unique",
    )
    op.drop_table("onboarding_asset_results")
