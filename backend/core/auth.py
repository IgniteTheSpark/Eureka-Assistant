"""
Auth — THE single source of truth for "who is the current user".

Resolves the user from the request's `Authorization: Bearer <token>` header
(HS256 token minted by /api/auth/login|register). Used via FastAPI Depends:

    from fastapi import Depends
    from core.auth import get_current_user_id

    @router.get("/something")
    async def endpoint(user_id: str = Depends(get_current_user_id)):
        ...

Every data route depends on this, so a missing/invalid token → 401 and content
is isolated per user (all tables are `user_id`-scoped). The only unauthenticated
routes are /api/auth/* and /health.
"""
from fastapi import HTTPException, Request

from core.security import decode_token


def get_current_user_id(request: Request) -> str:
    """Resolve the current request's user_id from the Bearer token. 401 if absent
    or invalid/expired."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        payload = decode_token(auth[len("Bearer "):].strip())
        if payload and payload.get("sub"):
            return str(payload["sub"])
    raise HTTPException(status_code=401, detail="未登录或登录已过期")
