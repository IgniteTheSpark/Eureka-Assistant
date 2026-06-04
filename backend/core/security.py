"""
Password hashing + auth tokens — stdlib only (no new deps, works with the live
`--reload` container).

- Passwords: PBKDF2-HMAC-SHA256 with a per-password random salt.
- Tokens: a minimal HS256 JWT (header.payload.signature). We only ever issue +
  verify our own HS256 token signed with `settings.jwt_secret`; we never honor
  `alg:none` or any other alg, so the usual JWT footguns don't apply.

Swapping to passlib/pyjwt later is a drop-in (same function signatures).
"""
import base64
import hashlib
import hmac
import json
import os
import time

from config import settings

_PBKDF2_ITERATIONS = 200_000


def _b64u(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def _b64u_dec(s: str) -> bytes:
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _PBKDF2_ITERATIONS)
    return f"pbkdf2_sha256${_PBKDF2_ITERATIONS}${_b64u(salt)}${_b64u(dk)}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, iters, salt_b64, hash_b64 = stored.split("$")
        if algo != "pbkdf2_sha256":
            return False
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), _b64u_dec(salt_b64), int(iters))
        return hmac.compare_digest(dk, _b64u_dec(hash_b64))
    except Exception:
        return False


def create_token(user_id: str) -> str:
    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    payload = {"sub": user_id, "iat": now, "exp": now + settings.jwt_expire_hours * 3600}
    seg = (
        _b64u(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64u(json.dumps(payload, separators=(",", ":")).encode())
    )
    sig = hmac.new(settings.jwt_secret.encode(), seg.encode(), hashlib.sha256).digest()
    return f"{seg}.{_b64u(sig)}"


def decode_token(token: str) -> dict | None:
    """Return the payload if the signature is valid and the token isn't expired,
    else None. Never raises."""
    try:
        seg_h, seg_p, seg_s = token.split(".")
        signing_input = f"{seg_h}.{seg_p}".encode()
        expected = hmac.new(settings.jwt_secret.encode(), signing_input, hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64u_dec(seg_s)):
            return None
        payload = json.loads(_b64u_dec(seg_p))
        if int(payload.get("exp", 0)) < int(time.time()):
            return None
        return payload
    except Exception:
        return None
