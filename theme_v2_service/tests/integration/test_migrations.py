from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.dialects import mysql

from app.config import get_settings
from app.db.base import Base
from app.db import models as domain_models  # noqa: F401
from app.auth import models as auth_models  # noqa: F401


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
        "notifications",
        "outbox_events",
        "trigger_trackers",
        "trigger_counted_assets",
        "trigger_executions",
        "report_generation_runs",
        "reports",
        "files",
        "workflow_jobs",
    }.issubset(set(inspector.get_table_names()))

    asset_columns = {column["name"]: column for column in inspector.get_columns("assets")}
    assert asset_columns["id"]["type"].length == 36
    assert isinstance(asset_columns["payload_json"]["type"], mysql.JSON)
    assert asset_columns["created_at"]["type"].fsp == 6

    with engine.connect() as connection:
        revision = connection.scalar(text("SELECT version_num FROM alembic_version"))
    assert revision == "0005_report_share"
    engine.dispose()
