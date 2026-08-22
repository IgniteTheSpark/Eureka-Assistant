from datetime import datetime, timedelta

from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.notifications.schemas import NotificationCreate


async def publish_domain_event(
    session: AsyncSession,
    *,
    event_type: str,
    aggregate_type: str,
    aggregate_id: str,
    user_id: str,
    payload: dict,
) -> OutboxEvent:
    event = OutboxEvent(
        event_type=event_type,
        aggregate_type=aggregate_type,
        aggregate_id=aggregate_id,
        user_id=user_id,
        payload_json=payload,
    )
    session.add(event)
    await session.flush()
    return event


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

    outbox_payload: dict = {"notification_id": notification.id}
    if command.confirmed_mutation:
        outbox_payload["confirmed_mutation"] = True
    await publish_domain_event(
        session,
        event_type="notification.created",
        aggregate_type="notification",
        aggregate_id=notification.id,
        user_id=notification.user_id,
        payload=outbox_payload,
    )
    return notification


async def list_notifications(
    session: AsyncSession,
    user_id: str,
    *,
    limit: int = 30,
) -> tuple[list[Notification], int]:
    bounded_limit = max(1, min(limit, 100))
    result = await session.scalars(
        select(Notification)
        .where(Notification.user_id == user_id)
        .order_by(Notification.created_at.desc(), Notification.id.desc())
        .limit(bounded_limit)
    )
    unread = await session.scalar(
        select(func.count())
        .select_from(Notification)
        .where(
            Notification.user_id == user_id,
            Notification.read.is_(False),
        )
    )
    return list(result), int(unread or 0)


async def mark_read(
    session: AsyncSession,
    user_id: str,
    notification_id: str,
) -> bool:
    notification = await session.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
        )
    )
    if notification is None:
        return False
    notification.read = True
    await session.flush()
    return True


async def mark_all_read(session: AsyncSession, user_id: str) -> int:
    result = await session.execute(
        update(Notification)
        .where(
            Notification.user_id == user_id,
            Notification.read.is_(False),
        )
        .values(read=True)
    )
    return int(result.rowcount or 0)


async def delete_notification(
    session: AsyncSession,
    user_id: str,
    notification_id: str,
) -> bool:
    notification = await session.scalar(
        select(Notification).where(
            Notification.id == notification_id,
            Notification.user_id == user_id,
        )
    )
    if notification is None:
        return False
    await session.delete(notification)
    await session.flush()
    return True


async def prune_notifications(
    session: AsyncSession,
    *,
    now: datetime,
) -> int:
    cutoff = now - timedelta(days=14)
    result = await session.execute(
        delete(Notification).where(Notification.created_at < cutoff)
    )
    return int(result.rowcount or 0)
