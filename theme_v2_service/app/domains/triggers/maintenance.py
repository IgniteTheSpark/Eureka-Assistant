import asyncio
import logging
from dataclasses import dataclass
from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.base import utc_now
from app.db.session import AsyncSessionFactory
from app.domains.triggers.models import TriggerExecution, TriggerTracker
from app.domains.triggers.notifications import ensure_report_available_notification
from app.domains.triggers.pre_event_report import (
    expire_stale_pre_event_executions,
    scan_pre_event_window,
)


logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class TriggerMaintenanceResult:
    expired: int
    fired: int
    notifications_repaired: int
    trackers_repaired: int


def _local_date(now: datetime, timezone_name: str) -> date:
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)
    return now.astimezone(ZoneInfo(timezone_name)).date()


def _is_blocked(tracker: TriggerTracker, now: datetime) -> bool:
    return bool(
        tracker.dismissed_until is not None and now < tracker.dismissed_until
    ) or bool(
        tracker.proactive_suppressed_until is not None
        and now < tracker.proactive_suppressed_until
    )


async def repair_missing_notifications(
    session: AsyncSession,
    *,
    now: datetime,
) -> int:
    executions = list(
        await session.scalars(
            select(TriggerExecution)
            .where(TriggerExecution.status == "available")
            .order_by(TriggerExecution.id)
            .with_for_update(skip_locked=True)
            .limit(100)
        )
    )
    repaired = 0
    timezone_name = get_settings().default_user_timezone
    today = _local_date(now, timezone_name)
    for execution in executions:
        if (
            execution.last_notified_revision is not None
            and execution.last_notified_revision >= execution.revision
        ):
            continue

        tracker = None
        notification_date = None
        if execution.trigger_type == "proactive_summary":
            if execution.tracker_id is None:
                continue
            tracker = await session.get(
                TriggerTracker,
                execution.tracker_id,
                with_for_update=True,
            )
            if (
                tracker is None
                or _is_blocked(tracker, now)
                or tracker.last_notified_local_date == today
            ):
                continue
            notification_date = today
            count = int(execution.payload_json.get("asset_count", 0))
            title = f"已经积累了 {count} 条记录，可以生成报告了"
            body = (
                f"{execution.payload_json.get('scope_started_at', '')}"
                f"—{execution.payload_json.get('scope_ended_at', '')}"
            )
        elif execution.trigger_type == "pre_event_report":
            title = f"“{execution.payload_json.get('event_title', '日程')}”将在 1 小时后开始"
            body = "需要准备一份会前调研吗？"
        else:
            continue

        await ensure_report_available_notification(
            session,
            execution=execution,
            tracker=tracker,
            title=title,
            body=body,
            now=now,
            local_date=notification_date,
        )
        repaired += 1
    return repaired


async def repair_tracker_references(
    session: AsyncSession,
    *,
    now: datetime,
) -> int:
    del now
    trackers = list(
        await session.scalars(
            select(TriggerTracker)
            .where(TriggerTracker.active_execution_id.is_not(None))
            .order_by(TriggerTracker.id)
            .with_for_update(skip_locked=True)
            .limit(100)
        )
    )
    repaired = 0
    for tracker in trackers:
        execution = await session.get(
            TriggerExecution,
            tracker.active_execution_id,
            with_for_update=True,
        )
        if (
            execution is None
            or execution.status != "available"
            or execution.tracker_id != tracker.id
            or execution.user_id != tracker.user_id
        ):
            tracker.active_execution_id = None
            repaired += 1
    await session.flush()
    return repaired


async def run_trigger_maintenance(
    session: AsyncSession,
    *,
    now: datetime,
) -> TriggerMaintenanceResult:
    expired = await expire_stale_pre_event_executions(session, now=now)
    fired = await scan_pre_event_window(session, now=now)
    repaired = await repair_missing_notifications(session, now=now)
    trackers = await repair_tracker_references(session, now=now)
    return TriggerMaintenanceResult(
        expired=expired,
        fired=fired,
        notifications_repaired=repaired,
        trackers_repaired=trackers,
    )


async def run_trigger_maintenance_scheduler(
    *,
    stop_event: asyncio.Event,
    interval_seconds: float = 60,
) -> None:
    while not stop_event.is_set():
        try:
            async with AsyncSessionFactory() as session:
                await run_trigger_maintenance(session, now=utc_now())
                await session.commit()
        except Exception as exc:
            logger.error(
                "trigger maintenance failed: %s",
                type(exc).__name__,
            )

        try:
            await asyncio.wait_for(
                stop_event.wait(),
                timeout=interval_seconds,
            )
        except TimeoutError:
            pass
