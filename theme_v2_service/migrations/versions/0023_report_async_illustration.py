"""Persist asynchronous Report illustration state.

Revision ID: 0023_report_async_illustration
Revises: 0022_report_scope_draft
Create Date: 2026-08-11
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0023_report_async_illustration"
down_revision = "0022_report_scope_draft"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "reports",
        sa.Column(
            "illustration_status",
            sa.String(length=24),
            nullable=False,
            server_default="not_required",
        ),
    )
    op.add_column(
        "reports",
        sa.Column("illustration_job_id", sa.CHAR(length=36), nullable=True),
    )
    op.add_column(
        "reports",
        sa.Column(
            "revision",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("1"),
        ),
    )
    op.add_column(
        "reports",
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=True),
    )
    op.execute("UPDATE reports SET updated_at = created_at WHERE updated_at IS NULL")
    op.alter_column(
        "reports",
        "updated_at",
        existing_type=mysql.DATETIME(fsp=6),
        nullable=False,
    )
    op.create_check_constraint(
        "ck_reports_illustration_status",
        "reports",
        "illustration_status IN ('not_required','pending','ready','failed')",
    )

    op.drop_constraint(
        "ck_report_generation_runs_state",
        "report_generation_runs",
        type_="check",
    )
    op.create_check_constraint(
        "ck_report_generation_runs_state",
        "report_generation_runs",
        "state IN ('planning','awaiting_selection','generating',"
        "'illustration_pending','completed','failed','cancelled','expired')",
    )


def downgrade() -> None:
    op.drop_constraint(
        "ck_report_generation_runs_state",
        "report_generation_runs",
        type_="check",
    )
    op.create_check_constraint(
        "ck_report_generation_runs_state",
        "report_generation_runs",
        "state IN ('planning','awaiting_selection','generating',"
        "'completed','failed','cancelled','expired')",
    )
    op.drop_constraint(
        "ck_reports_illustration_status",
        "reports",
        type_="check",
    )
    op.drop_column("reports", "updated_at")
    op.drop_column("reports", "revision")
    op.drop_column("reports", "illustration_job_id")
    op.drop_column("reports", "illustration_status")
