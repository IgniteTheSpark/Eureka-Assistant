from datetime import datetime

from sqlalchemy import CHAR, CheckConstraint, ForeignKey, Index, String
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now


class Card(Base):
    __tablename__ = "cards"

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    card_sn: Mapped[str] = mapped_column(String(160), unique=True, nullable=False)
    card_device_uuid: Mapped[str] = mapped_column(String(255), nullable=False)
    card_mac: Mapped[str | None] = mapped_column(String(64))
    card_mac_from: Mapped[str | None] = mapped_column(String(64))
    card_name: Mapped[str | None] = mapped_column(String(160))
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


class CardBinding(Base):
    __tablename__ = "card_bindings"
    __table_args__ = (
        CheckConstraint(
            "bind_status IN ('bound', 'unbound')",
            name="ck_card_bindings_status",
        ),
        Index(
            "ix_card_bindings_user_status",
            "user_id",
            "bind_status",
            "bind_time",
        ),
        Index("ix_card_bindings_card_created", "card_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    card_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("cards.id", ondelete="CASCADE"),
        nullable=False,
    )
    active_card_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("cards.id", ondelete="SET NULL"),
        unique=True,
    )
    card_nick: Mapped[str | None] = mapped_column(String(160))
    card_app_uuid: Mapped[str] = mapped_column(String(255), nullable=False)
    bind_status: Mapped[str] = mapped_column(
        String(32),
        default="bound",
        nullable=False,
    )
    bind_time: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    unbind_time: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
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
