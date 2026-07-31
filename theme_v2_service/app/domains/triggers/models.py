from datetime import date, datetime

from sqlalchemy import (
    CHAR,
    CheckConstraint,
    Date,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now


class TriggerTracker(Base):
    __tablename__ = "trigger_trackers"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "trigger_type",
            "scope_type",
            "scope_id",
            name="uq_trigger_trackers_scope",
        ),
        CheckConstraint(
            "new_asset_count >= 0",
            name="ck_trigger_trackers_asset_count_nonnegative",
        ),
        Index("ix_trigger_trackers_active_execution", "active_execution_id"),
        Index("ix_trigger_trackers_dismissed_until", "dismissed_until"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(32), nullable=False)
    scope_type: Mapped[str] = mapped_column(String(32), nullable=False)
    scope_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    cycle_started_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        nullable=False,
    )
    new_asset_count: Mapped[int] = mapped_column(
        Integer,
        default=0,
        nullable=False,
    )
    active_execution_id: Mapped[str | None] = mapped_column(CHAR(36))
    last_notified_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    last_notified_local_date: Mapped[date | None] = mapped_column(Date)
    dismissed_until: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    proactive_suppressed_until: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6)
    )
    last_consumed_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    metadata_json: Mapped[dict] = mapped_column(
        mysql.JSON,
        default=dict,
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


class TriggerCountedAsset(Base):
    __tablename__ = "trigger_counted_assets"
    __table_args__ = (
        UniqueConstraint(
            "tracker_id",
            "asset_id",
            name="uq_trigger_counted_assets_tracker_asset",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    tracker_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("trigger_trackers.id", ondelete="CASCADE"),
        nullable=False,
    )
    asset_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    counted_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )


class TriggerExecution(Base):
    __tablename__ = "trigger_executions"
    __table_args__ = (
        UniqueConstraint("dedupe_key", name="uq_trigger_executions_dedupe_key"),
        CheckConstraint("revision > 0", name="ck_trigger_executions_revision_positive"),
        CheckConstraint(
            "status IN ('available', 'consumed', 'expired')",
            name="ck_trigger_executions_status",
        ),
        Index(
            "ix_trigger_executions_user_status_created",
            "user_id",
            "status",
            "created_at",
        ),
        Index(
            "ix_trigger_executions_tracker_status",
            "tracker_id",
            "status",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(32), nullable=False)
    workflow_type: Mapped[str] = mapped_column(String(100), nullable=False)
    tracker_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("trigger_trackers.id", ondelete="SET NULL"),
    )
    scope_type: Mapped[str] = mapped_column(String(32), nullable=False)
    scope_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    status: Mapped[str] = mapped_column(String(32), default="available", nullable=False)
    dedupe_key: Mapped[str] = mapped_column(String(255), nullable=False)
    revision: Mapped[int] = mapped_column(Integer, nullable=False)
    payload_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    first_fired_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        nullable=False,
    )
    last_fired_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        nullable=False,
    )
    last_notified_revision: Mapped[int | None] = mapped_column(Integer)
    consumed_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    expires_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    workflow_run_id: Mapped[str | None] = mapped_column(CHAR(36))
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
