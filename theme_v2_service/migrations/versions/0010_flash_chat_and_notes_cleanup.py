"""Add flash chat history and consolidate default free-form skills.

Revision ID: 0010_flash_chat_notes
Revises: 0009_user_skill_presentation
Create Date: 2026-08-03
"""

from datetime import datetime, timezone
import uuid

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0010_flash_chat_notes"
down_revision = "0009_user_skill_presentation"
branch_labels = None
depends_on = None


NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "content": {"type": "string"},
        "domain": {"type": "string"},
    },
    "required": ["title", "content"],
    "additionalProperties": False,
    "x-capture-enabled": True,
}


LEGACY_NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "content": {"type": "string"},
        "tags": {"type": "array", "items": {"type": "string"}},
        "domain": {"type": "string"},
    },
    "required": ["title", "content", "tags"],
    "additionalProperties": False,
    "x-capture-enabled": True,
}


def upgrade() -> None:
    op.create_table(
        "flash_chat_messages",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("session_date", sa.Date(), nullable=False),
        sa.Column("role", sa.String(length=16), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column(
            "status",
            sa.String(length=16),
            nullable=False,
            server_default="done",
        ),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.CheckConstraint(
            "role IN ('user', 'agent')",
            name="ck_flash_chat_messages_role",
        ),
        sa.CheckConstraint(
            "status IN ('done', 'failed')",
            name="ck_flash_chat_messages_status",
        ),
        sa.PrimaryKeyConstraint("id"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_flash_chat_messages_user_date_created",
        "flash_chat_messages",
        ["user_id", "session_date", "created_at"],
    )

    connection = op.get_bind()
    metadata = sa.MetaData()
    skills = sa.Table("user_skills", metadata, autoload_with=connection)
    assets = sa.Table("assets", metadata, autoload_with=connection)
    recordings = sa.Table("capture_recordings", metadata, autoload_with=connection)

    skill_rows = connection.execute(
        sa.select(
            skills.c.id,
            skills.c.user_id,
            skills.c.machine_name,
        ).where(skills.c.machine_name.in_(["notes", "idea", "misc"]))
    ).mappings().all()
    notes_by_user = {
        row["user_id"]: row["id"]
        for row in skill_rows
        if row["machine_name"] == "notes"
    }
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    for row in skill_rows:
        user_id = row["user_id"]
        if user_id in notes_by_user:
            continue
        notes_id = str(uuid.uuid4())
        connection.execute(
            skills.insert().values(
                id=notes_id,
                user_id=user_id,
                machine_name="notes",
                display_name="随记",
                description="无法归入结构化技能时，忠于原文保存的自由文本内容",
                domain="knowledge",
                schema_json=NOTES_SCHEMA,
                render_spec_json={},
                chat_starters_json=[],
                created_at=now,
                updated_at=now,
            )
        )
        notes_by_user[user_id] = notes_id

    legacy_skill_to_notes = {
        row["id"]: notes_by_user[row["user_id"]]
        for row in skill_rows
        if row["machine_name"] in {"idea", "misc"}
    }
    free_form_skill_ids = set(legacy_skill_to_notes) | set(notes_by_user.values())
    if free_form_skill_ids:
        asset_rows = connection.execute(
            sa.select(
                assets.c.id,
                assets.c.user_skill_id,
                assets.c.payload_json,
            ).where(assets.c.user_skill_id.in_(free_form_skill_ids))
        ).mappings().all()
        for row in asset_rows:
            payload = dict(row["payload_json"] or {})
            connection.execute(
                assets.update()
                .where(assets.c.id == row["id"])
                .values(
                    user_skill_id=legacy_skill_to_notes.get(
                        row["user_skill_id"], row["user_skill_id"]
                    ),
                    payload_json=payload,
                )
            )

    recording_rows = connection.execute(
        sa.select(
            recordings.c.id,
            recordings.c.user_id,
            recordings.c.result_records_json,
        )
    ).mappings().all()
    for row in recording_rows:
        references = list(row["result_records_json"] or [])
        changed = False
        notes_id = notes_by_user.get(row["user_id"])
        for reference in references:
            if not isinstance(reference, dict):
                continue
            if (
                reference.get("user_skill_id") in legacy_skill_to_notes
                or reference.get("skill_machine_name") in {"idea", "misc"}
            ):
                reference["user_skill_id"] = notes_id
                reference["skill_machine_name"] = "notes"
                changed = True
        if changed:
            connection.execute(
                recordings.update()
                .where(recordings.c.id == row["id"])
                .values(result_records_json=references)
            )

    connection.execute(
        skills.update()
        .where(skills.c.machine_name == "notes")
        .values(
            display_name="随记",
            description="无法归入结构化技能时，忠于原文保存的自由文本内容",
            schema_json=NOTES_SCHEMA,
            updated_at=now,
        )
    )
    if legacy_skill_to_notes:
        connection.execute(
            skills.delete().where(skills.c.id.in_(legacy_skill_to_notes.keys()))
        )


def downgrade() -> None:
    connection = op.get_bind()
    metadata = sa.MetaData()
    skills = sa.Table("user_skills", metadata, autoload_with=connection)
    connection.execute(
        skills.update()
        .where(skills.c.machine_name == "notes")
        .values(schema_json=LEGACY_NOTES_SCHEMA)
    )
    op.drop_table("flash_chat_messages")
