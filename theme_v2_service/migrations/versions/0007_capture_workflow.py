"""Add durable Theme V2 capture workflow state.

Revision ID: 0007_capture_workflow
Revises: 0006_device_bindings
Create Date: 2026-08-02
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0007_capture_workflow"
down_revision = "0006_device_bindings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "capture_files",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("storage_url", sa.String(length=1024), nullable=False),
        sa.Column("file_type", sa.String(length=100), nullable=False),
        sa.Column("source_tag", sa.String(length=32), nullable=False),
        sa.Column("duration_ms", sa.Integer(), nullable=True),
        sa.Column("asr_status", sa.String(length=32), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_capture_files_user_created",
        "capture_files",
        ["user_id", "created_at"],
    )
    op.create_table(
        "capture_recordings",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("file_id", sa.CHAR(length=36), nullable=False),
        sa.Column("card_sn", sa.String(length=160), nullable=False),
        sa.Column("device_file_name", sa.String(length=255), nullable=False),
        sa.Column("client_task_id", sa.String(length=160), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("device_crc", sa.Integer(), nullable=True),
        sa.Column("device_size_bytes", sa.Integer(), nullable=True),
        sa.Column("capture_started_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("capture_ended_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("local_mp3_sha256", sa.String(length=64), nullable=True),
        sa.Column("local_mp3_size_bytes", sa.Integer(), nullable=True),
        sa.Column("local_audio_sha256", sa.String(length=64), nullable=True),
        sa.Column("local_audio_size_bytes", sa.Integer(), nullable=True),
        sa.Column("audio_format", sa.String(length=20), nullable=False),
        sa.Column("asr_mode", sa.String(length=20), nullable=False),
        sa.Column("s3_key", sa.String(length=512), nullable=False),
        sa.Column("s3_content_type", sa.String(length=100), nullable=True),
        sa.Column("s3_upload_url", mysql.MEDIUMTEXT(), nullable=True),
        sa.Column("s3_audio_url", mysql.MEDIUMTEXT(), nullable=True),
        sa.Column("s3_upload_headers_json", mysql.JSON(), nullable=False),
        sa.Column("s3_upload_expires_in", sa.Integer(), nullable=True),
        sa.Column("s3_uploaded_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("tencent_asr_task_id", sa.String(length=160), nullable=True),
        sa.Column("tencent_engine_type", sa.String(length=64), nullable=True),
        sa.Column("tencent_speaker_diarization", sa.Integer(), nullable=False),
        sa.Column("tencent_hotword_list", sa.Text(), nullable=True),
        sa.Column("tencent_status", sa.String(length=32), nullable=False),
        sa.Column("tencent_error_message", sa.Text(), nullable=True),
        sa.Column("tencent_task_response_json", mysql.JSON(), nullable=False),
        sa.Column("tencent_result_response_json", mysql.JSON(), nullable=True),
        sa.Column("upload_status", sa.String(length=32), nullable=False),
        sa.Column("process_status", sa.String(length=32), nullable=False),
        sa.Column("asr_provider", sa.String(length=100), nullable=False),
        sa.Column("asr_text", sa.Text(), nullable=True),
        sa.Column("asr_segments_json", mysql.JSON(), nullable=False),
        sa.Column("asr_error", sa.Text(), nullable=True),
        sa.Column("result_summary", sa.Text(), nullable=True),
        sa.Column("result_records_json", mysql.JSON(), nullable=False),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("retry_count", sa.Integer(), nullable=False),
        sa.Column("accepted_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("processed_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint(
            "process_status IN ('accepted', 'asr_processing', 'asr_done', "
            "'agent_processing', 'done', 'empty', 'failed')",
            name="ck_capture_recordings_process_status",
        ),
        sa.ForeignKeyConstraint(
            ["file_id"],
            ["capture_files.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "client_task_id",
            name="uq_capture_recordings_user_client_task",
        ),
        sa.UniqueConstraint(
            "user_id",
            "tencent_asr_task_id",
            name="uq_capture_recordings_user_tencent_task",
        ),
        sa.UniqueConstraint(
            "user_id",
            "card_sn",
            "device_file_name",
            "device_crc",
            name="uq_capture_recordings_device_crc",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_capture_recordings_user_status",
        "capture_recordings",
        ["user_id", "process_status", "created_at"],
    )
    op.create_index(
        "ix_capture_recordings_user_file",
        "capture_recordings",
        ["user_id", "file_id"],
    )
    op.create_index(
        "ix_capture_recordings_s3_key",
        "capture_recordings",
        ["s3_key"],
    )
    op.create_table(
        "capture_turns",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("recording_id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("transcript", sa.Text(), nullable=False),
        sa.Column("source", sa.String(length=32), nullable=False),
        sa.Column("provenance_json", mysql.JSON(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(
            ["recording_id"],
            ["capture_recordings.id"],
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "recording_id",
            name="uq_capture_turns_recording",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_capture_turns_user_created",
        "capture_turns",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_table("capture_turns")
    op.drop_table("capture_recordings")
    op.drop_table("capture_files")
