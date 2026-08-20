from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql


revision = "0029_email_rate_limit_buckets"
down_revision = "0028_deletion_cleanup_items"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "email_rate_limit_buckets",
        sa.Column("scope_type", sa.String(length=32), nullable=False),
        sa.Column("scope_hash", sa.String(length=128), nullable=False),
        sa.Column("bucket_start", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("last_request_at", mysql.DATETIME(fsp=6), nullable=True),
        sa.Column("request_count", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("scope_type", "scope_hash", "bucket_start"),
    )


def downgrade() -> None:
    op.drop_table("email_rate_limit_buckets")
