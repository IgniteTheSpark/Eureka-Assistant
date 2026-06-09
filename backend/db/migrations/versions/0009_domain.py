"""add domain columns (§8 Domain system, Layer A)

Adds the life-domain label column to assets (per-record truth), user_skills
(per-skill prior), and global_skills (provisioning default). All nullable
(null = 不归域). Adds a (user_id, domain) index on assets for the
`GET /api/assets?domain=` read path. No backfill — data is reseeded fresh.

Revision ID: 0009_domain
Revises: 0008_merge_suiji
Create Date: 2026-06-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0009_domain"
down_revision = "0008_merge_suiji"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Idempotent: 0001 create_all() on the LIVE models already adds these columns
    # on a FRESH deploy. Skip-if-exists keeps a clean `alembic upgrade head` from
    # colliding (existing incremental DBs already ran this and are untouched).
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    def _has_idx(table, name):
        return insp.has_table(table) and any(i["name"] == name for i in insp.get_indexes(table))

    if not _has_col("assets", "domain"):
        op.add_column("assets", sa.Column("domain", sa.String(20)))
    if not _has_col("user_skills", "domain"):
        op.add_column("user_skills", sa.Column("domain", sa.String(20)))
    if not _has_col("global_skills", "domain"):
        op.add_column("global_skills", sa.Column("domain", sa.String(20)))
    if not _has_idx("assets", "idx_assets_domain"):
        op.create_index("idx_assets_domain", "assets", ["user_id", "domain"])


def downgrade() -> None:
    op.drop_index("idx_assets_domain", table_name="assets")
    op.drop_column("global_skills", "domain")
    op.drop_column("user_skills", "domain")
    op.drop_column("assets", "domain")
