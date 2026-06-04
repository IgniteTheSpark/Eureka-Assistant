"""add users table (email + password auth)

Introduces real per-user accounts. `users.id` (uuid hex, String(50)) is the
value that already populates every table's `user_id` column, so no other schema
changes are needed — existing rows under user_id="default" simply belong to the
legacy single-tenant fallback.

Revision ID: 0004_users
Revises: 0003_contact_source_input_turn
Create Date: 2026-06-03
"""
import sqlalchemy as sa
from alembic import op

revision = "0004_users"
down_revision = "0003_contact_source_input_turn"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.String(length=50), primary_key=True),
        sa.Column("email", sa.String(length=255), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=True),
    )
    op.create_index("ix_users_email", "users", ["email"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_users_email", table_name="users")
    op.drop_table("users")
