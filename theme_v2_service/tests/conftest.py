import pytest_asyncio
from sqlalchemy import text

from app.auth import models as auth_models  # noqa: F401
from app.db.base import Base
from app.db.session import AsyncSessionFactory, engine


async def _assert_test_database(connection) -> None:
    database = (await connection.execute(text("SELECT DATABASE()"))).scalar_one()
    assert database == "eureka_theme_v2_test"


@pytest_asyncio.fixture
async def session():
    async with engine.begin() as connection:
        await _assert_test_database(connection)
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)

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
