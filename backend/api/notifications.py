"""
/api/notifications — Phase D M6.

  GET    /api/notifications            — list newest N + unread count
  POST   /api/notifications/{id}/read  — mark one read
  POST   /api/notifications/read-all   — mark all read
  DELETE /api/notifications/{id}       — dismiss (delete) one
  GET    /api/notifications/stream     — SSE; pushes new notifications live

Notifications are created by completion hooks via core.notifications.create_notification
(flash done, async task done/failed) and, in M7, by the reminder scheduler.
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import func, select, update

from core.auth import get_current_user_id
from core.notifications import serialize, subscribe, unsubscribe
from core.streaming import sse_comment, sse_event, with_heartbeats
from db.database import AsyncSessionLocal
from db.models import Notification

router = APIRouter()


@router.get("/notifications")
async def list_notifications(
    limit:   int = Query(30, le=100),
    user_id: str = Depends(get_current_user_id),
):
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc())
            .limit(limit)
        )).scalars().all()
        unread = (await db.execute(
            select(func.count())
            .select_from(Notification)
            .where(Notification.user_id == user_id, Notification.read == 0)
        )).scalar_one()
    return {
        "ok":            True,
        "notifications": [serialize(n) for n in rows],
        "unread":        int(unread),
    }


@router.post("/notifications/{notif_id}/read")
async def mark_read(notif_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        nid = uuid.UUID(notif_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid notification id")
    async with AsyncSessionLocal() as db:
        await db.execute(
            update(Notification)
            .where(Notification.id == nid, Notification.user_id == user_id)
            .values(read=1)
        )
        await db.commit()
    return {"ok": True}


@router.post("/notifications/read-all")
async def mark_all_read(user_id: str = Depends(get_current_user_id)):
    async with AsyncSessionLocal() as db:
        await db.execute(
            update(Notification)
            .where(Notification.user_id == user_id, Notification.read == 0)
            .values(read=1)
        )
        await db.commit()
    return {"ok": True}


@router.delete("/notifications/{notif_id}")
async def dismiss(notif_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        nid = uuid.UUID(notif_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid notification id")
    async with AsyncSessionLocal() as db:
        n = (await db.execute(
            select(Notification).where(Notification.id == nid, Notification.user_id == user_id)
        )).scalar_one_or_none()
        if n is not None:
            await db.delete(n)
            await db.commit()
    return {"ok": True}


@router.get("/notifications/stream")
async def stream(user_id: str = Depends(get_current_user_id)):
    """SSE — emits one `notification` event per newly-created notification."""
    async def gen():
        q = subscribe(user_id)
        try:
            yield sse_comment("connected")
            while True:
                payload = await q.get()
                # Generic routing: payloads may carry an `_event` name (e.g.
                # "listening") for non-notification app signals. Plain
                # notification rows have no `_event` → default "notification".
                if isinstance(payload, dict) and "_event" in payload:
                    payload = dict(payload)
                    event = payload.pop("_event")
                else:
                    event = "notification"
                yield sse_event(event, payload)
        finally:
            unsubscribe(user_id, q)

    return StreamingResponse(
        with_heartbeats(gen()),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
