"""add connected_apps table (§1.7.1 Connected Apps)

Per-user external app connections with encrypted credentials. The connector
catalog stays in code (agents/connectors.py); this table only stores which
connector a user connected, their encrypted creds, and the connection status.

Revision ID: 0007_connected_apps
Revises: 0006_reports
Create Date: 2026-06-04
"""
import sqlalchemy as sa
from alembic import op

revision = "0007_connected_apps"
down_revision = "0006_reports"
branch_labels = None
depends_on = None


def upgrade() -> None:
    from db.models import GUID, TIMESTAMPTZ
    # Idempotent: 0001 create_all() on the LIVE models already builds
    # `connected_apps` on a FRESH deploy. Skip-if-exists avoids a duplicate-table
    # collision on a clean `alembic upgrade head` (existing DBs already ran this).
    from sqlalchemy import inspect
    if inspect(op.get_bind()).has_table("connected_apps"):
        return
    op.create_table(
        "connected_apps",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("user_id", sa.String(50), nullable=False),
        sa.Column("connector_id", sa.String(50), nullable=False),
        sa.Column("display_name", sa.String(100)),
        sa.Column("auth_type", sa.String(20), nullable=False),
        sa.Column("credentials_enc", sa.Text(), nullable=False),
        sa.Column("config_json", sa.JSON()),
        sa.Column("status", sa.String(20), nullable=False, server_default="connected"),
        sa.Column("last_used_at", TIMESTAMPTZ),
        sa.Column("created_at", TIMESTAMPTZ),
        sa.UniqueConstraint("user_id", "connector_id", name="uq_connected_apps_user_connector"),
    )
    op.create_index("idx_connected_apps_user_status", "connected_apps", ["user_id", "status"])


def downgrade() -> None:
    op.drop_index("idx_connected_apps_user_status", table_name="connected_apps")
    op.drop_table("connected_apps")
