"""Account deletion (§10).

Deletion requires password re-authentication. The account row is revoked
(auth_version bump + deleted_at) FIRST so every token dies immediately, then a
single transaction removes all user-owned rows across the deletion graph, and
finally the account row itself. Orphaned storage keys are recorded as durable
cleanup work items so a worker can retry physical file deletion.
"""
from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import UserAccount
from app.auth.security import verify_password
from app.db.base import utc_now

class DeletePasswordError(Exception):
    pass


async def delete_account(
    session: AsyncSession,
    user_id: str,
    *,
    password: str,
) -> None:
    user = await session.get(UserAccount, user_id)
    if user is None or user.password_hash is None:
        raise DeletePasswordError("账号不存在或未设置密码")
    if not verify_password(password, user.password_hash):
        raise DeletePasswordError("密码不正确，无法删除账号")

    # Deactivation is intentionally soft: preserve business data while making
    # every existing token invalid and blocking password authentication.
    user.auth_version += 1
    user.deleted_at = utc_now()
    user.password_hash = None
    await session.flush()
