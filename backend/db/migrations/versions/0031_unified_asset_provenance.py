"""persist exact turn provenance and mutable entity versions

Revision ID: 0031_unified_asset_provenance
Revises: 0030_eureka_user_id
Create Date: 2026-07-29
"""

import sqlalchemy as sa
from alembic import op

revision = "0031_unified_asset_provenance"
down_revision = "0030_eureka_user_id"
branch_labels = None
depends_on = None


def _columns(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {column["name"] for column in inspect(op.get_bind()).get_columns(table_name)}


def _foreign_key_names(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {
        foreign_key["name"]
        for foreign_key in inspect(op.get_bind()).get_foreign_keys(table_name)
        if foreign_key.get("name")
    }


def _index_names(table_name: str) -> set[str]:
    from sqlalchemy import inspect

    return {
        index["name"]
        for index in inspect(op.get_bind()).get_indexes(table_name)
        if index.get("name")
    }


def upgrade() -> None:
    from db.models import GUID, TIMESTAMPTZ

    if "input_turn_id" not in _columns("messages"):
        op.add_column(
            "messages",
            sa.Column("input_turn_id", GUID(), nullable=True),
        )
    if "fk_messages_input_turn" not in _foreign_key_names("messages"):
        op.create_foreign_key(
            "fk_messages_input_turn",
            "messages",
            "input_turns",
            ["input_turn_id"],
            ["id"],
        )
    if "idx_messages_input_turn" not in _index_names("messages"):
        op.create_index(
            "idx_messages_input_turn",
            "messages",
            ["user_id", "input_turn_id"],
        )

    if "updated_at" not in _columns("assets"):
        op.add_column(
            "assets",
            sa.Column("updated_at", TIMESTAMPTZ, nullable=True),
        )
    if "updated_at" not in _columns("contacts"):
        op.add_column(
            "contacts",
            sa.Column("updated_at", TIMESTAMPTZ, nullable=True),
        )


def downgrade() -> None:
    if "updated_at" in _columns("contacts"):
        op.drop_column("contacts", "updated_at")
    if "updated_at" in _columns("assets"):
        op.drop_column("assets", "updated_at")
    if "idx_messages_input_turn" in _index_names("messages"):
        op.drop_index("idx_messages_input_turn", table_name="messages")
    if "fk_messages_input_turn" in _foreign_key_names("messages"):
        op.drop_constraint(
            "fk_messages_input_turn",
            "messages",
            type_="foreignkey",
        )
    if "input_turn_id" in _columns("messages"):
        op.drop_column("messages", "input_turn_id")
