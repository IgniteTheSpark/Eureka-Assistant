"""add flash recording sync ASR metadata

Revision ID: 0027_flash_recording_sync_asr
Revises: 0026_pet_onboarding_completed
Create Date: 2026-06-13
"""

import sqlalchemy as sa
from alembic import op

revision = "0027_flash_recording_sync_asr"
down_revision = "0026_pet_onboarding_completed"
branch_labels = None
depends_on = None


def _columns(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {c["name"] for c in inspect(op.get_bind()).get_columns(table_name)}


def upgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("flash_recordings"):
        return

    cols = _columns("flash_recordings")
    if "local_audio_sha256" not in cols:
        op.add_column("flash_recordings", sa.Column("local_audio_sha256", sa.String(64), nullable=True))
    if "local_audio_size_bytes" not in cols:
        op.add_column("flash_recordings", sa.Column("local_audio_size_bytes", sa.Integer(), nullable=True))
    if "audio_format" not in cols:
        op.add_column("flash_recordings", sa.Column("audio_format", sa.String(20), nullable=True))
    if "asr_mode" not in cols:
        op.add_column("flash_recordings", sa.Column("asr_mode", sa.String(20), nullable=True))


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("flash_recordings"):
        return

    cols = _columns("flash_recordings")
    for column_name in ("asr_mode", "audio_format", "local_audio_size_bytes", "local_audio_sha256"):
        if column_name in cols:
            op.drop_column("flash_recordings", column_name)
