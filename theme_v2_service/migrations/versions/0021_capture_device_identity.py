"""Add stable hardware identity to capture recordings.

Revision ID: 0021_capture_device_identity
Revises: 0020_capture_root_mutation_key
Create Date: 2026-08-11
"""

import sqlalchemy as sa
from alembic import op


revision = "0021_capture_device_identity"
down_revision = "0020_capture_root_mutation_key"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "capture_recordings",
        sa.Column("device_capture_key", sa.String(length=255), nullable=True),
    )
    op.add_column(
        "capture_recordings",
        sa.Column("device_kind", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "capture_recordings",
        sa.Column("device_id", sa.String(length=160), nullable=True),
    )
    op.create_unique_constraint(
        "uq_capture_recordings_user_device_capture",
        "capture_recordings",
        ["user_id", "device_capture_key"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_capture_recordings_user_device_capture",
        "capture_recordings",
        type_="unique",
    )
    op.drop_column("capture_recordings", "device_id")
    op.drop_column("capture_recordings", "device_kind")
    op.drop_column("capture_recordings", "device_capture_key")
