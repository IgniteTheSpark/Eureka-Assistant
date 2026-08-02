import asyncio
import json
from collections.abc import AsyncIterator, Callable

from app.domains.notifications.subscribers import (
    NotificationFrame,
    SubscriberFrame,
    SubscriberQueue,
)


def sse_event(event: str, payload: NotificationFrame) -> str:
    if "\n" in event or "\r" in event:
        raise ValueError("SSE event name cannot contain a newline")
    data = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    )
    return f"event: {event}\ndata: {data}\n\n"


def sse_comment(comment: str) -> str:
    lines = comment.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    return "".join(f": {line}\n" for line in lines) + "\n"


async def with_heartbeats(
    queue: SubscriberQueue,
    *,
    heartbeat_seconds: float = 15,
    on_close: Callable[[], None] | None = None,
) -> AsyncIterator[str]:
    try:
        while True:
            try:
                frame = await asyncio.wait_for(
                    queue.get(),
                    timeout=heartbeat_seconds,
                )
            except TimeoutError:
                yield sse_comment("heartbeat")
            else:
                if isinstance(frame, SubscriberFrame):
                    yield sse_event(frame.event, frame.payload)
                else:
                    yield sse_event("notification", frame)
    finally:
        if on_close is not None:
            on_close()
