import asyncio
import os
import socket
from collections.abc import Callable
from datetime import datetime
from uuid import uuid4

from app.config import get_settings
from app.db.base import utc_now
from app.db.session import session_scope
from app.jobs.queue import (
    claim_next_job,
    complete_job,
    fail_job,
    renew_lease,
)
from app.jobs.registry import JobHandlerRegistry


def _worker_owner() -> str:
    return f"{socket.gethostname()}:{os.getpid()}:{uuid4()}"


async def _heartbeat_lease(
    *,
    job_id: str,
    owner: str,
    lease_seconds: int,
    stopped: asyncio.Event,
    clock: Callable[[], datetime],
) -> None:
    interval = max(1.0, lease_seconds / 3)
    while not stopped.is_set():
        try:
            await asyncio.wait_for(stopped.wait(), timeout=interval)
            return
        except TimeoutError:
            async with session_scope() as session:
                renewed = await renew_lease(
                    session,
                    job_id=job_id,
                    owner=owner,
                    now=clock(),
                    lease_seconds=lease_seconds,
                )
            if not renewed:
                return


async def run_worker_once(
    registry: JobHandlerRegistry,
    *,
    owner: str,
    lease_seconds: int,
    now: datetime | None = None,
) -> bool:
    clock = (lambda: now) if now is not None else utc_now
    async with session_scope() as session:
        job = await claim_next_job(
            session,
            owner=owner,
            now=clock(),
            lease_seconds=lease_seconds,
        )
    if job is None:
        return False

    heartbeat_stopped = asyncio.Event()
    heartbeat = asyncio.create_task(
        _heartbeat_lease(
            job_id=job.id,
            owner=owner,
            lease_seconds=lease_seconds,
            stopped=heartbeat_stopped,
            clock=clock,
        )
    )
    try:
        try:
            handler = registry.resolve(job.job_type)
        except KeyError:
            async with session_scope() as session:
                await fail_job(
                    session,
                    job_id=job.id,
                    owner=owner,
                    now=clock(),
                    error_code="unknown_job_type",
                    error_message=job.job_type,
                    retryable=False,
                )
            return True

        try:
            await handler(job)
        except Exception as exc:
            async with session_scope() as session:
                await fail_job(
                    session,
                    job_id=job.id,
                    owner=owner,
                    now=clock(),
                    error_code="handler_error",
                    error_message=type(exc).__name__,
                    retryable=True,
                )
        else:
            async with session_scope() as session:
                await complete_job(
                    session,
                    job_id=job.id,
                    owner=owner,
                    now=clock(),
                )
        return True
    finally:
        heartbeat_stopped.set()
        await heartbeat


async def _wait_for_work_or_stop(
    stop_event: asyncio.Event,
    poll_seconds: float,
) -> None:
    try:
        await asyncio.wait_for(stop_event.wait(), timeout=poll_seconds)
    except TimeoutError:
        pass


async def run_worker(
    registry: JobHandlerRegistry,
    *,
    stop_event: asyncio.Event,
    owner: str | None = None,
) -> None:
    settings = get_settings()
    worker_owner = owner or _worker_owner()
    while not stop_event.is_set():
        handled = await run_worker_once(
            registry,
            owner=worker_owner,
            lease_seconds=settings.job_lease_seconds,
        )
        if not handled:
            await _wait_for_work_or_stop(
                stop_event,
                settings.worker_poll_seconds,
            )
