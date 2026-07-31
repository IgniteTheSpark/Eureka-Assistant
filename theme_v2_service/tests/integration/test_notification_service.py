from sqlalchemy import func, select

from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification


async def test_notification_and_outbox_commit_together(session):
    notification = await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="report_done",
            title="报告已生成",
            link="report:r1",
        ),
    )
    await session.commit()

    events = list(await session.scalars(select(OutboxEvent)))
    assert len(events) == 1
    assert events[0].aggregate_id == notification.id
    assert events[0].event_type == "notification.created"
    assert events[0].payload_json == {"notification_id": notification.id}


async def test_rollback_removes_notification_and_outbox(session):
    await create_notification(
        session,
        NotificationCreate(
            user_id="user-1",
            type="report_done",
            title="不会提交",
        ),
    )

    await session.rollback()

    notification_count = await session.scalar(
        select(func.count()).select_from(Notification)
    )
    outbox_count = await session.scalar(select(func.count()).select_from(OutboxEvent))
    assert notification_count == 0
    assert outbox_count == 0
