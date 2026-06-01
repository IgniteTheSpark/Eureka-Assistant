"""
SQLAlchemy models — Phase B v1.4 schema.

12 tables:
  global_skills, user_skills, sessions, files, input_turns,
  assets, asset_fields, contacts, messages,
  events, event_attendees, event_files   ← NEW in v1.4

v1.4 changes (Event as first-class entity, like contacts):
- Event no longer goes through assets table — it has its own structurally-
  rich storage (start_at, end_at, location, recurrence, attendees, files)
- Sessions can be anchored to an event via Session.event_id (chat-about-event
  workflow: "帮我准备这个会议的人员调研")
- event-skill (Flash Pipeline) now calls create_event MCP tool instead of
  create_asset; events surface in Calendar via dedicated EventCard, not SkillCard

v1.3 baseline (kept):
- File and InputTurn are first-class (InputTurn replaces old Transcript concept)
- Asset has source_input_turn_id FK; user_skill_id NOT NULL
- Asset payload no longer carries asset_type (derived via user_skill_id → global_skills.name)
- Message gains tool_call, tool_result columns
- UserSkill gains display_name, render_spec (nullable for system skills like qa)
- Session.session_type values: flash | chat | meeting | manual
- input_turn.source values: voice | typed | imported (modality, NOT session_type)
- file_id on InputTurn only, NOT on Session
"""
from sqlalchemy import (
    Column, String, Integer, Numeric, Text, Date, ARRAY,
    ForeignKey, UniqueConstraint, Index, TIMESTAMP,
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import declarative_base
from sqlalchemy.sql import func
import uuid

TIMESTAMPTZ = TIMESTAMP(timezone=True)
Base = declarative_base()


class GlobalSkill(Base):
    __tablename__ = "global_skills"

    id          = Column(Integer, primary_key=True, autoincrement=True)
    name        = Column(String(50), unique=True, nullable=False)
    description = Column(Text)
    created_at  = Column(TIMESTAMPTZ, server_default=func.now())


class UserSkill(Base):
    __tablename__ = "user_skills"

    id               = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id          = Column(String(50), nullable=False, server_default="default")
    skill_id         = Column(Integer, ForeignKey("global_skills.id"))
    display_name     = Column(String(100))
    payload_schema   = Column(JSONB)   # nullable: system skills (e.g. qa) have no payload
    render_spec      = Column(JSONB)   # nullable: skills that don't produce visible assets
    queryable_fields = Column(JSONB)   # nullable
    # Position drives the 3×3 SKILLS grid order in the library. 0-based,
    # contiguous within (user_id). Drag-to-reorder writes via
    # PUT /api/skills/reorder. New skills land at the end.
    position         = Column(Integer, nullable=False, server_default="0")
    created_at       = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("user_id", "skill_id", name="uq_user_skills_user_skill"),
    )


class Session(Base):
    __tablename__ = "sessions"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(String(50), nullable=False, server_default="default")
    session_type = Column(String(20), nullable=False)   # flash | chat | meeting | manual
    title        = Column(String(255))
    date         = Column(Date)                          # natural-day grouping for flash; null for others
    # ── Subject FKs (M2.3) — each asset/entity has ONE home discussion
    # session. get-or-create on「在 chat 里讨论」. Exactly one of these is
    # set per chat-discussion session (manual/flash sessions have none set).
    event_id          = Column(UUID(as_uuid=True), ForeignKey("events.id"))    # v1.4
    contact_id        = Column(UUID(as_uuid=True), ForeignKey("contacts.id"))  # M2.3
    file_id           = Column(UUID(as_uuid=True), ForeignKey("files.id"))     # M2.3
    subject_asset_id  = Column(UUID(as_uuid=True), ForeignKey("assets.id"))    # M2.3
    # ── Additive context (M2.2) — assets pulled into discussion via
    # 「+ 添加资产」, mutable list. Distinct from subject FK above.
    context_asset_ids = Column(ARRAY(UUID(as_uuid=True)), nullable=False, server_default="{}")
    created_at   = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_sessions_user_date", "user_id", "date"),
        Index("idx_sessions_user_type",  "user_id", "session_type", "created_at"),
        Index("idx_sessions_event",      "user_id", "event_id"),
    )


class File(Base):
    __tablename__ = "files"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id      = Column(String(50), nullable=False)
    storage_url  = Column(Text)
    file_type    = Column(String(50))
    duration_sec = Column(Integer)
    source_tag   = Column(String(20))   # flash | meeting
    asr_status   = Column(String(20))   # pending | processing | completed | failed
    created_at   = Column(TIMESTAMPTZ, server_default=func.now())


class InputTurn(Base):
    """
    One unit of input within a Session. Replaces the old Transcript concept.

    Two dimensions are INDEPENDENT (Phase B v1.3):
    - session.session_type: flash | chat | meeting | manual  (the CONTAINER)
    - input_turn.source:    voice | typed | imported          (the MODALITY)

    A flash session may have a voice turn followed by a typed turn (user
    saying "把刚才那个待办改成 4 点" after a voice capture). A chat session
    may have a voice turn (user voices a message). Routing decisions in the
    API layer use `source` (modality), not `session_type`.

    Routing per turn:
    - source=voice  + session=flash   → Flash Pipeline (multi-intent fan-out)
    - source=voice  + session=meeting → Meeting Pipeline (future)
    - source=voice  + session=chat    → Assistant (transcript treated as user text)
    - source=typed  + any session     → Assistant (intent → CRUD/query/converse)
    - source=imported                 → handled by importer (not in demo)
    """
    __tablename__ = "input_turns"

    id                 = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id            = Column(String(50), nullable=False)
    session_id         = Column(UUID(as_uuid=True), ForeignKey("sessions.id"), nullable=False)
    index              = Column(Integer, nullable=False)             # 0-based position within session
    file_id            = Column(UUID(as_uuid=True), ForeignKey("files.id"))   # nullable: typed / chat has no file
    source_file_offset = Column(Integer)                              # ms in audio (meeting segment)
    text               = Column(Text, nullable=False)
    segments           = Column(JSONB)                                # optional speaker / per-token detail
    source             = Column(String(20), nullable=False)           # voice | typed | imported (modality, NOT session_type)
    asr_provider       = Column(String(50))
    language           = Column(String(10))
    created_at         = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        UniqueConstraint("session_id", "index", name="uq_input_turns_session_index"),
        Index("idx_input_turns_session", "user_id", "session_id", "index"),
        Index("idx_input_turns_source",  "user_id", "source", "created_at"),
    )


class Asset(Base):
    __tablename__ = "assets"

    id                   = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id              = Column(String(50), nullable=False, server_default="default")
    user_skill_id        = Column(UUID(as_uuid=True), ForeignKey("user_skills.id"), nullable=False)
    session_id           = Column(UUID(as_uuid=True), ForeignKey("sessions.id"))
    source_input_turn_id = Column(UUID(as_uuid=True), ForeignKey("input_turns.id"))   # nullable: manual session has no input_turn
    payload              = Column(JSONB, nullable=False)
    created_at           = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_assets_user",       "user_id", "created_at"),
        Index("idx_assets_skill",      "user_id", "user_skill_id", "created_at"),
        Index("idx_assets_input_turn", "user_id", "source_input_turn_id"),
    )


class AssetField(Base):
    """Queryable field inverted index — one row per indexed field per asset."""
    __tablename__ = "asset_fields"

    asset_id     = Column(UUID(as_uuid=True), ForeignKey("assets.id", ondelete="CASCADE"), primary_key=True)
    user_id      = Column(String(50), nullable=False, primary_key=True)
    field_name   = Column(String(100), nullable=False, primary_key=True)
    value_text   = Column(Text)
    value_number = Column(Numeric)
    value_date   = Column(TIMESTAMPTZ)

    __table_args__ = (
        Index("idx_asset_fields_num",  "user_id", "field_name", "value_number"),
        Index("idx_asset_fields_text", "user_id", "field_name", "value_text"),
        Index("idx_asset_fields_date", "user_id", "field_name", "value_date"),
    )


class Contact(Base):
    __tablename__ = "contacts"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(String(50), nullable=False, server_default="default")
    name       = Column(String(255), nullable=False)
    phone      = Column(String(50))
    company    = Column(String(255))
    title      = Column(String(255))
    email      = Column(String(255))
    notes      = Column(ARRAY(Text), server_default="{}")
    created_at = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_contacts_name", "user_id", "name"),
    )


class Event(Base):
    """
    First-class scheduled event (v1.4). Distinct from todo (which has deadline):
    event has a start_at and usually end_at — a time block on the calendar.

    Created via:
    - Voice flash → Flash Pipeline → event-skill → create_event MCP tool
    - Manual: POST /api/events
    - Future: 3rd-party sync (Google Calendar, Outlook) populates sync_source +
      sync_external_id; updates from upstream find the row by (sync_source, sync_external_id)

    Owns relations:
    - event_attendees: people invited (link to contacts when matched)
    - event_files: pre-meeting docs, recordings, notes
    - sessions(event_id=event.id): chat sessions about this event
    """
    __tablename__ = "events"

    id               = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id          = Column(String(50), nullable=False, server_default="default")
    title            = Column(String(255), nullable=False)
    start_at         = Column(TIMESTAMPTZ, nullable=False)
    end_at           = Column(TIMESTAMPTZ)
    all_day          = Column(Integer, server_default="0")   # 0/1 (Postgres has no bool default-friendly idiom we already use here)
    location         = Column(String(255))
    description      = Column(Text)
    recurrence_rule  = Column(String(255))                    # iCal RRULE; null = non-recurring
    status           = Column(String(20), server_default="scheduled")   # scheduled | cancelled | done
    sync_source      = Column(String(20))                     # manual | google | outlook | ... ; null = manual
    sync_external_id = Column(String(255))                    # upstream id for de-dup on sync
    source_input_turn_id = Column(UUID(as_uuid=True), ForeignKey("input_turns.id"))   # provenance when voice-created
    created_at       = Column(TIMESTAMPTZ, server_default=func.now())
    updated_at       = Column(TIMESTAMPTZ, server_default=func.now(), onupdate=func.now())

    __table_args__ = (
        Index("idx_events_user_start",         "user_id", "start_at"),
        Index("idx_events_user_status",        "user_id", "status", "start_at"),
        UniqueConstraint("user_id", "sync_source", "sync_external_id", name="uq_events_sync"),
    )


class EventAttendee(Base):
    """Join: event ↔ contact (or unresolved name when no contact match)."""
    __tablename__ = "event_attendees"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id   = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    contact_id = Column(UUID(as_uuid=True), ForeignKey("contacts.id"))   # nullable: name without contact match
    name_raw   = Column(String(255))                                      # fallback display when contact_id null
    role       = Column(String(20), server_default="attendee")            # organizer | attendee | optional
    created_at = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_event_attendees_event",   "event_id"),
        Index("idx_event_attendees_contact", "contact_id"),
    )


class EventFile(Base):
    """Join: event ↔ file (pre-meeting docs, recordings, notes attached to an event)."""
    __tablename__ = "event_files"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_id    = Column(UUID(as_uuid=True), ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    file_id     = Column(UUID(as_uuid=True), ForeignKey("files.id"), nullable=False)
    kind        = Column(String(20), server_default="attachment")   # prep | recording | notes | attachment
    attached_at = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_event_files_event", "event_id"),
        UniqueConstraint("event_id", "file_id", name="uq_event_files"),
    )


class Message(Base):
    __tablename__ = "messages"

    id          = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id  = Column(UUID(as_uuid=True), ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False)
    user_id     = Column(String(50), nullable=False, server_default="default")
    role        = Column(String(10), nullable=False)        # user | agent | tool
    text        = Column(Text, nullable=False, server_default="")
    tool_call   = Column(JSONB)                              # {name, args} when agent invokes a tool
    tool_result = Column(JSONB)                              # tool output (role=tool)
    cards       = Column(JSONB, server_default="[]")         # rendered asset card snapshots
    elapsed_ms  = Column(Integer)
    created_at  = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_messages_session", "session_id", "created_at"),
    )


class Task(Base):
    """
    Async task — wraps a third-party MCP call (Notion / Google Calendar /
    Dingtalk / etc.). Two-phase lifecycle:
      1. Sync head: row created with status=pending + placeholder external_ref
         asset; both returned to caller immediately.
      2. Async tail: asyncio.create_task picks up, runs the MCP via an
         ephemeral LlmAgent with that MCP's toolset attached, updates row +
         placeholder asset on success/failure.

    `result_asset_id` points to the external_ref asset that will eventually
    hold the {external_system, external_id, external_url, ...} payload after
    the MCP returns.
    """
    __tablename__ = "tasks"

    id                   = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id              = Column(String(50), nullable=False, server_default="default")
    user_text            = Column(Text, nullable=False)                       # original ask
    mcp_target           = Column(String(50))                                 # filled by agent after tool selection (notion/google_calendar/...)
    status               = Column(String(20), nullable=False, server_default="pending")  # pending | running | done | failed
    error_message        = Column(Text)
    result_asset_id      = Column(UUID(as_uuid=True), ForeignKey("assets.id"))
    session_id           = Column(UUID(as_uuid=True), ForeignKey("sessions.id"))
    source_input_turn_id = Column(UUID(as_uuid=True), ForeignKey("input_turns.id"))
    started_at           = Column(TIMESTAMPTZ)
    completed_at         = Column(TIMESTAMPTZ)
    created_at           = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_tasks_user_status", "user_id", "status", "created_at"),
        Index("idx_tasks_session",     "session_id", "created_at"),
    )


class Notification(Base):
    """
    Notification — Phase D M6/M7. A lightweight, user-facing event log that
    powers the NotificationBell badge, the toast queue, and the history page.

    Created by:
      - M6: flash completion, async task done/failed (api/flash.py, agents/task_skill.py)
      - M7: time-driven reminders (todo due / event starting soon)

    `link` is an opaque target the frontend resolves (usually an asset_id or
    event_id) so tapping a notification can deep-link to the thing it's about.
    `read` follows the codebase's 0/1 Integer convention (no Boolean type).
    """
    __tablename__ = "notifications"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id    = Column(String(50), nullable=False, server_default="default")
    type       = Column(String(20), nullable=False)   # flash_done | task_done | task_failed | reminder
    title      = Column(String(255), nullable=False)
    body       = Column(Text)
    link       = Column(String(255))                   # opaque deep-link target (asset/event id)
    read       = Column(Integer, nullable=False, server_default="0")  # 0/1
    created_at = Column(TIMESTAMPTZ, server_default=func.now())

    __table_args__ = (
        Index("idx_notifications_user_created", "user_id", "created_at"),
    )
