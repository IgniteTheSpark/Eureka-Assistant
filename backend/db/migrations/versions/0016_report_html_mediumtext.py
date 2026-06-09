"""widen reports.html TEXT → MEDIUMTEXT (§6.6.2 · inline AI image)

A report's rendered HTML now embeds the AI concept illustration inline as a
`data:image/...;base64,...` URI (self-contained, shareable). MySQL TEXT caps at
64KB → a ~0.3-1MB image would truncate/fail the write (the figure silently
vanished). MEDIUMTEXT (16MB) holds it. content_md only gets a tiny
`![配图](asset://id)` suffix, so it stays TEXT.

Revision ID: 0016_report_html_mediumtext
Revises: 0015_file_storage_mediumtext
Create Date: 2026-06-08
"""
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql

revision = "0016_report_html_mediumtext"
down_revision = "0015_file_storage_mediumtext"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "reports", "html",
        existing_type=sa.Text(),
        type_=mysql.MEDIUMTEXT(),
        existing_nullable=False,
    )


def downgrade() -> None:
    op.alter_column(
        "reports", "html",
        existing_type=mysql.MEDIUMTEXT(),
        type_=sa.Text(),
        existing_nullable=False,
    )
