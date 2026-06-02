"""initial MySQL schema (squashed)

The prior Postgres migration chain (0001..0007) used Postgres-specific DDL
(UUID / JSONB / ARRAY) that doesn't run on MySQL. For the MySQL relational
store we squash to a single migration that builds the *current* schema straight
from the SQLAlchemy models via create_all — the models are the source of truth
and dev re-seeds, so there's no data history to preserve here.

Revision ID: 0001_mysql_init
Revises:
Create Date: 2026-06-02
"""
from alembic import op

revision = "0001_mysql_init"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Import here so the metadata is resolved at migration time (not import).
    from db.models import Base
    Base.metadata.create_all(bind=op.get_bind())


def downgrade() -> None:
    from db.models import Base
    Base.metadata.drop_all(bind=op.get_bind())
