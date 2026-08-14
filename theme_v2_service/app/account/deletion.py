"""Account deletion (§10).

Deletion requires password re-authentication. The account row is revoked
(auth_version bump + deleted_at) FIRST so every token dies immediately, then a
single transaction removes all user-owned rows across the deletion graph, and
finally the account row itself. Orphaned storage keys are recorded as durable
cleanup work items so a worker can retry physical file deletion.
"""
from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import UserAccount
from app.auth.security import verify_password

# Every table carrying a user_id column in the Theme V2 schema (§10.2), verified
# against the models on 2026-08-13. Order matters: child rows before parents.
# `workflow_jobs` has no user_id — it links to runs via run_id, so it is cleared
# before report_generation_runs (whose rows carry user_id).
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

# workflow_jobs: no user_id column; referenced runs carry user_id.
_WORKFLOW_JOB_TABLE = "workflow_jobs"
# report_generation_runs deleted right after workflow_jobs clears its jobs.
_RUNS_TABLE = "report_generation_runs"

# storage-bearing tables: collect keys into cleanup items before row deletion.
_STORAGE_SOURCES: tuple[tuple[str, str, str], ...] = (
    ("capture_files", "storage_url", "capture"),
    ("files", "storage_key", "file"),
)


class DeletePasswordError(Exception):
    pass


async def _collect_storage_keys(
    session: AsyncSession,
    user_id: str,
) -> None:
    """Record orphaned storage keys as durable cleanup work items (§10.2)."""
    for table, column, source in _STORAGE_SOURCES:
        rows = (
            await session.execute(
                text(f"SELECT {column} FROM {table} WHERE user_id = :uid"),
                {"uid": user_id},
            )
        ).all()
        for (key,) in rows:
            if key:
                await session.execute(
                    text(
                        "INSERT INTO deletion_cleanup_items "
                        "(id, user_id, storage_key, source, status, attempts, created_at) "
                        "VALUES (UUID(), :uid, :key, :src, 'pending', 0, UTC_TIMESTAMP(6))"
                    ),
                    {"uid": user_id, "key": key, "src": source},
                )


async def _clear_workflow_jobs(session: AsyncSession, user_id: str) -> None:
    """workflow_jobs has no user_id; delete jobs whose run belongs to the user."""
    await session.execute(
        text(
            f"DELETE FROM {_WORKFLOW_JOB_TABLE} WHERE run_id IN "
            f"(SELECT id FROM {_RUNS_TABLE} WHERE user_id = :uid)"
        ),
        {"uid": user_id},
    )


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

    # 2. Record storage keys for async physical cleanup.
    await _collect_storage_keys(session, user_id)

    # 3. Clear workflow_jobs (run-linked, no user_id) before its runs.
    await _clear_workflow_jobs(session, user_id)

    # 4. Remove every user-owned row in one transaction.
    for table in DELETION_GRAPH:
        if table == "user_accounts":
            continue
        await session.execute(
            text(f"DELETE FROM {table} WHERE user_id = :uid"),
            {"uid": user_id},
        )

    # 5. Account row last.
    await session.execute(
        text("DELETE FROM user_accounts WHERE id = :uid"),
        {"uid": user_id},
    )
    await session.flush()
