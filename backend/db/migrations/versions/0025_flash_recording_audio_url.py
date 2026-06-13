"""add flash recording ASR audio URL

Revision ID: 0025_flash_recording_audio_url
Revises: 0024_flash_recording_server_asr
Create Date: 2026-06-12
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0025_flash_recording_audio_url"
down_revision = "0024_flash_recording_server_asr"
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
    if "s3_audio_url" not in cols:
        op.add_column(
            "flash_recordings",
            sa.Column("s3_audio_url", sa.Text().with_variant(mysql.MEDIUMTEXT(), "mysql"), nullable=True),
        )


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("flash_recordings"):
        return

    cols = _columns("flash_recordings")
    if "s3_audio_url" in cols:
        op.drop_column("flash_recordings", "s3_audio_url")
