import pytest_asyncio
from sqlalchemy import text

from app.auth import models as auth_models  # noqa: F401
from app.db import models as domain_models  # noqa: F401
from app.db.base import Base
from app.db.session import AsyncSessionFactory, engine
from app.domains.capture import models as capture_models  # noqa: F401
from app.domains.devices import models as device_models  # noqa: F401
from app.domains.notifications import models as notification_models  # noqa: F401
from app.domains.reports import models as report_models  # noqa: F401
from app.domains.reka import models as reka_models  # noqa: F401
from app.domains.sessions import models as session_models  # noqa: F401
from app.domains.triggers import models as trigger_models  # noqa: F401


async def _assert_test_database(connection) -> None:
    database = (await connection.execute(text("SELECT DATABASE()"))).scalar_one()
    assert database == "eureka_theme_v2_test"


@pytest_asyncio.fixture
async def session():
    async with engine.begin() as connection:
        await _assert_test_database(connection)
        # deletion_cleanup_items is migration-managed (no ORM model); drop it
        # first so create_all below starts from a clean state each time.
        await connection.execute(
            text("DROP TABLE IF EXISTS deletion_cleanup_items")
        )
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)
        # Recreate deletion_cleanup_items so account-deletion tests can use it.
        await connection.execute(text(
            "CREATE TABLE IF NOT EXISTS deletion_cleanup_items ("
            "id CHAR(36) PRIMARY KEY, "
            "user_id CHAR(36) NOT NULL, "
            "storage_key VARCHAR(1024) NOT NULL, "
            "source VARCHAR(32) NOT NULL, "
            "status VARCHAR(16) NOT NULL DEFAULT 'pending', "
            "attempts INT NOT NULL DEFAULT 0, "
            "created_at DATETIME(6) NOT NULL, "
            "updated_at DATETIME(6) NULL, "
            "INDEX ix_deletion_cleanup_items_status (status))"
        ))

    try:
        async with AsyncSessionFactory() as database_session:
            yield database_session
            await database_session.rollback()
    finally:
        async with engine.begin() as connection:
            await connection.execute(text("SET FOREIGN_KEY_CHECKS=0"))
            try:
                for table in reversed(Base.metadata.sorted_tables):
                    await connection.execute(table.delete())
            finally:
                await connection.execute(text("SET FOREIGN_KEY_CHECKS=1"))
