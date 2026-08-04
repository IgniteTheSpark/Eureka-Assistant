from datetime import datetime

from sqlalchemy import (
    Boolean,
    CHAR,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, new_uuid, utc_now


class UserSkill(Base):
    __tablename__ = "user_skills"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "machine_name",
            name="uq_user_skills_user_machine_name",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
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
    effective_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    source_report_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("reports.id", ondelete="SET NULL"),
    )
    source_report_action_id: Mapped[str | None] = mapped_column(String(64))
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


class Event(Base):
    __tablename__ = "events"
    __table_args__ = (
        Index("ix_events_user_start", "user_id", "start_at"),
        Index("ix_events_user_created", "user_id", "created_at"),
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
    __table_args__ = (Index("ix_event_attendees_event", "event_id"),)

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    event_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("events.id", ondelete="CASCADE"),
        nullable=False,
    )
    contact_id: Mapped[str | None] = mapped_column(CHAR(36))
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
