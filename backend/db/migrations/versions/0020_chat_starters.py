"""user_skills.chat_starters (§1.5.1 资产锚定会话的开场 hint · L0)

2-3 条起聊文案 per skill: baseline skills get them from the seed; custom skills
from the design agent (produced in the same LLM call that designs the skill,
§1.8). Null → the hint endpoint falls back to the generic trio.

Idempotent skip-if-exists, mirroring 0017-0019.

Revision ID: 0020_chat_starters
Revises: 0019_companion_nudges
Create Date: 2026-06-11
"""
import sqlalchemy as sa
from alembic import op

revision = "0020_chat_starters"
down_revision = "0019_companion_nudges"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    if insp.has_table("user_skills") and not any(
        c["name"] == "chat_starters" for c in insp.get_columns("user_skills")
    ):
        op.add_column("user_skills", sa.Column("chat_starters", sa.JSON(), nullable=True))


def downgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())
    if insp.has_table("user_skills") and any(
        c["name"] == "chat_starters" for c in insp.get_columns("user_skills")
    ):
        op.drop_column("user_skills", "chat_starters")
