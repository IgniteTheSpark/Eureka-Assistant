"""add reports.tokens_used + reports.gen_ms (§6.12 batch 0 · usage telemetry)

Per-report cost/timing telemetry: summed model tokens across the pipeline
(dispatcher + content [+ image later]) and wall-clock generation time in ms.
Both nullable (older rows have none). Feeds §6.7 display (gen_ms) + §12.5 cost
aggregation (tokens_used).

Idempotent: 0001 create_all() on the LIVE models already adds these on a FRESH
deploy. Skip-if-exists keeps a clean `alembic upgrade head` from colliding.

Revision ID: 0012_report_telemetry
Revises: 0011_contact_socials
Create Date: 2026-06-08
"""
import sqlalchemy as sa
from alembic import op

revision = "0012_report_telemetry"
down_revision = "0011_contact_socials"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    if not _has_col("reports", "tokens_used"):
        op.add_column("reports", sa.Column("tokens_used", sa.Integer()))
    if not _has_col("reports", "gen_ms"):
        op.add_column("reports", sa.Column("gen_ms", sa.Integer()))


def downgrade() -> None:
    op.drop_column("reports", "gen_ms")
    op.drop_column("reports", "tokens_used")
