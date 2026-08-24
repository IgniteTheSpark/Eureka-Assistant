"""Bind onboarding idempotency keys to canonical confirmation content.

Revision ID: 0032_onboarding_request_fp
Revises: 0031_challenge_indexes
Create Date: 2026-08-24
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "0032_onboarding_request_fp"
down_revision = "0031_challenge_indexes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "onboarding_asset_results",
        sa.Column("request_fingerprint", sa.String(length=64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("onboarding_asset_results", "request_fingerprint")
