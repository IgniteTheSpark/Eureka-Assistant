"""reports.suggested_actions + assets.source_report_id (§6.13 报告→待办 / handoff Phase 1)

The report pipeline extracts the content skill's `:::actions` block into
`reports.suggested_actions` = [{title, kind?, due?}] so the viewer can render a
NATIVE action bar (the in-report checklist stays read-only). A todo created from
a report action carries `assets.source_report_id` — provenance both ways: the
todo knows it came from 报告《X》, the report knows which actions were acted on
(dedupe: "已加 ✓").

Idempotent skip-if-exists, mirroring 0017.

Revision ID: 0018_report_actions
Revises: 0017_baizhi_user_id
Create Date: 2026-06-10
"""
import sqlalchemy as sa
from alembic import op

revision = "0018_report_actions"
down_revision = "0017_baizhi_user_id"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    def _has_index(table, name):
        return insp.has_table(table) and any(ix["name"] == name for ix in insp.get_indexes(table))

    if not _has_col("reports", "suggested_actions"):
        op.add_column("reports", sa.Column("suggested_actions", sa.JSON(), nullable=True))

    # GUID columns are CHAR(36) on MySQL (db.types.GUID) — match it so joins compare cleanly.
    if not _has_col("assets", "source_report_id"):
        op.add_column("assets", sa.Column("source_report_id", sa.CHAR(36), nullable=True))
    if not _has_index("assets", "idx_assets_source_report"):
        op.create_index("idx_assets_source_report", "assets", ["user_id", "source_report_id"])


def downgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    if insp.has_table("assets") and any(
        ix["name"] == "idx_assets_source_report" for ix in insp.get_indexes("assets")
    ):
        op.drop_index("idx_assets_source_report", table_name="assets")
    if insp.has_table("assets") and any(c["name"] == "source_report_id" for c in insp.get_columns("assets")):
        op.drop_column("assets", "source_report_id")
    if insp.has_table("reports") and any(c["name"] == "suggested_actions" for c in insp.get_columns("reports")):
        op.drop_column("reports", "suggested_actions")
