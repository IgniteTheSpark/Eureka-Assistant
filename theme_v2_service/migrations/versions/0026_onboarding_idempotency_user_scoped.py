"""Ensure onboarding idempotency is unique per (user_id, idempotency_key).

Revision ID: 0026_onboarding_idempotency_user_scoped
Revises: 0025_onboarding_asset_results
Create Date: 2026-08-13
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0026_onboarding_idempotency_user_scoped"
down_revision = "0025_onboarding_asset_results"
branch_labels = None
depends_on = None


def _has_constraint(connection, name: str) -> bool:
    row = connection.execute(
        sa.text(
            "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS "
            "WHERE CONSTRAINT_SCHEMA = DATABASE() "
            "AND TABLE_NAME = 'onboarding_asset_results' "
            "AND CONSTRAINT_NAME = :name"
        ),
        {"name": name},
    ).scalar_one()
    return row > 0


def upgrade() -> None:
    connection = op.get_bind()
    if _has_constraint(connection, "uq_onboarding_asset_results_key"):
        op.drop_constraint(
            "uq_onboarding_asset_results_key",
            "onboarding_asset_results",
            type_="unique",
        )
    if not _has_constraint(connection, "uq_onboarding_asset_results_user_key"):
        op.create_unique_constraint(
            "uq_onboarding_asset_results_user_key",
            "onboarding_asset_results",
            ["user_id", "idempotency_key"],
        )


def downgrade() -> None:
    connection = op.get_bind()
    if _has_constraint(connection, "uq_onboarding_asset_results_user_key"):
        op.drop_constraint(
            "uq_onboarding_asset_results_user_key",
            "onboarding_asset_results",
            type_="unique",
        )
