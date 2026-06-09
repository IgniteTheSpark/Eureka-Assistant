"""add user_skills.enabled (active-set flag)

Active-set feature: a user may *register* up to USER_SKILL_CAP skills but only
keep ACTIVE_SKILL_CAP active at once. `enabled=1` → shows in the library grid +
the agent routes to it; `enabled=0` → hidden + not routed (input falls back to
misc/notes), but its history stays queryable. Existing rows default to active.

Revision ID: 0005_skill_enabled
Revises: 0004_users
Create Date: 2026-06-04
"""
import sqlalchemy as sa
from alembic import op

revision = "0005_skill_enabled"
down_revision = "0004_users"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Idempotent: 0001 create_all() on the LIVE models already adds this column
    # on a FRESH deploy. Skip-if-exists avoids a duplicate-column collision on a
    # clean `alembic upgrade head` (existing DBs already ran this).
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    cols = [c["name"] for c in insp.get_columns("user_skills")] if insp.has_table("user_skills") else []
    if "enabled" in cols:
        return
    op.add_column(
        "user_skills",
        sa.Column("enabled", sa.Integer(), nullable=False, server_default="1"),
    )


def downgrade() -> None:
    op.drop_column("user_skills", "enabled")
