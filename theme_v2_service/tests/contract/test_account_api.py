"""Account export + deactivation (停用账户) contract tests (§9 / §10)."""
import json

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select, text

from app.auth.models import UserAccount
from app.auth.api import ChangePasswordRequest
from app.auth.security import hash_password
from app.account.api import change_password
from app.account.deletion import delete_account
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


class _LockRecordingSession:
    def __init__(self, user: UserAccount):
        self.user = user
        self.used_for_update = False

    async def scalar(self, statement):
        self.used_for_update = statement._for_update_arg is not None
        return self.user

    async def get(self, model, user_id):
        return self.user

    async def flush(self):
        return None


async def test_change_password_locks_account_before_mutation():
    user = UserAccount(
        id="lock-change-user",
        email="lock-change@example.com",
        password_hash=hash_password("Secret123!"),
        auth_version=1,
        onboarding_status="pending",
    )
    session = _LockRecordingSession(user)

    await change_password(
        ChangePasswordRequest(
            current_password="Secret123!",
            new_password="Changed789!",
        ),
        user_id=user.id,
        session=session,
    )

    assert session.used_for_update is True


async def test_soft_delete_locks_account_before_mutation():
    user = UserAccount(
        id="lock-delete-user",
        email="lock-delete@example.com",
        password_hash=hash_password("Secret123!"),
        auth_version=1,
        onboarding_status="pending",
    )
    session = _LockRecordingSession(user)

    await delete_account(session, user.id, password="Secret123!")

    assert session.used_for_update is True


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
            "field_keys": ["distance_km", "duration_min"],
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
    assert response.json()["detail"] == "密码不正确，无法停用账户"

    me = await client.get("/api/auth/me", headers=_headers(token))
    assert me.status_code == 200


async def test_change_password_rejects_weak_new_password(client):
    """Account change enforces the same password policy as register/reset."""
    registered = await register_user(client, "weakchange@example.com")
    token = registered["token"]

    response = await client.patch(
        "/api/account/password",
        headers=_headers(token),
        json={"current_password": "Secret123!", "new_password": "weakpass1"},
    )

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert isinstance(detail, list)
    assert "大写字母" in detail[0]["msg"]

    # The existing password is untouched.
    me = await client.get("/api/auth/me", headers=_headers(token))
    assert me.status_code == 200


async def test_stopped_account_cannot_re_register_or_login(client):
    token, _ = await _user_with_asset(client, "delre@example.com")

    response = await client.request(
        "DELETE",
        "/api/account",
        headers={**_headers(token), "content-type": "application/json"},
        content=json.dumps({"password": "Secret123!"}),
    )
    assert response.status_code == 200

    # Retained email must block re-registration: requesting a register
    # verification code for the stopped address fails with 409.
    code_response = await client.post(
        "/api/auth/verification-codes",
        json={"email": "delre@example.com", "purpose": "register"},
    )
    assert code_response.status_code == 409
    assert code_response.json()["detail"] == "该邮箱已注册"

    # Password login for the stopped account fails safely.
    login = await client.post(
        "/api/auth/login",
        json={"email": "delre@example.com", "password": "Secret123!"},
    )
    assert login.status_code == 401

    # The stopped account's old token is rejected on every authenticated route.
    me = await client.get("/api/auth/me", headers=_headers(token))
    assert me.status_code == 401
    options = await client.get("/api/account/export-options", headers=_headers(token))
    assert options.status_code == 401
