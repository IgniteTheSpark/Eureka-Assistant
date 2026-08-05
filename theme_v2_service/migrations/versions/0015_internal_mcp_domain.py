"""Add the internal MCP domain foundation.

Revision ID: 0015_internal_mcp_domain
Revises: 0014_agent_session_foundation
Create Date: 2026-08-05
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0015_internal_mcp_domain"
down_revision = "0014_agent_session_foundation"
branch_labels = None
depends_on = None


def _json(value, fallback):
    if value is None:
        return fallback
    if isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return fallback


def _backfill_asset_fields() -> None:
    connection = op.get_bind()
    skill_rows = connection.execute(
        sa.text("SELECT id, schema_json FROM user_skills")
    ).mappings()
    skill_metadata: dict[str, tuple[dict, list[str]]] = {}
    for row in skill_rows:
        schema = _json(row["schema_json"], {})
        properties = schema.get("properties") or {}
        fields = [str(name) for name in properties] if isinstance(properties, dict) else []
        skill_metadata[row["id"]] = (schema, fields)
        connection.execute(
            sa.text(
                "UPDATE user_skills SET queryable_fields_json=:fields WHERE id=:id"
            ),
            {"id": row["id"], "fields": json.dumps(fields, ensure_ascii=False)},
        )

    asset_rows = connection.execute(
        sa.text(
            "SELECT id, user_id, user_skill_id, payload_json FROM assets"
        )
    ).mappings()
    inserts: list[dict] = []
    for row in asset_rows:
        schema, field_names = skill_metadata.get(row["user_skill_id"], ({}, []))
        properties = schema.get("properties") or {}
        payload = _json(row["payload_json"], {})
        if not isinstance(payload, dict):
            continue
        for field_name in field_names:
            value = payload.get(field_name)
            if value is None or isinstance(value, (dict, list)):
                continue
            value_text = None
            value_number = None
            value_date = None
            field_schema = properties.get(field_name) or {}
            if isinstance(value, (int, float)) and not isinstance(value, bool):
                try:
                    value_number = Decimal(str(value))
                except InvalidOperation:
                    value_number = None
            elif (
                isinstance(value, str)
                and field_schema.get("format") in {"date", "date-time"}
            ):
                try:
                    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
                    if parsed.tzinfo is not None:
                        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
                    value_date = parsed
                except ValueError:
                    value_text = value[:500]
            else:
                value_text = (
                    "true" if value is True else "false" if value is False else str(value)
                )[:500]
            inserts.append(
                {
                    "asset_id": row["id"],
                    "user_id": row["user_id"],
                    "field_name": field_name,
                    "value_text": value_text,
                    "value_number": value_number,
                    "value_date": value_date,
                }
            )
    if inserts:
        table = sa.table(
            "asset_fields",
            sa.column("asset_id", sa.CHAR(36)),
            sa.column("user_id", sa.CHAR(36)),
            sa.column("field_name", sa.String(100)),
            sa.column("value_text", sa.String(500)),
            sa.column("value_number", sa.Numeric(30, 10)),
            sa.column("value_date", mysql.DATETIME(fsp=6)),
        )
        op.bulk_insert(table, inserts)


def upgrade() -> None:
    op.create_table(
        "global_skills",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("machine_name", sa.String(length=100), nullable=False),
        sa.Column("display_name", sa.String(length=160), nullable=False),
        sa.Column("description", sa.String(length=1000), nullable=True),
        sa.Column("domain", sa.String(length=100), nullable=True),
        sa.Column("entity_kind", sa.String(length=32), nullable=False),
        sa.Column("schema_json", mysql.JSON(), nullable=True),
        sa.Column("system_enabled", sa.Boolean(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("machine_name", name="uq_global_skills_machine_name"),
        mysql_charset="utf8mb4",
    )
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    global_skills = sa.table(
        "global_skills",
        sa.column("machine_name", sa.String),
        sa.column("display_name", sa.String),
        sa.column("description", sa.String),
        sa.column("domain", sa.String),
        sa.column("entity_kind", sa.String),
        sa.column("schema_json", mysql.JSON),
        sa.column("system_enabled", sa.Boolean),
        sa.column("created_at", mysql.DATETIME(fsp=6)),
        sa.column("updated_at", mysql.DATETIME(fsp=6)),
    )
    op.bulk_insert(
        global_skills,
        [
            {"machine_name": "todo", "display_name": "待办", "description": "待完成事项", "domain": "生活", "entity_kind": "asset", "schema_json": None, "system_enabled": True, "created_at": now, "updated_at": now},
            {"machine_name": "expense", "display_name": "消费", "description": "消费记录", "domain": "生活", "entity_kind": "asset", "schema_json": None, "system_enabled": True, "created_at": now, "updated_at": now},
            {"machine_name": "notes", "display_name": "随记", "description": "自由文本记录", "domain": "灵感", "entity_kind": "asset", "schema_json": None, "system_enabled": True, "created_at": now, "updated_at": now},
            {"machine_name": "contact", "display_name": "联系人", "description": "人物与联系信息", "domain": "社交", "entity_kind": "contact", "schema_json": None, "system_enabled": True, "created_at": now, "updated_at": now},
            {"machine_name": "event", "display_name": "日程", "description": "有时间范围的日程", "domain": "生活", "entity_kind": "event", "schema_json": None, "system_enabled": True, "created_at": now, "updated_at": now},
            {"machine_name": "qa", "display_name": "问答", "description": "不持久化资产的通用问答", "domain": None, "entity_kind": "qa", "schema_json": None, "system_enabled": True, "created_at": now, "updated_at": now},
        ],
    )

    op.add_column("user_skills", sa.Column("global_skill_id", sa.Integer(), nullable=True))
    op.add_column(
        "user_skills",
        sa.Column(
            "queryable_fields_json",
            mysql.JSON(),
            nullable=False,
            server_default=sa.text("(JSON_ARRAY())"),
        ),
    )
    op.add_column(
        "user_skills",
        sa.Column("position", sa.Integer(), nullable=False, server_default=sa.text("0")),
    )
    op.add_column(
        "user_skills",
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("1")),
    )
    op.create_foreign_key(
        "fk_user_skills_global_skill",
        "user_skills",
        "global_skills",
        ["global_skill_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_user_skills_global_skill", "user_skills", ["global_skill_id"])
    op.execute(
        sa.text(
            """
            UPDATE user_skills AS user_skill
            JOIN global_skills AS global_skill
              ON global_skill.machine_name = user_skill.machine_name
            SET user_skill.global_skill_id = global_skill.id
            """
        )
    )

    op.add_column("assets", sa.Column("domain", sa.String(length=100), nullable=True))
    op.create_index(
        "ix_assets_user_domain_created",
        "assets",
        ["user_id", "domain", "created_at"],
    )

    op.create_table(
        "contacts",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("name", sa.String(length=320), nullable=False),
        sa.Column("phone", sa.String(length=100), nullable=True),
        sa.Column("company", sa.String(length=320), nullable=True),
        sa.Column("title", sa.String(length=320), nullable=True),
        sa.Column("email", sa.String(length=320), nullable=True),
        sa.Column("notes_json", mysql.JSON(), nullable=False),
        sa.Column("socials_json", mysql.JSON(), nullable=False),
        sa.Column("session_id", sa.CHAR(length=36), nullable=True),
        sa.Column("source_input_turn_id", sa.CHAR(length=36), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(["session_id"], ["chat_sessions.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["source_input_turn_id"], ["input_turns.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index("ix_contacts_user_name", "contacts", ["user_id", "name"])
    op.create_index(
        "ix_contacts_user_input_turn",
        "contacts",
        ["user_id", "source_input_turn_id"],
    )

    op.add_column("events", sa.Column("recurrence_rule", sa.String(length=500), nullable=True))
    op.add_column("events", sa.Column("sync_source", sa.String(length=32), nullable=True))
    op.add_column("events", sa.Column("sync_external_id", sa.String(length=500), nullable=True))
    op.add_column("events", sa.Column("source_input_turn_id", sa.CHAR(length=36), nullable=True))
    op.create_foreign_key(
        "fk_events_source_input_turn",
        "events",
        "input_turns",
        ["source_input_turn_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_events_user_source_input_turn",
        "events",
        ["user_id", "source_input_turn_id"],
    )
    op.create_unique_constraint(
        "uq_events_user_sync",
        "events",
        ["user_id", "sync_source", "sync_external_id"],
    )

    op.add_column(
        "event_attendees",
        sa.Column("legacy_contact_asset_id", sa.CHAR(length=36), nullable=True),
    )
    op.execute(
        sa.text(
            "UPDATE event_attendees SET legacy_contact_asset_id=contact_id WHERE contact_id IS NOT NULL"
        )
    )
    op.execute(sa.text("UPDATE event_attendees SET contact_id=NULL"))
    op.create_foreign_key(
        "fk_event_attendees_contact",
        "event_attendees",
        "contacts",
        ["contact_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_event_attendees_contact", "event_attendees", ["contact_id"])

    op.create_table(
        "asset_fields",
        sa.Column("asset_id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("field_name", sa.String(length=100), nullable=False),
        sa.Column("value_text", sa.String(length=500), nullable=True),
        sa.Column("value_number", sa.Numeric(precision=30, scale=10), nullable=True),
        sa.Column("value_date", mysql.DATETIME(fsp=6), nullable=True),
        sa.ForeignKeyConstraint(["asset_id"], ["assets.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("asset_id", "user_id", "field_name"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_asset_fields_number",
        "asset_fields",
        ["user_id", "field_name", "value_number"],
    )
    op.create_index(
        "ix_asset_fields_text",
        "asset_fields",
        ["user_id", "field_name", "value_text"],
    )
    op.create_index(
        "ix_asset_fields_date",
        "asset_fields",
        ["user_id", "field_name", "value_date"],
    )
    _backfill_asset_fields()

    op.create_table(
        "agent_tool_executions",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("session_id", sa.CHAR(length=36), nullable=True),
        sa.Column("input_turn_id", sa.CHAR(length=36), nullable=True),
        sa.Column("idempotency_key", sa.String(length=255), nullable=False),
        sa.Column("tool_name", sa.String(length=100), nullable=False),
        sa.Column("arguments_hash", sa.CHAR(length=64), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column("result_json", mysql.JSON(), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(["session_id"], ["chat_sessions.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["input_turn_id"], ["input_turns.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "user_id",
            "idempotency_key",
            name="uq_agent_tool_executions_user_key",
        ),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_agent_tool_executions_turn",
        "agent_tool_executions",
        ["user_id", "input_turn_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_agent_tool_executions_turn", table_name="agent_tool_executions")
    op.drop_table("agent_tool_executions")

    op.drop_index("ix_asset_fields_date", table_name="asset_fields")
    op.drop_index("ix_asset_fields_text", table_name="asset_fields")
    op.drop_index("ix_asset_fields_number", table_name="asset_fields")
    op.drop_table("asset_fields")

    op.drop_constraint(
        "fk_event_attendees_contact", "event_attendees", type_="foreignkey"
    )
    op.execute(
        sa.text(
            "UPDATE event_attendees "
            "SET contact_id=legacy_contact_asset_id "
            "WHERE legacy_contact_asset_id IS NOT NULL"
        )
    )
    op.drop_index("ix_event_attendees_contact", table_name="event_attendees")
    op.drop_column("event_attendees", "legacy_contact_asset_id")

    op.drop_constraint("uq_events_user_sync", "events", type_="unique")
    op.drop_index("ix_events_user_source_input_turn", table_name="events")
    op.drop_constraint("fk_events_source_input_turn", "events", type_="foreignkey")
    op.drop_column("events", "source_input_turn_id")
    op.drop_column("events", "sync_external_id")
    op.drop_column("events", "sync_source")
    op.drop_column("events", "recurrence_rule")

    op.drop_index("ix_contacts_user_input_turn", table_name="contacts")
    op.drop_index("ix_contacts_user_name", table_name="contacts")
    op.drop_table("contacts")

    op.drop_index("ix_assets_user_domain_created", table_name="assets")
    op.drop_column("assets", "domain")

    op.drop_constraint("fk_user_skills_global_skill", "user_skills", type_="foreignkey")
    op.drop_index("ix_user_skills_global_skill", table_name="user_skills")
    op.drop_column("user_skills", "enabled")
    op.drop_column("user_skills", "position")
    op.drop_column("user_skills", "queryable_fields_json")
    op.drop_column("user_skills", "global_skill_id")
    op.drop_table("global_skills")
