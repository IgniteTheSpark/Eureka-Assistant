from __future__ import annotations

import asyncio
import logging
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.session import AsyncSessionFactory
from app.domains.reminders.service import dispatch_due_reminders


logger = logging.getLogger(__name__)


async def run_reminder_maintenance(
    session: AsyncSession,
    *,
    now: datetime,
    timezone_name: str,
) -> int:
    return await dispatch_due_reminders(
        session,
        now=now,
        timezone_name=timezone_name,
    )


async def run_reminder_maintenance_scheduler(
    *,
    stop_event: asyncio.Event,
    interval_seconds: float = 60,
) -> None:
    timezone_name = get_settings().default_user_timezone
    while not stop_event.is_set():
        try:
            async with AsyncSessionFactory() as session:
                await run_reminder_maintenance(
                    session,
                    now=utc_now(),
                    timezone_name=timezone_name,
                )
                await session.commit()
        except Exception as exc:
            logger.error("reminder maintenance failed: %s", type(exc).__name__)

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval_seconds)
        except TimeoutError:
            pass
