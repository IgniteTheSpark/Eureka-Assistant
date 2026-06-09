"""add pet + completion_events (§9 球球 Pet / §7 gamemode currency)

球球 pet (one per user): genome (skin/emblem/emblem_color + equipped accessory
slots), collected cosmetics (unlocked), cumulative milestones, spawned flag.
completion_events = the append-only currency the pet subscribes to (§9.1, fully
decoupled from island/domain — but we carry `domain` so the future weekly island
can aggregate per-domain without a schema change).

Idempotent guards: 0001 does create_all() on live models, so a fresh deploy
already has these — skip-if-exists keeps `alembic upgrade head` from colliding.

Revision ID: 0010_pet
Revises: 0009_domain
Create Date: 2026-06-05
"""
import sqlalchemy as sa
from alembic import op

revision = "0010_pet"
down_revision = "0009_domain"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from db.models import GUID, TIMESTAMPTZ
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    if not insp.has_table("pets"):
        op.create_table(
            "pets",
            sa.Column("id", GUID(), primary_key=True),
            sa.Column("user_id", sa.String(50), nullable=False),
            sa.Column("seed", sa.String(50), nullable=False),
            sa.Column("name", sa.String(50)),
            sa.Column("skin", sa.String(20)),
            sa.Column("emblem", sa.String(20)),
            sa.Column("emblem_color", sa.String(20)),
            sa.Column("equipped", sa.JSON()),     # {head, leftItem, rightItem}
            sa.Column("unlocked", sa.JSON()),      # {skin:[], emblem:[], head:[], item:[]}
            sa.Column("milestones", sa.JSON()),    # {capture_count, streak_days, last_event_date, domains:[]}
            sa.Column("spawned", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at", TIMESTAMPTZ),
            sa.UniqueConstraint("user_id", name="uq_pets_user"),
        )

    if not insp.has_table("completion_events"):
        op.create_table(
            "completion_events",
            sa.Column("id", GUID(), primary_key=True),
            sa.Column("user_id", sa.String(50), nullable=False),
            sa.Column("domain", sa.String(20)),                 # §8 (pet ignores; island will aggregate)
            sa.Column("source", sa.String(20), nullable=False),  # task | record | opportunistic
            sa.Column("ref", sa.String(50)),                     # asset/event/contact id
            sa.Column("created_at", TIMESTAMPTZ),
        )
        op.create_index("idx_completion_events_user", "completion_events", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("idx_completion_events_user", table_name="completion_events")
    op.drop_table("completion_events")
    op.drop_table("pets")
