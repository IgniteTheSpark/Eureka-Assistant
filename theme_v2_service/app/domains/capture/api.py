from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.db.session import get_session
from app.domains.capture import service
from app.domains.capture.schemas import (
    CaptureAcceptance,
    TencentAsrS3UploadRequest,
    TencentAsrSyncResultRequest,
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
