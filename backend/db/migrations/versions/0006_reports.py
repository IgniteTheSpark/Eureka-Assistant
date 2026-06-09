"""add reports table (synthesis/report engine, §6)

The report engine (report-dispatcher → content skill → render skill) persists
each report as a first-class entity: `content_md` (annotated Markdown substance,
re-renderable), `html` (rendered snapshot), `spec_json` (re-render recipe).

Revision ID: 0006_reports
Revises: 0005_skill_enabled
Create Date: 2026-06-04
"""
import sqlalchemy as sa
from alembic import op

revision = "0006_reports"
down_revision = "0005_skill_enabled"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Import here so type decorators resolve at migration time (mirrors 0001).
    from db.models import GUID, TIMESTAMPTZ
    # Idempotent: 0001 create_all() on the LIVE models already builds `reports`
    # on a FRESH deploy. Skip-if-exists avoids a duplicate-table collision on a
    # clean `alembic upgrade head` (existing DBs already ran this).
    from sqlalchemy import inspect
    if inspect(op.get_bind()).has_table("reports"):
        return
    op.create_table(
        "reports",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("user_id", sa.String(50), nullable=False, server_default="default"),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("genre", sa.String(30), nullable=False),
        sa.Column("content_md", sa.Text(), nullable=False),
        sa.Column("html", sa.Text(), nullable=False),
        sa.Column("spec_json", sa.JSON()),
        sa.Column("created_at", TIMESTAMPTZ),
    )
    op.create_index("idx_reports_user_created", "reports", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("idx_reports_user_created", table_name="reports")
    op.drop_table("reports")
