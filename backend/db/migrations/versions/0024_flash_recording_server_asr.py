"""flash recordings server-side ASR task creation

Revision ID: 0024_flash_recording_server_asr
Revises: 0023_flash_recordings
Create Date: 2026-06-12
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0024_flash_recording_server_asr"
down_revision = "0023_flash_recordings"
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
    if "s3_upload_url" not in cols:
        op.add_column(
            "flash_recordings",
            sa.Column("s3_upload_url", sa.Text().with_variant(mysql.MEDIUMTEXT(), "mysql"), nullable=True),
        )
    if "s3_upload_headers" not in cols:
        op.add_column("flash_recordings", sa.Column("s3_upload_headers", sa.JSON(), nullable=True))

    bind = op.get_bind()
    dialect = bind.dialect.name
    if "tencent_asr_task_id" in cols:
        if dialect == "mysql":
            op.alter_column(
                "flash_recordings",
                "tencent_asr_task_id",
                existing_type=sa.String(100),
                nullable=True,
            )
        else:
            op.alter_column("flash_recordings", "tencent_asr_task_id", nullable=True)


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("flash_recordings"):
        return

    cols = _columns("flash_recordings")
    if "s3_upload_headers" in cols:
        op.drop_column("flash_recordings", "s3_upload_headers")
    if "s3_upload_url" in cols:
        op.drop_column("flash_recordings", "s3_upload_url")
