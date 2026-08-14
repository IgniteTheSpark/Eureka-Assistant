"""Add deletion cleanup work items for orphaned storage cleanup (§10.2).

Revision ID: 0027_deletion_cleanup_items
Revises: 0026_onboarding_idempotency_user_scoped
Create Date: 2026-08-13
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0027_deletion_cleanup_items"
down_revision = "0026_onboarding_idempotency_user_scoped"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "deletion_cleanup_items",
        sa.Column("id", sa.CHAR(length=36), primary_key=True),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("storage_key", sa.String(length=1024), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=True),
    )
    op.create_index(
        "ix_deletion_cleanup_items_status",
        "deletion_cleanup_items",
        ["status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_deletion_cleanup_items_status",
        table_name="deletion_cleanup_items",
    )
    op.drop_table("deletion_cleanup_items")
