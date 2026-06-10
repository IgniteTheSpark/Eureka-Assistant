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
    Column, String, Integer, Numeric, Text, Date,
    ForeignKey, UniqueConstraint, Index, DateTime, JSON,
)
from sqlalchemy.types import TypeDecorator, CHAR
from sqlalchemy.dialects.mysql import DATETIME as MySQLDateTime, MEDIUMTEXT
from sqlalchemy.orm import declarative_base
from datetime import datetime, timezone
import uuid


def _utcnow():
    """Python-side timestamp default. MySQL has no INSERT...RETURNING, so a DB
    server_default (func.now()) never flows back onto the ORM object — reading
    obj.created_at after the session closes then raises DetachedInstanceError.
    Setting the value in Python at flush populates the attribute on both
    MySQL and Postgres."""
    return datetime.now(timezone.utc)


class GUID(TypeDecorator):
    """Portable UUID stored as CHAR(36) so the schema runs on MySQL (which has
    no native UUID / JSONB / ARRAY). Behaves like the old
    postgresql UUID(as_uuid=True): accepts uuid.UUID or str, returns uuid.UUID.
    All UUIDs are generated app-side (default=uuid.uuid4), so there's no DB
    gen_random_uuid dependency to lose."""
    impl = CHAR(36)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        return str(value if isinstance(value, uuid.UUID) else uuid.UUID(str(value)))

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))


class UTCDateTime(TypeDecorator):
    """Timezone-correct datetime across MySQL + Postgres.

    Two problems this solves, both MySQL-specific (Postgres TIMESTAMPTZ already
    behaves correctly):

    1. **Timezone**: MySQL DATETIME has no timezone, so values round-trip as
       NAIVE. `dt.isoformat()` then omits the offset → the frontend does
       `new Date("2026-06-02T07:31:00")`, reads it as LOCAL time, and shows the
       raw UTC clock value (an N-hour skew vs the user's wall clock). We
       normalize to UTC on write and re-attach UTC on read, so every serialized
       timestamp carries `+00:00` and the client converts to local correctly.

    2. **Precision**: fsp=6 (microseconds) is required for stable ordering —
       plain DATETIME truncates to whole seconds, so same-turn rows tie on
       created_at and ORDER BY resolves the tie randomly (reversed chat replay,
       scrambled lists).
    """
    impl = DateTime
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "mysql":
            return dialect.type_descriptor(MySQLDateTime(fsp=6))
        return dialect.type_descriptor(DateTime(timezone=True))

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)   # treat naive input as UTC
        value = value.astimezone(timezone.utc)           # normalize to UTC
        if dialect.name == "mysql":
            value = value.replace(tzinfo=None)           # MySQL DATETIME stores naive
        return value

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)   # naive from MySQL == UTC
        return value


TIMESTAMPTZ = UTCDateTime()
Base = declarative_base()


class GlobalSkill(Base):
    __tablename__ = "global_skills"

    id          = Column(Integer, primary_key=True, autoincrement=True)
    name        = Column(String(50), unique=True, nullable=False)
    description = Column(Text)
    domain      = Column(String(20))   # §8 provisioning default domain prior
    created_at  = Column(TIMESTAMPTZ, default=_utcnow)


class User(Base):
    """Account row (email + password auth). `users.id` is the value that lands
    in every other table's `user_id` column, so it's a String(50) uuid hex."""
    __tablename__ = "users"

    id            = Column(String(50), primary_key=True, default=lambda: uuid.uuid4().hex)
    # email + password_hash are nullable: a 百智-OAuth user (§13.1) has neither —
    # their identity is `baizhi_user_id`. Email users still set both.
    email         = Column(String(255), unique=True, nullable=True, index=True)
    password_hash = Column(String(255), nullable=True)
    # §13.1 — stable 百智 (100wiser) identity ↔ Eureka user mapping. Unique so one
    # 百智 account = one Eureka user; null for email-registered users.
    baizhi_user_id = Column(String(64), unique=True, nullable=True, index=True)
    created_at    = Column(TIMESTAMPTZ, default=_utcnow)


class UserSkill(Base):
    __tablename__ = "user_skills"

    id               = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id          = Column(String(50), nullable=False, server_default="default")
    skill_id         = Column(Integer, ForeignKey("global_skills.id"))
    display_name     = Column(String(100))
    payload_schema   = Column(JSON)   # nullable: system skills (e.g. qa) have no payload
    render_spec      = Column(JSON)   # nullable: skills that don't produce visible assets
    queryable_fields = Column(JSON)   # nullable
    # Position drives the 3×3 SKILLS grid order in the library. 0-based,
    # contiguous within (user_id). Drag-to-reorder writes via
    # PUT /api/skills/reorder. New skills land at the end.
    position         = Column(Integer, nullable=False, server_default="0")
    # Active-set flag: 1 = shows in the grid + agent routes to it; 0 = hidden +
    # not routed (input falls back to misc/notes), but history stays queryable.
    # Cap on simultaneously-active skills is ACTIVE_SKILL_CAP (api/skills.py).
    enabled          = Column(Integer, nullable=False, server_default="1")
    domain           = Column(String(20))   # §8 per-skill prior (default for new assets)
    created_at       = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        UniqueConstraint("user_id", "skill_id", name="uq_user_skills_user_skill"),
    )


class Session(Base):
    __tablename__ = "sessions"

    id           = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id      = Column(String(50), nullable=False, server_default="default")
    session_type = Column(String(20), nullable=False)   # flash | chat | meeting | manual
    title        = Column(String(255))
    date         = Column(Date)                          # natural-day grouping for flash; null for others
    # ── Subject FKs (M2.3) — each asset/entity has ONE home discussion
    # session. get-or-create on「在 chat 里讨论」. Exactly one of these is
    # set per chat-discussion session (manual/flash sessions have none set).
    event_id          = Column(GUID(), ForeignKey("events.id"))    # v1.4
    contact_id        = Column(GUID(), ForeignKey("contacts.id"))  # M2.3
    file_id           = Column(GUID(), ForeignKey("files.id"))     # M2.3
    subject_asset_id  = Column(GUID(), ForeignKey("assets.id"))    # M2.3
    # ── Additive context (M2.2) — assets pulled into discussion via
    # 「+ 添加资产」, mutable list. Distinct from subject FK above.
    context_asset_ids = Column(JSON, nullable=False, default=list)   # was ARRAY(UUID) on PG
    created_at   = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_sessions_user_date", "user_id", "date"),
        Index("idx_sessions_user_type",  "user_id", "session_type", "created_at"),
        Index("idx_sessions_event",      "user_id", "event_id"),
    )


class File(Base):
    __tablename__ = "files"

    id           = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id      = Column(String(50), nullable=False)
    # MEDIUMTEXT (16MB) on MySQL — holds a base64 data:URI for an AI report image
    # (§6.6.2); plain Text (64KB) would truncate it. Other backends fall back to Text.
    storage_url  = Column(Text().with_variant(MEDIUMTEXT, "mysql"))
    file_type    = Column(String(50))
    duration_sec = Column(Integer)
    source_tag   = Column(String(20))   # flash | meeting
    asr_status   = Column(String(20))   # pending | processing | completed | failed
    created_at   = Column(TIMESTAMPTZ, default=_utcnow)


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

    id                 = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id            = Column(String(50), nullable=False)
    session_id         = Column(GUID(), ForeignKey("sessions.id"), nullable=False)
    index              = Column(Integer, nullable=False)             # 0-based position within session
    file_id            = Column(GUID(), ForeignKey("files.id"))   # nullable: typed / chat has no file
    source_file_offset = Column(Integer)                              # ms in audio (meeting segment)
    text               = Column(Text, nullable=False)
    segments           = Column(JSON)                                # optional speaker / per-token detail
    source             = Column(String(20), nullable=False)           # voice | typed | imported (modality, NOT session_type)
    asr_provider       = Column(String(50))
    language           = Column(String(10))
    created_at         = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        UniqueConstraint("session_id", "index", name="uq_input_turns_session_index"),
        Index("idx_input_turns_session", "user_id", "session_id", "index"),
        Index("idx_input_turns_source",  "user_id", "source", "created_at"),
    )


class Asset(Base):
    __tablename__ = "assets"

    id                   = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id              = Column(String(50), nullable=False, server_default="default")
    user_skill_id        = Column(GUID(), ForeignKey("user_skills.id"), nullable=False)
    session_id           = Column(GUID(), ForeignKey("sessions.id"))
    source_input_turn_id = Column(GUID(), ForeignKey("input_turns.id"))   # nullable: manual session has no input_turn
    payload              = Column(JSON, nullable=False)
    domain               = Column(String(20))   # §8 life-domain label (nullable = 不归域)
    # §6.13 / §14 溯源: a todo created from a report action (or later a nudge)
    # points back at its origin — todo detail shows「来自报告《X》」, and the
    # report's native action bar dedupes against it ("已加 ✓").
    source_report_id     = Column(GUID())
    created_at           = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_assets_user",          "user_id", "created_at"),
        Index("idx_assets_skill",         "user_id", "user_skill_id", "created_at"),
        Index("idx_assets_input_turn",    "user_id", "source_input_turn_id"),
        Index("idx_assets_domain",        "user_id", "domain"),
        Index("idx_assets_source_report", "user_id", "source_report_id"),
    )


class AssetField(Base):
    """Queryable field inverted index — one row per indexed field per asset."""
    __tablename__ = "asset_fields"

    asset_id     = Column(GUID(), ForeignKey("assets.id", ondelete="CASCADE"), primary_key=True)
    user_id      = Column(String(50), nullable=False, primary_key=True)
    field_name   = Column(String(100), nullable=False, primary_key=True)
    value_text   = Column(Text)
    value_number = Column(Numeric)
    value_date   = Column(TIMESTAMPTZ)

    __table_args__ = (
        Index("idx_asset_fields_num",  "user_id", "field_name", "value_number"),
        # value_text is TEXT (unbounded) → MySQL needs a key-length prefix to
        # index it. 255 chars is plenty for the queryable-field value match.
        Index("idx_asset_fields_text", "user_id", "field_name", "value_text",
              mysql_length={"value_text": 255}),
        Index("idx_asset_fields_date", "user_id", "field_name", "value_date"),
    )


class Contact(Base):
    __tablename__ = "contacts"

    id         = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id    = Column(String(50), nullable=False, server_default="default")
    name       = Column(String(255), nullable=False)
    phone      = Column(String(50))
    company    = Column(String(255))
    title      = Column(String(255))
    email      = Column(String(255))
    notes      = Column(JSON, default=list)   # was ARRAY(Text) on PG; list of md annotation lines
    # 名片 socials: {platform_key: handle} chosen from a fixed supported set
    # (x/telegram/linkedin/wechat/xiaohongshu/instagram — see core/contacts_meta.py).
    socials    = Column(JSON, default=dict)
    # Provenance: the flash/voice input_turn that produced this contact (nullable —
    # chat/manual contacts have none). Powers the timeline ⚡ capture summary
    # ("联系人 ×1"). Other entities (asset/event) already carry this FK.
    source_input_turn_id = Column(GUID(), ForeignKey("input_turns.id"))
    created_at = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_contacts_name", "user_id", "name"),
        Index("idx_contacts_input_turn", "user_id", "source_input_turn_id"),
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

    id               = Column(GUID(), primary_key=True, default=uuid.uuid4)
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
    source_input_turn_id = Column(GUID(), ForeignKey("input_turns.id"))   # provenance when voice-created
    created_at       = Column(TIMESTAMPTZ, default=_utcnow)
    updated_at       = Column(TIMESTAMPTZ, default=_utcnow, onupdate=_utcnow)

    __table_args__ = (
        Index("idx_events_user_start",         "user_id", "start_at"),
        Index("idx_events_user_status",        "user_id", "status", "start_at"),
        UniqueConstraint("user_id", "sync_source", "sync_external_id", name="uq_events_sync"),
    )


class EventAttendee(Base):
    """Join: event ↔ contact (or unresolved name when no contact match)."""
    __tablename__ = "event_attendees"

    id         = Column(GUID(), primary_key=True, default=uuid.uuid4)
    event_id   = Column(GUID(), ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    contact_id = Column(GUID(), ForeignKey("contacts.id"))   # nullable: name without contact match
    name_raw   = Column(String(255))                                      # fallback display when contact_id null
    role       = Column(String(20), server_default="attendee")            # organizer | attendee | optional
    created_at = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_event_attendees_event",   "event_id"),
        Index("idx_event_attendees_contact", "contact_id"),
    )


class EventFile(Base):
    """Join: event ↔ file (pre-meeting docs, recordings, notes attached to an event)."""
    __tablename__ = "event_files"

    id          = Column(GUID(), primary_key=True, default=uuid.uuid4)
    event_id    = Column(GUID(), ForeignKey("events.id", ondelete="CASCADE"), nullable=False)
    file_id     = Column(GUID(), ForeignKey("files.id"), nullable=False)
    kind        = Column(String(20), server_default="attachment")   # prep | recording | notes | attachment
    attached_at = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_event_files_event", "event_id"),
        UniqueConstraint("event_id", "file_id", name="uq_event_files"),
    )


class Message(Base):
    __tablename__ = "messages"

    id          = Column(GUID(), primary_key=True, default=uuid.uuid4)
    session_id  = Column(GUID(), ForeignKey("sessions.id", ondelete="CASCADE"), nullable=False)
    user_id     = Column(String(50), nullable=False, server_default="default")
    role        = Column(String(10), nullable=False)        # user | agent | tool
    text        = Column(Text, nullable=False, default="")   # MySQL TEXT can't take a server_default
    tool_call   = Column(JSON)                              # {name, args} when agent invokes a tool
    tool_result = Column(JSON)                              # tool output (role=tool)
    cards       = Column(JSON, default=list)                # rendered asset card snapshots
    elapsed_ms  = Column(Integer)
    # §1.5.1.3 batch A — durable turn lifecycle (agent messages only):
    # running → done | failed. User msgs + legacy rows default 'done' (terminal).
    # A returning client reconciles against this: running → 「分析中…」 + poll.
    status      = Column(String(12), default="done")
    created_at  = Column(TIMESTAMPTZ, default=_utcnow)

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

    id                   = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id              = Column(String(50), nullable=False, server_default="default")
    user_text            = Column(Text, nullable=False)                       # original ask
    mcp_target           = Column(String(50))                                 # filled by agent after tool selection (notion/google_calendar/...)
    status               = Column(String(20), nullable=False, server_default="pending")  # pending | running | done | failed
    error_message        = Column(Text)
    result_asset_id      = Column(GUID(), ForeignKey("assets.id"))
    session_id           = Column(GUID(), ForeignKey("sessions.id"))
    source_input_turn_id = Column(GUID(), ForeignKey("input_turns.id"))
    started_at           = Column(TIMESTAMPTZ)
    completed_at         = Column(TIMESTAMPTZ)
    created_at           = Column(TIMESTAMPTZ, default=_utcnow)

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

    id         = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id    = Column(String(50), nullable=False, server_default="default")
    type       = Column(String(20), nullable=False)   # flash_done | task_done | task_failed | reminder
    title      = Column(String(255), nullable=False)
    body       = Column(Text)
    link       = Column(String(255))                   # opaque deep-link target (asset/event id)
    read       = Column(Integer, nullable=False, server_default="0")  # 0/1
    created_at = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_notifications_user_created", "user_id", "created_at"),
    )


class Report(Base):
    """
    Synthesis/report engine output (§6). A first-class entity (资产库「报告」容器).

    The pipeline (report-dispatcher → content skill → render skill) produces two
    layers that are stored side by side:
    - `content_md`: annotated Markdown (the *substance* — re-renderable). Numbers
      and quotes only ever come from queried records; never fabricated.
    - `html`: the rendered snapshot the user currently sees (the *presentation*).

    `spec_json` = {time_range, asset_types, source_asset_ids, surface, palette,
    seed} — everything needed to re-render (换装) or re-run without re-thinking.
    Re-render = same content_md + new seed/palette/surface → new html, no re-query.
    """
    __tablename__ = "reports"

    id         = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id    = Column(String(50), nullable=False, server_default="default")
    title      = Column(String(255), nullable=False)
    genre      = Column(String(30), nullable=False)   # data-report | idea-synthesis | proposal | digest
    content_md = Column(Text, nullable=False)          # annotated Markdown (substance)
    # MEDIUMTEXT (16MB) on MySQL — the rendered HTML inlines the AI image as a
    # base64 data:URI (§6.6.2); plain Text (64KB) would truncate it.
    html       = Column(Text().with_variant(MEDIUMTEXT, "mysql"), nullable=False)
    spec_json  = Column(JSON)                           # {time_range, asset_types, source_asset_ids, surface, palette, seed}
    # §6.7 / §6.12 batch 0 telemetry: summed model tokens (dispatcher+content[+image])
    # and wall-clock generation time. Cost aggregation (admin) + gen_ms can be shown.
    tokens_used = Column(Integer)
    gen_ms      = Column(Integer)
    # §6.6.1 / §6.12 batch 3: REKA genome snapshot for the footer signature band
    # (so a re-shared old report keeps the pet it was made with).
    pet_gene   = Column(JSON)
    # §6.13 / handoff Phase 1: actions extracted from the content skill's
    # `:::actions` block — [{title, kind?, due?}]. The viewer renders these as a
    # NATIVE「✦ 接下来」action bar (+ 待办); the in-HTML checklist stays read-only.
    suggested_actions = Column(JSON)
    created_at = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_reports_user_created", "user_id", "created_at"),
    )


class ConnectedApp(Base):
    """
    Per-user external app connection (§1.7.1 Connected Apps). Replaces the old
    dev-wired global MCP: each user connects their own apps (钉钉 / Notion / …)
    with their own credentials, stored **encrypted at rest**.

    The connector *catalog* (what apps exist + which fields to fill) is NOT in
    the DB — it's developer-maintained in `agents/connectors.py` and exposed via
    `GET /api/connectors`. This table only stores "user X connected connector Y
    with these (encrypted) creds + this status".

    `credentials_enc` is a Fernet-encrypted JSON blob ({field: value}); it is
    write-only — **never** returned by any API, never logged. The task runner
    decrypts it at call time to build that user's external MCP toolsets.
    """
    __tablename__ = "connected_apps"

    id              = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id         = Column(String(50), nullable=False)
    connector_id    = Column(String(50), nullable=False)   # catalog key (dingtalk_calendar / notion / …)
    display_name    = Column(String(100))                  # user-editable alias
    auth_type       = Column(String(20), nullable=False)   # token / gateway_url / oauth
    credentials_enc = Column(Text, nullable=False)         # Fernet-encrypted JSON; NEVER in responses/logs
    config_json     = Column(JSON)                         # non-secret config (scopes, options)
    status          = Column(String(20), nullable=False, server_default="connected")  # connected/needs_reauth/error/disconnected
    last_used_at    = Column(TIMESTAMPTZ)
    created_at      = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        UniqueConstraint("user_id", "connector_id", name="uq_connected_apps_user_connector"),
        Index("idx_connected_apps_user_status", "user_id", "status"),
    )


class Pet(Base):
    """§9 球球 Pet — one per user. A gradient jelly body + forehead emblem, 7
    swappable cosmetic slots (skin / emblem(+color) / head / leftItem / rightItem
    / carrier / aura; eyes & mouth are state-driven, not stored). NO levels —
    growth = horizontally collecting cosmetics (random drops + milestone-gated
    unlocks, each carrying a rarity tier; see core/pet.py). Subscribes only to
    completion_events (§9.1, decoupled from island/tasks/domain). `seed` makes the
    spawn skin deterministic per user. carrier/aura live in the `equipped` JSON
    (no migration); pre-v2 pets back-fill to carrier='none', aura='soft'.
    """
    __tablename__ = "pets"

    id           = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id      = Column(String(50), nullable=False)
    seed         = Column(String(50), nullable=False)
    name         = Column(String(50))
    skin         = Column(String(20))                 # colorway (aurora/grape/…)
    emblem       = Column(String(20))                 # forehead mark (star/drop/…)
    emblem_color = Column(String(20))
    equipped     = Column(JSON)                        # {head, leftItem, rightItem}
    unlocked     = Column(JSON)                        # {skin:[], emblem:[], head:[], item:[]}
    milestones   = Column(JSON)                        # {capture_count, streak_days, last_event_date, domains:[]}
    spawned      = Column(Integer, nullable=False, server_default="0")  # 0 = egg (pre-hatch), 1 = hatched
    created_at   = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        UniqueConstraint("user_id", name="uq_pets_user"),
    )


class CompletionEvent(Base):
    """Append-only currency: one row per closed loop (task done / record logged /
    opportunistic first-class create). The pet subscribes to these (celebrate +
    drop + milestone); the future weekly island aggregates them per `domain`."""
    __tablename__ = "completion_events"

    id         = Column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id    = Column(String(50), nullable=False)
    domain     = Column(String(20))                    # §8 (pet ignores; island aggregates)
    source     = Column(String(20), nullable=False)    # task | record | opportunistic
    ref        = Column(String(50))                    # asset/event/contact id
    created_at = Column(TIMESTAMPTZ, default=_utcnow)

    __table_args__ = (
        Index("idx_completion_events_user", "user_id", "created_at"),
    )
