from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session as get_database_session
from app.domains.sessions import service
from app.domains.sessions.schemas import SessionContextUpdate, SessionCreate


router = APIRouter(prefix="/api", tags=["sessions"])


def _not_found() -> HTTPException:
    return HTTPException(status_code=404, detail="session not found")


@router.post("/sessions")
async def create_session(
    command: SessionCreate,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_database_session),
):
    model = await service.create_or_peek_session(database, user_id, command)
    return {"session_id": model.id if model is not None else None}


@router.get("/sessions")
async def list_sessions(
    limit: int = Query(default=100, ge=1, le=200),
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_database_session),
):
    models = await service.list_sessions(database, user_id, limit=limit)
    return {"sessions": [service.session_list_item(model) for model in models]}


@router.get("/sessions/opening-hint")
async def opening_hint(
    subject_type: str,
    subject_id: str,
    user_id: str = Depends(get_current_user_id),
):
    del subject_type, subject_id, user_id
    return {"opener": "你想从这条记录继续了解什么？", "starters": []}


@router.get("/sessions/{session_id}")
async def get_session(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_database_session),
):
    model = await service.get_session(database, user_id, session_id)
    if model is None:
        raise _not_found()
    return {"session": await service.session_detail(database, model)}


@router.get("/sessions/{session_id}/messages")
async def get_messages(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_database_session),
):
    if await service.get_session(database, user_id, session_id) is None:
        raise _not_found()
    models = await service.list_messages(database, user_id, session_id)
    return {"messages": [service.message_payload(model) for model in models]}


@router.patch("/sessions/{session_id}/context")
async def patch_context(
    session_id: str,
    command: SessionContextUpdate,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_database_session),
):
    model = await service.get_session(database, user_id, session_id)
    if model is None:
        raise _not_found()
    try:
        await service.update_context(database, model, command)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return {"session": await service.session_detail(database, model)}


@router.delete("/sessions/{session_id}")
async def delete_session(
    session_id: str,
    user_id: str = Depends(get_current_user_id),
    database: AsyncSession = Depends(get_database_session),
):
    if not await service.delete_session(database, user_id, session_id):
        raise _not_found()
    return {"ok": True}
