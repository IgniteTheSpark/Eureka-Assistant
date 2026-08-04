from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.dialects import mysql

from app.config import get_settings
from app.db.base import Base
from app.db import models as domain_models  # noqa: F401
from app.auth import models as auth_models  # noqa: F401
from app.domains.capture import models as capture_models  # noqa: F401
from app.domains.devices import models as device_models  # noqa: F401


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
    }.issubset(set(inspector.get_table_names()))

    asset_columns = {column["name"]: column for column in inspector.get_columns("assets")}
    assert asset_columns["id"]["type"].length == 36
    assert isinstance(asset_columns["payload_json"]["type"], mysql.JSON)
    assert asset_columns["created_at"]["type"].fsp == 6
    assert asset_columns["source_report_id"]["type"].length == 36
    assert asset_columns["source_report_action_id"]["type"].length == 64

    asset_indexes = {index["name"]: index for index in inspector.get_indexes("assets")}
    assert asset_indexes["ix_assets_user_source_report"]["column_names"] == [
        "user_id",
        "source_report_id",
    ]
    assert asset_indexes["uq_assets_user_report_action"]["unique"] is True

    asset_foreign_keys = inspector.get_foreign_keys("assets")
    assert any(
        key["referred_table"] == "reports"
        and key["constrained_columns"] == ["source_report_id"]
        for key in asset_foreign_keys
    )

    skill_columns = {
        column["name"]: column
        for column in inspector.get_columns("user_skills")
    }
    assert isinstance(skill_columns["render_spec_json"]["type"], mysql.JSON)
    assert isinstance(skill_columns["chat_starters_json"]["type"], mysql.JSON)

    with engine.connect() as connection:
        revision = connection.scalar(text("SELECT version_num FROM alembic_version"))
    assert revision == "0011_report_actions"
    engine.dispose()
