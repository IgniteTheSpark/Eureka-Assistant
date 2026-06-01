"""Phase B v1.4 — Event as first-class entity

Adds:
- events            (top-level scheduled-event records, parallel to contacts/files)
- event_attendees   (event ↔ contact join, with name_raw fallback)
- event_files       (event ↔ file join, kind: prep/recording/notes/attachment)
- sessions.event_id (chat sessions can be anchored to an event)

Revision ID: 0002
Revises: 0001
Create Date: 2026-05-25
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

TIMESTAMPTZ = sa.TIMESTAMP(timezone=True)

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── events ─────────────────────────────────────────────────────────────────
    op.create_table(
        "events",
        sa.Column("id",               UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id",          sa.String(50), nullable=False, server_default="default"),
        sa.Column("title",            sa.String(255), nullable=False),
        sa.Column("start_at",         TIMESTAMPTZ, nullable=False),
        sa.Column("end_at",           TIMESTAMPTZ),
        sa.Column("all_day",          sa.Integer(), server_default="0"),
        sa.Column("location",         sa.String(255)),
        sa.Column("description",      sa.Text()),
        sa.Column("recurrence_rule",  sa.String(255)),                              # iCal RRULE
        sa.Column("status",           sa.String(20), server_default="scheduled"),   # scheduled | cancelled | done
        sa.Column("sync_source",      sa.String(20)),                               # manual | google | outlook | ...
        sa.Column("sync_external_id", sa.String(255)),
        sa.Column("source_input_turn_id", UUID(as_uuid=True), sa.ForeignKey("input_turns.id")),
        sa.Column("created_at",       TIMESTAMPTZ, server_default=sa.func.now()),
        sa.Column("updated_at",       TIMESTAMPTZ, server_default=sa.func.now()),
        sa.UniqueConstraint("user_id", "sync_source", "sync_external_id", name="uq_events_sync"),
    )
    op.create_index("idx_events_user_start",  "events", ["user_id", "start_at"])
    op.create_index("idx_events_user_status", "events", ["user_id", "status", "start_at"])

    # ── event_attendees ────────────────────────────────────────────────────────
    op.create_table(
        "event_attendees",
        sa.Column("id",         UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("event_id",   UUID(as_uuid=True), sa.ForeignKey("events.id", ondelete="CASCADE"), nullable=False),
        sa.Column("contact_id", UUID(as_uuid=True), sa.ForeignKey("contacts.id")),   # nullable: name without contact match
        sa.Column("name_raw",   sa.String(255)),                                     # fallback display
        sa.Column("role",       sa.String(20), server_default="attendee"),           # organizer | attendee | optional
        sa.Column("created_at", TIMESTAMPTZ, server_default=sa.func.now()),
    )
    op.create_index("idx_event_attendees_event",   "event_attendees", ["event_id"])
    op.create_index("idx_event_attendees_contact", "event_attendees", ["contact_id"])

    # ── event_files ────────────────────────────────────────────────────────────
    op.create_table(
        "event_files",
        sa.Column("id",          UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("event_id",    UUID(as_uuid=True), sa.ForeignKey("events.id", ondelete="CASCADE"), nullable=False),
        sa.Column("file_id",     UUID(as_uuid=True), sa.ForeignKey("files.id"), nullable=False),
        sa.Column("kind",        sa.String(20), server_default="attachment"),   # prep | recording | notes | attachment
        sa.Column("attached_at", TIMESTAMPTZ, server_default=sa.func.now()),
        sa.UniqueConstraint("event_id", "file_id", name="uq_event_files"),
    )
    op.create_index("idx_event_files_event", "event_files", ["event_id"])

    # ── sessions.event_id ─────────────────────────────────────────────────────
    op.add_column(
        "sessions",
        sa.Column("event_id", UUID(as_uuid=True), sa.ForeignKey("events.id")),
    )
    op.create_index("idx_sessions_event", "sessions", ["user_id", "event_id"])


def downgrade() -> None:
    op.drop_index("idx_sessions_event", table_name="sessions")
    op.drop_constraint("sessions_event_id_fkey", "sessions", type_="foreignkey")
    op.drop_column("sessions", "event_id")

    op.drop_table("event_files")
    op.drop_table("event_attendees")
    op.drop_table("events")
