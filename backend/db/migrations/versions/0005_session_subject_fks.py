"""Phase D M2.3 — session subject FKs

Adds three nullable FK columns to sessions so each asset / first-class
entity can have ONE home discussion session (get-or-create on
「在 chat 里讨论」). Previously every click created a new session, causing
fragmentation when the user revisited the same subject.

Columns added (alongside existing sessions.event_id):
  - contact_id        UUID  → contacts.id  (sessions about a contact)
  - file_id           UUID  → files.id     (sessions about a file/transcript)
  - subject_asset_id  UUID  → assets.id    (sessions about a sub-asset:
                                            todo/idea/notes/misc/expense)

context_asset_ids (added in 0004) remains the mutable, additive list of
extra assets pulled into the session via「+ 添加资产」 — distinct concept.

Each FK is nullable + indexed for O(log n) get-or-create lookup.

Revision ID: 0005
Revises: 0004
Create Date: 2026-05-27
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "sessions",
        sa.Column("contact_id", UUID(as_uuid=True), sa.ForeignKey("contacts.id"), nullable=True),
    )
    op.add_column(
        "sessions",
        sa.Column("file_id", UUID(as_uuid=True), sa.ForeignKey("files.id"), nullable=True),
    )
    op.add_column(
        "sessions",
        sa.Column("subject_asset_id", UUID(as_uuid=True), sa.ForeignKey("assets.id"), nullable=True),
    )
    # Indexes for get-or-create lookup performance
    op.create_index("idx_sessions_contact",       "sessions", ["user_id", "contact_id"])
    op.create_index("idx_sessions_file",          "sessions", ["user_id", "file_id"])
    op.create_index("idx_sessions_subject_asset", "sessions", ["user_id", "subject_asset_id"])


def downgrade() -> None:
    op.drop_index("idx_sessions_subject_asset", table_name="sessions")
    op.drop_index("idx_sessions_file",          table_name="sessions")
    op.drop_index("idx_sessions_contact",       table_name="sessions")
    op.drop_column("sessions", "subject_asset_id")
    op.drop_column("sessions", "file_id")
    op.drop_column("sessions", "contact_id")
