"""
Auth — Phase B Step 3 (decision #1).

THE single source of truth for "who is the current user". In demo mode this
returns the configured single-user id; in production, swap the implementation
to validate a JWT / session cookie / API key and callers do not need to change.

Use via FastAPI Depends:

    from fastapi import Depends
    from core.auth import get_current_user_id

    @router.get("/something")
    async def endpoint(user_id: str = Depends(get_current_user_id)):
        ...

NEVER `from config import settings; settings.user_id` directly elsewhere —
always go through this dep. That is decision #1's clean seam.
"""
from config import settings


def get_current_user_id() -> str:
    """
    Resolve the current request's user_id.

    Demo: returns the configured single-user id (settings.user_id, default "default").

    Production replacement: read Authorization header, validate JWT, look up
    the user, return user.id. Signature can grow (add `request: Request` or
    similar) — callers using Depends() are unaffected.
    """
    return settings.user_id
