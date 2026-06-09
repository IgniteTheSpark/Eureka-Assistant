"""add reports.pet_gene (§6.12 batch 3 · Reka Insights signature band)

Snapshot of the user's REKA genome at generation time (skin/emblem/emblemColor/
head/leftItem/rightItem/carrier/aura). The report footer band renders THIS pet
via mascot.js; storing a snapshot means an old report still shows the REKA it was
made with even after the user re-equips (deterministic, no history rewrite,
§6.6.1). Nullable (older rows + users without a pet have none → band shows just
the wordmark).

Idempotent: 0001 create_all() on the LIVE models already adds this on a FRESH
deploy. Skip-if-exists keeps a clean `alembic upgrade head` from colliding.

Revision ID: 0013_report_pet_gene
Revises: 0012_report_telemetry
Create Date: 2026-06-08
"""
import sqlalchemy as sa
from alembic import op

revision = "0013_report_pet_gene"
down_revision = "0012_report_telemetry"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    has = insp.has_table("reports") and any(c["name"] == "pet_gene" for c in insp.get_columns("reports"))
    if not has:
        op.add_column("reports", sa.Column("pet_gene", sa.JSON()))


def downgrade() -> None:
    op.drop_column("reports", "pet_gene")
