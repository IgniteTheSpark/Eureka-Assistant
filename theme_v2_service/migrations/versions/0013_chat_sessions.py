"""Add persistent ordinary chat sessions.

Revision ID: 0013_chat_sessions
Revises: 0012_asset_temporal
Create Date: 2026-08-05
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0013_chat_sessions"
down_revision = "0012_asset_temporal"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "chat_sessions",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("session_type", sa.String(length=32), nullable=False),
        sa.Column("title", sa.String(length=500), nullable=True),
        sa.Column("subject_type", sa.String(length=64), nullable=True),
        sa.Column("subject_id", sa.String(length=128), nullable=True),
        sa.Column("context_asset_ids_json", mysql.JSON(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "subject_type",
            "subject_id",
            name="uq_chat_sessions_user_subject",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_chat_sessions_user_updated",
        "chat_sessions",
        ["user_id", "updated_at"],
    )
    op.create_table(
        "session_messages",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("session_id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("status", sa.String(length=16), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("input_turn_id", sa.CHAR(length=36), nullable=True),
        sa.Column("tool_call_json", mysql.JSON(), nullable=True),
        sa.Column("tool_result_json", mysql.JSON(), nullable=True),
        sa.Column("cards_json", mysql.JSON(), nullable=False),
        sa.Column("elapsed_ms", sa.Integer(), nullable=True),
        sa.Column("token_count", sa.Integer(), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"], ["chat_sessions.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_session_messages_session_created",
        "session_messages",
        ["session_id", "created_at"],
    )
    op.add_column(
        "assets", sa.Column("session_id", sa.CHAR(length=36), nullable=True)
    )
    op.add_column(
        "assets",
        sa.Column("source_input_turn_id", sa.CHAR(length=36), nullable=True),
    )
    op.create_foreign_key(
        "fk_assets_session_id_chat_sessions",
        "assets",
        "chat_sessions",
        ["session_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_assets_session_id_chat_sessions", "assets", type_="foreignkey"
    )
    op.drop_column("assets", "source_input_turn_id")
    op.drop_column("assets", "session_id")
    op.drop_table("session_messages")
    op.drop_table("chat_sessions")
