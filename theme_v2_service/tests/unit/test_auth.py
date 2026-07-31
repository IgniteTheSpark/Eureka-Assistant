import base64
import json

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.auth.dependencies import get_current_user_id
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


def test_current_user_dependency_accepts_bearer_token():
    token = create_token("user-1")

    assert get_current_user_id(_request(f"Bearer {token}")) == "user-1"


@pytest.mark.parametrize("authorization", [None, "", "Basic abc", "Bearer invalid"])
def test_current_user_dependency_rejects_missing_or_invalid_token(authorization):
    with pytest.raises(HTTPException) as exc_info:
        get_current_user_id(_request(authorization))

    assert exc_info.value.status_code == 401
