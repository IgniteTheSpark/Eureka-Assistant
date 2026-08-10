"""Guard one successful root mutation per atomic capture intent.

Revision ID: 0020_capture_root_mutation_key
Revises: 0019_reka_overdue_rhythm
Create Date: 2026-08-10
"""

import sqlalchemy as sa
from alembic import op


revision = "0020_capture_root_mutation_key"
down_revision = "0019_reka_overdue_rhythm"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "agent_tool_executions",
        sa.Column("root_mutation_key", sa.String(length=255), nullable=True),
    )
    op.create_unique_constraint(
        "uq_agent_tool_executions_user_root_mutation",
        "agent_tool_executions",
        ["user_id", "root_mutation_key"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_agent_tool_executions_user_root_mutation",
        "agent_tool_executions",
        type_="unique",
    )
    op.drop_column("agent_tool_executions", "root_mutation_key")
