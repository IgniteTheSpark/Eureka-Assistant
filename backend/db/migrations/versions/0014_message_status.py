"""add messages.status (§1.5.1.1 / §1.5.1.3 batch A · durable chat turns)

A chat turn now persists its agent message as a `running` placeholder the moment
the user sends, then a background task (which survives client disconnect) flips it
to `done` / `failed`. `status` is what a returning client reconciles against:
`running` → 「分析中…」 placeholder + poll; `done` → reply/cards; `failed` → error.

Nullable, default 'done' — existing rows + every user message are terminal/normal.
Idempotent skip-if-exists (0001 create_all on a fresh deploy already adds it).

Revision ID: 0014_message_status
Revises: 0013_report_pet_gene
Create Date: 2026-06-08
"""
import sqlalchemy as sa
from alembic import op

revision = "0014_message_status"
down_revision = "0013_report_pet_gene"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from sqlalchemy import inspect
    insp = inspect(op.get_bind())

    def _has_col(table, col):
        return insp.has_table(table) and any(c["name"] == col for c in insp.get_columns(table))

    if not _has_col("messages", "status"):
        op.add_column(
            "messages",
            sa.Column("status", sa.String(12), nullable=True, server_default="done"),
        )


def downgrade() -> None:
    op.drop_column("messages", "status")
