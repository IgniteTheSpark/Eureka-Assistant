from datetime import datetime

from sqlalchemy import CHAR, ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, new_uuid, utc_now


class ChatSession(Base):
    __tablename__ = "chat_sessions"
    __table_args__ = (
        Index("ix_chat_sessions_user_updated", "user_id", "updated_at"),
        UniqueConstraint(
            "user_id",
            "subject_type",
            "subject_id",
            name="uq_chat_sessions_user_subject",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    session_type: Mapped[str] = mapped_column(
        String(32), default="chat", nullable=False
    )
    title: Mapped[str | None] = mapped_column(String(500))
    subject_type: Mapped[str | None] = mapped_column(String(64))
    subject_id: Mapped[str | None] = mapped_column(String(128))
    context_asset_ids_json: Mapped[list] = mapped_column(
        mysql.JSON, default=list, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, onupdate=utc_now, nullable=False
    )
    messages: Mapped[list["SessionMessage"]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class SessionMessage(Base):
    __tablename__ = "session_messages"
    __table_args__ = (
        Index("ix_session_messages_session_created", "session_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    session_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("chat_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="done", nullable=False)
    text: Mapped[str] = mapped_column(Text, default="", nullable=False)
    input_turn_id: Mapped[str | None] = mapped_column(CHAR(36))
    tool_call_json: Mapped[dict | None] = mapped_column(mysql.JSON)
    tool_result_json: Mapped[dict | None] = mapped_column(mysql.JSON)
    cards_json: Mapped[list] = mapped_column(mysql.JSON, default=list, nullable=False)
    elapsed_ms: Mapped[int | None] = mapped_column()
    token_count: Mapped[int | None] = mapped_column()
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, onupdate=utc_now, nullable=False
    )
    session: Mapped[ChatSession] = relationship(back_populates="messages")
