import base64
import binascii
import hashlib
import hmac
import json
import os
import time

from app.config import get_settings


_PBKDF2_ITERATIONS = 200_000


def _b64u(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode()


def _b64u_dec(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode(),
        salt,
        _PBKDF2_ITERATIONS,
    )
    return (
        f"pbkdf2_sha256${_PBKDF2_ITERATIONS}"
        f"${_b64u(salt)}${_b64u(digest)}"
    )


def verify_password(password: str, stored: str) -> bool:
    try:
        algorithm, iterations, salt_text, digest_text = stored.split("$")
        if algorithm != "pbkdf2_sha256":
            return False
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode(),
            _b64u_dec(salt_text),
            int(iterations),
        )
        return hmac.compare_digest(digest, _b64u_dec(digest_text))
    except (ValueError, TypeError, binascii.Error):
        return False


def create_token(
    user_id: str,
    *,
    now: int | None = None,
    ttl_seconds: int = 86_400,
) -> str:
    issued_at = int(time.time()) if now is None else now
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {
        "sub": user_id,
        "iat": issued_at,
        "exp": issued_at + ttl_seconds,
    }
    signing_text = (
        f"{_b64u(json.dumps(header, separators=(',', ':')).encode())}."
        f"{_b64u(json.dumps(payload, separators=(',', ':')).encode())}"
    )
    signature = hmac.new(
        get_settings().jwt_secret.encode(),
        signing_text.encode(),
        hashlib.sha256,
    ).digest()
    return f"{signing_text}.{_b64u(signature)}"


def decode_token(token: str, *, now: int | None = None) -> dict | None:
    try:
        header_text, payload_text, signature_text = token.split(".")
        header = json.loads(_b64u_dec(header_text))
        if header != {"alg": "HS256", "typ": "JWT"}:
            return None

        signing_text = f"{header_text}.{payload_text}"
        expected = hmac.new(
            get_settings().jwt_secret.encode(),
            signing_text.encode(),
            hashlib.sha256,
        ).digest()
        if not hmac.compare_digest(expected, _b64u_dec(signature_text)):
            return None

        payload = json.loads(_b64u_dec(payload_text))
        current = int(time.time()) if now is None else now
        if not payload.get("sub") or int(payload.get("exp", 0)) < current:
            return None
        return payload
    except (
        ValueError,
        TypeError,
        json.JSONDecodeError,
        binascii.Error,
        UnicodeDecodeError,
    ):
        return None
