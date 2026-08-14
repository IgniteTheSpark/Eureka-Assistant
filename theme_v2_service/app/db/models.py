from datetime import datetime

from sqlalchemy import (
    Boolean,
    CHAR,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, new_uuid, utc_now


class GlobalSkill(Base):
    __tablename__ = "global_skills"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    machine_name: Mapped[str] = mapped_column(
        String(100), unique=True, nullable=False
    )
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000))
    domain: Mapped[str | None] = mapped_column(String(100))
    entity_kind: Mapped[str] = mapped_column(
        String(32), default="asset", nullable=False
    )
    schema_json: Mapped[dict | None] = mapped_column(mysql.JSON)
    system_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class UserSkill(Base):
    __tablename__ = "user_skills"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "machine_name",
            name="uq_user_skills_user_machine_name",
        ),
        Index("ix_user_skills_global_skill", "global_skill_id"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    global_skill_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("global_skills.id", ondelete="SET NULL"),
    )
    machine_name: Mapped[str] = mapped_column(String(100), nullable=False)
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000))
    domain: Mapped[str | None] = mapped_column(String(100))
    schema_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    render_spec_json: Mapped[dict] = mapped_column(
        mysql.JSON,
        default=dict,
        nullable=False,
    )
    chat_starters_json: Mapped[list] = mapped_column(
        mysql.JSON,
        default=list,
        nullable=False,
    )
    queryable_fields_json: Mapped[list] = mapped_column(
        mysql.JSON,
        default=list,
        nullable=False,
    )
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class Asset(Base):
    __tablename__ = "assets"
    __table_args__ = (
        Index("ix_assets_user_created", "user_id", "created_at"),
        Index(
            "ix_assets_user_skill_effective",
            "user_id",
            "user_skill_id",
            "effective_at",
        ),
        Index("ix_assets_user_source_report", "user_id", "source_report_id"),
        Index("ix_assets_user_domain_created", "user_id", "domain", "created_at"),
        Index(
            "uq_assets_migrated_contact_id",
            "migrated_contact_id",
            unique=True,
        ),
        Index(
            "ix_assets_user_source_input_turn",
            "user_id",
            "source_input_turn_id",
        ),
        UniqueConstraint(
            "user_id",
            "source_report_id",
            "source_report_action_id",
            name="uq_assets_user_report_action",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    user_skill_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("user_skills.id", ondelete="CASCADE"),
        nullable=False,
    )
    payload_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    domain: Mapped[str | None] = mapped_column(String(100))
    effective_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    period: Mapped[str | None] = mapped_column(String(8))
    occurred_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    session_id: Mapped[str | None] = mapped_column(
        CHAR(36), ForeignKey("chat_sessions.id", ondelete="SET NULL")
    )
    source_input_turn_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("input_turns.id", ondelete="SET NULL"),
    )
    source_report_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("reports.id", ondelete="SET NULL"),
    )
    source_report_action_id: Mapped[str | None] = mapped_column(String(64))
    migrated_contact_id: Mapped[str | None] = mapped_column(CHAR(36))
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class AssetField(Base):
    __tablename__ = "asset_fields"
    __table_args__ = (
        Index(
            "ix_asset_fields_number",
            "user_id",
            "field_name",
            "value_number",
        ),
        Index(
            "ix_asset_fields_text",
            "user_id",
            "field_name",
            "value_text",
        ),
        Index(
            "ix_asset_fields_date",
            "user_id",
            "field_name",
            "value_date",
        ),
    )

    asset_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("assets.id", ondelete="CASCADE"),
        primary_key=True,
    )
    user_id: Mapped[str] = mapped_column(CHAR(36), primary_key=True)
    field_name: Mapped[str] = mapped_column(String(100), primary_key=True)
    value_text: Mapped[str | None] = mapped_column(String(500))
    value_number: Mapped[float | None] = mapped_column(Numeric(30, 10))
    value_date: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))


class Contact(Base):
    __tablename__ = "contacts"
    __table_args__ = (
        Index("ix_contacts_user_name", "user_id", "name"),
        Index(
            "ix_contacts_user_input_turn",
            "user_id",
            "source_input_turn_id",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    name: Mapped[str] = mapped_column(String(320), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(100))
    company: Mapped[str | None] = mapped_column(String(320))
    title: Mapped[str | None] = mapped_column(String(320))
    email: Mapped[str | None] = mapped_column(String(320))
    notes_json: Mapped[list] = mapped_column(mysql.JSON, default=list, nullable=False)
    socials_json: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    session_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("chat_sessions.id", ondelete="SET NULL"),
    )
    source_input_turn_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("input_turns.id", ondelete="SET NULL"),
    )
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        Index("ix_events_user_start", "user_id", "start_at"),
        Index("ix_events_user_created", "user_id", "created_at"),
        Index(
            "ix_events_user_source_input_turn",
            "user_id",
            "source_input_turn_id",
        ),
        UniqueConstraint(
            "user_id",
            "sync_source",
            "sync_external_id",
            name="uq_events_user_sync",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    description: Mapped[str | None] = mapped_column(Text)
    location: Mapped[str | None] = mapped_column(String(500))
    start_at: Mapped[datetime] = mapped_column(mysql.DATETIME(fsp=6), nullable=False)
    end_at: Mapped[datetime] = mapped_column(mysql.DATETIME(fsp=6), nullable=False)
    all_day: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    status: Mapped[str] = mapped_column(
        String(32),
        default="scheduled",
        nullable=False,
    )
    recurrence_rule: Mapped[str | None] = mapped_column(String(500))
    sync_source: Mapped[str | None] = mapped_column(String(32))
    sync_external_id: Mapped[str | None] = mapped_column(String(500))
    source_input_turn_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("input_turns.id", ondelete="SET NULL"),
    )
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )
    attendees: Mapped[list["EventAttendee"]] = relationship(
        back_populates="event",
        cascade="all, delete-orphan",
        lazy="selectin",
    )


class EventAttendee(Base):
    __tablename__ = "event_attendees"
    __table_args__ = (
        Index("ix_event_attendees_event", "event_id"),
        Index("ix_event_attendees_contact", "contact_id"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    event_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("events.id", ondelete="CASCADE"),
        nullable=False,
    )
    contact_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("contacts.id", ondelete="SET NULL"),
    )
    legacy_contact_asset_id: Mapped[str | None] = mapped_column(CHAR(36))
    name_raw: Mapped[str] = mapped_column(String(320), nullable=False)
    role: Mapped[str] = mapped_column(
        String(32),
        default="attendee",
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )
    event: Mapped[Event] = relationship(back_populates="attendees")


class WorkflowJob(Base):
    __tablename__ = "workflow_jobs"
    __table_args__ = (
        Index(
            "ix_workflow_jobs_claim",
            "status",
            "available_at",
            "lease_expires_at",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    run_id: Mapped[str | None] = mapped_column(CHAR(36))
    job_type: Mapped[str] = mapped_column(String(100), nullable=False)
    status: Mapped[str] = mapped_column(
        String(32),
        default="queued",
        nullable=False,
    )
    attempt: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    max_attempts: Mapped[int] = mapped_column(Integer, default=3, nullable=False)
    available_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    lease_owner: Mapped[str | None] = mapped_column(String(200))
    lease_expires_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    checkpoint_json: Mapped[dict | None] = mapped_column(mysql.JSON)
    input_dedupe_key: Mapped[str | None] = mapped_column(
        String(255),
        unique=True,
    )
    error_code: Mapped[str | None] = mapped_column(String(100))
    error_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    started_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    completed_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )


class AgentToolExecution(Base):
    __tablename__ = "agent_tool_executions"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "idempotency_key",
            name="uq_agent_tool_executions_user_key",
        ),
        UniqueConstraint(
            "user_id",
            "root_mutation_key",
            name="uq_agent_tool_executions_user_root_mutation",
        ),
        Index(
            "ix_agent_tool_executions_turn",
            "user_id",
            "input_turn_id",
            "created_at",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    session_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("chat_sessions.id", ondelete="SET NULL"),
    )
    input_turn_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("input_turns.id", ondelete="SET NULL"),
    )
    idempotency_key: Mapped[str] = mapped_column(String(255), nullable=False)
    root_mutation_key: Mapped[str | None] = mapped_column(String(255))
    tool_name: Mapped[str] = mapped_column(String(100), nullable=False)
    arguments_hash: Mapped[str] = mapped_column(CHAR(64), nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="running", nullable=False)
    result_json: Mapped[dict | None] = mapped_column(mysql.JSON)
    error_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        onupdate=utc_now,
        nullable=False,
    )

