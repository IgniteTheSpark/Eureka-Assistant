"""Add unresolved and contact-linked event attendees.

Revision ID: 0008_event_attendees
Revises: 0007_capture_workflow
Create Date: 2026-08-02
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0008_event_attendees"
down_revision = "0007_capture_workflow"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "event_attendees",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("event_id", sa.CHAR(length=36), nullable=False),
        sa.Column("contact_id", sa.CHAR(length=36), nullable=True),
        sa.Column("name_raw", sa.String(length=320), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(["event_id"], ["events.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_event_attendees_event",
        "event_attendees",
        ["event_id"],
    )


def downgrade() -> None:
    op.drop_table("event_attendees")
