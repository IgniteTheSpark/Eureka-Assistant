"""Phase D — user_skills.position for drag-to-reorder

Adds:
- user_skills.position int column — drives the 3x3 SKILLS grid order in
  the library. NULL/0 default = "not yet ordered"; backfill assigns
  positions by created_at ASC so existing skills keep their order. New
  skills land at the end (position = current count).

Revision ID: 0007
Revises: 0006
Create Date: 2026-05-30
"""
from alembic import op
import sqlalchemy as sa


revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_skills",
        sa.Column("position", sa.Integer, nullable=False, server_default="0"),
    )
    # Backfill: order existing rows by created_at within each user. NULL
    # user_skills don't exist (user_id is NOT NULL), but the partition is
    # still safe.
    op.execute("""
        UPDATE user_skills
        SET position = sub.rn - 1
        FROM (
            SELECT id,
                   ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at ASC) AS rn
            FROM user_skills
        ) sub
        WHERE user_skills.id = sub.id
    """)
    op.create_index(
        "idx_user_skills_user_position",
        "user_skills",
        ["user_id", "position"],
    )


def downgrade() -> None:
    op.drop_index("idx_user_skills_user_position", table_name="user_skills")
    op.drop_column("user_skills", "position")
