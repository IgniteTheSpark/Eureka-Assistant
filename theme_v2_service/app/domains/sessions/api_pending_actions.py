from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.sessions import pending_actions
from app.domains.sessions.schemas_pending_actions import (
    PendingActionCancel,
    PendingActionResolve,
)


router = APIRouter(prefix="/api/agent-pending-actions", tags=["agent-pending-actions"])


def _http_error(exc: Exception) -> HTTPException:
    if isinstance(exc, pending_actions.PendingActionNotFound):
        return HTTPException(status_code=404, detail=str(exc))
    if isinstance(exc, pending_actions.PendingActionInvalid):
        return HTTPException(status_code=422, detail=str(exc))
    if isinstance(exc, pending_actions.PendingActionConflict):
        return HTTPException(status_code=409, detail=str(exc))
    return HTTPException(status_code=500, detail="pending action failed")


@router.post("/{action_id}/resolve")
async def resolve_pending_action(
    action_id: str,
    command: PendingActionResolve,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_session),
):
    try:
        action = await pending_actions.resolve_contact_pending_action(
            database,
            user_id,
            action_id,
            contact_id=command.contact_id,
            resolution_source=command.resolution_source,
        )
    except Exception as exc:
        raise _http_error(exc) from exc
    return pending_actions.pending_action_payload(action)


@router.post("/{action_id}/cancel")
async def cancel_pending_action(
    action_id: str,
    command: PendingActionCancel,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_session),
):
    try:
        action = await pending_actions.cancel_pending_action(
            database,
            user_id,
            action_id,
            resolution_source=command.resolution_source,
        )
    except Exception as exc:
        raise _http_error(exc) from exc
    return pending_actions.pending_action_payload(action)
