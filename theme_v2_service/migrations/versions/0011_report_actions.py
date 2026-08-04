"""Add Report action provenance to Todo assets.

Revision ID: 0011_report_actions
Revises: 0010_flash_chat_notes
Create Date: 2026-08-04
"""

import sqlalchemy as sa
from alembic import op


revision = "0011_report_actions"
down_revision = "0010_flash_chat_notes"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "assets",
        sa.Column("source_report_id", sa.CHAR(length=36), nullable=True),
    )
    op.add_column(
        "assets",
        sa.Column(
            "source_report_action_id",
            sa.String(length=64),
            nullable=True,
        ),
    )
    op.create_foreign_key(
        "fk_assets_source_report",
        "assets",
        "reports",
        ["source_report_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_unique_constraint(
        "uq_assets_user_report_action",
        "assets",
        ["user_id", "source_report_id", "source_report_action_id"],
    )
    op.create_index(
        "ix_assets_user_source_report",
        "assets",
        ["user_id", "source_report_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_assets_user_source_report", table_name="assets")
    op.drop_constraint(
        "uq_assets_user_report_action",
        "assets",
        type_="unique",
    )
    op.drop_constraint(
        "fk_assets_source_report",
        "assets",
        type_="foreignkey",
    )
    op.drop_column("assets", "source_report_action_id")
    op.drop_column("assets", "source_report_id")
