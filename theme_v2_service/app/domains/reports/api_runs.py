from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.config import get_settings
from app.db.session import get_session
from app.domains.reports import service
from app.domains.reports.evidence_options import list_evidence_options
from app.domains.reports.schemas import (
    ReportPlanDraftUpdate,
    ReportRunCreate,
    ReportScopeDraftUpdate,
    ReportScopePrepareRequest,
    RunDecisionRequest,
    RunGenerateRequest,
    TriggerRunCreate,
)
from app.domains.triggers.service import ExecutionExpired, ExecutionNotFound


router = APIRouter(prefix="/api/report-generation-runs", tags=["reports"])


def _require_provider(available: bool, detail: str) -> None:
    if not available:
        raise HTTPException(status_code=503, detail=detail)


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
    except (ExecutionNotFound, ExecutionExpired, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.get("/{run_id}/scope-candidates")
async def get_report_scope_candidates(
    run_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        candidates = await service.get_scope_candidates(
            session,
            user_id=user_id,
            run_id=run_id,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return candidates.model_dump(mode="json", by_alias=True)


@router.put("/{run_id}/scope-draft")
async def update_report_scope_draft(
    run_id: str,
    command: ReportScopeDraftUpdate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        run = await service.update_scope_draft(
            session,
            user_id=user_id,
            run_id=run_id,
            command=command,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.post("/{run_id}/prepare-plan")
async def prepare_report_plan(
    run_id: str,
    command: ReportScopePrepareRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    _require_provider(
        get_settings().report_planner_available(),
        "report planner is not configured",
    )
    try:
        run, _ = await service.prepare_scope_plan(
            session,
            user_id=user_id,
            run_id=run_id,
            expected_revision=command.expected_revision,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
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


@router.get("/evidence-options")
async def get_report_evidence_options(
    q: str = "",
    type: Literal["all", "asset", "event", "contact"] = "all",
    skill: str | None = None,
    cursor: str | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    page = await list_evidence_options(
        session,
        user_id=user_id,
        query=q,
        type_filter=type,
        skill_filter=skill,
        cursor=cursor,
        limit=limit,
    )
    return page.model_dump(mode="json")


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


@router.put("/{run_id}/plan-draft")
async def update_report_plan_draft(
    run_id: str,
    command: ReportPlanDraftUpdate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    _require_provider(
        get_settings().report_planner_available(),
        "report planner is not configured",
    )
    try:
        run, _ = await service.update_plan_draft(
            session,
            user_id=user_id,
            run_id=run_id,
            command=command,
        )
    except (service.RunNotFound, service.RunConflict) as exc:
        raise _translate_error(exc) from exc
    return await service.serialize_run(session, run)


@router.post("/{run_id}/decision")
async def decide_report_run(
    run_id: str,
    command: RunDecisionRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    _require_provider(
        get_settings().report_planner_available(),
        "report planner is not configured",
    )
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
    _require_provider(
        get_settings().report_pipeline_available(),
        "report generator is not configured",
    )
    try:
        run, _ = await service.generate_run(
            session,
            user_id=user_id,
            run_id=run_id,
            selected_option_id=command.selected_option_id,
            expected_plan_revision=command.expected_plan_revision,
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
        current = await service.get_owned_run(
            session,
            user_id=user_id,
            run_id=run_id,
        )
        if current.retry_from == "planning":
            _require_provider(
                get_settings().report_planner_available(),
                "report planner is not configured",
            )
        else:
            _require_provider(
                get_settings().report_pipeline_available(),
                "report generator is not configured",
            )
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
