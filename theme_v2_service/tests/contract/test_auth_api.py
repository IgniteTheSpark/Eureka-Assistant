"""Theme V2 auth API contract tests (§5.5)."""
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.auth.email_sender import get_verification_sender
from app.auth.models import UserAccount
from app.config import get_settings
from app.db.models import UserSkill
from app.db.session import AsyncSessionFactory
from app.domains.assets.service import BASELINE_CAPTURE_SKILLS
from app.main import app

from tests.fakes.auth_helpers import register_user


@pytest.fixture(autouse=True)
def _relax_email_cooldown(monkeypatch):
    settings = get_settings()
    monkeypatch.setattr(settings, "email_resend_cooldown_seconds", 0)


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


def _last_sent_code(email: str) -> str:
    sender = get_verification_sender()
    normalized = email.strip().lower()
    for item in reversed(sender.sent):
        if item["email"] == normalized:
            return item["code"]
    raise AssertionError(f"no code sent to {normalized}")


async def _request_register_code(client, email: str):
    return await client.post(
        "/api/auth/verification-codes",
        json={"email": email, "purpose": "register"},
    )


async def _register_with_code(client, email: str, *, password: str = "Secret123!"):
    request_response = await _request_register_code(client, email)
    assert request_response.status_code == 200, request_response.text
    code = _last_sent_code(email)
    return await client.post(
        "/api/auth/register",
        json={
            "email": email,
            "verification_code": code,
            "password": password,
            "terms_version": "2026-08-v1",
            "terms_accepted": True,
        },
    )


async def test_verification_code_request_returns_bounded_info(client):
    response = await _request_register_code(client, "person@example.com")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["resend_delay_seconds"] >= 0
    assert body["expires_in_seconds"] > 0
    assert "code" not in body


async def test_register_normalizes_email_and_creates_verified_account(client):
    response = await _register_with_code(client, "  Person@Example.COM ")

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["token"]
    assert body["user"]["email"] == "person@example.com"
    assert body["user"]["email_verified"] is True
    assert body["user"]["onboarding_status"] == "pending"

    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.email == "person@example.com")
        )
        assert user is not None
        assert user.email_verified_at is not None
        assert user.auth_version == 1
        skills = list(
            await database.scalars(
                select(UserSkill).where(UserSkill.user_id == user.id)
            )
        )
    assert {skill.machine_name for skill in skills} == {
        item["machine_name"] for item in BASELINE_CAPTURE_SKILLS
    }


async def test_register_without_terms_rejected(client):
    await _request_register_code(client, "person@example.com")
    code = _last_sent_code("person@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "person@example.com",
            "verification_code": code,
        "password": "Secret123!",
            "terms_version": "2026-08-v1",
            "terms_accepted": False,
        },
    )

    assert response.status_code == 400


async def test_register_with_wrong_code_rejected(client):
    await _request_register_code(client, "person@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "person@example.com",
            "verification_code": "000000",
        "password": "Secret123!",
            "terms_version": "2026-08-v1",
            "terms_accepted": True,
        },
    )

    assert response.status_code == 400


async def test_register_rejects_weak_password(client):
    await _request_register_code(client, "weak-password@example.com")
    code = _last_sent_code("weak-password@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "weak-password@example.com",
            "verification_code": code,
            "password": "weakpass1",
            "terms_version": "2026-08-v1",
            "terms_accepted": True,
        },
    )

    assert response.status_code == 422
    assert "大写字母" in response.json()["detail"]


async def test_register_conflict_surfaces_on_verified_register(client):
    assert (await _register_with_code(client, "person@example.com")).status_code == 200

    duplicate_code_request = await _request_register_code(client, "person@example.com")

    assert duplicate_code_request.status_code == 409


async def test_login_and_me_round_trip(client):
    registered = await _register_with_code(client, "person@example.com")
    user_id = registered.json()["user"]["id"]

    login = await client.post(
        "/api/auth/login",
        json={"email": "PERSON@example.com", "password": "Secret123!"},
    )
    assert login.status_code == 200
    assert login.json()["user"]["email"] == "person@example.com"

    me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {login.json()['token']}"},
    )
    assert me.status_code == 200
    assert me.json()["user"]["id"] == user_id


async def test_login_rejects_invalid_credentials(client):
    await _register_with_code(client, "person@example.com")

    response = await client.post(
        "/api/auth/login",
        json={"email": "person@example.com", "password": "wrong-password"},
    )

    assert response.status_code == 401


async def test_password_reset_does_not_enumerate(client):
    await _request_register_code(client, "known@example.com")
    await _register_with_code(client, "known@example.com")
    known_reset = await client.post(
        "/api/auth/verification-codes",
        json={"email": "known@example.com", "purpose": "password_reset"},
    )
    unknown_reset = await client.post(
        "/api/auth/verification-codes",
        json={"email": "ghost@example.com", "purpose": "password_reset"},
    )

    assert known_reset.status_code == 200
    assert unknown_reset.status_code == 200


async def test_auth_config_returns_legal_and_provider(client):
    response = await client.get("/api/auth/config")

    assert response.status_code == 200
    body = response.json()
    assert "terms_url" in body
    assert "privacy_url" in body
    assert "terms_version" in body
    assert body["email_provider"] == "mock"


async def _request_reset_code(client, email: str):
    return await client.post(
        "/api/auth/verification-codes",
        json={"email": email, "purpose": "password_reset"},
    )


async def test_password_reset_replaces_password_and_invalidates_old_token(client):
    registered = await _register_with_code(client, "reset@example.com")
    old_token = registered.json()["token"]

    assert (await _request_reset_code(client, "reset@example.com")).status_code == 200
    code = _last_sent_code("reset@example.com")
    reset = await client.post(
        "/api/auth/password-reset",
        json={
            "email": "reset@example.com",
            "verification_code": code,
        "new_password": "Newpass456!",
        },
    )
    assert reset.status_code == 200

    old_login = await client.post(
        "/api/auth/login",
        json={"email": "reset@example.com", "password": "Secret123!"},
    )
    assert old_login.status_code == 401

    new_login = await client.post(
        "/api/auth/login",
        json={"email": "reset@example.com", "password": "Newpass456!"},
    )
    assert new_login.status_code == 200

    old_token_me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {old_token}"},
    )
    assert old_token_me.status_code == 401


async def test_change_password_revokes_session_and_requires_relogin(client):
    registered = await _register_with_code(client, "change@example.com")
    old_token = registered.json()["token"]

    changed = await client.patch(
        "/api/account/password",
        headers={"Authorization": f"Bearer {old_token}"},
        json={"current_password": "Secret123!", "new_password": "Changed789!"},
    )
    assert changed.status_code == 200
    assert changed.json() == {"ok": True}

    old_token_me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {old_token}"},
    )
    assert old_token_me.status_code == 401

    relogin = await client.post(
        "/api/auth/login",
        json={"email": "change@example.com", "password": "Changed789!"},
    )
    assert relogin.status_code == 200


async def test_change_password_rejects_wrong_current(client):
    registered = await _register_with_code(client, "wrongpwd@example.com")
    token = registered.json()["token"]

    response = await client.patch(
        "/api/account/password",
        headers={"Authorization": f"Bearer {token}"},
        json={"current_password": "not-the-password", "new_password": "Changed789!"},
    )

    assert response.status_code == 400
