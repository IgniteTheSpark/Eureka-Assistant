"""Phase D M6 — notifications table

Adds:
- notifications table — user-facing event log (flash done / task done /
  task failed / reminder) powering the NotificationBell, toast queue, and
  the notification history page.

Revision ID: 0006
Revises: 0005
Create Date: 2026-05-28
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

TIMESTAMPTZ = sa.TIMESTAMP(timezone=True)

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "notifications",
        sa.Column("id",         UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id",    sa.String(50), nullable=False, server_default="default"),
        sa.Column("type",       sa.String(20), nullable=False),
        sa.Column("title",      sa.String(255), nullable=False),
        sa.Column("body",       sa.Text),
        sa.Column("link",       sa.String(255)),
        sa.Column("read",       sa.Integer, nullable=False, server_default="0"),
        sa.Column("created_at", TIMESTAMPTZ, server_default=sa.func.now()),
    )
    op.create_index("idx_notifications_user_created", "notifications", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("idx_notifications_user_created", table_name="notifications")
    op.drop_table("notifications")
