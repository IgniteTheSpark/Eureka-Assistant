from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.base import utc_now
from app.db.session import get_session
from app.domains.triggers.service import (
    ExecutionExpired,
    ExecutionNotFound,
    dismiss_execution,
)


router = APIRouter(prefix="/api/trigger-executions", tags=["triggers"])


@router.post("/{execution_id}/dismiss")
async def dismiss_trigger_execution(
    execution_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        execution = await dismiss_execution(
            session,
            user_id=user_id,
            execution_id=execution_id,
            now=utc_now(),
        )
    except ExecutionNotFound as exc:
        raise HTTPException(status_code=404, detail="not found") from exc
    except ExecutionExpired as exc:
        raise HTTPException(status_code=410, detail="execution expired") from exc
    return {
        "ok": True,
        "status": execution.status,
        "workflow_run_id": execution.workflow_run_id,
    }
