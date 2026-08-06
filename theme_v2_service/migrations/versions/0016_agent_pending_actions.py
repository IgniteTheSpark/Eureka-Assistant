"""Add durable Agent pending actions.

Revision ID: 0016_agent_pending_actions
Revises: 0015_internal_mcp_domain
Create Date: 2026-08-06
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0016_agent_pending_actions"
down_revision = "0015_internal_mcp_domain"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "session_messages",
        "status",
        existing_type=sa.String(length=16),
        type_=sa.String(length=24),
        existing_nullable=False,
    )
    op.create_table(
        "agent_pending_actions",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("session_id", sa.CHAR(length=36), nullable=False),
        sa.Column("input_turn_id", sa.CHAR(length=36), nullable=True),
        sa.Column("agent_message_id", sa.CHAR(length=36), nullable=True),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("operation", sa.String(length=32), nullable=False),
        sa.Column(
            "status",
            sa.String(length=24),
            nullable=False,
            server_default=sa.text("'pending'"),
        ),
        sa.Column("candidates_json", mysql.JSON(), nullable=False),
        sa.Column("intent_json", mysql.JSON(), nullable=False),
        sa.Column("selected_entity_id", sa.CHAR(length=36), nullable=True),
        sa.Column("resolution_source", sa.String(length=32), nullable=True),
        sa.Column("resolved_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"], ["chat_sessions.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["input_turn_id"], ["input_turns.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["agent_message_id"], ["session_messages.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_agent_pending_actions_user_status",
        "agent_pending_actions",
        ["user_id", "status", "created_at"],
    )
    op.create_index(
        "ix_agent_pending_actions_session_status",
        "agent_pending_actions",
        ["session_id", "status", "created_at"],
    )


def downgrade() -> None:
    op.drop_table("agent_pending_actions")
    op.alter_column(
        "session_messages",
        "status",
        existing_type=sa.String(length=24),
        type_=sa.String(length=16),
        existing_nullable=False,
    )
