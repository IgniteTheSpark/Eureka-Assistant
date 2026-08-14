import base64
import json
from datetime import datetime, timezone

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.auth.dependencies import get_current_user_id
from app.auth.models import UserAccount
from app.auth.security import (
    create_token,
    decode_token,
    hash_password,
    verify_password,
)


def _request(authorization: str | None = None) -> Request:
    headers = []
    if authorization is not None:
        headers.append((b"authorization", authorization.encode()))
    return Request({"type": "http", "headers": headers})


def test_token_round_trip():
    token = create_token("user-1", now=1_700_000_000, ttl_seconds=3600)

    assert decode_token(token, now=1_700_000_001)["sub"] == "user-1"


def test_tampered_token_is_rejected():
    token = create_token("user-1")

    assert decode_token(token + "x") is None


def test_expired_token_is_rejected():
    token = create_token("user-1", now=1_700_000_000, ttl_seconds=60)

    assert decode_token(token, now=1_700_000_061) is None


def test_non_hs256_token_is_rejected():
    token = create_token("user-1", now=1_700_000_000)
    _, payload, signature = token.split(".")
    header = base64.urlsafe_b64encode(
        json.dumps({"alg": "none", "typ": "JWT"}, separators=(",", ":")).encode()
    ).rstrip(b"=").decode()

    assert decode_token(f"{header}.{payload}.{signature}", now=1_700_000_001) is None


def test_password_hash_round_trip():
    stored = hash_password("correct horse battery staple")

    assert verify_password("correct horse battery staple", stored)
    assert not verify_password("wrong", stored)


def test_malformed_password_hash_is_rejected():
    assert not verify_password("password", "not-a-supported-hash")


async def test_current_user_dependency_accepts_bearer_token(session):
    user = UserAccount(
        email="u@x.com",
        password_hash=hash_password("password123"),
        email_verified_at=datetime.now(timezone.utc),
        onboarding_status="skipped",
        auth_version=1,
    )
    session.add(user)
    await session.flush()
    token = create_token(user.id, auth_version=1)

    assert await get_current_user_id(_request(f"Bearer {token}"), session) == user.id


@pytest.mark.parametrize("authorization", [None, "", "Basic abc", "Bearer invalid"])
async def test_current_user_dependency_rejects_missing_or_invalid_token(authorization, session):
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_request(authorization), session)

    assert exc_info.value.status_code == 401


async def test_current_user_dependency_rejects_stale_auth_version(session):
    user = UserAccount(
        email="u@x.com",
        password_hash=hash_password("password123"),
        email_verified_at=datetime.now(timezone.utc),
        onboarding_status="skipped",
        auth_version=2,
    )
    session.add(user)
    await session.flush()
    stale_token = create_token(user.id, auth_version=1)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_request(f"Bearer {stale_token}"), session)

    assert exc_info.value.status_code == 401


async def test_current_user_dependency_rejects_deleted_account(session):
    user = UserAccount(
        email="u@x.com",
        password_hash=hash_password("password123"),
        email_verified_at=datetime.now(timezone.utc),
        onboarding_status="skipped",
        auth_version=1,
        deleted_at=datetime.now(timezone.utc),
    )
    session.add(user)
    await session.flush()
    token = create_token(user.id, auth_version=1)

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(_request(f"Bearer {token}"), session)

    assert exc_info.value.status_code == 401
