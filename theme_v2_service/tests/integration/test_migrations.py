import json

from alembic import command
from alembic.config import Config
from sqlalchemy import Integer, create_engine, inspect, text
from sqlalchemy.dialects import mysql

from app.config import get_settings
from app.db.base import Base
from app.db import models as domain_models  # noqa: F401
from app.auth import models as auth_models  # noqa: F401
from app.domains.capture import models as capture_models  # noqa: F401
from app.domains.devices import models as device_models  # noqa: F401
from app.domains.sessions import models as session_models  # noqa: F401
from app.domains.reka import models as reka_models  # noqa: F401


def _sync_url(url: str) -> str:
    scheme, rest = url.split("://", 1)
    return f"{scheme.split('+', 1)[0]}+pymysql://{rest}"


def test_foundation_migration_round_trip_and_physical_types():
    engine = create_engine(_sync_url(get_settings().database_url))
    with engine.connect() as connection:
        assert connection.scalar(text("SELECT DATABASE()")) == "eureka_theme_v2_test"

    Base.metadata.drop_all(bind=engine)
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
        connection.execute(text("DROP TABLE IF EXISTS onboarding_asset_results"))
        connection.execute(text("DROP TABLE IF EXISTS deletion_cleanup_items"))

    config = Config("alembic.ini")
    command.upgrade(config, "head")
    command.downgrade(config, "base")
    command.upgrade(config, "head")

    inspector = inspect(engine)
    assert {
        "user_accounts",
        "user_skills",
        "assets",
        "events",
        "event_attendees",
        "notifications",
        "outbox_events",
        "trigger_trackers",
        "trigger_counted_assets",
        "trigger_executions",
        "report_generation_runs",
        "reports",
        "files",
        "workflow_jobs",
        "cards",
        "card_bindings",
        "capture_files",
        "capture_recordings",
        "capture_turns",
        "flash_chat_messages",
        "chat_sessions",
        "session_messages",
        "input_turns",
        "global_skills",
        "asset_fields",
        "contacts",
        "agent_tool_executions",
        "agent_pending_actions",
        "nudges",
        "rhythm_profiles",
    }.issubset(set(inspector.get_table_names()))
    assert "deletion_cleanup_items" not in inspector.get_table_names()

    asset_columns = {column["name"]: column for column in inspector.get_columns("assets")}
    assert asset_columns["id"]["type"].length == 36
    assert isinstance(asset_columns["payload_json"]["type"], mysql.JSON)
    assert asset_columns["created_at"]["type"].fsp == 6
    assert asset_columns["source_report_id"]["type"].length == 36
    assert asset_columns["source_report_action_id"]["type"].length == 64
    assert asset_columns["period"]["type"].length == 8
    assert asset_columns["occurred_at"]["type"].fsp == 6
    assert asset_columns["session_id"]["type"].length == 36
    assert asset_columns["source_input_turn_id"]["type"].length == 36
    assert asset_columns["domain"]["type"].length == 100
    assert asset_columns["migrated_contact_id"]["type"].length == 36

    asset_indexes = {index["name"]: index for index in inspector.get_indexes("assets")}
    assert asset_indexes["ix_assets_user_source_report"]["column_names"] == [
        "user_id",
        "source_report_id",
    ]
    assert asset_indexes["uq_assets_user_report_action"]["unique"] is True
    assert asset_indexes["ix_assets_user_source_input_turn"]["column_names"] == [
        "user_id",
        "source_input_turn_id",
    ]

    asset_foreign_keys = inspector.get_foreign_keys("assets")
    assert any(
        key["referred_table"] == "reports"
        and key["constrained_columns"] == ["source_report_id"]
        for key in asset_foreign_keys
    )
    assert any(
        key["referred_table"] == "input_turns"
        and key["constrained_columns"] == ["source_input_turn_id"]
        for key in asset_foreign_keys
    )

    skill_columns = {
        column["name"]: column
        for column in inspector.get_columns("user_skills")
    }
    assert isinstance(skill_columns["render_spec_json"]["type"], mysql.JSON)
    assert isinstance(skill_columns["chat_starters_json"]["type"], mysql.JSON)
    assert isinstance(skill_columns["queryable_fields_json"]["type"], mysql.JSON)
    assert isinstance(skill_columns["global_skill_id"]["type"], Integer)

    report_run_columns = {
        column["name"]: column
        for column in inspector.get_columns("report_generation_runs")
    }
    assert report_run_columns["scope_adapter"]["type"].length == 32
    assert isinstance(report_run_columns["scope_draft"]["type"], mysql.JSON)
    assert isinstance(report_run_columns["scope_revision"]["type"], Integer)
    assert report_run_columns["scope_hash"]["type"].length == 64
    assert report_run_columns["plan_scope_hash"]["type"].length == 64

    report_columns = {
        column["name"]: column for column in inspector.get_columns("reports")
    }
    assert report_columns["illustration_status"]["type"].length == 24
    assert report_columns["illustration_job_id"]["type"].length == 36
    assert isinstance(report_columns["revision"]["type"], Integer)
    assert report_columns["updated_at"]["type"].fsp == 6

    contact_columns = {
        column["name"]: column for column in inspector.get_columns("contacts")
    }
    assert isinstance(contact_columns["notes_json"]["type"], mysql.JSON)
    assert isinstance(contact_columns["socials_json"]["type"], mysql.JSON)

    message_columns = {
        column["name"]: column
        for column in inspector.get_columns("session_messages")
    }
    assert message_columns["status"]["type"].length == 24

    pending_columns = {
        column["name"]: column
        for column in inspector.get_columns("agent_pending_actions")
    }
    assert isinstance(pending_columns["candidates_json"]["type"], mysql.JSON)
    assert isinstance(pending_columns["intent_json"]["type"], mysql.JSON)

    tool_execution_columns = {
        column["name"]: column
        for column in inspector.get_columns("agent_tool_executions")
    }
    assert tool_execution_columns["root_mutation_key"]["type"].length == 255
    tool_execution_indexes = {
        index["name"]: index
        for index in inspector.get_indexes("agent_tool_executions")
    }
    assert tool_execution_indexes[
        "uq_agent_tool_executions_user_root_mutation"
    ]["unique"] is True

    legacy_flash_columns = {
        column["name"]: column
        for column in inspector.get_columns("flash_chat_messages")
    }
    assert legacy_flash_columns["migrated_session_message_id"]["type"].length == 36

    attendee_foreign_keys = inspector.get_foreign_keys("event_attendees")
    assert any(
        key["referred_table"] == "contacts"
        and key["constrained_columns"] == ["contact_id"]
        for key in attendee_foreign_keys
    )

    with engine.connect() as connection:
        revision = connection.scalar(text("SELECT version_num FROM alembic_version"))
    nudge_columns = {
        column["name"]: column for column in inspector.get_columns("nudges")
    }
    assert nudge_columns["natural_key"]["type"].length == 255
    assert nudge_columns["dismissed_at"]["type"].fsp == 6

    rhythm_columns = {
        column["name"]: column
        for column in inspector.get_columns("rhythm_profiles")
    }
    assert isinstance(rhythm_columns["patterns_json"]["type"], mysql.JSON)
    assert rhythm_columns["timezone_name"]["type"].length == 64

    onboarding_marker_columns = {
        column["name"]: column
        for column in inspector.get_columns("onboarding_asset_results")
    }
    assert onboarding_marker_columns["request_fingerprint"]["type"].length == 64
    assert onboarding_marker_columns["request_fingerprint"]["nullable"] is True

    assert revision == "0032_onboarding_request_fp"
    assert not inspector.has_table("deletion_cleanup_items")
    assert inspector.has_table("email_rate_limit_buckets")
    engine.dispose()


def test_internal_mcp_migration_backfills_existing_domain_data():
    engine = create_engine(_sync_url(get_settings().database_url))
    Base.metadata.drop_all(bind=engine)
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
        connection.execute(text("DROP TABLE IF EXISTS onboarding_asset_results"))
        connection.execute(text("DROP TABLE IF EXISTS deletion_cleanup_items"))

    config = Config("alembic.ini")
    command.upgrade(config, "0014_agent_session_foundation")
    timestamp = "2026-08-05 08:00:00.000000"
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                INSERT INTO user_skills (
                    id, user_id, machine_name, display_name, description, domain,
                    schema_json, render_spec_json, chat_starters_json,
                    created_at, updated_at
                ) VALUES (
                    :id, :user_id, :machine_name, :display_name, NULL, :domain,
                    :schema_json, '{}', '[]', :created_at, :updated_at
                )
                """
            ),
            [
                {
                    "id": "skill-todo",
                    "user_id": "owner",
                    "machine_name": "todo",
                    "display_name": "待办",
                    "domain": "生活",
                    "schema_json": json.dumps(
                        {"type": "object", "properties": {"title": {"type": "string"}}}
                    ),
                    "created_at": timestamp,
                    "updated_at": timestamp,
                },
                {
                    "id": "skill-running",
                    "user_id": "owner",
                    "machine_name": "running_training",
                    "display_name": "跑步训练",
                    "domain": "运动",
                    "schema_json": json.dumps(
                        {
                            "type": "object",
                            "properties": {
                                "distance": {"type": "number"},
                                "run_date": {"type": "string", "format": "date"},
                            },
                            "required": ["distance", "run_date"],
                        }
                    ),
                    "created_at": timestamp,
                    "updated_at": timestamp,
                },
            ],
        )
        connection.execute(
            text(
                """
                INSERT INTO assets (
                    id, user_id, user_skill_id, payload_json, effective_at,
                    period, occurred_at, session_id, source_input_turn_id,
                    source_report_id, source_report_action_id, created_at, updated_at
                ) VALUES (
                    'asset-running', 'owner', 'skill-running', :payload, NULL,
                    NULL, NULL, NULL, NULL, NULL, NULL, :created_at, :updated_at
                )
                """
            ),
            {
                "payload": json.dumps(
                    {"distance": 5.25, "run_date": "2026-08-05"}
                ),
                "created_at": timestamp,
                "updated_at": timestamp,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO events (
                    id, user_id, title, description, location, start_at, end_at,
                    all_day, status, created_at, updated_at
                ) VALUES (
                    'event-existing', 'owner', '项目会', NULL, NULL,
                    :start_at, :end_at, 0, 'scheduled', :created_at, :updated_at
                )
                """
            ),
            {
                "start_at": "2026-08-06 07:00:00.000000",
                "end_at": "2026-08-06 08:00:00.000000",
                "created_at": timestamp,
                "updated_at": timestamp,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO event_attendees (
                    id, event_id, contact_id, name_raw, role, created_at, updated_at
                ) VALUES (
                    'attendee-existing', 'event-existing', 'legacy-contact-asset',
                    '冯总', 'attendee', :created_at, :updated_at
                )
                """
            ),
            {"created_at": timestamp, "updated_at": timestamp},
        )

    command.upgrade(config, "head")
    # An already-upgraded runtime must remain a no-op.
    command.upgrade(config, "head")

    with engine.connect() as connection:
        todo_link = connection.execute(
            text(
                """
                SELECT global_skill.machine_name
                FROM user_skills AS user_skill
                JOIN global_skills AS global_skill
                  ON global_skill.id = user_skill.global_skill_id
                WHERE user_skill.id = 'skill-todo'
                """
            )
        ).scalar_one()
        queryable = connection.execute(
            text(
                "SELECT queryable_fields_json FROM user_skills "
                "WHERE id='skill-running'"
            )
        ).scalar_one()
        field_rows = connection.execute(
            text(
                """
                SELECT field_name, value_number, value_date
                FROM asset_fields
                WHERE asset_id='asset-running'
                ORDER BY field_name
                """
            )
        ).mappings().all()
        attendee = connection.execute(
            text(
                """
                SELECT contact_id, legacy_contact_asset_id
                FROM event_attendees WHERE id='attendee-existing'
                """
            )
        ).mappings().one()

    assert todo_link == "todo"
    assert json.loads(queryable) == ["distance", "run_date"]
    assert [row["field_name"] for row in field_rows] == ["distance", "run_date"]
    assert float(field_rows[0]["value_number"]) == 5.25
    assert str(field_rows[1]["value_date"]).startswith("2026-08-05")
    assert attendee["contact_id"] is None
    assert attendee["legacy_contact_asset_id"] == "legacy-contact-asset"

    command.downgrade(config, "0014_agent_session_foundation")
    with engine.connect() as connection:
        restored_contact_id = connection.execute(
            text(
                "SELECT contact_id FROM event_attendees "
                "WHERE id='attendee-existing'"
            )
        ).scalar_one()
    assert restored_contact_id == "legacy-contact-asset"
    command.upgrade(config, "head")
    with engine.connect() as connection:
        revision = connection.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar_one()
    assert revision == "0031_challenge_indexes"
    engine.dispose()


def test_legacy_agent_data_backfill_preserves_same_name_contacts_and_chat():
    engine = create_engine(_sync_url(get_settings().database_url))
    Base.metadata.drop_all(bind=engine)
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE IF EXISTS alembic_version"))
        connection.execute(text("DROP TABLE IF EXISTS onboarding_asset_results"))

    config = Config("alembic.ini")
    command.upgrade(config, "0016_agent_pending_actions")
    timestamp = "2026-08-06 01:00:00.000000"
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                INSERT INTO user_skills (
                    id, user_id, machine_name, display_name, description, domain,
                    schema_json, render_spec_json, chat_starters_json,
                    global_skill_id, queryable_fields_json, position, enabled,
                    created_at, updated_at
                ) VALUES (
                    'skill-contact', 'owner', 'contact', '联系人', NULL, 'people',
                    :schema, '{}', '[]',
                    (SELECT id FROM global_skills WHERE machine_name='contact'),
                    '["name"]', 0, 1, :created_at, :updated_at
                )
                """
            ),
            {
                "schema": json.dumps(
                    {"type": "object", "properties": {"name": {"type": "string"}}}
                ),
                "created_at": timestamp,
                "updated_at": timestamp,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO chat_sessions (
                    id, user_id, session_type, session_date, revision, title,
                    subject_type, subject_id, context_asset_ids_json,
                    created_at, updated_at
                ) VALUES (
                    'flash-session', 'owner', 'flash', '2026-08-06', 0,
                    '8月6日 闪念', NULL, NULL, '[]', :created_at, :updated_at
                )
                """
            ),
            {"created_at": timestamp, "updated_at": timestamp},
        )
        connection.execute(
            text(
                """
                INSERT INTO assets (
                    id, user_id, user_skill_id, payload_json, domain,
                    effective_at, period, occurred_at, session_id,
                    source_input_turn_id, source_report_id,
                    source_report_action_id, created_at, updated_at
                ) VALUES
                    ('asset-alex-acme', 'owner', 'skill-contact', :acme, 'people',
                     NULL, NULL, NULL, 'flash-session', NULL, NULL, NULL,
                     :created_at, :updated_at),
                    ('asset-alex-byte', 'owner', 'skill-contact', :byte, 'people',
                     NULL, NULL, NULL, 'flash-session', NULL, NULL, NULL,
                     :created_at, :updated_at),
                    ('asset-invalid-contact', 'owner', 'skill-contact', :invalid, 'people',
                     NULL, NULL, NULL, NULL, NULL, NULL, NULL,
                     :created_at, :updated_at)
                """
            ),
            {
                "acme": json.dumps(
                    {
                        "name": "Alex",
                        "company": "Acme",
                        "title": "设计师",
                        "notes": "第一次见面",
                        "socials": {"linkedin": "alex-acme"},
                    },
                    ensure_ascii=False,
                ),
                "byte": json.dumps(
                    {"name": "Alex", "company": "字节", "phone": "10086"},
                    ensure_ascii=False,
                ),
                "invalid": json.dumps({"company": "无姓名公司"}, ensure_ascii=False),
                "created_at": timestamp,
                "updated_at": timestamp,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO events (
                    id, user_id, title, description, location, start_at, end_at,
                    all_day, status, recurrence_rule, sync_source,
                    sync_external_id, source_input_turn_id, created_at, updated_at
                ) VALUES (
                    'event-1', 'owner', '产品会', NULL, NULL,
                    '2026-08-06 02:00:00', '2026-08-06 03:00:00',
                    0, 'scheduled', NULL, NULL, NULL, NULL,
                    :created_at, :updated_at
                )
                """
            ),
            {"created_at": timestamp, "updated_at": timestamp},
        )
        connection.execute(
            text(
                """
                INSERT INTO event_attendees (
                    id, event_id, contact_id, legacy_contact_asset_id,
                    name_raw, role, created_at, updated_at
                ) VALUES (
                    'attendee-1', 'event-1', NULL, 'asset-alex-acme',
                    'Alex', 'attendee', :created_at, :updated_at
                )
                """
            ),
            {"created_at": timestamp, "updated_at": timestamp},
        )
        connection.execute(
            text(
                """
                INSERT INTO session_messages (
                    id, session_id, user_id, role, status, text, input_turn_id,
                    tool_call_json, tool_result_json, cards_json, elapsed_ms,
                    token_count, created_at, updated_at
                ) VALUES (
                    'legacy-card-message', 'flash-session', 'owner', 'agent',
                    'done', '已保存联系人', NULL, NULL, NULL, :cards,
                    NULL, NULL, :created_at, :updated_at
                )
                """
            ),
            {
                "cards": json.dumps(
                    [
                        {
                            "kind": "asset",
                            "card_type": "contact",
                            "asset_id": "asset-alex-acme",
                            "user_skill_name": "contact",
                            "title": "Alex",
                        }
                    ],
                    ensure_ascii=False,
                ),
                "created_at": timestamp,
                "updated_at": timestamp,
            },
        )
        connection.execute(
            text(
                """
                INSERT INTO flash_chat_messages (
                    id, user_id, session_date, role, text, status, created_at
                ) VALUES
                    ('legacy-chat-user', 'owner', '2026-08-06', 'user',
                     'Alex 在哪家公司？', 'done', '2026-08-06 01:10:00'),
                    ('legacy-chat-agent', 'owner', '2026-08-06', 'agent',
                     '目前有两位 Alex。', 'done', '2026-08-06 01:10:01')
                """
            )
        )

    command.upgrade(config, "head")
    command.upgrade(config, "head")

    with engine.connect() as connection:
        contacts = connection.execute(
            text(
                """
                SELECT id, name, company, title, phone, notes_json, socials_json
                FROM contacts WHERE user_id='owner' ORDER BY company
                """
            )
        ).mappings().all()
        mappings = connection.execute(
            text(
                """
                SELECT id, migrated_contact_id FROM assets
                WHERE id IN (
                    'asset-alex-acme', 'asset-alex-byte', 'asset-invalid-contact'
                ) ORDER BY id
                """
            )
        ).mappings().all()
        attendee_contact_id = connection.scalar(
            text("SELECT contact_id FROM event_attendees WHERE id='attendee-1'")
        )
        cards = connection.scalar(
            text("SELECT cards_json FROM session_messages WHERE id='legacy-card-message'")
        )
        migrated_chat = connection.execute(
            text(
                """
                SELECT legacy.id, legacy.migrated_session_message_id,
                       message.role, message.text, message.input_turn_id
                FROM flash_chat_messages AS legacy
                JOIN session_messages AS message
                  ON message.id=legacy.migrated_session_message_id
                ORDER BY legacy.created_at
                """
            )
        ).mappings().all()
        typed_turn_count = connection.scalar(
            text(
                """
                SELECT COUNT(*) FROM input_turns
                WHERE session_id='flash-session' AND source='typed'
                """
            )
        )

    assert len(contacts) == 2
    assert [row["name"] for row in contacts] == ["Alex", "Alex"]
    assert {row["company"] for row in contacts} == {"Acme", "字节"}
    acme = next(row for row in contacts if row["company"] == "Acme")
    assert acme["title"] == "设计师"
    assert json.loads(acme["notes_json"]) == ["第一次见面"]
    assert json.loads(acme["socials_json"]) == {"linkedin": "alex-acme"}
    mapping_by_asset = {row["id"]: row["migrated_contact_id"] for row in mappings}
    assert mapping_by_asset["asset-alex-acme"] == acme["id"]
    assert mapping_by_asset["asset-alex-byte"] not in {None, acme["id"]}
    assert mapping_by_asset["asset-invalid-contact"] is None
    assert attendee_contact_id == acme["id"]
    card = json.loads(cards)[0]
    assert card["kind"] == "contact"
    assert card["card_type"] == "contact"
    assert card["contact_id"] == acme["id"]
    assert card["legacy_asset_id"] == "asset-alex-acme"
    assert "asset_id" not in card
    assert [(row["role"], row["text"]) for row in migrated_chat] == [
        ("user", "Alex 在哪家公司？"),
        ("agent", "目前有两位 Alex。"),
    ]
    assert migrated_chat[0]["input_turn_id"] is not None
    assert migrated_chat[1]["input_turn_id"] == migrated_chat[0]["input_turn_id"]
    assert typed_turn_count == 1
    engine.dispose()
