from datetime import date, datetime

from sqlalchemy import (
    CHAR,
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now


class CaptureFile(Base):
    __tablename__ = "capture_files"
    __table_args__ = (Index("ix_capture_files_user_created", "user_id", "created_at"),)

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    storage_url: Mapped[str] = mapped_column(String(1024), nullable=False)
    file_type: Mapped[str] = mapped_column(String(100), nullable=False)
    source_tag: Mapped[str] = mapped_column(String(32), nullable=False)
    duration_ms: Mapped[int | None] = mapped_column(Integer)
    asr_status: Mapped[str] = mapped_column(String(32), nullable=False)
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


class CaptureRecording(Base):
    __tablename__ = "capture_recordings"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "client_task_id",
            name="uq_capture_recordings_user_client_task",
        ),
        UniqueConstraint(
            "user_id",
            "device_capture_key",
            name="uq_capture_recordings_user_device_capture",
        ),
        UniqueConstraint(
            "user_id",
            "tencent_asr_task_id",
            name="uq_capture_recordings_user_tencent_task",
        ),
        UniqueConstraint(
            "user_id",
            "card_sn",
            "device_file_name",
            "device_crc",
            name="uq_capture_recordings_device_crc",
        ),
        CheckConstraint(
            "process_status IN ('accepted', 'asr_processing', 'asr_done', "
            "'agent_processing', 'done', 'empty', 'failed')",
            name="ck_capture_recordings_process_status",
        ),
        Index(
            "ix_capture_recordings_user_status",
            "user_id",
            "process_status",
            "created_at",
        ),
        Index("ix_capture_recordings_user_file", "user_id", "file_id"),
        Index("ix_capture_recordings_user_session", "user_id", "session_id"),
        Index("ix_capture_recordings_input_turn", "input_turn_id"),
        Index("ix_capture_recordings_s3_key", "s3_key"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    file_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("capture_files.id", ondelete="CASCADE"),
        nullable=False,
    )
    session_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("chat_sessions.id", ondelete="SET NULL"),
    )
    input_turn_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("input_turns.id", ondelete="SET NULL"),
    )
    agent_message_id: Mapped[str | None] = mapped_column(
        CHAR(36),
        ForeignKey("session_messages.id", ondelete="SET NULL"),
    )
    card_sn: Mapped[str] = mapped_column(String(160), nullable=False)
    device_file_name: Mapped[str] = mapped_column(String(255), nullable=False)
    client_task_id: Mapped[str] = mapped_column(String(160), nullable=False)
    device_capture_key: Mapped[str | None] = mapped_column(String(255))
    device_kind: Mapped[str | None] = mapped_column(String(32))
    device_id: Mapped[str | None] = mapped_column(String(160))
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    device_crc: Mapped[int | None] = mapped_column(Integer)
    device_size_bytes: Mapped[int | None] = mapped_column(Integer)
    capture_started_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    capture_ended_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    local_mp3_sha256: Mapped[str | None] = mapped_column(String(64))
    local_mp3_size_bytes: Mapped[int | None] = mapped_column(Integer)
    local_audio_sha256: Mapped[str | None] = mapped_column(String(64))
    local_audio_size_bytes: Mapped[int | None] = mapped_column(Integer)
    audio_format: Mapped[str] = mapped_column(String(20), nullable=False)
    asr_mode: Mapped[str] = mapped_column(String(20), nullable=False)
    s3_key: Mapped[str] = mapped_column(String(512), nullable=False)
    s3_content_type: Mapped[str | None] = mapped_column(String(100))
    s3_upload_url: Mapped[str | None] = mapped_column(mysql.MEDIUMTEXT)
    s3_audio_url: Mapped[str | None] = mapped_column(mysql.MEDIUMTEXT)
    s3_upload_headers_json: Mapped[dict] = mapped_column(
        mysql.JSON,
        default=dict,
        nullable=False,
    )
    s3_upload_expires_in: Mapped[int | None] = mapped_column(Integer)
    s3_uploaded_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
    tencent_asr_task_id: Mapped[str | None] = mapped_column(String(160))
    tencent_engine_type: Mapped[str | None] = mapped_column(String(64))
    tencent_speaker_diarization: Mapped[int] = mapped_column(
        Integer,
        default=0,
        nullable=False,
    )
    tencent_hotword_list: Mapped[str | None] = mapped_column(Text)
    tencent_status: Mapped[str] = mapped_column(String(32), nullable=False)
    tencent_error_message: Mapped[str | None] = mapped_column(Text)
    tencent_task_response_json: Mapped[dict] = mapped_column(
        mysql.JSON,
        default=dict,
        nullable=False,
    )
    tencent_result_response_json: Mapped[dict | None] = mapped_column(mysql.JSON)
    upload_status: Mapped[str] = mapped_column(String(32), nullable=False)
    process_status: Mapped[str] = mapped_column(String(32), nullable=False)
    asr_provider: Mapped[str] = mapped_column(String(100), nullable=False)
    asr_text: Mapped[str | None] = mapped_column(Text)
    asr_segments_json: Mapped[list] = mapped_column(
        mysql.JSON,
        default=list,
        nullable=False,
    )
    asr_error: Mapped[str | None] = mapped_column(Text)
    result_summary: Mapped[str | None] = mapped_column(Text)
    result_records_json: Mapped[list] = mapped_column(
        mysql.JSON,
        default=list,
        nullable=False,
    )
    error_message: Mapped[str | None] = mapped_column(Text)
    retry_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    accepted_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
    processed_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6))
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


class CaptureTurn(Base):
    __tablename__ = "capture_turns"
    __table_args__ = (
        UniqueConstraint(
            "recording_id",
            name="uq_capture_turns_recording",
        ),
        Index("ix_capture_turns_user_created", "user_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    recording_id: Mapped[str] = mapped_column(
        CHAR(36),
        ForeignKey("capture_recordings.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    transcript: Mapped[str] = mapped_column(Text, nullable=False)
    source: Mapped[str] = mapped_column(String(32), nullable=False)
    provenance_json: Mapped[dict] = mapped_column(mysql.JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )


class FlashChatMessage(Base):
    __tablename__ = "flash_chat_messages"
    __table_args__ = (
        CheckConstraint(
            "role IN ('user', 'agent')",
            name="ck_flash_chat_messages_role",
        ),
        CheckConstraint(
            "status IN ('done', 'failed')",
            name="ck_flash_chat_messages_status",
        ),
        Index(
            "ix_flash_chat_messages_user_date_created",
            "user_id",
            "session_date",
            "created_at",
        ),
        Index(
            "uq_flash_chat_migrated_message_id",
            "migrated_session_message_id",
            unique=True,
        ),
    )

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(CHAR(36), nullable=False)
    session_date: Mapped[date] = mapped_column(mysql.DATE, nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(String(16), default="done", nullable=False)
    migrated_session_message_id: Mapped[str | None] = mapped_column(CHAR(36))
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )
