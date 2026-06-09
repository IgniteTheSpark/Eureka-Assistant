"""
§13.1 / B1 — 百智 (100wiser) OAuth login. 百智 is the IdP; Eureka still mints its
OWN HS256 session token (§3 `get_current_user_id` / per-user isolation unchanged).

Flow (mobile, backend-mediated):

    GET /api/auth/baizhi/authorize          → {authorize_url}            (no token)
    GET /api/auth/baizhi/callback?token=tmp   (= 百智 console redirectUrl, no token)
        → POST {base}/api/applications/token/exchange {token} → 百智 real JWT
        → map to Eureka user (provision skills on first login)
        → mint Eureka JWT
        → 302 → {scheme}://auth?token=<eureka_jwt>   (deep-link back to the app)

IRON RULES (handoff §6 / §13.5):
  • `app_secret` + 百智 real token live ONLY on the backend; the client ever sees
    only the Eureka JWT.
  • The temp `token` is one-time, never persisted.
  • The 百智 real token is stored per-user, Fernet-encrypted, write-only — in the
    Connected Apps table (provider='baizhi', §1.7.1) — for B2/B4 to call 百智 with.
  • Every failure path deep-links back with `?error=…` (never a blank/silent page).
"""
import base64
import hashlib
import json
import secrets
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, HTTPException
from fastapi.responses import RedirectResponse
from sqlalchemy import select

from config import settings
from core.crypto import encrypt_credentials
from core.provisioning import provision_user_skills
from core.security import create_token
from db.database import AsyncSessionLocal
from db.models import ConnectedApp, User

router = APIRouter()

_SIGN_SALT = "BAIZHIAPPLICATION"      # 百智 platform sign salt (openapi.100wiser.com/doc)
_PROVIDER = "baizhi"                  # connector_id used to store the real token in connected_apps
# Stable-id claim priority when deriving identity from the real-token JWT / me-endpoint.
_ID_CLAIMS = ("userId", "user_id", "uid", "sub", "id", "accountId", "account")


def _require(name: str) -> str:
    """Read a required 百智 setting or 503 (login not configured). Keeps email
    login working when 百智 env is absent."""
    val = (getattr(settings, name, "") or "").strip()
    if not val:
        raise HTTPException(status_code=503, detail="百智登录未配置")
    return val


def _sign(nonce: str) -> str:
    """SHA256(app_id + app_secret + 'BAIZHIAPPLICATION' + nonce), lowercase hex.
    Computed server-side only — `app_secret` never reaches the client."""
    raw = f"{_require('baizhi_app_id')}{_require('baizhi_app_secret')}{_SIGN_SALT}{nonce}"
    return hashlib.sha256(raw.encode()).hexdigest()


def _authorize_url() -> str:
    nonce = secrets.token_hex(16)
    q = urlencode({
        "app_id": _require("baizhi_app_id"),
        "nonce": nonce,
        "sign": _sign(nonce),
        "app_name": _require("baizhi_app_name"),
    })
    return f"{_require('baizhi_oauth_base_url')}/oauth-bridge?{q}"


def _deeplink(*, token: str | None = None, error: str | None = None) -> str:
    scheme = (settings.eureka_app_scheme or "eureka").strip()
    q = urlencode({"token": token} if token else {"error": error or "baizhi_login_failed"})
    return f"{scheme}://auth?{q}"


def _pick_id(d: dict | None) -> str | None:
    if not isinstance(d, dict):
        return None
    for claim in _ID_CLAIMS:
        v = d.get(claim)
        if v not in (None, "", 0):
            return f"{v}"
    return None


def _id_from_jwt(real_token: str) -> str | None:
    """Decode the 百智 real-token JWT payload (no verification — we only read 百智's
    own token to extract a stable user id) and pick the first id-like claim."""
    try:
        seg = real_token.split(".")[1]
        seg += "=" * (-len(seg) % 4)
        return _pick_id(json.loads(base64.urlsafe_b64decode(seg)))
    except Exception:
        return None


async def _id_from_me(real_token: str) -> str | None:
    """Authoritative path: if BAIZHI_ME_URL is configured, call it with the real
    token for the stable user id. Returns None if unset/unavailable."""
    me_url = (settings.baizhi_me_url or "").strip()
    if not me_url:
        return None
    try:
        async with httpx.AsyncClient(timeout=10) as cx:
            r = await cx.get(me_url, headers={"Authorization": f"Bearer {real_token}"})
        if r.status_code == 200:
            body = r.json()
            data = body.get("data", body) if isinstance(body, dict) else None
            return _pick_id(data)
    except Exception:
        return None
    return None


@router.get("/auth/baizhi/authorize")
async def baizhi_authorize():
    """Return the 百智 oauth-bridge URL for the app to open in a web-auth session.
    No token required (this is the pre-login step). 503 if 百智 isn't configured."""
    return {"ok": True, "authorize_url": _authorize_url()}


@router.get("/auth/baizhi/callback")
async def baizhi_callback(token: str | None = None):
    """百智 console redirectUrl. Receives a one-time `token`, exchanges it for the
    real 百智 JWT, maps to an Eureka user (provisioning on first login), mints the
    Eureka session JWT, and deep-links back to the app. Always deep-links — success
    carries `?token=`, every failure carries `?error=`."""
    if not token:
        return RedirectResponse(_deeplink(error="missing_token"), status_code=302)

    # 1) Exchange the one-time token for 百智's real login JWT (authoritative
    #    endpoint — the quick-start doc's /api/baizhi/oauth/exchange is a typo).
    try:
        async with httpx.AsyncClient(timeout=15) as cx:
            r = await cx.post(
                f"{settings.baizhi_base_url.rstrip('/')}/api/applications/token/exchange",
                json={"token": token},
            )
        body = r.json() if "application/json" in r.headers.get("content-type", "") else {}
    except Exception:
        return RedirectResponse(_deeplink(error="baizhi_unreachable"), status_code=302)

    code = body.get("code") if isinstance(body, dict) else None
    real_token = ((body.get("data") or {}).get("token")) if isinstance(body, dict) else None
    if r.status_code != 200 or code not in (0, "0", None) or not real_token:
        return RedirectResponse(_deeplink(error="exchange_failed"), status_code=302)

    # 2) Stable 百智 identity — authoritative me-endpoint if configured, else the
    #    real-token JWT's id claim.
    baizhi_uid = await _id_from_me(real_token) or _id_from_jwt(real_token)
    if not baizhi_uid:
        return RedirectResponse(_deeplink(error="no_identity"), status_code=302)

    # 3) Map → Eureka user (provision on first login)  4) mint Eureka JWT
    #    5) store the real token encrypted (write-only) in connected_apps.
    try:
        async with AsyncSessionLocal() as db:
            user = (await db.execute(
                select(User).where(User.baizhi_user_id == baizhi_uid)
            )).scalar_one_or_none()
            if user is None:
                user = User(baizhi_user_id=baizhi_uid)
                db.add(user)
                await db.flush()                      # assign user.id before provisioning
                await provision_user_skills(db, user.id)
            uid = user.id

            enc = encrypt_credentials({"token": real_token})
            existing = (await db.execute(
                select(ConnectedApp).where(
                    ConnectedApp.user_id == uid,
                    ConnectedApp.connector_id == _PROVIDER,
                )
            )).scalar_one_or_none()
            if existing:
                existing.credentials_enc = enc
                existing.status = "connected"
            else:
                db.add(ConnectedApp(
                    user_id=uid, connector_id=_PROVIDER, display_name="百智",
                    auth_type="oauth", credentials_enc=enc, status="connected",
                ))
            await db.commit()
    except Exception as e:  # noqa — never leak; deep-link an error instead
        print(f"[baizhi] callback mapping failed (non-fatal): {str(e)[:140]}", flush=True)
        return RedirectResponse(_deeplink(error="server_error"), status_code=302)

    # 6) Deep-link back to the app with the Eureka JWT (the only thing the client gets).
    return RedirectResponse(_deeplink(token=create_token(uid)), status_code=302)
