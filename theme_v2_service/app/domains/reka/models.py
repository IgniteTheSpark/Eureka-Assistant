from datetime import datetime

from sqlalchemy import CHAR, CheckConstraint, Index, String, UniqueConstraint
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now


class Nudge(Base):
    __tablename__ = "nudges"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "natural_key",
            name="uq_nudges_user_natural_key",
        ),
        CheckConstraint(
            "status IN ('delivered', 'seen', 'acted', 'dismissed', 'expired')",
            name="ck_nudges_status",
        ),
        Index("ix_nudges_user_status", "user_id", "status"),
        Index("ix_nudges_user_kind_ref", "user_id", "kind", "ref"),
        Index("ix_nudges_expiry", "expires_at"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    natural_key: Mapped[str] = mapped_column(String(255), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    ref: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(
        String(16),
        default="delivered",
        nullable=False,
    )
    delivered_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    acted_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    dismissed_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    expires_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
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


class RhythmProfile(Base):
    __tablename__ = "rhythm_profiles"
    __table_args__ = (
        Index("ix_rhythm_profiles_user_computed", "user_id", "computed_at"),
    )

    user_id: Mapped[str] = mapped_column(CHAR(36), primary_key=True)
    skill: Mapped[str] = mapped_column(String(100), primary_key=True)
    timezone_name: Mapped[str] = mapped_column(String(64), nullable=False)
    patterns_json: Mapped[list] = mapped_column(mysql.JSON, nullable=False)
    computed_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        nullable=False,
    )
