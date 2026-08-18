from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.assets import service
from app.domains.assets.schemas import (
    AssetCreate,
    AssetRead,
    AssetUpdate,
    EventCreate,
    EventRead,
    EventUpdate,
    SkillDeletionImpact,
    SkillDeletionResult,
    SkillDraftRequest,
    UserSkillCreate,
    UserSkillRead,
    UserSkillUpdate,
)
from app.domains.assets.skill_design import (
    InvalidSkillDraft,
    SkillDesignUnavailable,
    design_skill_step,
)
from app.domains.assets.validation import AssetPayloadInvalid


router = APIRouter(prefix="/api", tags=["core-records"])


def _not_found() -> HTTPException:
    return HTTPException(status_code=404, detail="not found")


@router.post("/user-skills", response_model=UserSkillRead)
async def create_user_skill(
    command: UserSkillCreate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        return await service.create_user_skill(session, user_id, command)
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(status_code=409, detail="machine name already exists") from exc


@router.get("/user-skills", response_model=list[UserSkillRead])
async def list_user_skills(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return await service.list_user_skills(session, user_id)


@router.get("/user-skills/recent-manual")
async def list_recent_manual_skills(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return {
        "skill_names": await service.list_recent_manual_skill_names(
            session,
            user_id,
        )
    }


@router.post("/user-skills/draft")
async def draft_user_skill(
    command: SkillDraftRequest,
    user_id: str = Depends(get_current_user_id),
):
    del user_id
    try:
        result = await design_skill_step(command.description, command.answers)
    except SkillDesignUnavailable as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except InvalidSkillDraft as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {"ok": True, **result}


@router.get("/user-skills/{skill_id}", response_model=UserSkillRead)
async def get_user_skill(
    skill_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    skill = await service.get_user_skill(session, user_id, skill_id)
    if skill is None:
        raise _not_found()
    return skill


@router.patch("/user-skills/{skill_id}", response_model=UserSkillRead)
async def update_user_skill(
    skill_id: str,
    command: UserSkillUpdate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        skill = await service.update_user_skill(session, user_id, skill_id, command)
    except service.SkillUpdateConflict as exc:
        raise HTTPException(
            status_code=409,
            detail={"code": exc.code, "message": exc.message},
        ) from exc
    if skill is None:
        raise _not_found()
    return skill


@router.get(
    "/user-skills/{skill_id}/deletion-impact",
    response_model=SkillDeletionImpact,
)
async def get_user_skill_deletion_impact(
    skill_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        impact = await service.skill_deletion_impact(session, user_id, skill_id)
    except service.SkillUpdateConflict as exc:
        raise HTTPException(
            status_code=409,
            detail={"code": exc.code, "message": exc.message},
        ) from exc
    if impact is None:
        raise _not_found()
    return impact


@router.delete(
    "/user-skills/{skill_id}",
    response_model=SkillDeletionResult,
)
async def delete_user_skill(
    skill_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        result = await service.delete_user_skill(session, user_id, skill_id)
    except service.SkillUpdateConflict as exc:
        raise HTTPException(
            status_code=409,
            detail={"code": exc.code, "message": exc.message},
        ) from exc
    if result is None:
        raise _not_found()
    return result


@router.post("/assets", response_model=AssetRead)
async def create_asset(
    command: AssetCreate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        return await service.create_asset(session, user_id, command)
    except service.UserSkillNotFound as exc:
        raise _not_found() from exc
    except service.ChatSessionNotFound as exc:
        raise _not_found() from exc
    except AssetPayloadInvalid as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/assets", response_model=list[AssetRead])
async def list_assets(
    user_skill_id: str | None = None,
    created_from: datetime | None = None,
    created_to: datetime | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return await service.list_assets(
        session,
        user_id,
        user_skill_id=user_skill_id,
        created_from=created_from,
        created_to=created_to,
        limit=limit,
    )


@router.get("/assets/{asset_id}", response_model=AssetRead)
async def get_asset(
    asset_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    asset = await service.get_asset(session, user_id, asset_id)
    if asset is None:
        raise _not_found()
    return asset


@router.patch("/assets/{asset_id}", response_model=AssetRead)
async def update_asset(
    asset_id: str,
    command: AssetUpdate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        asset = await service.update_asset(session, user_id, asset_id, command)
    except AssetPayloadInvalid as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if asset is None:
        raise _not_found()
    return asset


@router.delete("/assets/{asset_id}")
async def delete_asset(
    asset_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict[str, bool]:
    if not await service.delete_asset(session, user_id, asset_id):
        raise _not_found()
    return {"ok": True}


@router.post("/events", response_model=EventRead)
async def create_event(
    command: EventCreate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return await service.create_event(session, user_id, command)


@router.get("/events", response_model=list[EventRead])
async def list_events(
    start_from: datetime | None = None,
    start_to: datetime | None = None,
    created_from: datetime | None = None,
    created_to: datetime | None = None,
    limit: int = Query(default=50, ge=1, le=100),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return await service.list_events(
        session,
        user_id,
        start_from=start_from,
        start_to=start_to,
        created_from=created_from,
        created_to=created_to,
        limit=limit,
    )


@router.get("/events/{event_id}", response_model=EventRead)
async def get_event(
    event_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    event = await service.get_event(session, user_id, event_id)
    if event is None:
        raise _not_found()
    return event


@router.patch("/events/{event_id}", response_model=EventRead)
async def update_event(
    event_id: str,
    command: EventUpdate,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    event = await service.update_event(session, user_id, event_id, command)
    if event is None:
        raise _not_found()
    return event


@router.delete("/events/{event_id}")
async def delete_event(
    event_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict[str, bool]:
    if not await service.delete_event(session, user_id, event_id):
        raise _not_found()
    return {"ok": True}
