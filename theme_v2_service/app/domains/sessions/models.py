from datetime import date, datetime

from sqlalchemy import CHAR, ForeignKey, Index, Integer, String, Text, UniqueConstraint
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
        UniqueConstraint(
            "user_id",
            "session_type",
            "session_date",
            name="uq_chat_sessions_user_type_date",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    session_type: Mapped[str] = mapped_column(
        String(32), default="chat", nullable=False
    )
    session_date: Mapped[date | None] = mapped_column(mysql.DATE)
    revision: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
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


class InputTurn(Base):
    __tablename__ = "input_turns"
    __table_args__ = (
        UniqueConstraint(
            "session_id",
            "turn_index",
            name="uq_input_turns_session_index",
        ),
        UniqueConstraint(
            "recording_id",
            name="uq_input_turns_recording",
        ),
        Index(
            "ix_input_turns_user_session_index",
            "user_id",
            "session_id",
            "turn_index",
        ),
        Index(
            "ix_input_turns_user_source_created",
            "user_id",
            "source",
            "created_at",
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    session_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("chat_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    turn_index: Mapped[int] = mapped_column(Integer, nullable=False)
    file_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("capture_files.id", ondelete="SET NULL"),
    )
    # Kept unique but intentionally not a database FK. CaptureRecording points
    # back to InputTurn, and avoiding a circular FK keeps additive migrations
    # and deletes deterministic across MySQL versions.
    recording_id: Mapped[str | None] = mapped_column(CHAR(36))
    source_file_offset_ms: Mapped[int | None] = mapped_column(Integer)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    segments_json: Mapped[list] = mapped_column(mysql.JSON, default=list, nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    asr_provider: Mapped[str | None] = mapped_column(String(100))
    language: Mapped[str | None] = mapped_column(String(20))
    provenance_json: Mapped[dict] = mapped_column(mysql.JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, onupdate=utc_now, nullable=False
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
    input_turn_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("input_turns.id", ondelete="SET NULL"),
    )
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
