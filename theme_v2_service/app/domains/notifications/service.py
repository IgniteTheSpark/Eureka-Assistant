from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.notifications.schemas import NotificationCreate


async def create_notification(
    session: AsyncSession,
    command: NotificationCreate,
) -> Notification:
    notification = Notification(
        user_id=command.user_id,
        type=command.type,
        title=command.title[:255],
        body=command.body,
        link=command.link,
    )
    session.add(notification)
    await session.flush()

    session.add(
        OutboxEvent(
            event_type="notification.created",
            aggregate_type="notification",
            aggregate_id=notification.id,
            user_id=notification.user_id,
            payload_json={"notification_id": notification.id},
        )
    )
    await session.flush()
    return notification
