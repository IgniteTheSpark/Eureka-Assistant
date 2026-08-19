"""Account export + deletion contract tests (§9 / §10)."""
import json

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text

from app.auth.models import UserAccount
from app.db.models import Asset, UserSkill
from app.db.session import AsyncSessionFactory
from app.main import app
from tests.fakes.auth_helpers import register_user


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _user_with_asset(
    client, email: str
) -> tuple[str, str]:
    registered = await register_user(client, email)
    token = registered["token"]
    user_id = registered["user"]["id"]

    response = await client.post(
        "/api/onboarding/skills",
        headers=_headers(token),
        json={
            "category": "running",
            "fields": [
                {"key": "distance_km", "label": "距离(公里)", "type": "number"},
                {"key": "duration_min", "label": "时长(分钟)", "type": "duration"},
            ],
        },
    )
    skill_id = response.json()["skill"]["id"]
    await client.post(
        "/api/onboarding/confirm",
        headers=_headers(token),
        json={
            "skill_id": skill_id,
            "payload": {"distance_km": 5, "duration_min": 32},
            "idempotency_key": f"exp-{email}",
        },
    )
    return token, user_id


async def test_export_options_lists_types_with_counts(client):
    token, _ = await _user_with_asset(client, "expopt@example.com")

    response = await client.get(
        "/api/account/export-options", headers=_headers(token)
    )
    assert response.status_code == 200
    options = response.json()["options"]
    assert any(
        o["type"].startswith("skill:") and o["count"] == 1 for o in options
    )


async def test_export_options_requires_auth(client):
    response = await client.get("/api/account/export-options")
    assert response.status_code == 401


async def test_export_accepts_stable_skill_token(client):
    token, _ = await _user_with_asset(client, "expskill@example.com")
    options = (
        await client.get("/api/account/export-options", headers=_headers(token))
    ).json()["options"]
    skill_token = next(option["type"] for option in options if option["type"].startswith("skill:"))

    response = await client.post(
        "/api/account/export",
        headers=_headers(token),
        json={"types": [skill_token], "format": "md"},
    )

    assert response.status_code == 200
    assert "记录" in response.text


async def test_export_markdown(client):
    token, _ = await _user_with_asset(client, "expmd@example.com")

    response = await client.post(
        "/api/account/export",
        headers=_headers(token),
        json={"format": "md", "types": []},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/markdown")
    assert "UReka 数据导出" in response.text
    assert "记录" in response.text


async def test_export_csv(client):
    token, _ = await _user_with_asset(client, "expcsv@example.com")

    response = await client.post(
        "/api/account/export",
        headers=_headers(token),
        json={"format": "csv", "types": []},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/csv")
    lines = response.text.strip().splitlines()
    assert lines[0] == "kind,type,title,domain,created_at,detail_json"
    assert any("asset" in line for line in lines[1:])


async def test_export_empty_user_returns_empty(client):
    registered = await register_user(client, "expempty@example.com")
    token = registered["token"]

    response = await client.post(
        "/api/account/export",
        headers=_headers(token),
        json={"format": "md", "types": []},
    )
    assert response.status_code == 200
    assert "没有可导出的数据" in response.text


async def test_delete_account_revokes_and_preserves_business_data(client, session):
    token, user_id = await _user_with_asset(client, "del@example.com")

    response = await client.request(
        "DELETE",
        "/api/account",
        headers={**_headers(token), "content-type": "application/json"},
        content=json.dumps({"password": "Secret123!"}),
    )
    assert response.status_code == 200
    assert response.json() == {"ok": True}

    # Old token must fail after deletion.
    me = await client.get("/api/auth/me", headers=_headers(token))
    assert me.status_code == 401

    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.id == user_id)
        )
        asset_count = (
            await database.execute(text("SELECT COUNT(*) FROM assets WHERE user_id=:u"), {"u": user_id})
        ).scalar_one()
        skill_count = (
            await database.execute(text("SELECT COUNT(*) FROM user_skills WHERE user_id=:u"), {"u": user_id})
        ).scalar_one()
    assert user is not None
    assert user.deleted_at is not None
    assert user.password_hash is None
    assert asset_count > 0
    assert skill_count > 0


async def test_delete_account_rejects_wrong_password(client):
    token, _ = await _user_with_asset(client, "delwrong@example.com")

    response = await client.request(
        "DELETE",
        "/api/account",
        headers={**_headers(token), "content-type": "application/json"},
        content=json.dumps({"password": "wrong-password"}),
    )
    assert response.status_code == 400

    me = await client.get("/api/auth/me", headers=_headers(token))
    assert me.status_code == 200
