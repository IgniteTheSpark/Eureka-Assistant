"""Orphaned storage cleanup worker (§10.2).

Consumes `deletion_cleanup_items` and deletes the referenced physical files
under MEDIA_ROOT. Retries on failure; status transitions pending → done/failed.
"""
from __future__ import annotations

import asyncio
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.config import get_settings


async def _delete_file(storage_key: str) -> None:
    """Best-effort local deletion. Resolves the key under MEDIA_ROOT and removes
    the file if present. Remote-storage providers can extend this later."""
    root = Path(get_settings().media_root).resolve()
    # Guard against path traversal: never escape MEDIA_ROOT.
    candidate = (root / storage_key.lstrip("/")).resolve()
    if not candidate.is_relative_to(root):
        raise ValueError("storage key escapes media root")
    if candidate.exists():
        candidate.unlink()


async def _process_one(session: AsyncSession, item_id: str) -> bool:
    row = (
        await session.execute(
            text(
                "SELECT storage_key, source, attempts FROM deletion_cleanup_items "
                "WHERE id = :id AND status = 'pending'"
            ),
            {"id": item_id},
        )
    ).fetchone()
    if row is None:
        return True
    storage_key, source, attempts = row
    try:
        # Only 'file' sources are local MEDIA_ROOT keys (reports storage).
        # capture_files.storage_url may be an S3 key or service reference; the
        # local deletion path does not apply there yet.
        if source == "file":
            await _delete_file(storage_key)
    except Exception:
        attempts += 1
        if attempts >= 5:
            await session.execute(
                text(
                    "UPDATE deletion_cleanup_items SET status='failed', "
                    "attempts=:a, updated_at=UTC_TIMESTAMP(6) WHERE id=:id"
                ),
                {"a": attempts, "id": item_id},
            )
        else:
            await session.execute(
                text(
                    "UPDATE deletion_cleanup_items SET attempts=:a, "
                    "updated_at=UTC_TIMESTAMP(6) WHERE id=:id"
                ),
                {"a": attempts, "id": item_id},
            )
        await session.commit()
        return False
    await session.execute(
        text(
            "UPDATE deletion_cleanup_items SET status='done', "
            "updated_at=UTC_TIMESTAMP(6) WHERE id=:id"
        ),
        {"id": item_id},
    )
    await session.commit()
    return True


async def run_deletion_cleanup_worker(
    session_factory: async_sessionmaker[AsyncSession],
    *,
    poll_seconds: float = 5.0,
) -> None:
    while True:
        try:
            async with session_factory() as session:
                row = (
                    await session.execute(
                        text(
                            "SELECT id FROM deletion_cleanup_items "
                            "WHERE status = 'pending' LIMIT 10"
                        )
                    )
                ).fetchall()
                for (item_id,) in row:
                    await _process_one(session, item_id)
        except Exception:
            pass
        await asyncio.sleep(poll_seconds)
