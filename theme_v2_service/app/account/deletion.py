"""Account deletion (§10).

Deletion requires password re-authentication. The account row is revoked
(auth_version bump + deleted_at) FIRST so every token dies immediately, then a
single transaction removes all user-owned rows across the deletion graph, and
finally the account row itself. Storage cleanup is out of scope for M3.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import UserAccount
from app.auth.security import verify_password

# Every table carrying a user_id column in the Theme V2 schema (§10.2), verified
# against the models on 2026-08-13. The order matters: user_skills last among
# children so FK-referencing rows are gone first; user_accounts is removed last.
DELETION_GRAPH: tuple[str, ...] = (
    "agent_pending_actions",
    "agent_tool_executions",
    "asset_fields",
    "assets",
    "capture_files",
    "capture_recordings",
    "capture_turns",
    "card_bindings",
    "flash_chat_messages",
    "files",
    "input_turns",
    "notifications",
    "nudges",
    "onboarding_asset_results",
    "outbox_events",
    "report_generation_runs",
    "report_shares",
    "reports",
    "rhythm_profiles",
    "session_messages",
    "trigger_executions",
    "trigger_trackers",
    "chat_sessions",
    "events",
    "contacts",
    "user_skills",
    "user_accounts",
)


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

    # 1. Revoke all tokens immediately (§10.2): bump auth_version + tombstone.
    user.auth_version += 1
    user.deleted_at = user.created_at
    await session.flush()

    # 2. Remove every user-owned row in one transaction.
    for table in DELETION_GRAPH:
        if table == "user_accounts":
            continue
        await session.execute(
            text(f"DELETE FROM {table} WHERE user_id = :uid"),
            {"uid": user_id},
        )

    # 3. Account row last.
    await session.execute(
        text("DELETE FROM user_accounts WHERE id = :uid"),
        {"uid": user_id},
    )
    await session.flush()
