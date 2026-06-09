"""
Symmetric encryption for Connected Apps credentials (§1.7.1).

Per-user external-app credentials are stored **encrypted at rest** in
`connected_apps.credentials_enc`. We use Fernet (AES-128-CBC + HMAC) from the
`cryptography` package.

Key resolution:
  1. `CONNECTED_APPS_KEY` env (a Fernet key — urlsafe-base64 of 32 bytes). Prod.
  2. else derive deterministically from `jwt_secret` (dev convenience). A WARNING
     is printed once so prod doesn't silently rely on the derived key.

The plaintext is the JSON of `{field: value}` credentials. This module is the
only place that touches raw credentials; callers pass/receive dicts. Nothing
here logs the plaintext.
"""
from __future__ import annotations

import base64
import hashlib
import json
from functools import lru_cache

from cryptography.fernet import Fernet, InvalidToken

from config import settings


@lru_cache(maxsize=1)
def _fernet() -> Fernet:
    key = (settings.connected_apps_key or "").strip()
    if key:
        return Fernet(key.encode())
    # Dev fallback: derive a stable Fernet key from jwt_secret.
    print(
        "[crypto] WARNING: CONNECTED_APPS_KEY not set — deriving the credential "
        "encryption key from jwt_secret. Set CONNECTED_APPS_KEY in prod.",
        flush=True,
    )
    digest = hashlib.sha256(("connected-apps:" + settings.jwt_secret).encode()).digest()
    return Fernet(base64.urlsafe_b64encode(digest))


def encrypt_credentials(creds: dict) -> str:
    """JSON-encode + Fernet-encrypt a credentials dict → token string."""
    raw = json.dumps(creds, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return _fernet().encrypt(raw).decode("ascii")


def decrypt_credentials(token: str) -> dict:
    """Reverse of [encrypt_credentials]. Returns {} on any failure (never raises
    into the caller — a corrupt/rotated key shouldn't crash the task runner)."""
    try:
        raw = _fernet().decrypt(token.encode("ascii"))
        data = json.loads(raw.decode("utf-8"))
        return data if isinstance(data, dict) else {}
    except (InvalidToken, ValueError, TypeError):
        return {}
