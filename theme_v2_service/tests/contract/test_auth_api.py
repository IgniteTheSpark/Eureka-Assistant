import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.auth.security import create_token
from app.db.models import UserSkill
from app.db.session import AsyncSessionFactory
from app.domains.assets.service import BASELINE_CAPTURE_SKILLS
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str = "person@example.com"):
    return await client.post(
        "/api/auth/register",
        json={"email": email, "password": "secret1"},
    )


async def test_register_normalizes_email_and_returns_token(client):
    response = await _register(client, "  Person@Example.COM ")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["token"]
    assert body["user"]["email"] == "person@example.com"
    assert body["user"]["id"]
    async with AsyncSessionFactory() as database:
        skills = list(
            await database.scalars(
                select(UserSkill).where(UserSkill.user_id == body["user"]["id"])
            )
        )
    assert {skill.machine_name for skill in skills} == {
        item["machine_name"] for item in BASELINE_CAPTURE_SKILLS
    }


async def test_duplicate_register_returns_conflict(client):
    assert (await _register(client)).status_code == 200

    response = await _register(client)

    assert response.status_code == 409


@pytest.mark.parametrize(
    ("email", "password", "expected_detail"),
    [
        ("invalid", "secret1", "邮箱格式不正确"),
        ("person@example.com", "12345", "密码至少 6 位"),
    ],
)
async def test_register_validates_credentials(
    client,
    email,
    password,
    expected_detail,
):
    response = await client.post(
        "/api/auth/register",
        json={"email": email, "password": password},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == expected_detail


async def test_login_and_me_round_trip(client):
    registered = await _register(client)
    user_id = registered.json()["user"]["id"]

    login = await client.post(
        "/api/auth/login",
        json={"email": "PERSON@example.com", "password": "secret1"},
    )
    assert login.status_code == 200
    assert login.json()["user"] == {
        "id": user_id,
        "email": "person@example.com",
    }

    me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {login.json()['token']}"},
    )
    assert me.status_code == 200
    assert me.json()["user"]["id"] == user_id


async def test_login_rejects_invalid_credentials(client):
    await _register(client)

    response = await client.post(
        "/api/auth/login",
        json={"email": "person@example.com", "password": "wrong-password"},
    )

    assert response.status_code == 401


async def test_me_requires_valid_existing_user(client):
    unauthorized = await client.get("/api/auth/me")
    missing_user = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {create_token('missing-user')}"},
    )

    assert unauthorized.status_code == 401
    assert missing_user.status_code == 404
