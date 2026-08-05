"""Add physical Flash Sessions and first-class InputTurns.

Revision ID: 0014_agent_session_foundation
Revises: 0013_chat_sessions
Create Date: 2026-08-05
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import mysql


revision = "0014_agent_session_foundation"
down_revision = "0013_chat_sessions"
branch_labels = None
depends_on = None


def _stable_uuid(source_sql: str) -> str:
    digest = f"MD5({source_sql})"
    return (
        "LOWER(CONCAT("
        f"SUBSTR({digest}, 1, 8), '-', "
        f"SUBSTR({digest}, 9, 4), '-', "
        f"SUBSTR({digest}, 13, 4), '-', "
        f"SUBSTR({digest}, 17, 4), '-', "
        f"SUBSTR({digest}, 21, 12)))"
    )


def upgrade() -> None:
    op.add_column(
        "chat_sessions",
        sa.Column("session_date", mysql.DATE(), nullable=True),
    )
    op.add_column(
        "chat_sessions",
        sa.Column(
            "revision",
            sa.Integer(),
            nullable=False,
            server_default=sa.text("0"),
        ),
    )
    op.create_unique_constraint(
        "uq_chat_sessions_user_type_date",
        "chat_sessions",
        ["user_id", "session_type", "session_date"],
    )

    op.create_table(
        "input_turns",
        sa.Column("id", sa.CHAR(length=36), nullable=False),
        sa.Column("user_id", sa.CHAR(length=36), nullable=False),
        sa.Column("session_id", sa.CHAR(length=36), nullable=False),
        sa.Column("turn_index", sa.Integer(), nullable=False),
        sa.Column("file_id", sa.CHAR(length=36), nullable=True),
        sa.Column("recording_id", sa.CHAR(length=36), nullable=True),
        sa.Column("source_file_offset_ms", sa.Integer(), nullable=True),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("segments_json", mysql.JSON(), nullable=False),
        sa.Column("source", sa.String(length=20), nullable=False),
        sa.Column("asr_provider", sa.String(length=100), nullable=True),
        sa.Column("language", sa.String(length=20), nullable=True),
        sa.Column("provenance_json", mysql.JSON(), nullable=False),
        sa.Column("created_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["chat_sessions.id"],
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["file_id"],
            ["capture_files.id"],
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "session_id",
            "turn_index",
            name="uq_input_turns_session_index",
        ),
        sa.UniqueConstraint("recording_id", name="uq_input_turns_recording"),
        mysql_charset="utf8mb4",
    )
    op.create_index(
        "ix_input_turns_user_session_index",
        "input_turns",
        ["user_id", "session_id", "turn_index"],
    )
    op.create_index(
        "ix_input_turns_user_source_created",
        "input_turns",
        ["user_id", "source", "created_at"],
    )
    # Existing Theme V2 Chat messages already share a generated input_turn_id,
    # but the row was never persisted. Materialize those IDs before enforcing
    # the new FK so Chat provenance survives the additive migration.
    op.execute(
        sa.text(
            """
            INSERT IGNORE INTO input_turns (
                id, user_id, session_id, turn_index, file_id, recording_id,
                source_file_offset_ms, text, segments_json, source,
                asr_provider, language, provenance_json, created_at, updated_at
            )
            SELECT
                grouped.input_turn_id,
                grouped.user_id,
                grouped.session_id,
                ROW_NUMBER() OVER (
                    PARTITION BY grouped.session_id
                    ORDER BY grouped.created_at, grouped.input_turn_id
                ) - 1,
                NULL,
                NULL,
                NULL,
                grouped.user_text,
                JSON_ARRAY(),
                'typed',
                NULL,
                NULL,
                JSON_OBJECT('kind', 'migrated_theme_v2_chat'),
                grouped.created_at,
                grouped.updated_at
            FROM (
                SELECT
                    input_turn_id,
                    user_id,
                    session_id,
                    COALESCE(
                        MAX(CASE WHEN role = 'user' THEN text END),
                        ''
                    ) AS user_text,
                    MIN(created_at) AS created_at,
                    MAX(updated_at) AS updated_at
                FROM session_messages
                WHERE input_turn_id IS NOT NULL
                GROUP BY input_turn_id, user_id, session_id
            ) AS grouped
            """
        )
    )

    op.create_foreign_key(
        "fk_session_messages_input_turn",
        "session_messages",
        "input_turns",
        ["input_turn_id"],
        ["id"],
        ondelete="SET NULL",
    )

    op.add_column(
        "capture_recordings",
        sa.Column("session_id", sa.CHAR(length=36), nullable=True),
    )
    op.add_column(
        "capture_recordings",
        sa.Column("input_turn_id", sa.CHAR(length=36), nullable=True),
    )
    op.add_column(
        "capture_recordings",
        sa.Column("agent_message_id", sa.CHAR(length=36), nullable=True),
    )
    op.create_foreign_key(
        "fk_capture_recordings_session",
        "capture_recordings",
        "chat_sessions",
        ["session_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_capture_recordings_input_turn",
        "capture_recordings",
        "input_turns",
        ["input_turn_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_foreign_key(
        "fk_capture_recordings_agent_message",
        "capture_recordings",
        "session_messages",
        ["agent_message_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_capture_recordings_user_session",
        "capture_recordings",
        ["user_id", "session_id"],
    )
    op.create_index(
        "ix_capture_recordings_input_turn",
        "capture_recordings",
        ["input_turn_id"],
    )

    local_date = (
        "DATE(DATE_ADD(COALESCE(capture_started_at, created_at), "
        "INTERVAL 8 HOUR))"
    )
    grouped_session_uuid = _stable_uuid(
        "CONCAT('theme-v2-flash:', grouped.user_id, ':', grouped.local_date)"
    )
    op.execute(
        sa.text(
            f"""
            INSERT IGNORE INTO chat_sessions (
                id, user_id, session_type, session_date, revision, title,
                subject_type, subject_id, context_asset_ids_json,
                created_at, updated_at
            )
            SELECT
                {grouped_session_uuid},
                grouped.user_id,
                'flash',
                grouped.local_date,
                1,
                CONCAT(
                    MONTH(grouped.local_date),
                    '月',
                    DAY(grouped.local_date),
                    '日 闪念'
                ),
                NULL,
                NULL,
                JSON_ARRAY(),
                grouped.created_at,
                grouped.updated_at
            FROM (
                SELECT
                    user_id,
                    {local_date} AS local_date,
                    MIN(COALESCE(capture_started_at, created_at)) AS created_at,
                    MAX(updated_at) AS updated_at
                FROM capture_recordings
                WHERE TRIM(COALESCE(asr_text, '')) <> ''
                GROUP BY user_id, {local_date}
            ) AS grouped
            """
        )
    )

    turn_uuid = _stable_uuid("CONCAT('theme-v2-input-turn:', id)")
    ranked_capture_rows = f"""
        SELECT
            id,
            user_id,
            file_id,
            card_sn,
            device_file_name,
            source,
            asr_provider,
            asr_text,
            asr_segments_json,
            created_at,
            updated_at,
            {local_date} AS local_date,
            ROW_NUMBER() OVER (
                PARTITION BY user_id, {local_date}
                ORDER BY COALESCE(capture_started_at, created_at), id
            ) - 1 AS turn_index
        FROM capture_recordings
        WHERE TRIM(COALESCE(asr_text, '')) <> ''
    """
    ranked_session_uuid = _stable_uuid(
        "CONCAT('theme-v2-flash:', ranked.user_id, ':', ranked.local_date)"
    )
    ranked_turn_uuid = _stable_uuid(
        "CONCAT('theme-v2-input-turn:', ranked.id)"
    )
    op.execute(
        sa.text(
            f"""
            INSERT IGNORE INTO input_turns (
                id, user_id, session_id, turn_index, file_id, recording_id,
                source_file_offset_ms, text, segments_json, source,
                asr_provider, language, provenance_json, created_at, updated_at
            )
            SELECT
                {ranked_turn_uuid},
                ranked.user_id,
                {ranked_session_uuid},
                ranked.turn_index,
                ranked.file_id,
                ranked.id,
                NULL,
                ranked.asr_text,
                COALESCE(ranked.asr_segments_json, JSON_ARRAY()),
                'voice',
                ranked.asr_provider,
                NULL,
                JSON_OBJECT(
                    'kind', 'hardware_audio',
                    'recording_id', ranked.id,
                    'card_sn', ranked.card_sn,
                    'device_file_name', ranked.device_file_name,
                    'capture_source', ranked.source
                ),
                ranked.created_at,
                ranked.updated_at
            FROM ({ranked_capture_rows}) AS ranked
            """
        )
    )

    user_message_uuid = _stable_uuid("CONCAT('theme-v2-user-message:', id)")
    agent_message_uuid = _stable_uuid("CONCAT('theme-v2-agent-message:', id)")
    recording_session_uuid = _stable_uuid(
        f"CONCAT('theme-v2-flash:', user_id, ':', {local_date})"
    )
    op.execute(
        sa.text(
            f"""
            INSERT IGNORE INTO session_messages (
                id, session_id, user_id, role, status, text, input_turn_id,
                tool_call_json, tool_result_json, cards_json, elapsed_ms,
                token_count, created_at, updated_at
            )
            SELECT
                {user_message_uuid},
                {recording_session_uuid},
                user_id,
                'user',
                'done',
                asr_text,
                {turn_uuid},
                NULL,
                NULL,
                JSON_ARRAY(),
                NULL,
                NULL,
                created_at,
                updated_at
            FROM capture_recordings
            WHERE TRIM(COALESCE(asr_text, '')) <> ''
            """
        )
    )
    op.execute(
        sa.text(
            f"""
            INSERT IGNORE INTO session_messages (
                id, session_id, user_id, role, status, text, input_turn_id,
                tool_call_json, tool_result_json, cards_json, elapsed_ms,
                token_count, created_at, updated_at
            )
            SELECT
                {agent_message_uuid},
                {recording_session_uuid},
                user_id,
                'agent',
                CASE
                    WHEN process_status = 'done' THEN 'done'
                    WHEN process_status = 'failed' THEN 'failed'
                    ELSE 'running'
                END,
                CASE
                    WHEN process_status = 'done' THEN COALESCE(result_summary, '')
                    WHEN process_status = 'failed' THEN COALESCE(error_message, '')
                    ELSE ''
                END,
                {turn_uuid},
                NULL,
                NULL,
                COALESCE(result_records_json, JSON_ARRAY()),
                NULL,
                NULL,
                created_at,
                updated_at
            FROM capture_recordings
            WHERE TRIM(COALESCE(asr_text, '')) <> ''
            """
        )
    )
    op.execute(
        sa.text(
            f"""
            UPDATE capture_recordings
            SET
                session_id = {recording_session_uuid},
                input_turn_id = {turn_uuid},
                agent_message_id = {agent_message_uuid}
            WHERE TRIM(COALESCE(asr_text, '')) <> ''
              AND session_id IS NULL
            """
        )
    )

    # Repair any early Theme V2 capture provenance that stored the compatibility
    # CaptureTurn ID, then clear only dangling values before adding the FK.
    op.execute(
        sa.text(
            """
            UPDATE assets AS asset
            JOIN capture_turns AS capture_turn
              ON capture_turn.id = asset.source_input_turn_id
            JOIN capture_recordings AS recording
              ON recording.id = capture_turn.recording_id
            SET asset.source_input_turn_id = recording.input_turn_id
            WHERE recording.input_turn_id IS NOT NULL
            """
        )
    )
    op.execute(
        sa.text(
            """
            UPDATE assets AS asset
            LEFT JOIN input_turns AS input_turn
              ON input_turn.id = asset.source_input_turn_id
            SET asset.source_input_turn_id = NULL
            WHERE asset.source_input_turn_id IS NOT NULL
              AND input_turn.id IS NULL
            """
        )
    )
    op.create_foreign_key(
        "fk_assets_source_input_turn",
        "assets",
        "input_turns",
        ["source_input_turn_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_assets_user_source_input_turn",
        "assets",
        ["user_id", "source_input_turn_id"],
    )

    # Custom capture schemas are best-effort. Baseline skills retain explicit
    # invariants; custom type metadata remains available for manual editing.
    op.execute(
        sa.text(
            """
            UPDATE user_skills
            SET schema_json = JSON_SET(schema_json, '$.required', JSON_ARRAY())
            WHERE machine_name NOT IN ('todo', 'expense', 'contact', 'notes')
              AND JSON_TYPE(schema_json) = 'OBJECT'
            """
        )
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_assets_source_input_turn",
        "assets",
        type_="foreignkey",
    )
    op.drop_index(
        "ix_assets_user_source_input_turn",
        table_name="assets",
    )
    op.drop_constraint(
        "fk_capture_recordings_agent_message",
        "capture_recordings",
        type_="foreignkey",
    )
    op.drop_constraint(
        "fk_capture_recordings_input_turn",
        "capture_recordings",
        type_="foreignkey",
    )
    op.drop_constraint(
        "fk_capture_recordings_session",
        "capture_recordings",
        type_="foreignkey",
    )
    op.drop_index(
        "ix_capture_recordings_input_turn",
        table_name="capture_recordings",
    )
    op.drop_index(
        "ix_capture_recordings_user_session",
        table_name="capture_recordings",
    )
    op.drop_column("capture_recordings", "agent_message_id")
    op.drop_column("capture_recordings", "input_turn_id")
    op.drop_column("capture_recordings", "session_id")
    op.drop_constraint(
        "fk_session_messages_input_turn",
        "session_messages",
        type_="foreignkey",
    )
    op.drop_table("input_turns")
    op.drop_constraint(
        "uq_chat_sessions_user_type_date",
        "chat_sessions",
        type_="unique",
    )
    op.drop_column("chat_sessions", "revision")
    op.drop_column("chat_sessions", "session_date")
