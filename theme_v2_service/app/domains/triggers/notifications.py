from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.notifications.models import Notification
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.triggers.models import TriggerExecution, TriggerTracker


async def ensure_report_available_notification(
    session: AsyncSession,
    *,
    execution: TriggerExecution,
    title: str,
    body: str,
    now: datetime,
    tracker: TriggerTracker | None = None,
    local_date: date | None = None,
) -> bool:
    link = f"report-start:{execution.id}:{execution.revision}"
    existing = await session.scalar(
        select(Notification.id).where(
            Notification.user_id == execution.user_id,
            Notification.type == "report_available",
            Notification.link == link,
        )
    )
    created = existing is None
    if created:
        await create_notification(
            session,
            NotificationCreate(
                user_id=execution.user_id,
                type="report_available",
                title=title,
                body=body,
                link=link,
            ),
        )

    if tracker is not None:
        tracker.last_notified_at = now
        tracker.last_notified_local_date = local_date
    execution.last_notified_revision = execution.revision
    await session.flush()
    return created
