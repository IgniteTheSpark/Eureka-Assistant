"""Add immutable public report shares.

Revision ID: 0005_report_share
Revises: 0004_report_workflow
Create Date: 2026-07-31
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0005_report_share"
down_revision = "0004_report_workflow"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "report_shares",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("report_id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("expires_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("snapshot_content_md", sa.Text(), nullable=False),
        sa.Column("snapshot_spec_json", mysql.JSON(), nullable=False),
        sa.Column("snapshot_html", sa.Text(), nullable=True),
        sa.Column("media_map_json", mysql.JSON(), nullable=False),
        sa.Column("share_card_file_id", sa.CHAR(length=36), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("revoked_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.CheckConstraint(
            "status IN ('active', 'revoked', 'expired')",
            name="ck_report_shares_status",
        ),
        sa.ForeignKeyConstraint(
            ["report_id"],
            ["reports.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["share_card_file_id"],
            ["files.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash", name="uq_report_shares_token_hash"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_report_shares_user_created",
        "report_shares",
        ["user_id", "created_at"],
    )
    op.create_index(
        "ix_report_shares_status_expiry",
        "report_shares",
        ["status", "expires_at"],
    )


def downgrade() -> None:
    op.drop_table("report_shares")
