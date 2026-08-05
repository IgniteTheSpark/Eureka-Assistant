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
    }.issubset(set(inspector.get_table_names()))

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

    contact_columns = {
        column["name"]: column for column in inspector.get_columns("contacts")
    }
    assert isinstance(contact_columns["notes_json"]["type"], mysql.JSON)
    assert isinstance(contact_columns["socials_json"]["type"], mysql.JSON)

    attendee_foreign_keys = inspector.get_foreign_keys("event_attendees")
    assert any(
        key["referred_table"] == "contacts"
        and key["constrained_columns"] == ["contact_id"]
        for key in attendee_foreign_keys
    )

    with engine.connect() as connection:
        revision = connection.scalar(text("SELECT version_num FROM alembic_version"))
    assert revision == "0015_internal_mcp_domain"
    engine.dispose()


def test_internal_mcp_migration_backfills_existing_domain_data():
    engine = create_engine(_sync_url(get_settings().database_url))
    Base.metadata.drop_all(bind=engine)
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE IF EXISTS alembic_version"))

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
    assert revision == "0015_internal_mcp_domain"
    engine.dispose()
