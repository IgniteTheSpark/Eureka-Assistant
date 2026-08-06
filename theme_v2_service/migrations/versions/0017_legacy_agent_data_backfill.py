"""Backfill first-class Contacts and unified legacy Flash chat.

Revision ID: 0017_legacy_agent_data_backfill
Revises: 0016_agent_pending_actions
Create Date: 2026-08-06
"""

from __future__ import annotations

import json
import uuid
from collections import defaultdict
from typing import Any

import sqlalchemy as sa
from alembic import op


revision = "0017_legacy_agent_data_backfill"
down_revision = "0016_agent_pending_actions"
branch_labels = None
depends_on = None


def _json(value: Any, fallback: Any) -> Any:
    if value is None:
        return fallback
    if isinstance(value, (dict, list)):
        return value
    try:
        return json.loads(value)
    except (TypeError, json.JSONDecodeError):
        return fallback


def _stable_uuid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, label))


def _text(value: Any, *, limit: int | None = None) -> str | None:
    normalized = str(value or "").strip()
    if not normalized:
        return None
    return normalized[:limit] if limit is not None else normalized


def _notes(payload: dict[str, Any]) -> list[str]:
    value = payload.get("notes")
    if isinstance(value, str):
        values = [value]
    elif isinstance(value, list):
        values = value
    else:
        values = []
    return [str(item).strip() for item in values if str(item).strip()]


def _socials(payload: dict[str, Any]) -> dict[str, str]:
    supported = {
        "wechat",
        "x",
        "telegram",
        "linkedin",
        "xiaohongshu",
        "instagram",
    }
    raw = payload.get("socials")
    if not isinstance(raw, dict):
        raw = payload.get("social")
    values = dict(raw) if isinstance(raw, dict) else {}
    for key in supported:
        if key in payload:
            values[key] = payload[key]
    return {
        str(key): str(value).strip()
        for key, value in values.items()
        if str(key) in supported and str(value).strip()
    }


def _contact_mapping(connection) -> dict[str, str]:
    rows = connection.execute(
        sa.text(
            "SELECT id, migrated_contact_id FROM assets "
            "WHERE migrated_contact_id IS NOT NULL"
        )
    ).mappings()
    return {str(row["id"]): str(row["migrated_contact_id"]) for row in rows}


def _rewrite_contact_refs(value: Any, mapping: dict[str, str]) -> Any:
    if isinstance(value, list):
        return [_rewrite_contact_refs(item, mapping) for item in value]
    if not isinstance(value, dict):
        return value
    rewritten = {
        key: _rewrite_contact_refs(item, mapping)
        for key, item in value.items()
    }
    legacy_id = str(rewritten.get("asset_id") or "")
    contact_id = mapping.get(legacy_id)
    if contact_id:
        rewritten["legacy_asset_id"] = legacy_id
        rewritten["contact_id"] = contact_id
        rewritten.pop("asset_id", None)
        if str(rewritten.get("id") or "") == legacy_id:
            rewritten["id"] = contact_id
        rewritten["kind"] = "contact"
        rewritten["card_type"] = "contact"
        rewritten["icon"] = "👤"
    return rewritten


def _restore_contact_refs(value: Any, reverse_mapping: dict[str, str]) -> Any:
    if isinstance(value, list):
        return [_restore_contact_refs(item, reverse_mapping) for item in value]
    if not isinstance(value, dict):
        return value
    restored = {
        key: _restore_contact_refs(item, reverse_mapping)
        for key, item in value.items()
    }
    contact_id = str(restored.get("contact_id") or "")
    legacy_id = str(restored.get("legacy_asset_id") or "") or reverse_mapping.get(
        contact_id, ""
    )
    if legacy_id and reverse_mapping.get(contact_id) == legacy_id:
        restored["asset_id"] = legacy_id
        restored.pop("contact_id", None)
        restored.pop("legacy_asset_id", None)
        if str(restored.get("id") or "") == contact_id:
            restored["id"] = legacy_id
        restored["kind"] = "asset"
        restored["card_type"] = "contact"
    return restored


def _rewrite_json_column(
    connection,
    *,
    table: str,
    id_column: str,
    json_column: str,
    transform,
) -> None:
    rows = connection.execute(
        sa.text(
            f"SELECT {id_column} AS row_id, {json_column} AS payload "
            f"FROM {table} WHERE {json_column} IS NOT NULL"
        )
    ).mappings()
    for row in rows:
        original = _json(row["payload"], None)
        if original is None:
            continue
        changed = transform(original)
        if changed == original:
            continue
        connection.execute(
            sa.text(
                f"UPDATE {table} SET {json_column}=:payload "
                f"WHERE {id_column}=:row_id"
            ),
            {
                "payload": json.dumps(changed, ensure_ascii=False),
                "row_id": row["row_id"],
            },
        )


def _backfill_contacts(connection) -> dict[str, str]:
    rows = connection.execute(
        sa.text(
            """
            SELECT asset.id, asset.user_id, asset.payload_json, asset.session_id,
                   asset.source_input_turn_id, asset.created_at, asset.updated_at
            FROM assets AS asset
            JOIN user_skills AS skill ON skill.id=asset.user_skill_id
            WHERE skill.machine_name='contact'
              AND asset.migrated_contact_id IS NULL
            ORDER BY asset.created_at, asset.id
            """
        )
    ).mappings()
    for row in rows:
        payload = _json(row["payload_json"], {})
        if not isinstance(payload, dict):
            continue
        name = _text(payload.get("name"), limit=320)
        if name is None:
            continue
        contact_id = _stable_uuid(f"theme-v2-contact-asset:{row['id']}")
        connection.execute(
            sa.text(
                """
                INSERT IGNORE INTO contacts (
                    id, user_id, name, phone, company, title, email,
                    notes_json, socials_json, session_id, source_input_turn_id,
                    created_at, updated_at
                ) VALUES (
                    :id, :user_id, :name, :phone, :company, :title, :email,
                    :notes, :socials, :session_id, :source_input_turn_id,
                    :created_at, :updated_at
                )
                """
            ),
            {
                "id": contact_id,
                "user_id": row["user_id"],
                "name": name,
                "phone": _text(payload.get("phone"), limit=100),
                "company": _text(payload.get("company"), limit=320),
                "title": _text(
                    payload.get("title") or payload.get("job_title"),
                    limit=320,
                ),
                "email": _text(payload.get("email"), limit=320),
                "notes": json.dumps(_notes(payload), ensure_ascii=False),
                "socials": json.dumps(_socials(payload), ensure_ascii=False),
                "session_id": row["session_id"],
                "source_input_turn_id": row["source_input_turn_id"],
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
            },
        )
        connection.execute(
            sa.text(
                "UPDATE assets SET migrated_contact_id=:contact_id "
                "WHERE id=:asset_id AND migrated_contact_id IS NULL"
            ),
            {"contact_id": contact_id, "asset_id": row["id"]},
        )
    return _contact_mapping(connection)


def _rewrite_contact_links(connection, mapping: dict[str, str]) -> None:
    connection.execute(
        sa.text(
            """
            UPDATE event_attendees AS attendee
            JOIN assets AS asset
              ON asset.id=attendee.legacy_contact_asset_id
            SET attendee.contact_id=asset.migrated_contact_id
            WHERE attendee.contact_id IS NULL
              AND asset.migrated_contact_id IS NOT NULL
            """
        )
    )
    if not mapping:
        return
    transform = lambda value: _rewrite_contact_refs(value, mapping)
    _rewrite_json_column(
        connection,
        table="session_messages",
        id_column="id",
        json_column="cards_json",
        transform=transform,
    )
    _rewrite_json_column(
        connection,
        table="session_messages",
        id_column="id",
        json_column="tool_result_json",
        transform=transform,
    )
    _rewrite_json_column(
        connection,
        table="capture_recordings",
        id_column="id",
        json_column="result_records_json",
        transform=transform,
    )
    for asset_id, contact_id in mapping.items():
        connection.execute(
            sa.text(
                """
                UPDATE chat_sessions
                SET subject_type='contact', subject_id=:contact_id
                WHERE subject_type='asset' AND subject_id=:asset_id
                """
            ),
            {"asset_id": asset_id, "contact_id": contact_id},
        )


def _backfill_flash_chat(connection) -> None:
    rows = connection.execute(
        sa.text(
            """
            SELECT legacy.id, legacy.user_id, legacy.session_date, legacy.role,
                   legacy.text, legacy.status, legacy.created_at,
                   chat.id AS session_id
            FROM flash_chat_messages AS legacy
            JOIN chat_sessions AS chat
              ON chat.user_id=legacy.user_id
             AND chat.session_type='flash'
             AND chat.session_date=legacy.session_date
            WHERE legacy.migrated_session_message_id IS NULL
            ORDER BY chat.id, legacy.created_at, legacy.id
            """
        )
    ).mappings().all()
    by_session: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        by_session[str(row["session_id"])].append(dict(row))

    for session_id, messages in by_session.items():
        next_index = int(
            connection.scalar(
                sa.text(
                    "SELECT COALESCE(MAX(turn_index), -1) + 1 "
                    "FROM input_turns WHERE session_id=:session_id"
                ),
                {"session_id": session_id},
            )
        )
        current_input_turn_id: str | None = None
        last_created_at = messages[-1]["created_at"]
        for message in messages:
            if message["role"] == "user":
                current_input_turn_id = _stable_uuid(
                    f"theme-v2-migrated-flash-chat-turn:{message['id']}"
                )
                connection.execute(
                    sa.text(
                        """
                        INSERT IGNORE INTO input_turns (
                            id, user_id, session_id, turn_index, file_id,
                            recording_id, source_file_offset_ms, text,
                            segments_json, source, asr_provider, language,
                            provenance_json, created_at, updated_at
                        ) VALUES (
                            :id, :user_id, :session_id, :turn_index, NULL,
                            NULL, NULL, :text, '[]', 'typed', NULL, NULL,
                            :provenance, :created_at, :created_at
                        )
                        """
                    ),
                    {
                        "id": current_input_turn_id,
                        "user_id": message["user_id"],
                        "session_id": session_id,
                        "turn_index": next_index,
                        "text": message["text"],
                        "provenance": json.dumps(
                            {
                                "kind": "migrated_flash_chat",
                                "legacy_message_id": message["id"],
                            },
                            ensure_ascii=False,
                        ),
                        "created_at": message["created_at"],
                    },
                )
                next_index += 1

            unified_message_id = _stable_uuid(
                f"theme-v2-migrated-flash-chat-message:{message['id']}"
            )
            connection.execute(
                sa.text(
                    """
                    INSERT IGNORE INTO session_messages (
                        id, session_id, user_id, role, status, text,
                        input_turn_id, tool_call_json, tool_result_json,
                        cards_json, elapsed_ms, token_count, created_at, updated_at
                    ) VALUES (
                        :id, :session_id, :user_id, :role, :status, :text,
                        :input_turn_id, NULL, NULL, '[]', NULL, NULL,
                        :created_at, :created_at
                    )
                    """
                ),
                {
                    "id": unified_message_id,
                    "session_id": session_id,
                    "user_id": message["user_id"],
                    "role": message["role"],
                    "status": message["status"],
                    "text": message["text"],
                    "input_turn_id": current_input_turn_id,
                    "created_at": message["created_at"],
                },
            )
            connection.execute(
                sa.text(
                    """
                    UPDATE flash_chat_messages
                    SET migrated_session_message_id=:message_id
                    WHERE id=:legacy_id
                      AND migrated_session_message_id IS NULL
                    """
                ),
                {"message_id": unified_message_id, "legacy_id": message["id"]},
            )
        connection.execute(
            sa.text(
                """
                UPDATE chat_sessions
                SET revision=revision + 1,
                    updated_at=GREATEST(updated_at, :updated_at)
                WHERE id=:session_id
                """
            ),
            {"session_id": session_id, "updated_at": last_created_at},
        )


def upgrade() -> None:
    op.add_column(
        "assets",
        sa.Column("migrated_contact_id", sa.CHAR(length=36), nullable=True),
    )
    op.create_index(
        "uq_assets_migrated_contact_id",
        "assets",
        ["migrated_contact_id"],
        unique=True,
    )
    op.add_column(
        "flash_chat_messages",
        sa.Column(
            "migrated_session_message_id",
            sa.CHAR(length=36),
            nullable=True,
        ),
    )
    op.create_index(
        "uq_flash_chat_migrated_message_id",
        "flash_chat_messages",
        ["migrated_session_message_id"],
        unique=True,
    )
    connection = op.get_bind()
    mapping = _backfill_contacts(connection)
    _rewrite_contact_links(connection, mapping)
    _backfill_flash_chat(connection)


def downgrade() -> None:
    connection = op.get_bind()
    mapping = _contact_mapping(connection)
    reverse_mapping = {contact_id: asset_id for asset_id, contact_id in mapping.items()}
    if reverse_mapping:
        transform = lambda value: _restore_contact_refs(value, reverse_mapping)
        _rewrite_json_column(
            connection,
            table="session_messages",
            id_column="id",
            json_column="cards_json",
            transform=transform,
        )
        _rewrite_json_column(
            connection,
            table="session_messages",
            id_column="id",
            json_column="tool_result_json",
            transform=transform,
        )
        _rewrite_json_column(
            connection,
            table="capture_recordings",
            id_column="id",
            json_column="result_records_json",
            transform=transform,
        )
        for contact_id, asset_id in reverse_mapping.items():
            connection.execute(
                sa.text(
                    """
                    UPDATE chat_sessions
                    SET subject_type='asset', subject_id=:asset_id
                    WHERE subject_type='contact' AND subject_id=:contact_id
                    """
                ),
                {"asset_id": asset_id, "contact_id": contact_id},
            )
    connection.execute(
        sa.text(
            """
            UPDATE event_attendees AS attendee
            JOIN assets AS asset
              ON asset.id=attendee.legacy_contact_asset_id
            SET attendee.contact_id=NULL
            WHERE asset.migrated_contact_id IS NOT NULL
            """
        )
    )
    migrated_message_ids = list(
        connection.scalars(
            sa.text(
                "SELECT migrated_session_message_id FROM flash_chat_messages "
                "WHERE migrated_session_message_id IS NOT NULL"
            )
        )
    )
    if migrated_message_ids:
        connection.execute(
            sa.text(
                "DELETE FROM session_messages "
                "WHERE id IN :ids"
            ).bindparams(sa.bindparam("ids", expanding=True)),
            {"ids": migrated_message_ids},
        )
    connection.execute(
        sa.text(
            "DELETE FROM input_turns "
            "WHERE JSON_UNQUOTE(JSON_EXTRACT(provenance_json, '$.kind'))="
            "'migrated_flash_chat'"
        )
    )
    if reverse_mapping:
        connection.execute(
            sa.text("DELETE FROM contacts WHERE id IN :ids").bindparams(
                sa.bindparam("ids", expanding=True)
            ),
            {"ids": list(reverse_mapping)},
        )
    op.drop_index(
        "uq_flash_chat_migrated_message_id",
        table_name="flash_chat_messages",
    )
    op.drop_column("flash_chat_messages", "migrated_session_message_id")
    op.drop_index("uq_assets_migrated_contact_id", table_name="assets")
    op.drop_column("assets", "migrated_contact_id")
