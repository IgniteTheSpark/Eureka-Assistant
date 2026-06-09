"""widen files.storage_url TEXT → MEDIUMTEXT (§6.6.2 AI 配图 · base64 图)

Report AI images are stored as `data:image/...;base64,...` URIs in
files.storage_url. MySQL TEXT caps at 64KB; a single 1K illustration's base64 is
~1-2MB → it would silently truncate. MEDIUMTEXT (16MB) holds it comfortably.
Widening is safe + backward-compatible (existing short values unaffected).

Revision ID: 0015_file_storage_mediumtext
Revises: 0014_message_status
Create Date: 2026-06-08
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0015_file_storage_mediumtext"
down_revision = "0014_message_status"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "files", "storage_url",
        existing_type=sa.Text(),
        type_=mysql.MEDIUMTEXT(),
        existing_nullable=True,
    )


def downgrade() -> None:
    op.alter_column(
        "files", "storage_url",
        existing_type=mysql.MEDIUMTEXT(),
        type_=sa.Text(),
        existing_nullable=True,
    )
