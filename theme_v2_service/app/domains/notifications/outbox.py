import asyncio
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db.base import utc_now
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.notifications.schemas import NotificationPayload
from app.domains.notifications.subscribers import (
    SubscriberFrame,
    SubscriberRegistry,
)


async def dispatch_one(
    session_factory: async_sessionmaker[AsyncSession],
    registry: SubscriberRegistry,
    *,
    now: datetime,
) -> bool:
    async with session_factory() as session:
        event = await session.scalar(
            select(OutboxEvent)
            .where(
                OutboxEvent.published_at.is_(None),
                OutboxEvent.available_at <= now,
            )
            .order_by(OutboxEvent.created_at, OutboxEvent.id)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if event is None:
            return False

        event_id = event.id
        try:
            if event.aggregate_type == "notification":
                notification = await session.get(Notification, event.aggregate_id)
                if notification is not None:
                    payload = NotificationPayload.model_validate(
                        notification
                    ).model_dump(mode="json")
                    registry.publish(
                        notification.user_id,
                        SubscriberFrame(event="notification", payload=payload),
                    )
            else:
                registry.publish(
                    event.user_id,
                    SubscriberFrame(
                        event=event.event_type,
                        payload=event.payload_json,
                    ),
                )
            event.published_at = now
            event.last_error = None
            await session.commit()
        except Exception as exc:
            await session.rollback()
            failed_event = await session.get(
                OutboxEvent,
                event_id,
                with_for_update=True,
            )
            if failed_event is not None and failed_event.published_at is None:
                failed_event.attempt += 1
                delay_seconds = min(2 ** min(failed_event.attempt, 6), 60)
                failed_event.available_at = now + timedelta(seconds=delay_seconds)
                failed_event.last_error = type(exc).__name__
                await session.commit()
        return True


async def run_outbox_dispatcher(
    session_factory: async_sessionmaker[AsyncSession],
    registry: SubscriberRegistry,
    *,
    poll_seconds: float = 0.5,
) -> None:
    while True:
        try:
            handled = await dispatch_one(
                session_factory,
                registry,
                now=utc_now(),
            )
        except Exception:
            handled = False

        if not handled:
            await asyncio.sleep(poll_seconds)
