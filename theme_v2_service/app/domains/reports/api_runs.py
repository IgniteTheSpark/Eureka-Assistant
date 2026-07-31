from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.reports import service
from app.domains.reports.schemas import (
    ReportRunCreate,
    RunDecisionRequest,
    RunGenerateRequest,
    TriggerRunCreate,
)
from app.domains.triggers.service import ExecutionExpired, ExecutionNotFound


router = APIRouter(prefix="/api/report-generation-runs", tags=["reports"])


def _translate_error(exc: Exception) -> HTTPException:
    if isinstance(exc, (service.RunNotFound, ExecutionNotFound)):
        return HTTPException(status_code=404, detail="not found")
    if isinstance(exc, ExecutionExpired):
        return HTTPException(status_code=410, detail="execution expired")
    return HTTPException(status_code=409, detail=str(exc))


@router.post("")
async def create_report_run(
    command: ReportRunCreate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        if isinstance(command, TriggerRunCreate):
            run = await service.create_trigger_run(
                session,
                user_id=user_id,
                command=command,
            )
        else:
            run = await service.create_user_run(
                session,
                user_id=user_id,
                command=command,
            )
    except (ExecutionNotFound, ExecutionExpired) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.get("")
async def list_report_runs(
    active: bool = True,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> list[dict]:
    runs = await service.list_owned_runs(
        session,
        user_id=user_id,
        active=active,
    )
    return [await service.serialize_run(session, run) for run in runs]


@router.get("/{run_id}")
async def get_report_run(
    run_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        run = await service.get_owned_run(
            session,
            user_id=user_id,
            run_id=run_id,
        )
    except service.RunNotFound as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.post("/{run_id}/decision")
async def decide_report_run(
    run_id: str,
    command: RunDecisionRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        run = await service.submit_decision(
            session,
            user_id=user_id,
            run_id=run_id,
            command=command,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.post("/{run_id}/generate")
async def generate_report_run(
    run_id: str,
    command: RunGenerateRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        run, _ = await service.generate_run(
            session,
            user_id=user_id,
            run_id=run_id,
            selected_option_id=command.selected_option_id,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.post("/{run_id}/retry")
async def retry_report_run(
    run_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        run, _ = await service.retry_run(
            session,
            user_id=user_id,
            run_id=run_id,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.post("/{run_id}/cancel")
async def cancel_report_run(
    run_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        run = await service.cancel_run(
            session,
            user_id=user_id,
            run_id=run_id,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)
