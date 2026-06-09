"""§1.5.1.3 batch A — in-memory live view for durable chat turns.

The work of a chat turn (running the agent + persisting the result) lives in a
background task that OWNS the turn — it survives the client disconnecting. The
SSE connection is just a *view* onto that task: it subscribes to this per-turn
channel and forwards events (token / tool_call / tool_result / usage) to the
client as they happen. If the client never connects, or disconnects midway, the
background task keeps publishing here (non-blocking; events are dropped if no one
drains) and still finalizes the turn in the DB. A returning client doesn't
re-stream — it reconciles via the persisted message `status` (running → done).

This mirrors core/notifications.py's _subscribers pattern, scoped per turn_id
(the agent message id) instead of per user.
"""
import asyncio
from typing import Optional

# turn_id (agent message id) → channel. Created when the turn starts, removed a
# short grace period after it finishes (so a slightly-late viewer still drains
# the tail + sees the sentinel).
_channels: dict[str, "TurnChannel"] = {}

# Sentinel pushed when the turn is fully done (after persistence). A viewer that
# sees this stops forwarding and closes its SSE.
DONE = object()


class TurnChannel:
    """A single in-flight turn's live event buffer. One producer (the background
    task), zero-or-one consumer (the SSE viewer)."""

    def __init__(self) -> None:
        # Bounded so a producer never blocks / leaks memory when nobody drains.
        self.q: "asyncio.Queue" = asyncio.Queue(maxsize=512)
        self.finished = False

    def publish(self, event) -> None:
        """Non-blocking. Drops the event if the buffer is full (live view only —
        the DB persistence is the source of truth, never this queue)."""
        try:
            self.q.put_nowait(event)
        except asyncio.QueueFull:
            pass


def open_channel(turn_id: str) -> TurnChannel:
    ch = TurnChannel()
    _channels[turn_id] = ch
    return ch


def get_channel(turn_id: str) -> Optional[TurnChannel]:
    return _channels.get(turn_id)


def publish(turn_id: str, event) -> None:
    ch = _channels.get(turn_id)
    if ch is not None:
        ch.publish(event)


async def close(turn_id: str, grace_seconds: float = 30.0) -> None:
    """Signal end-of-turn to any live viewer, then drop the channel after a grace
    period (lets a viewer drain the tail). Safe to call once per turn."""
    ch = _channels.get(turn_id)
    if ch is None:
        return
    ch.finished = True
    ch.publish(DONE)
    await asyncio.sleep(grace_seconds)
    _channels.pop(turn_id, None)
