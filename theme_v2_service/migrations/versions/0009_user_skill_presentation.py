"""Add Theme V2 user-skill presentation metadata.

Revision ID: 0009_user_skill_presentation
Revises: 0008_event_attendees
Create Date: 2026-08-03
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0009_user_skill_presentation"
down_revision = "0008_event_attendees"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_skills",
        sa.Column(
            "render_spec_json",
            mysql.JSON(),
            nullable=False,
            server_default=sa.text("('{}')"),
        ),
    )
    op.add_column(
        "user_skills",
        sa.Column(
            "chat_starters_json",
            mysql.JSON(),
            nullable=False,
            server_default=sa.text("('[]')"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_skills", "chat_starters_json")
    op.drop_column("user_skills", "render_spec_json")
