"""add contacts.source_input_turn_id (flash provenance)

Contacts were a first-class table with no link back to the voice/flash capture
that produced them, so a flash-derived 名片 couldn't be counted under the
timeline's ⚡ capture summary. Add the nullable provenance column + an index for
the per-capture grouping query. Mirrors source_input_turn_id on assets/events.

Revision ID: 0003_contact_source_input_turn
Revises: 0002_datetime_fsp6
Create Date: 2026-06-02
"""
import sqlalchemy as sa
from alembic import op

revision = "0003_contact_source_input_turn"
down_revision = "0002_datetime_fsp6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # GUID is stored as CHAR(36); add as a plain nullable column (no FK
    # constraint needed on the live DB — fresh schemas get the FK via models).
    op.add_column("contacts", sa.Column("source_input_turn_id", sa.CHAR(length=36), nullable=True))
    op.create_index("idx_contacts_input_turn", "contacts", ["user_id", "source_input_turn_id"])


def downgrade() -> None:
    op.drop_index("idx_contacts_input_turn", table_name="contacts")
    op.drop_column("contacts", "source_input_turn_id")
