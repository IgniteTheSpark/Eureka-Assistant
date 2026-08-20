import asyncio
import logging

from app.auth.challenges import cleanup_expired
from app.db.session import AsyncSessionFactory


_SCHEDULER_INTERVAL_SECONDS = 24 * 60 * 60
logger = logging.getLogger(__name__)


async def run_challenge_cleanup_scheduler(
    *,
    stop_event: asyncio.Event,
    interval_seconds: float = _SCHEDULER_INTERVAL_SECONDS,
) -> None:
    while not stop_event.is_set():
        try:
            async with AsyncSessionFactory() as session:
                await cleanup_expired(session)
                await session.commit()
        except Exception:
            logger.exception("failed to clean up email challenges")

        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval_seconds)
        except TimeoutError:
            pass
