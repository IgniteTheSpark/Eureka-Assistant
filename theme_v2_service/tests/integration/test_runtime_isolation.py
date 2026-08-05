from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.config import get_settings
from app.db.session import AsyncSessionFactory
from app.main import app


async def test_runtime_uses_only_theme_v2_database_and_migration():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as client:
        health = await client.get("/health")
        ready = await client.get("/ready")

    settings = get_settings()
    expected_database = (
        "eureka_theme_v2_test" if settings.env == "test" else "eureka_theme_v2"
    )
    async with AsyncSessionFactory() as session:
        database = (await session.execute(text("SELECT DATABASE()"))).scalar_one()
        revision = (
            await session.execute(text("SELECT version_num FROM alembic_version"))
        ).scalar_one()

    assert health.json() == {"status": "ok", "service": "theme-v2"}
    assert ready.json() == {"status": "ready"}
    assert database == expected_database
    assert revision == "0014_agent_session_foundation"
