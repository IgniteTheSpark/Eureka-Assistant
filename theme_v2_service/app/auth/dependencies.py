from fastapi import Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import UserAccount
from app.auth.security import decode_token
from app.db.session import get_session


async def get_current_user_id(
    request: Request,
    session: AsyncSession = Depends(get_session),
) -> str:
    """Resolve the authenticated user id, enforcing auth_version (§5.4).

    Token must be valid, reference an existing account, carry an auth_version
    equal to the account's current one, and the account must not be deleted.
    """
    value = request.headers.get("Authorization", "")
    if not value.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="未登录或登录已过期")

    payload = decode_token(value[7:].strip())
    if payload is None or not payload.get("sub"):
        raise HTTPException(status_code=401, detail="未登录或登录已过期")

    user = await session.scalar(
        select(UserAccount).where(UserAccount.id == str(payload["sub"]))
    )
    if user is None or user.deleted_at is not None:
        raise HTTPException(status_code=401, detail="账号不存在或已注销")

    token_version = int(payload.get("av", 0))
    if token_version != user.auth_version:
        raise HTTPException(status_code=401, detail="登录已失效，请重新登录")

    return user.id
