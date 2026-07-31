from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.notifications.schemas import NotificationListResponse
from app.domains.notifications.service import (
    delete_notification,
    list_notifications,
    mark_all_read,
    mark_read,
)


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
