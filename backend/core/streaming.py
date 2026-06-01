"""
SSE (Server-Sent Events) utilities — Phase B Step 3 (decision #6).

Used by /api/chat and /api/flash to stream agent output to the frontend.
Frontend uses native EventSource; auto-reconnects on disconnect.

Format reference:
  https://html.spec.whatwg.org/multipage/server-sent-events.html

Each event is shaped:
    event: <event_name>\\n
    data: <json>\\n
    \\n
"""
import asyncio
import json
from typing import Any, AsyncIterator


def sse_event(event: str, data: Any) -> str:
    """
    Format a single SSE event. Yield the returned string into a FastAPI
    StreamingResponse with media_type='text/event-stream'.

    `data` is JSON-encoded (ensure_ascii=False, so 中文 stays readable).
    """
    payload = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata: {payload}\n\n"


def sse_comment(text: str = "ping") -> str:
    """
    SSE comment line. Browsers ignore; used as keep-alive heartbeat to
    prevent proxies / load balancers from idle-disconnecting the stream.
    """
    return f": {text}\n\n"


async def with_heartbeats(
    stream: AsyncIterator[str],
    interval_seconds: int = 15,
) -> AsyncIterator[str]:
    """
    Wrap an SSE stream and interleave heartbeats when idle for >interval.

    Useful when the agent might think for a long time before emitting any
    tokens. Without heartbeats, idle proxies (Cloud Run, nginx default 60s)
    will close the connection.

    Implementation: an asyncio.Queue mediates between the feeder coroutine
    (which reads from the source stream) and the consumer (which yields
    events with timeout-based heartbeats).
    """
    queue: asyncio.Queue = asyncio.Queue()
    sentinel = object()
    feeder_error: list = []

    async def feeder():
        try:
            async for chunk in stream:
                await queue.put(chunk)
        except Exception as exc:
            feeder_error.append(exc)
        finally:
            await queue.put(sentinel)

    feed_task = asyncio.create_task(feeder())

    try:
        while True:
            try:
                item = await asyncio.wait_for(queue.get(), timeout=interval_seconds)
            except asyncio.TimeoutError:
                yield sse_comment("ping")
                continue
            if item is sentinel:
                if feeder_error:
                    raise feeder_error[0]
                break
            yield item
    finally:
        if not feed_task.done():
            feed_task.cancel()
            try:
                await feed_task
            except (asyncio.CancelledError, Exception):
                pass
