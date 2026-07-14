"""Cross-worker serialization for destructive and content-writing operations."""

from __future__ import annotations

import hashlib
from contextlib import asynccontextmanager

from sqlalchemy import text

from db.database import async_engine


class WorkspaceOperationInProgress(RuntimeError):
    """Raised when another operation already owns a user's workspace lock."""


def _lock_name(user_id: str) -> str:
    # MySQL lock names are limited to 64 characters. Hashing also prevents a
    # user-controlled identifier from creating ambiguous lock namespaces.
    digest = hashlib.sha256(user_id.encode("utf-8")).hexdigest()[:47]
    return f"eureka:workspace:{digest}"


@asynccontextmanager
async def user_workspace_operation(user_id: str):
    """Acquire one connection-scoped MySQL named lock without waiting.

    The dedicated connection stays checked out for the whole operation because
    ``GET_LOCK`` ownership belongs to the MySQL connection, not a transaction.
    This makes the lock effective across asyncio tasks and backend workers that
    share the database while keeping Reset/Flash conflict behavior predictable.
    """
    lock_name = _lock_name(user_id)
    async with async_engine.connect() as connection:
        acquired = await connection.scalar(
            text("SELECT GET_LOCK(:lock_name, 0)"),
            {"lock_name": lock_name},
        )
        if acquired != 1:
            raise WorkspaceOperationInProgress(
                "workspace operation in progress"
            )
        try:
            yield
        finally:
            await connection.scalar(
                text("SELECT RELEASE_LOCK(:lock_name)"),
                {"lock_name": lock_name},
            )
