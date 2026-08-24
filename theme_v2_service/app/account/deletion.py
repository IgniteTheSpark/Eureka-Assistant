"""Account deactivation (§10, 停用账户).

Deactivation requires password re-authentication. The account row is revoked
(auth_version bump + deleted_at + password_hash clear) so every existing token
dies immediately and password login is blocked. Deactivation is intentionally
soft: the email and all business data are retained, and there is no
self-service restore. No rows are deleted and no physical cleanup is enqueued.
"""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import UserAccount
from app.auth.security import verify_password_async
from app.db.base import utc_now

class DeletePasswordError(Exception):
    pass


async def delete_account(
    session: AsyncSession,
    user_id: str,
    *,
    password: str,
) -> None:
    user = await session.scalar(
        select(UserAccount)
        .where(UserAccount.id == user_id)
        .with_for_update()
    )
    if user is None or user.password_hash is None:
        raise DeletePasswordError("账号不存在或未设置密码")
    if not await verify_password_async(password, user.password_hash):
        raise DeletePasswordError("密码不正确，无法停用账户")

    # Deactivation is intentionally soft: preserve business data while making
    # every existing token invalid and blocking password authentication.
    user.auth_version += 1
    user.deleted_at = utc_now()
    user.password_hash = None
    await session.flush()
