from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.config import get_settings
from app.db.session import get_session, session_scope
from app.domains.capture import service
from app.domains.capture.schemas import (
    CaptureAcceptance,
    FlashRequest,
    FlashResponse,
    ListeningRequest,
    TencentAsrS3UploadRequest,
    TencentAsrSyncResultRequest,
)
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
