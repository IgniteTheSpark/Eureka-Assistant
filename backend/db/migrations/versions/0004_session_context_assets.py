"""Phase D M2.2 — session.context_asset_ids

Adds:
- sessions.context_asset_ids UUID[] — user-attached assets that become
  contextual input to the chat agent. Populated when the user clicks
  「在 chat 里讨论」 on an asset, or selects N assets in the library and
  taps「一起讨论」(future). Mutated during chat via PATCH endpoint.

The Assistant's system prompt loads these assets and injects them into a
「本 session 上下文资产」 block so the agent can reason about them
(combine ideas, derive new todos from old ones, etc.).

Independent of session.event_id / session.contact_id / session.file_id
(those are 1:1 anchoring to a single first-class entity); this is N:M for
ad-hoc per-session focus.

Revision ID: 0004
Revises: 0003
Create Date: 2026-05-27
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY, UUID

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "sessions",
        sa.Column(
            "context_asset_ids",
            ARRAY(UUID(as_uuid=True)),
            nullable=False,
            server_default="{}",
        ),
    )


def downgrade() -> None:
    op.drop_column("sessions", "context_asset_ids")
