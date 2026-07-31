from datetime import datetime, timedelta

from sqlalchemy import select

from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.notifications.outbox import dispatch_one
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.notifications.subscribers import SubscriberRegistry


NOW = datetime(2026, 7, 31, 10, 0, 0)


async def _create_committed(*, user_id: str, title: str = "Report ready") -> str:
    async with AsyncSessionFactory() as session:
        notification = await create_notification(
            session,
            NotificationCreate(
                user_id=user_id,
                type="report_done",
                title=title,
                body="Open the report",
                link="/reports/run-1",
            ),
        )
        notification.created_at = NOW
        event = await session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_id == notification.id
            )
        )
        event.created_at = NOW
        event.available_at = NOW
        await session.commit()
        return notification.id


async def test_uncommitted_outbox_is_not_visible(session):
    registry = SubscriberRegistry()
    queue = registry.subscribe("user-1")
    async with AsyncSessionFactory() as producer:
        notification = await create_notification(
            producer,
            NotificationCreate(
                user_id="user-1",
                type="report_done",
                title="not committed",
            ),
        )
        event = await producer.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_id == notification.id
            )
        )
        event.available_at = NOW
        await producer.flush()

        assert not await dispatch_one(
            AsyncSessionFactory,
            registry,
            now=NOW,
        )
        assert queue.empty()
        await producer.rollback()


async def test_committed_outbox_routes_to_matching_user(session):
    notification_id = await _create_committed(user_id="user-1")
    registry = SubscriberRegistry()
    matching = registry.subscribe("user-1")
    foreign = registry.subscribe("user-2")

    assert await dispatch_one(AsyncSessionFactory, registry, now=NOW)

    assert await matching.get() == {
        "id": notification_id,
        "type": "report_done",
        "title": "Report ready",
        "body": "Open the report",
        "link": "/reports/run-1",
        "read": False,
        "created_at": "2026-07-31T10:00:00Z",
    }
    assert foreign.empty()
    async with AsyncSessionFactory() as check:
        event = await check.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_id == notification_id
            )
        )
        assert event.published_at == NOW
        assert event.last_error is None


async def test_missing_notification_marks_outbox_published(session):
    notification_id = await _create_committed(user_id="user-1")
    registry = SubscriberRegistry()
    queue = registry.subscribe("user-1")
    async with AsyncSessionFactory() as database_session:
        notification = await database_session.get(Notification, notification_id)
        await database_session.delete(notification)
        await database_session.commit()

    assert await dispatch_one(AsyncSessionFactory, registry, now=NOW)

    assert queue.empty()
    async with AsyncSessionFactory() as check:
        event = await check.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_id == notification_id
            )
        )
        assert event.published_at == NOW


async def test_failure_after_publish_can_duplicate_same_notification(session):
    notification_id = await _create_committed(user_id="user-1")

    class FailOnceAfterPublishRegistry(SubscriberRegistry):
        failed = False

        def publish(self, user_id, payload):
            dropped = super().publish(user_id, payload)
            if not self.failed:
                self.failed = True
                raise RuntimeError("private notification content")
            return dropped

    registry = FailOnceAfterPublishRegistry()
    queue = registry.subscribe("user-1")

    assert await dispatch_one(AsyncSessionFactory, registry, now=NOW)
    async with AsyncSessionFactory() as check:
        event = await check.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_id == notification_id
            )
        )
        assert event.published_at is None
        assert event.attempt == 1
        assert event.last_error == "RuntimeError"
        assert NOW < event.available_at <= NOW + timedelta(seconds=60)
        retry_at = event.available_at

    assert await dispatch_one(AsyncSessionFactory, registry, now=retry_at)

    first = await queue.get()
    second = await queue.get()
    assert first["id"] == notification_id
    assert second["id"] == notification_id
    async with AsyncSessionFactory() as check:
        event = await check.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_id == notification_id
            )
        )
        assert event.published_at == retry_at
        assert event.last_error is None
