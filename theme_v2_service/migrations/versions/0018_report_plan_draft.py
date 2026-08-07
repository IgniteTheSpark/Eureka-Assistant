"""Add editable Report plan drafts.

Revision ID: 0018_report_plan_draft
Revises: 0017_legacy_agent_data_backfill
Create Date: 2026-08-07
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0018_report_plan_draft"
down_revision = "0017_legacy_agent_data_backfill"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "report_generation_runs",
        sa.Column("plan_draft", mysql.JSON(), nullable=True),
    )
    op.add_column(
        "report_generation_runs",
        sa.Column(
            "plan_revision",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
    )
    op.add_column(
        "report_generation_runs",
        sa.Column("scope_resolution_job_id", sa.CHAR(length=36), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("report_generation_runs", "scope_resolution_job_id")
    op.drop_column("report_generation_runs", "plan_revision")
    op.drop_column("report_generation_runs", "plan_draft")
