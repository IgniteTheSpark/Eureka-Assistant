import asyncio

import pytest

from app.domains.notifications.sse import sse_comment, sse_event, with_heartbeats
from app.domains.notifications.subscribers import SubscriberFrame, SubscriberRegistry


async def test_registry_is_user_scoped_and_fans_out():
    registry = SubscriberRegistry(queue_size=1)
    first = registry.subscribe("user-1")
    second = registry.subscribe("user-1")
    foreign = registry.subscribe("user-2")

    assert registry.publish("user-1", {"id": "n1"}) == 0
    assert await first.get() == {"id": "n1"}
    assert await second.get() == {"id": "n1"}
    assert foreign.empty()


def test_unsubscribe_removes_only_requested_queue():
    registry = SubscriberRegistry(queue_size=1)
    removed = registry.subscribe("user-1")
    active = registry.subscribe("user-1")

    registry.unsubscribe("user-1", removed)

    assert registry.publish("user-1", {"id": "n1"}) == 0
    assert removed.empty()
    assert active.get_nowait() == {"id": "n1"}


def test_full_queue_drops_frame_without_raising():
    registry = SubscriberRegistry(queue_size=1)
    queue = registry.subscribe("user-1")
    registry.publish("user-1", {"id": "n1"})

    assert registry.publish("user-1", {"id": "n2"}) == 1
    assert queue.get_nowait() == {"id": "n1"}


def test_full_status_queue_preserves_incoming_confirmed_mutation_signal():
    registry = SubscriberRegistry(queue_size=2)
    queue = registry.subscribe("user-1")
    registry.publish(
        "user-1",
        SubscriberFrame(event="flash_file_status", payload={"status": "running"}),
    )
    registry.publish(
        "user-1",
        SubscriberFrame(event="session_changed", payload={"revision": 1}),
    )

    dropped = registry.publish(
        "user-1",
        SubscriberFrame(
            event="notification",
            payload={"id": "n1", "confirmed_mutation": True},
        ),
    )

    frames = [queue.get_nowait(), queue.get_nowait()]
    assert dropped == 1
    assert any(frame.payload.get("confirmed_mutation") is True for frame in frames)


def test_full_queue_coalesces_confirmed_mutation_without_losing_signal():
    registry = SubscriberRegistry(queue_size=1)
    queue = registry.subscribe("user-1")
    registry.publish(
        "user-1",
        SubscriberFrame(
            event="notification",
            payload={"id": "n1", "confirmed_mutation": True},
        ),
    )

    dropped = registry.publish(
        "user-1",
        SubscriberFrame(
            event="notification",
            payload={"id": "n2", "confirmed_mutation": True},
        ),
    )

    assert dropped == 1
    assert queue.get_nowait().payload["confirmed_mutation"] is True


def test_confirmed_mutation_with_no_subscriber_is_not_buffered_globally():
    registry = SubscriberRegistry(queue_size=1)

    assert registry.publish(
        "user-1",
        SubscriberFrame(
            event="notification",
            payload={"id": "n1", "confirmed_mutation": True},
        ),
    ) == 0
    assert registry.subscribe("user-1").empty()


def test_sse_helpers_encode_utf8_json_and_safe_comments():
    assert sse_event(
        "notification",
        {"title": "报告完成", "body": "first\nsecond"},
    ) == (
        'event: notification\n'
        'data: {"title":"报告完成","body":"first\\nsecond"}\n\n'
    )
    assert sse_comment("heartbeat") == ": heartbeat\n\n"
    assert sse_comment("first\nsecond") == ": first\n: second\n\n"


async def test_with_heartbeats_yields_events_and_closes_subscriber():
    queue = SubscriberRegistry(queue_size=1).subscribe("user-1")
    closed = False

    def close() -> None:
        nonlocal closed
        closed = True

    stream = with_heartbeats(
        queue,
        heartbeat_seconds=0.01,
        on_close=close,
    )
    assert await anext(stream) == ": heartbeat\n\n"

    queue.put_nowait({"id": "n1"})
    assert await anext(stream) == (
        'event: notification\n'
        'data: {"id":"n1"}\n\n'
    )

    await stream.aclose()
    assert closed is True


async def test_with_heartbeats_preserves_cancellation():
    queue = SubscriberRegistry(queue_size=1).subscribe("user-1")
    stream = with_heartbeats(queue, heartbeat_seconds=60)

    with pytest.raises(TimeoutError):
        await asyncio.wait_for(anext(stream), timeout=0.01)

    await stream.aclose()
