import asyncio
from uuid import UUID
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.config import get_settings
from app.db.session import get_session, session_scope
from app.domains.capture import service
from app.domains.capture.schemas import (
    CaptureAcceptance,
    FlashChatRequest,
    FlashChatResponse,
    FlashRequest,
    FlashResponse,
    ListeningRequest,
    TencentAsrS3UploadRequest,
    TencentAsrSyncResultRequest,
)
from app.domains.sessions.chat import SessionChatProvider, get_session_chat_provider
from app.domains.sessions.turns import prepare_chat_turn, start_chat_turn
from app.domains.notifications.subscribers import (
    SubscriberFrame,
    SubscriberRegistry,
)


router = APIRouter(prefix="/api", tags=["capture"])


def _capture_error(exc: Exception) -> HTTPException:
    if isinstance(exc, service.CardNotBound):
        return HTTPException(
            status_code=403,
            detail="card not bound by current user",
        )
    if isinstance(exc, service.ConflictingCapture):
        return HTTPException(status_code=409, detail=str(exc))
    if isinstance(exc, ValueError):
        return HTTPException(status_code=422, detail=str(exc))
    return HTTPException(status_code=409, detail="conflicting capture")


@router.post("/flash", response_model=FlashResponse)
async def flash(
    command: FlashRequest,
    user_id: str = Depends(get_current_user_id),
):
    async with session_scope() as session:
        accepted = await service.accept_text_capture(session, user_id, command)
        recording_id = accepted.recording.id
    settings = get_settings()
    result, elapsed_ms = await service.wait_for_recording(
        user_id,
        recording_id,
        timeout_seconds=settings.capture_flash_wait_seconds,
        poll_interval_seconds=settings.capture_flash_poll_interval_seconds,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="recording not found")
    return service.flash_response_payload(result, elapsed_ms=elapsed_ms)


@router.post(
    "/flash/tencent-asr-sync-results",
    response_model=CaptureAcceptance,
)
async def tencent_asr_sync_results(
    command: TencentAsrSyncResultRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        result = await service.accept_sync_result(session, user_id, command)
    except (
        service.CardNotBound,
        service.ConflictingCapture,
        ValueError,
    ) as exc:
        raise _capture_error(exc) from exc
    except IntegrityError as exc:
        await session.rollback()
        raise _capture_error(exc) from exc
    return service.acceptance_payload(result)


@router.post(
    "/flash/tencent-asr-s3-uploads",
    response_model=CaptureAcceptance,
)
async def tencent_asr_s3_uploads(
    command: TencentAsrS3UploadRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        result = await service.accept_s3_upload(session, user_id, command)
    except (
        service.CardNotBound,
        service.ConflictingCapture,
        ValueError,
    ) as exc:
        raise _capture_error(exc) from exc
    except IntegrityError as exc:
        await session.rollback()
        raise _capture_error(exc) from exc
    return service.acceptance_payload(result)


@router.get("/flash/recordings/{recording_id}")
async def get_flash_recording(
    recording_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        UUID(recording_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="invalid recording id") from exc
    result = await service.get_recording(session, user_id, recording_id)
    if result is None:
        raise HTTPException(status_code=404, detail="recording not found")
    return service.recording_payload(result)


@router.get("/flash/recordings")
async def list_flash_recordings(
    limit: int = Query(default=100, ge=1, le=200),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    recordings = await service.list_recordings(session, user_id, limit=limit)
    return {
        "recordings": [
            service.recording_archive_item(recording) for recording in recordings
        ]
    }


@router.get("/flash/sessions")
async def list_flash_sessions(
    limit: int = Query(default=100, ge=1, le=200),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    settings = get_settings()
    return {
        "sessions": await service.list_daily_sessions(
            session,
            user_id,
            timezone_name=settings.default_user_timezone,
            limit=limit,
        )
    }


@router.get("/flash/sessions/{session_date}")
async def get_flash_session(
    session_date: date,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    result = await service.get_daily_session(
        session,
        user_id,
        session_date,
        timezone_name=get_settings().default_user_timezone,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="flash session not found")
    return {"session": result}


@router.post(
    "/flash/sessions/{session_date}/chat",
    response_model=FlashChatResponse,
)
async def chat_with_flash_session(
    session_date: date,
    command: FlashChatRequest,
    user_id: str = Depends(get_current_user_id),
    provider: SessionChatProvider = Depends(get_session_chat_provider),
):
    async with session_scope() as session:
        daily = await service.get_daily_session(
            session,
            user_id,
            session_date,
            timezone_name=get_settings().default_user_timezone,
        )
        if daily is None or not daily.get("physical_session_id"):
            raise HTTPException(status_code=404, detail="flash session not found")
        physical_session_id = str(daily["physical_session_id"])
    prepared = await prepare_chat_turn(
        user_id=user_id,
        session_id=physical_session_id,
        question=command.user_text,
    )
    completed = await asyncio.shield(
        start_chat_turn(provider=provider, prepared=prepared)
    )
    if completed.result is None:
        raise HTTPException(status_code=503, detail=completed.public_error)
    return FlashChatResponse(
        session_id=prepared.session_id,
        input_turn_id=prepared.input_turn_id,
        message_id=prepared.agent_message_id,
        reply=completed.result.text,
    )


@router.delete("/flash/sessions/{session_date}")
async def delete_flash_session(
    session_date: date,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    deleted = await service.delete_daily_session(
        session,
        user_id,
        session_date,
        timezone_name=get_settings().default_user_timezone,
    )
    if deleted == 0:
        raise HTTPException(status_code=404, detail="flash session not found")
    return {"ok": True, "deleted_recording_count": deleted}


@router.delete("/flash/recordings/{recording_id}")
async def delete_flash_recording(
    recording_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        UUID(recording_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="invalid recording id") from exc
    if not await service.delete_recording(session, user_id, recording_id):
        raise HTTPException(status_code=404, detail="recording not found")
    return {"ok": True}


@router.post("/flash/recordings/{recording_id}/retry")
async def retry_flash_recording(
    recording_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        UUID(recording_id)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="invalid recording id") from exc
    try:
        mode = await service.retry_recording(session, user_id, recording_id)
    except service.CaptureRetryUnavailable as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    if mode is None:
        raise HTTPException(status_code=404, detail="recording not found")
    return {
        "ok": True,
        "queued": True,
        "mode": mode,
        "recording_id": recording_id,
        "error": "",
    }


@router.post("/flash/listening")
async def flash_listening(
    command: ListeningRequest,
    request: Request,
    user_id: str = Depends(get_current_user_id),
):
    registry: SubscriberRegistry = request.app.state.notification_subscribers
    registry.publish(
        user_id,
        SubscriberFrame(
            event="listening",
            payload={"state": command.state},
        ),
    )
    return {"ok": True, "state": command.state}
