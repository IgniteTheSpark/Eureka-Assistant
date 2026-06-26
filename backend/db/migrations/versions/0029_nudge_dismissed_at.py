"""add nudges.dismissed_at (§14.5a PULL dismissed-today filter)

Revision ID: 0029_nudge_dismissed_at
Revises: 0028_asset_period_occurred_at
Create Date: 2026-06-26

§14.5a 现算 comprehensive offer set (GET /api/offers/today): a PULL UPSERTs every
valid candidate into a Nudge so 执行/跳过 work by id, then EXCLUDES any offer the
user dismissed TODAY (Beijing +08). The outcome handler previously stamped only
`acted_at`; a dismissal left no timestamp, so "dismissed today" was unknowable.
This adds `dismissed_at`, set in api/nudges.py when status → dismissed.

Idempotent skip-if-exists, mirroring 0028.
"""

import sqlalchemy as sa
from alembic import op

revision = "0029_nudge_dismissed_at"
down_revision = "0028_asset_period_occurred_at"
branch_labels = None
depends_on = None


def _columns(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {c["name"] for c in inspect(op.get_bind()).get_columns(table_name)}


def upgrade() -> None:
    from db.models import TIMESTAMPTZ
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("nudges"):
        return
    if "dismissed_at" not in _columns("nudges"):
        op.add_column("nudges", sa.Column("dismissed_at", TIMESTAMPTZ, nullable=True))


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("nudges"):
        return
    if "dismissed_at" in _columns("nudges"):
        op.drop_column("nudges", "dismissed_at")
