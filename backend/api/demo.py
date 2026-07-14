"""Exhibition-only workspace reset endpoint."""

from fastapi import APIRouter, Depends, HTTPException

from config import settings
from core.auth import get_current_user_id
from core.demo_reset import reset_demo_workspace
from core.workspace_operation_lock import (
    WorkspaceOperationInProgress,
    user_workspace_operation,
)
from db.database import AsyncSessionLocal


router = APIRouter()


@router.post("/demo/reset")
async def reset_demo(user_id: str = Depends(get_current_user_id)):
    if not settings.demo_reset_enabled:
        raise HTTPException(status_code=404, detail="not found")

    try:
        async with user_workspace_operation(user_id):
            async with AsyncSessionLocal() as db:
                async with db.begin():
                    deleted = await reset_demo_workspace(db, user_id)
    except WorkspaceOperationInProgress as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc

    return {"ok": True, "deleted": deleted}
