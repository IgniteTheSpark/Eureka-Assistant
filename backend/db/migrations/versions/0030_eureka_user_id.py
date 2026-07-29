"""add users.eureka_user_id for embedded EurekaMind PA Mode

Revision ID: 0030_eureka_user_id
Revises: 0029_nudge_dismissed_at
Create Date: 2026-06-29

PA Mode is embedded inside the EurekaMind meeting app. The host app remains the
primary identity owner; UREKA maps the host's stable user id into a derived
UREKA user and mints its own JWT. This column stores that mapping.
"""

import sqlalchemy as sa
from alembic import op

revision = "0030_eureka_user_id"
down_revision = "0029_nudge_dismissed_at"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect

    inspector = inspect(op.get_bind())
    if not inspector.has_table("users"):
        return
    columns = {column["name"] for column in inspector.get_columns("users")}
    indexes = {index["name"] for index in inspector.get_indexes("users")}
    if "eureka_user_id" not in columns:
        op.add_column(
            "users",
            sa.Column("eureka_user_id", sa.String(100), nullable=True),
        )
    if "uq_users_eureka_user_id" not in indexes:
        op.create_index(
            "uq_users_eureka_user_id",
            "users",
            ["eureka_user_id"],
            unique=True,
        )


def downgrade() -> None:
    from sqlalchemy import inspect

    inspector = inspect(op.get_bind())
    if not inspector.has_table("users"):
        return
    indexes = {index["name"] for index in inspector.get_indexes("users")}
    columns = {column["name"] for column in inspector.get_columns("users")}
    if "uq_users_eureka_user_id" in indexes:
        op.drop_index("uq_users_eureka_user_id", table_name="users")
    if "eureka_user_id" in columns:
        op.drop_column("users", "eureka_user_id")
