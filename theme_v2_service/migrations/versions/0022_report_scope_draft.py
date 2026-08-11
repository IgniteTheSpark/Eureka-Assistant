"""Add scope-first Report planning state.

Revision ID: 0022_report_scope_draft
Revises: 0021_capture_device_identity
Create Date: 2026-08-11
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0022_report_scope_draft"
down_revision = "0021_capture_device_identity"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "report_generation_runs",
        sa.Column("scope_adapter", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "report_generation_runs",
        sa.Column("scope_draft", mysql.JSON(), nullable=True),
    )
    op.add_column(
        "report_generation_runs",
        sa.Column(
            "scope_revision",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
    )
    op.add_column(
        "report_generation_runs",
        sa.Column("scope_hash", sa.CHAR(length=64), nullable=True),
    )
    op.add_column(
        "report_generation_runs",
        sa.Column("plan_scope_hash", sa.CHAR(length=64), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("report_generation_runs", "plan_scope_hash")
    op.drop_column("report_generation_runs", "scope_hash")
    op.drop_column("report_generation_runs", "scope_revision")
    op.drop_column("report_generation_runs", "scope_draft")
    op.drop_column("report_generation_runs", "scope_adapter")
