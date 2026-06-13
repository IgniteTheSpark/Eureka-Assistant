"""add pet onboarding completion marker

Revision ID: 0026_pet_onboarding_completed
Revises: 0025_flash_recording_audio_url
Create Date: 2026-06-13
"""

import sqlalchemy as sa
from alembic import op

revision = "0026_pet_onboarding_completed"
down_revision = "0025_flash_recording_audio_url"
branch_labels = None
depends_on = None


def _columns(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {c["name"] for c in inspect(op.get_bind()).get_columns(table_name)}


def upgrade() -> None:
    from db.models import TIMESTAMPTZ
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("pets"):
        return

    if "onboarding_completed_at" not in _columns("pets"):
        op.add_column("pets", sa.Column("onboarding_completed_at", TIMESTAMPTZ, nullable=True))
        op.execute(
            "UPDATE pets SET onboarding_completed_at = created_at "
            "WHERE spawned = 1 AND onboarding_completed_at IS NULL"
        )


def downgrade() -> None:
    from sqlalchemy import inspect

    insp = inspect(op.get_bind())
    if not insp.has_table("pets"):
        return

    if "onboarding_completed_at" in _columns("pets"):
        op.drop_column("pets", "onboarding_completed_at")
