from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import update
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.session import AsyncSessionFactory
from app.domains.reka.models import Nudge
from app.domains.reka.rhythm import recompute_rhythm_profiles


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class RekaMaintenanceResult:
    profiles_written: int
    expired: int
    recompute_failed: bool


def _db_time(value: datetime) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc).replace(tzinfo=None)


async def expire_stale_nudges(
    session: AsyncSession,
    *,
    now: datetime,
) -> int:
    now_db = _db_time(now)
    result = await session.execute(
        update(Nudge)
        .where(
            Nudge.status.in_(("delivered", "seen")),
            Nudge.expires_at.is_not(None),
            Nudge.expires_at <= now_db,
        )
        .values(status="expired", updated_at=now_db)
    )
    await session.flush()
    return int(result.rowcount or 0)


async def run_reka_maintenance_cycle(
    *,
    now: datetime,
    timezone_name: str,
    recompute_profiles: bool,
) -> RekaMaintenanceResult:
    profiles_written = 0
    recompute_failed = False
    if recompute_profiles:
        try:
            async with AsyncSessionFactory() as session:
                profiles_written = await recompute_rhythm_profiles(
                    session,
                    now=now,
                    timezone_name=timezone_name,
                )
                await session.commit()
        except Exception as exc:
            recompute_failed = True
            logger.warning(
                "Reka Rhythm recompute failed: %s",
                type(exc).__name__,
            )

    async with AsyncSessionFactory() as session:
        expired = await expire_stale_nudges(session, now=now)
        await session.commit()
    return RekaMaintenanceResult(
        profiles_written=profiles_written,
        expired=expired,
        recompute_failed=recompute_failed,
    )


async def run_reka_maintenance_scheduler(
    *,
    stop_event: asyncio.Event,
    interval_seconds: float = 1800,
) -> None:
    timezone_name = get_settings().default_user_timezone
    zone = ZoneInfo(timezone_name)
    last_successful_recompute_day = None
    while not stop_event.is_set():
        now = utc_now()
        aware_now = now.replace(tzinfo=timezone.utc)
        local_day = aware_now.astimezone(zone).date()
        recompute_due = local_day != last_successful_recompute_day
        try:
            result = await run_reka_maintenance_cycle(
                now=now,
                timezone_name=timezone_name,
                recompute_profiles=recompute_due,
            )
            if recompute_due and result is not None and not result.recompute_failed:
                last_successful_recompute_day = local_day
        except Exception as exc:
            logger.error(
                "Reka maintenance cycle failed: %s",
                type(exc).__name__,
            )

        if stop_event.is_set():
            break
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval_seconds)
        except TimeoutError:
            pass
