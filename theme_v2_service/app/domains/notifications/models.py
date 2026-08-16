from datetime import datetime

from sqlalchemy import (
    Boolean,
    CHAR,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (
        Index("ix_notifications_user_created", "user_id", "created_at"),
        Index(
            "ix_notifications_user_read_created",
            "user_id",
            "read",
            "created_at",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    type: Mapped[str] = mapped_column(String(32), nullable=False)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str | None] = mapped_column(Text)
    link: Mapped[str | None] = mapped_column(String(255))
    read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )


class OutboxEvent(Base):
    __tablename__ = "outbox_events"
    __table_args__ = (
        Index(
            "ix_outbox_events_publish",
            "published_at",
            "available_at",
            "id",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    event_type: Mapped[str] = mapped_column(String(100), nullable=False)
    aggregate_type: Mapped[str] = mapped_column(String(100), nullable=False)
    aggregate_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    payload_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    available_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    attempt: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    published_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    last_error: Mapped[str | None] = mapped_column(Text)


class ReminderDelivery(Base):
    __tablename__ = "reminder_deliveries"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "natural_key",
            name="uq_reminder_deliveries_user_natural_key",
        ),
        Index("ix_reminder_deliveries_user_delivered", "user_id", "delivered_at"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    natural_key: Mapped[str] = mapped_column(String(255), nullable=False)
    record_kind: Mapped[str] = mapped_column(String(16), nullable=False)
    record_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    anchor_at: Mapped[datetime] = mapped_column(mysql.DATETIME(fsp=6), nullable=False)
    offset_minutes: Mapped[int] = mapped_column(Integer, nullable=False)
    notification_id: Mapped[str | None] = mapped_column(
        CHAR(36),
    )
    delivered_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
