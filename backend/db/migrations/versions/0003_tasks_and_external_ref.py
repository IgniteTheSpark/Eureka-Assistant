"""Phase B v1.4.x — tasks table + external_ref skill

Adds:
- tasks table — async task tracking for third-party MCP calls
  (Notion / Google Calendar / Dingtalk / etc.)

Note: the `external_ref` global_skill + user_skill row is added via
db/seed.py (idempotent), NOT in this migration — seeding skills is
orchestrated in Python code and re-run on every fresh boot.

Revision ID: 0003
Revises: 0002
Create Date: 2026-05-26
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

TIMESTAMPTZ = sa.TIMESTAMP(timezone=True)

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "tasks",
        sa.Column("id",                   UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id",              sa.String(50), nullable=False, server_default="default"),
        sa.Column("user_text",            sa.Text, nullable=False),
        sa.Column("mcp_target",           sa.String(50)),
        sa.Column("status",               sa.String(20), nullable=False, server_default="pending"),
        sa.Column("error_message",        sa.Text),
        sa.Column("result_asset_id",      UUID(as_uuid=True), sa.ForeignKey("assets.id")),
        sa.Column("session_id",           UUID(as_uuid=True), sa.ForeignKey("sessions.id")),
        sa.Column("source_input_turn_id", UUID(as_uuid=True), sa.ForeignKey("input_turns.id")),
        sa.Column("started_at",           TIMESTAMPTZ),
        sa.Column("completed_at",         TIMESTAMPTZ),
        sa.Column("created_at",           TIMESTAMPTZ, server_default=sa.func.now()),
    )
    op.create_index("idx_tasks_user_status", "tasks", ["user_id", "status", "created_at"])
    op.create_index("idx_tasks_session",     "tasks", ["session_id", "created_at"])


def downgrade() -> None:
    op.drop_index("idx_tasks_session", table_name="tasks")
    op.drop_index("idx_tasks_user_status", table_name="tasks")
    op.drop_table("tasks")
