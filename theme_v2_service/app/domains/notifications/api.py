from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.responses import StreamingResponse

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.notifications.schemas import NotificationListResponse
from app.domains.notifications.sse import sse_comment, with_heartbeats
from app.domains.notifications.service import (
    delete_notification,
    list_notifications,
    mark_all_read,
    mark_read,
)
from app.domains.notifications.subscribers import SubscriberRegistry


router = APIRouter(prefix="/api/notifications", tags=["notifications"])


@router.get("", response_model=NotificationListResponse)
async def get_notifications(
    limit: int = Query(default=30, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> NotificationListResponse:
    notifications, unread = await list_notifications(
        session,
        user_id,
        limit=limit,
    )
    return NotificationListResponse(
        notifications=notifications,
        unread=unread,
    )


@router.get("/stream")
async def notification_stream(
    request: Request,
    user_id: str = Depends(get_current_user_id),
) -> StreamingResponse:
    registry: SubscriberRegistry = request.app.state.notification_subscribers
    queue = registry.subscribe(user_id)

    async def frames():
        yield sse_comment("connected")
        heartbeat_stream = with_heartbeats(
            queue,
            on_close=lambda: registry.unsubscribe(user_id, queue),
        )
        try:
            async for frame in heartbeat_stream:
                yield frame
        finally:
            await heartbeat_stream.aclose()

    return StreamingResponse(
        frames(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/read-all")
async def read_all_notifications(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict[str, bool]:
    await mark_all_read(session, user_id)
    return {"ok": True}


@router.post("/{notification_id}/read")
async def read_notification(
    notification_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict[str, bool]:
    await mark_read(session, user_id, notification_id)
    return {"ok": True}


@router.delete("/{notification_id}")
async def remove_notification(
    notification_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict[str, bool]:
    await delete_notification(session, user_id, notification_id)
    return {"ok": True}
