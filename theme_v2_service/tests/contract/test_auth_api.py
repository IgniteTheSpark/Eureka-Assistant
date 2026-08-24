"""Theme V2 auth API contract tests (§5.5)."""
import json
from datetime import datetime, timezone

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.auth.email_sender import EmailDeliveryError, get_verification_sender
from app.auth.models import (
    CHALLENGE_PASSWORD_RESET,
    CHALLENGE_REGISTER,
    EmailVerificationChallenge,
    UserAccount,
)
from app.config import get_settings
from app.auth.security import hash_password
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


def _current_terms_version() -> str:
    return get_settings().terms_version_current


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
            "terms_version": _current_terms_version(),
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


async def test_verification_code_503_when_sender_construction_fails(
    client, monkeypatch
):
    from app.auth import api as auth_api

    def failing_init():
        raise EmailDeliveryError("directmail not configured")

    monkeypatch.setattr(auth_api, "get_verification_sender", failing_init)

    response = await client.post(
        "/api/auth/verification-codes",
        json={"email": "bound@example.com", "purpose": "register"},
    )

    assert response.status_code == 503
    body = response.json()
    assert body["detail"] == "验证码发送失败，请稍后重试"
    assert "directmail" not in json.dumps(body)


async def test_verification_code_503_when_provider_fails(client, monkeypatch):
    from app.auth import api as auth_api

    class _FailingSender:
        async def send_code(self, **kwargs):
            raise EmailDeliveryError("provider timeout")

    monkeypatch.setattr(auth_api, "get_verification_sender", lambda: _FailingSender())

    response = await client.post(
        "/api/auth/verification-codes",
        json={"email": "bound@example.com", "purpose": "register"},
    )

    assert response.status_code == 503
    body = response.json()
    assert body["detail"] == "验证码发送失败，请稍后重试"
    assert "provider timeout" not in json.dumps(body)


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


async def test_register_failure_rolls_back_code_consumption_and_account(
    client, monkeypatch
):
    from app.auth import api as auth_api

    email = "register-rollback@example.com"
    assert (await _request_register_code(client, email)).status_code == 200
    code = _last_sent_code(email)

    async def failing_ensure_capture_skills(session, user_id):
        raise RuntimeError("baseline failed")

    monkeypatch.setattr(
        auth_api, "ensure_capture_skills", failing_ensure_capture_skills
    )
    with pytest.raises(RuntimeError, match="baseline failed"):
        await client.post(
            "/api/auth/register",
            json={
                "email": email,
                "verification_code": code,
                "password": "Secret123!",
                "terms_version": _current_terms_version(),
                "terms_accepted": True,
            },
        )

    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.email == email)
        )
        challenge = await database.scalar(
            select(EmailVerificationChallenge)
            .where(
                EmailVerificationChallenge.email == email,
                EmailVerificationChallenge.purpose == CHALLENGE_REGISTER,
            )
            .order_by(EmailVerificationChallenge.created_at.desc())
        )
    assert user is None
    assert challenge is not None
    assert challenge.consumed_at is None


async def test_register_without_terms_rejected(client):
    await _request_register_code(client, "person@example.com")
    code = _last_sent_code("person@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "person@example.com",
            "verification_code": code,
        "password": "Secret123!",
            "terms_version": _current_terms_version(),
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
            "terms_version": _current_terms_version(),
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
            "terms_version": _current_terms_version(),
            "terms_accepted": True,
        },
    )

    assert response.status_code == 422
    assert "大写字母" in response.json()["detail"]


async def test_register_rejects_short_password_without_input_echo(client):
    await _request_register_code(client, "short-password@example.com")
    code = _last_sent_code("short-password@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "short-password@example.com",
            "verification_code": code,
            "password": "abc",
            "terms_version": _current_terms_version(),
            "terms_accepted": True,
        },
    )

    assert response.status_code == 422
    assert response.json()["detail"] == "密码长度至少 8 位"


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


@pytest.mark.parametrize(
    ("path", "body"),
    [
        (
            "/api/auth/login",
            {"email": f"{'x' * 309}@example.com", "password": "Secret123!"},
        ),
        (
            "/api/auth/register",
            {
                "email": "person@example.com",
                "verification_code": "12345",
                "password": "Secret123!",
                "terms_version": "2026-08-v1",
                "terms_accepted": True,
            },
        ),
        (
            "/api/auth/password-reset",
            {
                "email": "person@example.com",
                "verification_code": "123456",
                "new_password": "X" * 129,
            },
        ),
    ],
)
async def test_auth_request_limits_reject_before_handler(client, path, body):
    response = await client.post(path, json=body)

    assert response.status_code == 422
    assert isinstance(response.json()["detail"], list)


async def test_login_rate_limit_counts_failed_attempts(client, monkeypatch):
    monkeypatch.setenv("LOGIN_ATTEMPTS_PER_EMAIL_15_MIN", "2")
    get_settings.cache_clear()
    try:
        payload = {
            "email": "limited@example.com",
            "password": "Wrong123!",
        }
        assert (await client.post("/api/auth/login", json=payload)).status_code == 401
        assert (await client.post("/api/auth/login", json=payload)).status_code == 401
        blocked = await client.post("/api/auth/login", json=payload)
    finally:
        get_settings.cache_clear()

    assert blocked.status_code == 429
    assert int(blocked.headers["retry-after"]) > 0


async def test_unknown_and_deleted_login_use_dummy_verification(client, monkeypatch):
    from app.auth import api as auth_api

    async with AsyncSessionFactory.begin() as database:
        database.add(
            UserAccount(
                email="deleted-timing@example.com",
                password_hash=hash_password("Secret123!"),
                deleted_at=datetime.now(timezone.utc).replace(tzinfo=None),
                auth_version=2,
            )
        )

    calls: list[tuple[str, str]] = []

    async def recording_verify(password: str, stored: str) -> bool:
        calls.append((password, stored))
        return False

    monkeypatch.setattr(
        auth_api,
        "verify_password_async",
        recording_verify,
        raising=False,
    )
    for email in ("unknown-timing@example.com", "deleted-timing@example.com"):
        response = await client.post(
            "/api/auth/login",
            json={"email": email, "password": "Wrong123!"},
        )
        assert response.status_code == 401

    assert len(calls) == 2
    assert all(stored.startswith("pbkdf2_sha256$") for _, stored in calls)


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


async def test_password_reset_failure_rolls_back_code_consumption_and_password(
    client, monkeypatch
):
    from app.auth import api as auth_api

    email = "reset-rollback@example.com"
    assert (await _register_with_code(client, email)).status_code == 200
    assert (await _request_reset_code(client, email)).status_code == 200
    code = _last_sent_code(email)

    def failing_hash_password(password):
        raise RuntimeError("hash failed")

    async def failing_hash_password_async(password):
        return failing_hash_password(password)

    monkeypatch.setattr(
        auth_api, "hash_password_async", failing_hash_password_async
    )
    with pytest.raises(RuntimeError, match="hash failed"):
        await client.post(
            "/api/auth/password-reset",
            json={
                "email": email,
                "verification_code": code,
                "new_password": "Newpass456!",
            },
        )

    async with AsyncSessionFactory() as database:
        challenge = await database.scalar(
            select(EmailVerificationChallenge)
            .where(
                EmailVerificationChallenge.email == email,
                EmailVerificationChallenge.purpose == CHALLENGE_PASSWORD_RESET,
            )
            .order_by(EmailVerificationChallenge.created_at.desc())
        )
    assert challenge is not None
    assert challenge.consumed_at is None

    old_login = await client.post(
        "/api/auth/login",
        json={"email": email, "password": "Secret123!"},
    )
    assert old_login.status_code == 200


async def test_change_password_revokes_session_and_requires_relogin(client):
    registered = await _register_with_code(client, "change@example.com")
    old_token = registered.json()["token"]

    changed = await client.patch(
        "/api/account/password",
        headers={"Authorization": f"Bearer {old_token}"},
        json={"current_password": "Secret123!", "new_password": "Changed789!"},
    )
    assert changed.status_code == 200
    replacement = changed.json()
    assert replacement["ok"] is True
    assert replacement["token"]
    assert replacement["user"]["id"] == registered.json()["user"]["id"]

    old_token_me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {old_token}"},
    )
    assert old_token_me.status_code == 401

    replacement_me = await client.get(
        "/api/auth/me",
        headers={"Authorization": f"Bearer {replacement['token']}"},
    )
    assert replacement_me.status_code == 200

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


# --- Server-authoritative terms version (§5.5) ---


async def test_register_rejects_missing_terms_version(client):
    await _request_register_code(client, "termless@example.com")
    code = _last_sent_code("termless@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "termless@example.com",
            "verification_code": code,
            "password": "Secret123!",
            "terms_version": "",
            "terms_accepted": True,
        },
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "缺少服务条款版本，请刷新后重试"


async def test_register_rejects_stale_terms_version(client):
    await _request_register_code(client, "stale@example.com")
    code = _last_sent_code("stale@example.com")

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "stale@example.com",
            "verification_code": code,
            "password": "Secret123!",
            "terms_version": "2020-01-v0",
            "terms_accepted": True,
        },
    )

    assert response.status_code == 409
    assert "最新版本" in response.json()["detail"]


async def test_register_records_server_current_terms_version(client):
    await _request_register_code(client, "terms@example.com")
    code = _last_sent_code("terms@example.com")
    current = _current_terms_version()

    response = await client.post(
        "/api/auth/register",
        json={
            "email": "terms@example.com",
            "verification_code": code,
            "password": "Secret123!",
            "terms_version": current,
            "terms_accepted": True,
        },
    )
    assert response.status_code == 200

    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.email == "terms@example.com")
        )
    assert user is not None
    # The server records its own current version — never a client-supplied value.
    assert user.terms_version == current
    assert user.terms_accepted_at is not None


async def test_register_records_rotated_server_terms_version(client, monkeypatch):
    """After the server bumps TERMS_VERSION_CURRENT, the recorded value follows
    the server, and the previously-current client version becomes stale."""
    from app.config import get_settings as _get_settings

    monkeypatch.setattr(_get_settings(), "terms_version_current", "2026-09-v2")

    stale = await client.post(
        "/api/auth/register",
        json={
            "email": "rotate@example.com",
            "verification_code": "000000",
            "password": "Secret123!",
            "terms_version": "2026-08-v1",
            "terms_accepted": True,
        },
    )
    assert stale.status_code == 409

    await _request_register_code(client, "rotate@example.com")
    code = _last_sent_code("rotate@example.com")
    fresh = await client.post(
        "/api/auth/register",
        json={
            "email": "rotate@example.com",
            "verification_code": code,
            "password": "Secret123!",
            "terms_version": "2026-09-v2",
            "terms_accepted": True,
        },
    )
    assert fresh.status_code == 200

    async with AsyncSessionFactory() as database:
        user = await database.scalar(
            select(UserAccount).where(UserAccount.email == "rotate@example.com")
        )
    assert user is not None
    assert user.terms_version == "2026-09-v2"


# --- Unified password policy across register / reset / account change (§5.5) ---


async def test_password_reset_rejects_weak_password(client):
    registered = await _register_with_code(client, "weakreset@example.com")
    assert registered.status_code == 200

    assert (await _request_reset_code(client, "weakreset@example.com")).status_code == 200
    code = _last_sent_code("weakreset@example.com")

    response = await client.post(
        "/api/auth/password-reset",
        json={
            "email": "weakreset@example.com",
            "verification_code": code,
            "new_password": "weakpass1",
        },
    )

    assert response.status_code == 422
    assert "大写字母" in response.json()["detail"]

    # The reset must NOT have consumed the code or changed the password.
    old_login = await client.post(
        "/api/auth/login",
        json={"email": "weakreset@example.com", "password": "Secret123!"},
    )
    assert old_login.status_code == 200
