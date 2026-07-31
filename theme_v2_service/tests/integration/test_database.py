from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app.db.session import AsyncSessionFactory
from app.main import app


async def test_theme_v2_test_mysql_connection():
    async with AsyncSessionFactory() as session:
        database = (await session.execute(text("SELECT DATABASE()"))).scalar_one()

    assert database == "eureka_theme_v2_test"


async def test_readiness_checks_database_connection():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as client:
        response = await client.get("/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ready"}
