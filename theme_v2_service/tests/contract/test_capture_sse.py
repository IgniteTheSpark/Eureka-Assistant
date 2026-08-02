from datetime import datetime

from sqlalchemy import select

from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import OutboxEvent
from app.domains.notifications.outbox import dispatch_one
from app.domains.notifications.service import publish_domain_event
from app.domains.notifications.sse import with_heartbeats
from app.domains.notifications.subscribers import (
    SubscriberFrame,
    SubscriberRegistry,
)


NOW = datetime(2026, 8, 2, 8, 0, 0)
USER_ID = "00000000-0000-0000-0000-000000000010"
RECORDING_ID = "00000000-0000-0000-0000-000000000020"


async def test_generic_outbox_frame_preserves_capture_event_name(session):
    registry = SubscriberRegistry()
    queue = registry.subscribe(USER_ID)
    async with AsyncSessionFactory() as producer:
        await publish_domain_event(
            producer,
            event_type="flash_file_status",
            aggregate_type="capture_recording",
            aggregate_id=RECORDING_ID,
            user_id=USER_ID,
            payload={"recording_id": RECORDING_ID, "status": "asr_done"},
        )
        event = await producer.scalar(select(OutboxEvent))
        event.available_at = NOW
        await producer.commit()

    assert await dispatch_one(AsyncSessionFactory, registry, now=NOW)
    frame = queue.get_nowait()
    assert isinstance(frame, SubscriberFrame)
    assert frame.event == "flash_file_status"
    assert frame.payload == {
        "recording_id": RECORDING_ID,
        "status": "asr_done",
    }


async def test_capture_frame_uses_its_event_name_in_sse():
    registry = SubscriberRegistry()
    queue = registry.subscribe(USER_ID)
    registry.publish(
        USER_ID,
        SubscriberFrame(
            event="flash_file_status",
            payload={"recording_id": RECORDING_ID, "status": "done"},
        ),
    )
    stream = with_heartbeats(queue, heartbeat_seconds=60)

    assert await anext(stream) == (
        "event: flash_file_status\n"
        f'data: {{"recording_id":"{RECORDING_ID}","status":"done"}}\n\n'
    )
    await stream.aclose()
