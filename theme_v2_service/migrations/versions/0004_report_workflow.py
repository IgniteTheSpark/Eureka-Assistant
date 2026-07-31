"""Add report workflow, report, and file persistence.

Revision ID: 0004_report_workflow
Revises: 0003_triggers
Create Date: 2026-07-31
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0004_report_workflow"
down_revision = "0003_triggers"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "report_generation_runs",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("origin", sa.String(length=32), nullable=False),
        sa.Column("trigger_execution_id", sa.CHAR(length=36), nullable=True),
        sa.Column("state", sa.String(length=32), nullable=False),
        sa.Column("active_stage", sa.String(length=100), nullable=True),
        sa.Column("launch_context", mysql.JSON(), nullable=False),
        sa.Column("intent", sa.Text(), nullable=True),
        sa.Column("answers", mysql.JSON(), nullable=False),
        sa.Column("evidence_scope", mysql.JSON(), nullable=False),
        sa.Column("pending_decision", mysql.JSON(), nullable=True),
        sa.Column("plan_options", mysql.JSON(), nullable=False),
        sa.Column("selected_option_id", sa.String(length=100), nullable=True),
        sa.Column("execution_plan", mysql.JSON(), nullable=True),
        sa.Column("template_id", sa.String(length=100), nullable=True),
        sa.Column("template_version", sa.String(length=32), nullable=True),
        sa.Column("resolved_asset_ids", mysql.JSON(), nullable=False),
        sa.Column("planner_job_id", sa.CHAR(length=36), nullable=True),
        sa.Column("generation_job_id", sa.CHAR(length=36), nullable=True),
        sa.Column("draft_content_md", sa.Text(), nullable=True),
        sa.Column("generation_context", mysql.JSON(), nullable=False),
        sa.Column("usage_json", mysql.JSON(), nullable=False),
        sa.Column("report_id", sa.CHAR(length=36), nullable=True),
        sa.Column("failure_stage", sa.String(length=100), nullable=True),
        sa.Column("error_code", sa.String(length=100), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("retry_from", sa.String(length=100), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("expires_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("completed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("cancelled_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.CheckConstraint(
            "origin IN ('trigger', 'user_initiated')",
            name="ck_report_generation_runs_origin",
        ),
        sa.CheckConstraint(
            "state IN ('planning', 'awaiting_selection', 'generating', "
            "'completed', 'failed', 'cancelled', 'expired')",
            name="ck_report_generation_runs_state",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "trigger_execution_id",
            name="uq_report_generation_runs_trigger_execution",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_report_generation_runs_user_state_updated",
        "report_generation_runs",
        ["user_id", "state", "updated_at"],
    )
    op.create_index(
        "ix_report_generation_runs_user_created",
        "report_generation_runs",
        ["user_id", "created_at"],
    )

    op.create_table(
        "reports",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("generation_run_id", sa.CHAR(length=36), nullable=False),
        sa.Column("title", sa.String(length=255), nullable=False),
        sa.Column("template_id", sa.String(length=100), nullable=False),
        sa.Column("template_version", sa.String(length=32), nullable=False),
        sa.Column("base_family", sa.String(length=100), nullable=False),
        sa.Column("content_md", sa.Text(), nullable=False),
        sa.Column("html", sa.Text(), nullable=True),
        sa.Column("spec_json", mysql.JSON(), nullable=False),
        sa.Column("share_card_spec", mysql.JSON(), nullable=False),
        sa.Column("tokens_used", sa.Integer(), nullable=False),
        sa.Column("gen_ms", sa.Integer(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint("gen_ms >= 0", name="ck_reports_gen_ms_nonnegative"),
        sa.CheckConstraint(
            "tokens_used >= 0",
            name="ck_reports_tokens_nonnegative",
        ),
        sa.ForeignKeyConstraint(
            ["generation_run_id"],
            ["report_generation_runs.id"],
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "generation_run_id",
            name="uq_reports_generation_run",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_reports_user_created",
        "reports",
        ["user_id", "created_at"],
    )

    op.create_table(
        "files",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("purpose", sa.String(length=100), nullable=False),
        sa.Column("mime_type", sa.String(length=255), nullable=False),
        sa.Column("size_bytes", sa.Integer(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("storage_key", sa.String(length=500), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint(
            "size_bytes >= 0",
            name="ck_files_size_nonnegative",
        ),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_files_user_created",
        "files",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_table("files")
    op.drop_table("reports")
    op.drop_table("report_generation_runs")
