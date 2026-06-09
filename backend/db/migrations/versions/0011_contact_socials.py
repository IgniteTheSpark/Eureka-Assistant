"""add contacts.socials (名片 social-media handles, fixed platform set)

Adds a JSON `socials` column to contacts: {platform_key: handle} where
platform_key ∈ x/telegram/linkedin/wechat/xiaohongshu/instagram (the supported
set lives in core/contacts_meta.py). Default empty dict (= 无社媒). notes stays
a JSON list of markdown annotation lines (no schema change — append semantics
are enforced in the API / MCP layer, not the column).

Idempotent: 0001 create_all() on the LIVE models already adds this column on a
FRESH deploy. Skip-if-exists keeps a clean `alembic upgrade head` from colliding.

Revision ID: 0011_contact_socials
Revises: 0010_pet
Create Date: 2026-06-08
"""
import sqlalchemy as sa
from alembic import op

revision = "0011_contact_socials"
down_revision = "0010_pet"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    if not _has_col("contacts", "socials"):
        op.add_column("contacts", sa.Column("socials", sa.JSON()))


def downgrade() -> None:
    op.drop_column("contacts", "socials")
