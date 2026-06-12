"""flash recordings for Tencent ASR S3 task polling

Revision ID: 0023_flash_recordings
Revises: 0022_merge_cards_expense_heads
Create Date: 2026-06-12
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0023_flash_recordings"
down_revision = "0022_merge_cards_expense_heads"
branch_labels = None
depends_on = None


def _dt():
    return sa.DateTime(timezone=True).with_variant(mysql.DATETIME(fsp=6), "mysql")


def upgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if insp.has_table("flash_recordings"):
        return

    op.create_table(
        "flash_recordings",
        sa.Column("id", sa.CHAR(36), primary_key=True),
        sa.Column("user_id", sa.String(50), nullable=False),
        sa.Column("file_id", sa.CHAR(36), nullable=False),
        sa.Column("card_sn", sa.String(100), nullable=False),
        sa.Column("device_file_name", sa.String(255), nullable=False),
        sa.Column("client_task_id", sa.String(100), nullable=False),
        sa.Column("source", sa.String(20), nullable=False),
        sa.Column("device_crc", sa.Integer(), nullable=True),
        sa.Column("device_size_bytes", sa.Integer(), nullable=True),
        sa.Column("capture_started_at", _dt(), nullable=True),
        sa.Column("capture_ended_at", _dt(), nullable=True),
        sa.Column("local_mp3_sha256", sa.String(64), nullable=True),
        sa.Column("local_mp3_size_bytes", sa.Integer(), nullable=True),
        sa.Column("s3_key", sa.String(512), nullable=False),
        sa.Column("s3_content_type", sa.String(100), nullable=True),
        sa.Column("s3_upload_url", sa.Text().with_variant(mysql.MEDIUMTEXT(), "mysql"), nullable=True),
        sa.Column("s3_upload_headers", sa.JSON(), nullable=True),
        sa.Column("s3_upload_expires_in", sa.Integer(), nullable=True),
        sa.Column("s3_uploaded_at", _dt(), nullable=True),
        sa.Column("tencent_asr_task_id", sa.String(100), nullable=True),
        sa.Column("tencent_engine_type", sa.String(50), nullable=True),
        sa.Column("tencent_speaker_diarization", sa.Integer(), nullable=True),
        sa.Column("tencent_hotword_list", sa.Text(), nullable=True),
        sa.Column("tencent_status", sa.String(30), nullable=False),
        sa.Column("tencent_error_message", sa.Text(), nullable=True),
        sa.Column("tencent_task_response", sa.JSON(), nullable=False),
        sa.Column("tencent_result_response", sa.JSON(), nullable=True),
        sa.Column("upload_status", sa.String(20), nullable=False),
        sa.Column("process_status", sa.String(20), nullable=False),
        sa.Column("asr_provider", sa.String(50), nullable=False),
        sa.Column("asr_text", sa.Text(), nullable=True),
        sa.Column("asr_segments", sa.JSON(), nullable=True),
        sa.Column("asr_error", sa.Text(), nullable=True),
        sa.Column("session_id", sa.CHAR(36), nullable=True),
        sa.Column("input_turn_id", sa.CHAR(36), nullable=True),
        sa.Column("result_summary", sa.Text(), nullable=True),
        sa.Column("result_cards", sa.JSON(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("retry_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("accepted_at", _dt(), nullable=True),
        sa.Column("processed_at", _dt(), nullable=True),
        sa.Column("created_at", _dt(), nullable=True),
        sa.Column("updated_at", _dt(), nullable=True),
        sa.ForeignKeyConstraint(["file_id"], ["files.id"], name="fk_flash_recordings_file_id"),
        sa.ForeignKeyConstraint(["session_id"], ["sessions.id"], name="fk_flash_recordings_session_id"),
        sa.ForeignKeyConstraint(["input_turn_id"], ["input_turns.id"], name="fk_flash_recordings_input_turn_id"),
        sa.UniqueConstraint("user_id", "client_task_id", name="uq_flash_recording_client_task"),
        sa.UniqueConstraint("user_id", "tencent_asr_task_id", name="uq_flash_recording_tencent_task"),
        sa.UniqueConstraint(
            "user_id", "card_sn", "device_file_name", "device_crc",
            name="uq_flash_recording_device_crc",
        ),
    )
    op.create_index(
        "idx_flash_recordings_user_status",
        "flash_recordings",
        ["user_id", "process_status", "created_at"],
    )
    op.create_index("idx_flash_recordings_file", "flash_recordings", ["user_id", "file_id"])
    op.create_index("idx_flash_recordings_s3_key", "flash_recordings", ["s3_key"])
    op.create_index("ix_flash_recordings_user_id", "flash_recordings", ["user_id"])


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if insp.has_table("flash_recordings"):
        op.drop_table("flash_recordings")
