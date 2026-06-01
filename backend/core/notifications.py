"""
core/notifications — Phase D M6.

A tiny in-process pub/sub plus a `create_notification` helper. Completion
hooks (flash done, task done/failed, reminders) call `create_notification`,
which (1) persists a Notification row and (2) fans the serialized payload out
to any live SSE subscriber (`/api/notifications/stream`).

Single-process uvicorn (the MVP deploy) means a module-level registry of
per-connection asyncio.Queues is sufficient — no Redis/broker needed. If we
ever run multiple workers, swap `_publish` for a Postgres LISTEN/NOTIFY or
Redis fan-out; the call sites won't change.
"""
import asyncio
from typing import Optional

from db.database import AsyncSessionLocal
from db.models import Notification

# user_id → set of subscriber queues (one per open SSE connection)
_subscribers: dict[str, set["asyncio.Queue[dict]"]] = {}


def subscribe(user_id: str) -> "asyncio.Queue[dict]":
    q: "asyncio.Queue[dict]" = asyncio.Queue(maxsize=100)
    _subscribers.setdefault(user_id, set()).add(q)
    return q


def unsubscribe(user_id: str, q: "asyncio.Queue[dict]") -> None:
    subs = _subscribers.get(user_id)
    if subs:
        subs.discard(q)
        if not subs:
            _subscribers.pop(user_id, None)


def _publish(user_id: str, payload: dict) -> None:
    for q in list(_subscribers.get(user_id, ())):
        try:
            q.put_nowait(payload)
        except asyncio.QueueFull:
            # Slow consumer — drop the realtime push; the row is still in the
            # DB and will appear on the next list fetch / reconnect.
            pass


def publish_event(user_id: str, event: str, **data) -> None:
    """
    Push a non-notification app event over the SAME SSE channel the
    notifications stream uses. The frontend's single EventSource dispatches
    by event name. Used for ephemeral, un-persisted signals like the flash
    "listening" state — no DB row, just a live nudge to the UI.

    The stream tags each frame with the `_event` key (see api/notifications
    stream). Notifications omit it and default to event name "notification".
    """
    _publish(user_id, {"_event": event, **data})


def serialize(n: Notification) -> dict:
    return {
        "id":         str(n.id),
        "type":       n.type,
        "title":      n.title,
        "body":       n.body or "",
        "link":       n.link,
        "read":       bool(n.read),
        "created_at": n.created_at.isoformat() if n.created_at else None,
    }


async def create_notification(
    *,
    user_id: str,
    type: str,
    title: str,
    body: str = "",
    link: Optional[str] = None,
) -> dict:
    """
    Persist a notification (own session, own commit — decoupled from any
    caller transaction so completion hooks can fire it after their own
    commits without ordering hazards) and push it to live subscribers.

    Returns the serialized payload. Never raises into the caller: a logging
    failure must not break flash/task completion.
    """
    try:
        async with AsyncSessionLocal() as db:
            n = Notification(user_id=user_id, type=type, title=title[:255], body=body, link=link)
            db.add(n)
            await db.commit()
            await db.refresh(n)
        payload = serialize(n)
        _publish(user_id, payload)
        return payload
    except Exception:
        return {}
