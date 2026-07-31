"""Create the isolated Theme V2 foundation schema.

Revision ID: 0001_foundation
Revises:
Create Date: 2026-07-31
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0001_foundation"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_accounts",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("email", name="uq_user_accounts_email"),
        mysql_charset="utf8mb4",
    )

    op.create_table(
        "user_skills",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("machine_name", sa.String(length=100), nullable=False),
        sa.Column("display_name", sa.String(length=160), nullable=False),
        sa.Column("description", sa.String(length=1000), nullable=True),
        sa.Column("domain", sa.String(length=100), nullable=True),
        sa.Column("schema_json", mysql.JSON(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "machine_name",
            name="uq_user_skills_user_machine_name",
        ),
        mysql_charset="utf8mb4",
    )

    op.create_table(
        "events",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("location", sa.String(length=500), nullable=True),
        sa.Column("start_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("end_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("all_day", sa.Boolean(), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index("ix_events_user_start", "events", ["user_id", "start_at"])
    op.create_index(
        "ix_events_user_created",
        "events",
        ["user_id", "created_at"],
    )

    op.create_table(
        "workflow_jobs",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("run_id", sa.CHAR(length=36), nullable=True),
        sa.Column("job_type", sa.String(length=100), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("attempt", sa.Integer(), nullable=False),
        sa.Column("max_attempts", sa.Integer(), nullable=False),
        sa.Column("available_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("lease_owner", sa.String(length=200), nullable=True),
        sa.Column("lease_expires_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("checkpoint_json", mysql.JSON(), nullable=True),
        sa.Column("input_dedupe_key", sa.String(length=255), nullable=True),
        sa.Column("error_code", sa.String(length=100), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("started_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("completed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "input_dedupe_key",
            name="uq_workflow_jobs_input_dedupe_key",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_workflow_jobs_claim",
        "workflow_jobs",
        ["status", "available_at", "lease_expires_at"],
    )

    op.create_table(
        "assets",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_skill_id", sa.CHAR(length=36), nullable=False),
        sa.Column("payload_json", mysql.JSON(), nullable=False),
        sa.Column("effective_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(
            ["user_skill_id"],
            ["user_skills.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_assets_user_created",
        "assets",
        ["user_id", "created_at"],
    )
    op.create_index(
        "ix_assets_user_skill_effective",
        "assets",
        ["user_id", "user_skill_id", "effective_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_assets_user_skill_effective", table_name="assets")
    op.drop_index("ix_assets_user_created", table_name="assets")
    op.drop_table("assets")
    op.drop_index("ix_workflow_jobs_claim", table_name="workflow_jobs")
    op.drop_table("workflow_jobs")
    op.drop_index("ix_events_user_created", table_name="events")
    op.drop_index("ix_events_user_start", table_name="events")
    op.drop_table("events")
    op.drop_table("user_skills")
    op.drop_table("user_accounts")
