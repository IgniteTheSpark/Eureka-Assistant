"""Cross-worker serialization for destructive and content-writing operations."""

from __future__ import annotations

import asyncio
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


async def _release_lock(connection, lock_name: str) -> None:
    """Release the named lock or discard a connection that may still own it."""
    try:
        await connection.scalar(
            text("SELECT RELEASE_LOCK(:lock_name)"),
            {"lock_name": lock_name},
        )
    except BaseException:
        # Named locks survive transaction rollback. Never return a connection
        # with uncertain lock ownership to the pool.
        await connection.invalidate()


async def _release_lock_cancellation_safe(connection, lock_name: str) -> None:
    cleanup = asyncio.create_task(_release_lock(connection, lock_name))
    try:
        await asyncio.shield(cleanup)
    except asyncio.CancelledError:
        # Preserve caller cancellation, but only after the independent cleanup
        # task has released the lock or invalidated its physical connection.
        await cleanup
        raise


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
            await _release_lock_cancellation_safe(connection, lock_name)
