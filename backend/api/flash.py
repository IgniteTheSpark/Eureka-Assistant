"""
POST /api/flash — Voice flash ingest → Flash Pipeline (Phase B Step 5).

Per-request lifecycle:
1. Resolve / create today's flash session (get-or-create by user + date)
   — Phase B v1.3 折中:flash session 按天聚合,每次闪念是 session 内一个 input_turn
2. Create input_turn(source='voice', or 'typed' if explicitly typed in
   the flash UI) — provenance for derived assets
3. Run Flash Pipeline (3-step Python orchestration) — fans out to
   parallel skill agents; each create_asset writes source_input_turn_id
4. Return derived assets + summary + cards as sync JSON
5. Persist a single agent Message to messages table so the chat-like
   surface in Phase D can replay the flash result

Sync (not SSE) for demo simplicity — Phase D shows progress via UI animation
(60ms stagger per card per design §3.5). Easy to upgrade to SSE later if
real-time intermediate events become a product requirement.
"""
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select

from core.asr.base import AsrError
from core.auth import get_current_user_id
from core.flash_file_queue import (
    create_tencent_asr_task_if_needed,
    enqueue,
    publish_flash_file_status,
)
from core.flash_service import process_flash_text
from core.notifications import publish_event
from db.database import AsyncSessionLocal
from db.models import Card, CardBinding, File, FlashRecording

router = APIRouter()
logger = logging.getLogger("flash_file")
LOG_TAG = "[FlashFile]"


# ── Request / response ─────────────────────────────────────────────────────────

class FlashRequest(BaseModel):
    text: str
    session_id: str = ""     # empty = get-or-create today's flash session
    source: str = "voice"    # voice | typed (per Phase B v1.3 modality)
    capture_session_type: str = ""  # optional flash | manual override for onboarding typed first capture
    file_id: str = ""        # optional, when real audio upload exists (future)


class ListeningRequest(BaseModel):
    # "on" while the hardware mic (W1/W2 card flash-memo button) is held down
    # and capturing; "off" on release. Pushed live to the UI so it can show a
    # global「正在聆听」overlay. Ephemeral — no DB row.
    state: str   # "on" | "off"


class S3UploadInfo(BaseModel):
    s3_key: str
    upload_url: str
    audio_url: str = ""
    content_type: str = "audio/mpeg"
    headers: dict[str, str] = Field(default_factory=dict)
    upload_expires_in: Optional[int] = None
    uploaded_at: Optional[int | float | str] = None


class TencentAsrS3UploadRequest(BaseModel):
    client_task_id: str
    source: str = "realtime"  # realtime | offline
    card_sn: str
    device_file_name: str
    capture_started_at: Optional[int | float | str] = None
    capture_ended_at: Optional[int | float | str] = None
    device_crc: Optional[int] = None
    device_size_bytes: Optional[int] = None
    local_mp3_sha256: Optional[str] = None
    local_mp3_size_bytes: Optional[int] = None
    local_audio_sha256: Optional[str] = None
    local_audio_size_bytes: Optional[int] = None
    asr_mode: str = "async"
    audio_format: str = "mp3"
    s3: S3UploadInfo
    engine_type: str = "16k_zh"
    speaker_diarization: bool = False
    hotword_list: str = ""


class TencentAsrSyncResultRequest(BaseModel):
    client_task_id: str
    source: str = "realtime"
    card_sn: str
    device_file_name: str
    capture_started_at: Optional[int | float | str] = None
    capture_ended_at: Optional[int | float | str] = None
    device_crc: Optional[int] = None
    device_size_bytes: Optional[int] = None
    local_audio_sha256: str
    local_audio_size_bytes: int
    audio_format: str = "opus"
    asr_mode: str = "sync_client"
    asr_provider: str = "tencent_asr_sync_client"
    asr_status: str = "completed"
    asr_text: str = ""
    asr_segments: list = Field(default_factory=list)
    raw_response: dict = Field(default_factory=dict)
    asr_error: str = ""
    error_message: str = ""
    speaker_diarization: bool = False


class FlashResponse(BaseModel):
    ok:            bool
    session_id:    str
    input_turn_id: str
    # `reply` — conversational free-text answer (from qa-skill outputs).
    # Treated like a chat bubble in the session stream; NOT a card.
    # Cards are reserved for persistent asset / event references that have
    # an actionable handle (asset_id / event_id) the user can tap or edit.
    reply:         str = ""
    summary:       str = ""
    cards:         list = []
    derived_assets: list = []
    has_pending:   bool = False
    elapsed_ms:    int = 0
    error:         str = ""


def _now():
    return datetime.now(timezone.utc)


def _parse_time(value) -> datetime | None:
    if value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        # App may send seconds or milliseconds.
        ts = float(value) / 1000 if value > 10_000_000_000 else float(value)
        return datetime.fromtimestamp(ts, tz=timezone.utc)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            raise HTTPException(status_code=422, detail="invalid capture timestamp")
    raise HTTPException(status_code=422, detail="invalid capture timestamp")


def _require_flash_file_name(name: str) -> str:
    value = (name or "").strip()
    if not (value.startswith("F") and value.lower().endswith(".opus")):
        raise HTTPException(status_code=422, detail="device_file_name must be F*.opus")
    return value


def _clean_sha256(value: str | None, *, field_name: str = "local_mp3_sha256") -> str | None:
    if value in (None, ""):
        return None
    cleaned = value.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", cleaned):
        raise HTTPException(status_code=422, detail=f"invalid {field_name}")
    return cleaned


def _file_status(recording: FlashRecording, file: File | None = None) -> str:
    if file is not None and file.asr_status:
        return file.asr_status
    if recording.process_status in ("asr_done", "processing_flash", "done"):
        return "completed"
    if recording.process_status == "asr_processing":
        return "processing"
    if recording.process_status == "failed":
        return "failed"
    return "pending"


def _upload_response(
    recording: FlashRecording,
    file: File | None,
    *,
    duplicate: bool = False,
    error: str = "",
    message: str = "任务已添加",
) -> dict:
    return {
        "ok": True,
        "accepted": True,
        "duplicate": duplicate,
        "recording_id": str(recording.id),
        "file_id": str(recording.file_id),
        "asr_status": _file_status(recording, file),
        "asr_text": recording.asr_text or "",
        "pipeline_status": recording.process_status,
        "message": message,
        "error": error,
    }


async def _ensure_card_bound(db, user_id: str, card_sn: str) -> None:
    row = (await db.execute(
        select(CardBinding)
        .join(Card, CardBinding.card_id == Card.id)
        .where(
            Card.card_sn == card_sn,
            CardBinding.user_id == user_id,
            CardBinding.bind_status == "bound",
        )
        .limit(1)
    )).scalar_one_or_none()
    if row is None:
        logger.info("%s reject ASR task user=%s card_sn=%s reason=card_not_bound", LOG_TAG, user_id, card_sn)
        raise HTTPException(status_code=403, detail="card not bound by current user")


def _assert_same_upload(
    recording: FlashRecording,
    s3_key: str,
    upload_url: str,
    audio_url: str,
    sha256: str | None,
    audio_sha256: str | None,
    audio_size_bytes: int | None,
    asr_mode: str,
    audio_format: str,
) -> None:
    if recording.s3_key != s3_key:
        logger.info("%s reject duplicate recording=%s reason=different_s3_key", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different s3_key")
    if recording.s3_upload_url and recording.s3_upload_url != upload_url:
        logger.info("%s reject duplicate recording=%s reason=different_upload_url", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different upload_url")
    if recording.s3_audio_url and recording.s3_audio_url != audio_url:
        logger.info("%s reject duplicate recording=%s reason=different_audio_url", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different audio_url")
    if sha256 and recording.local_mp3_sha256 and recording.local_mp3_sha256 != sha256:
        logger.info("%s reject duplicate recording=%s reason=different_mp3_sha256", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different mp3 sha256")
    if audio_sha256 and recording.local_audio_sha256 and recording.local_audio_sha256 != audio_sha256:
        logger.info("%s reject duplicate recording=%s reason=different_audio_sha256", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different audio sha256")
    if audio_size_bytes is not None and recording.local_audio_size_bytes is not None and recording.local_audio_size_bytes != audio_size_bytes:
        logger.info("%s reject duplicate recording=%s reason=different_audio_size", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different audio size")
    if recording.asr_mode and recording.asr_mode != asr_mode:
        logger.info("%s reject duplicate recording=%s reason=different_asr_mode", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different asr_mode")
    if recording.audio_format and recording.audio_format != audio_format:
        logger.info("%s reject duplicate recording=%s reason=different_audio_format", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different audio_format")


def _assert_same_sync_result(
    recording: FlashRecording,
    audio_sha256: str,
    audio_size_bytes: int,
    text: str,
) -> None:
    if recording.local_audio_sha256 and recording.local_audio_sha256 != audio_sha256:
        logger.info("%s reject duplicate recording=%s reason=different_audio_sha256", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different audio sha256")
    if recording.local_audio_size_bytes is not None and recording.local_audio_size_bytes != audio_size_bytes:
        logger.info("%s reject duplicate recording=%s reason=different_audio_size", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different audio size")
    existing_text = (recording.asr_text or "").strip()
    if existing_text and existing_text != text:
        logger.info("%s reject duplicate recording=%s reason=different_asr_text", LOG_TAG, recording.id)
        raise HTTPException(status_code=409, detail="duplicate key with different asr_text")


def _sync_placeholder_key(client_task_id: str) -> str:
    return f"client-sync-asr:{client_task_id}"


# ── Endpoint ───────────────────────────────────────────────────────────────────

@router.post("/flash", response_model=FlashResponse)
async def flash(req: FlashRequest, user_id: str = Depends(get_current_user_id)):
    input_source = req.source if req.source in {"voice", "typed", "imported"} else "voice"
    result = await process_flash_text(
        user_id=user_id,
        text=req.text,
        source=input_source,
        file_id=req.file_id or None,
        session_id=req.session_id,
        capture_session_type=req.capture_session_type if req.capture_session_type in {"flash", "manual"} else None,
    )
    return FlashResponse(**{k: v for k, v in result.items() if k in FlashResponse.model_fields})


@router.post("/flash/tencent-asr-s3-uploads")
async def tencent_asr_s3_uploads(
    req: TencentAsrS3UploadRequest,
    user_id: str = Depends(get_current_user_id),
):
    client_task_id = (req.client_task_id or "").strip()
    if not client_task_id:
        logger.info("%s reject S3 upload reason=missing_client_task_id", LOG_TAG)
        raise HTTPException(status_code=422, detail="client_task_id required")
    source = req.source if req.source in {"realtime", "offline"} else "realtime"
    card_sn = (req.card_sn or "").strip()
    if not card_sn:
        logger.info("%s reject S3 upload client_task=%s reason=missing_card_sn", LOG_TAG, client_task_id)
        raise HTTPException(status_code=422, detail="card_sn required")
    device_file_name = _require_flash_file_name(req.device_file_name)
    asr_mode = (req.asr_mode or "async").strip().lower()
    if asr_mode != "async":
        raise HTTPException(status_code=422, detail="s3 upload endpoint requires asr_mode=async")
    audio_format = (req.audio_format or "mp3").strip().lower()
    if audio_format not in {"opus", "mp3"}:
        raise HTTPException(status_code=422, detail="invalid audio_format")
    if audio_format != "mp3":
        raise HTTPException(status_code=422, detail="async ASR requires mp3 audio_format")
    sha256 = _clean_sha256(req.local_mp3_sha256)
    audio_sha256 = _clean_sha256(req.local_audio_sha256, field_name="local_audio_sha256") or sha256
    audio_size_bytes = (
        req.local_audio_size_bytes
        if req.local_audio_size_bytes is not None
        else req.local_mp3_size_bytes
    )
    s3_key = (req.s3.s3_key or "").strip()
    if not s3_key:
        logger.info("%s reject S3 upload client_task=%s file=%s reason=missing_s3_key", LOG_TAG, client_task_id, device_file_name)
        raise HTTPException(status_code=422, detail="s3_key required")
    upload_url = (req.s3.upload_url or "").strip()
    if not upload_url:
        logger.info("%s reject S3 upload client_task=%s file=%s reason=missing_upload_url", LOG_TAG, client_task_id, device_file_name)
        raise HTTPException(status_code=422, detail="upload_url required")
    audio_url = (req.s3.audio_url or "").strip()
    if not audio_url:
        logger.info("%s reject S3 upload client_task=%s file=%s reason=missing_audio_url", LOG_TAG, client_task_id, device_file_name)
        raise HTTPException(status_code=422, detail="audio_url required")
    logger.info(
        "%s receive S3 upload user=%s client_task=%s card_sn=%s file=%s source=%s "
        "s3_key=%s mode=%s audio_format=%s audio_size=%s mp3_size=%s crc=%s",
        LOG_TAG,
        user_id,
        client_task_id,
        card_sn,
        device_file_name,
        source,
        s3_key,
        asr_mode,
        audio_format,
        audio_size_bytes,
        req.local_mp3_size_bytes,
        req.device_crc,
    )

    duplicate = False
    recording_id: uuid.UUID
    async with AsyncSessionLocal() as db:
        await _ensure_card_bound(db, user_id, card_sn)

        existing = (await db.execute(
            select(FlashRecording).where(
                FlashRecording.user_id == user_id,
                FlashRecording.client_task_id == client_task_id,
            )
        )).scalar_one_or_none()
        if existing is None and req.device_crc is not None:
            existing = (await db.execute(
                select(FlashRecording).where(
                    FlashRecording.user_id == user_id,
                    FlashRecording.card_sn == card_sn,
                    FlashRecording.device_file_name == device_file_name,
                    FlashRecording.device_crc == req.device_crc,
                )
            )).scalar_one_or_none()
        if existing is not None:
            _assert_same_upload(
                existing,
                s3_key,
                upload_url,
                audio_url,
                sha256,
                audio_sha256,
                audio_size_bytes,
                asr_mode,
                audio_format,
            )
            duplicate = True
            existing_updated = False
            if not existing.s3_upload_url:
                existing.s3_upload_url = upload_url
                existing_updated = True
            if not existing.s3_audio_url:
                existing.s3_audio_url = audio_url
                existing_updated = True
            if not existing.s3_upload_headers and req.s3.headers:
                existing.s3_upload_headers = req.s3.headers
                existing_updated = True
            if not existing.asr_mode:
                existing.asr_mode = asr_mode
                existing_updated = True
            if not existing.audio_format:
                existing.audio_format = audio_format
                existing_updated = True
            if not existing.local_audio_sha256 and audio_sha256:
                existing.local_audio_sha256 = audio_sha256
                existing_updated = True
            if existing.local_audio_size_bytes is None and audio_size_bytes is not None:
                existing.local_audio_size_bytes = audio_size_bytes
                existing_updated = True
            if existing.process_status == "failed" and not existing.tencent_asr_task_id:
                existing.process_status = "pending"
                existing.tencent_status = "pending"
                existing.tencent_error_message = None
                existing.asr_error = None
                existing.error_message = None
                existing_updated = True
            if existing_updated:
                existing.updated_at = _now()
                await db.commit()
                await db.refresh(existing)
            file = (await db.execute(select(File).where(File.id == existing.file_id))).scalar_one_or_none()
            logger.info(
                "%s duplicate S3 upload accepted user=%s recording=%s client_task=%s task_id=%s status=%s",
                LOG_TAG,
                user_id,
                existing.id,
                client_task_id,
                existing.tencent_asr_task_id,
                existing.process_status,
            )
            recording_id = existing.id
        else:
            file = File(
                user_id=user_id,
                storage_url=s3_key,
                file_type=(
                    req.s3.content_type
                    or ("application/octet-stream" if audio_format == "opus" else "audio/mpeg")
                ),
                source_tag="flash",
                asr_status="processing",
            )
            db.add(file)
            await db.flush()

            recording = FlashRecording(
                user_id=user_id,
                file_id=file.id,
                card_sn=card_sn,
                device_file_name=device_file_name,
                client_task_id=client_task_id,
                source=source,
                device_crc=req.device_crc,
                device_size_bytes=req.device_size_bytes,
                capture_started_at=_parse_time(req.capture_started_at),
                capture_ended_at=_parse_time(req.capture_ended_at),
                local_mp3_sha256=sha256,
                local_mp3_size_bytes=req.local_mp3_size_bytes,
                local_audio_sha256=audio_sha256,
                local_audio_size_bytes=audio_size_bytes,
                audio_format=audio_format,
                asr_mode=asr_mode,
                s3_key=s3_key,
                s3_content_type=req.s3.content_type,
                s3_upload_url=upload_url,
                s3_audio_url=audio_url,
                s3_upload_headers=req.s3.headers or {},
                s3_upload_expires_in=req.s3.upload_expires_in,
                s3_uploaded_at=_parse_time(req.s3.uploaded_at),
                tencent_engine_type=req.engine_type,
                tencent_speaker_diarization=1 if req.speaker_diarization else 0,
                tencent_hotword_list=req.hotword_list,
                tencent_status="pending",
                tencent_task_response={},
                upload_status="uploaded",
                process_status="pending",
                asr_provider="tencent_asr_sync" if asr_mode == "sync" else "tencent_asr_s3_async",
                accepted_at=_now(),
            )
            db.add(recording)
            await db.commit()
            await db.refresh(recording)
            logger.info(
                "%s S3 upload persisted user=%s recording=%s file_id=%s client_task=%s s3_key=%s",
                LOG_TAG,
                user_id,
                recording.id,
                file.id,
                client_task_id,
                s3_key,
            )
            recording_id = recording.id

    try:
        async with AsyncSessionLocal() as db:
            current_status = (await db.execute(
                select(FlashRecording.process_status).where(FlashRecording.id == recording_id)
            )).scalar_one_or_none()
        if current_status not in {"done", "asr_done", "processing_flash"}:
            await create_tencent_asr_task_if_needed(recording_id)
    except AsrError as e:
        logger.info(
            "%s ASR submit failed recording=%s mode=%s error=%s",
            LOG_TAG,
            recording_id,
            asr_mode,
            str(e)[:300],
        )
        raise HTTPException(status_code=502, detail=str(e)[:200])

    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == recording_id, FlashRecording.user_id == user_id)
        )).scalar_one_or_none()
        if recording is None:
            raise HTTPException(status_code=404, detail="recording not found")
        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
    if recording.process_status in {"pending", "asr_processing", "asr_done", "processing_flash"}:
        await enqueue(recording.id)
    logger.info(
        "%s ASR upload accepted recording=%s mode=%s task_id=%s status=%s",
        LOG_TAG,
        recording.id,
        recording.asr_mode,
        recording.tencent_asr_task_id,
        recording.process_status,
    )
    message = (
        "文件没内容"
        if recording.error_message == "文件没内容"
        else ("上传完成" if recording.asr_mode == "sync" else "任务已添加")
    )
    return _upload_response(recording, file, duplicate=duplicate, message=message)


@router.post("/flash/tencent-asr-sync-results")
async def tencent_asr_sync_results(
    req: TencentAsrSyncResultRequest,
    user_id: str = Depends(get_current_user_id),
):
    client_task_id = (req.client_task_id or "").strip()
    if not client_task_id:
        logger.info("%s reject client sync ASR result reason=missing_client_task_id", LOG_TAG)
        raise HTTPException(status_code=422, detail="client_task_id required")
    source = req.source if req.source in {"realtime", "offline"} else "realtime"
    card_sn = (req.card_sn or "").strip()
    if not card_sn:
        logger.info("%s reject client sync ASR result client_task=%s reason=missing_card_sn", LOG_TAG, client_task_id)
        raise HTTPException(status_code=422, detail="card_sn required")
    device_file_name = _require_flash_file_name(req.device_file_name)
    asr_mode = (req.asr_mode or "sync_client").strip().lower()
    if asr_mode != "sync_client":
        logger.info("%s reject client sync ASR result client_task=%s reason=invalid_asr_mode value=%s", LOG_TAG, client_task_id, asr_mode)
        raise HTTPException(status_code=422, detail="sync result requires asr_mode=sync_client")
    audio_format = (req.audio_format or "opus").strip().lower()
    if audio_format != "opus":
        logger.info("%s reject client sync ASR result client_task=%s reason=invalid_audio_format value=%s", LOG_TAG, client_task_id, audio_format)
        raise HTTPException(status_code=422, detail="sync result requires audio_format=opus")
    asr_status = (req.asr_status or "completed").strip().lower()
    if asr_status not in {"completed", "failed"}:
        logger.info("%s reject client sync ASR result client_task=%s reason=invalid_asr_status value=%s", LOG_TAG, client_task_id, asr_status)
        raise HTTPException(status_code=422, detail="invalid asr_status")
    asr_provider = (req.asr_provider or "tencent_asr_sync_client").strip() or "tencent_asr_sync_client"
    audio_sha256 = _clean_sha256(req.local_audio_sha256, field_name="local_audio_sha256")
    if not audio_sha256:
        logger.info("%s reject client sync ASR result client_task=%s reason=missing_audio_sha256", LOG_TAG, client_task_id)
        raise HTTPException(status_code=422, detail="local_audio_sha256 required")
    if req.local_audio_size_bytes <= 0:
        logger.info("%s reject client sync ASR result client_task=%s reason=invalid_audio_size value=%s", LOG_TAG, client_task_id, req.local_audio_size_bytes)
        raise HTTPException(status_code=422, detail="local_audio_size_bytes required")
    text = (req.asr_text or "").strip()
    segments = req.asr_segments if isinstance(req.asr_segments, list) else []
    raw_response = req.raw_response if isinstance(req.raw_response, dict) else {}
    asr_error = (req.asr_error or "").strip()
    error_message = (req.error_message or "").strip()
    no_content = asr_status == "completed" and not text
    asr_failed = asr_status == "failed"
    if no_content:
        terminal_message = "文件没内容"
    elif asr_failed:
        terminal_message = error_message or asr_error or "识别失败已记录"
    else:
        terminal_message = ""
    placeholder_key = _sync_placeholder_key(client_task_id)

    logger.info(
        "%s receive client sync ASR result user=%s client_task=%s card_sn=%s file=%s "
        "source=%s asr_status=%s text_len=%s segments=%s audio_size=%s crc=%s error=%s",
        LOG_TAG,
        user_id,
        client_task_id,
        card_sn,
        device_file_name,
        source,
        asr_status,
        len(text),
        len(segments),
        req.local_audio_size_bytes,
        req.device_crc,
        terminal_message or asr_error,
    )

    duplicate = False
    async with AsyncSessionLocal() as db:
        await _ensure_card_bound(db, user_id, card_sn)

        existing = (await db.execute(
            select(FlashRecording).where(
                FlashRecording.user_id == user_id,
                FlashRecording.client_task_id == client_task_id,
            )
        )).scalar_one_or_none()
        if existing is None and req.device_crc is not None:
            existing = (await db.execute(
                select(FlashRecording).where(
                    FlashRecording.user_id == user_id,
                    FlashRecording.card_sn == card_sn,
                    FlashRecording.device_file_name == device_file_name,
                    FlashRecording.device_crc == req.device_crc,
                )
            )).scalar_one_or_none()

        if existing is not None:
            logger.info(
                "%s client sync ASR existing found recording=%s client_task=%s status=%s process=%s text_len=%s",
                LOG_TAG,
                existing.id,
                client_task_id,
                existing.tencent_status,
                existing.process_status,
                len(existing.asr_text or ""),
            )
            _assert_same_sync_result(existing, audio_sha256, req.local_audio_size_bytes, text)
            duplicate = True
            file = (await db.execute(select(File).where(File.id == existing.file_id))).scalar_one_or_none()
            should_update_existing = (
                existing.process_status not in {"asr_done", "processing_flash"}
                or (bool(text) and not (existing.asr_text or "").strip())
            )
            if should_update_existing:
                existing.local_audio_sha256 = existing.local_audio_sha256 or audio_sha256
                existing.local_audio_size_bytes = existing.local_audio_size_bytes or req.local_audio_size_bytes
                existing.audio_format = audio_format
                existing.asr_mode = asr_mode
                existing.asr_provider = asr_provider
                existing.tencent_status = "failed" if asr_failed else "finished"
                existing.tencent_speaker_diarization = 1 if req.speaker_diarization else 0
                existing.tencent_result_response = raw_response
                existing.tencent_task_response = raw_response or existing.tencent_task_response or {}
                existing.asr_text = text
                existing.asr_segments = segments
                existing.asr_error = terminal_message if asr_failed else None
                existing.error_message = terminal_message or None
                existing.tencent_error_message = terminal_message or None
                existing.process_status = (
                    "failed" if asr_failed else ("asr_done" if text else "done")
                )
                if existing.process_status in {"done", "failed"}:
                    existing.result_summary = ""
                    existing.result_cards = []
                    existing.processed_at = _now()
                existing.updated_at = _now()
                if file:
                    file.asr_status = "failed" if asr_failed else "completed"
                await db.commit()
                await db.refresh(existing)
                logger.info(
                    "%s client sync ASR committed existing recording=%s file_id=%s process_status=%s asr_status=%s message=%s",
                    LOG_TAG,
                    existing.id,
                    existing.file_id,
                    existing.process_status,
                    asr_status,
                    terminal_message,
                )
            else:
                logger.info(
                    "%s client sync ASR existing unchanged recording=%s process_status=%s asr_status=%s",
                    LOG_TAG,
                    existing.id,
                    existing.process_status,
                    asr_status,
                )
            recording = existing
        else:
            logger.info("%s client sync ASR existing not found client_task=%s", LOG_TAG, client_task_id)
            file = File(
                user_id=user_id,
                storage_url=placeholder_key,
                file_type="audio/opus",
                source_tag="flash",
                asr_status="failed" if asr_failed else "completed",
            )
            db.add(file)
            await db.flush()
            recording = FlashRecording(
                user_id=user_id,
                file_id=file.id,
                card_sn=card_sn,
                device_file_name=device_file_name,
                client_task_id=client_task_id,
                source=source,
                device_crc=req.device_crc,
                device_size_bytes=req.device_size_bytes,
                capture_started_at=_parse_time(req.capture_started_at),
                capture_ended_at=_parse_time(req.capture_ended_at),
                local_audio_sha256=audio_sha256,
                local_audio_size_bytes=req.local_audio_size_bytes,
                audio_format=audio_format,
                asr_mode=asr_mode,
                s3_key=placeholder_key,
                s3_content_type=None,
                s3_upload_url=None,
                s3_audio_url=None,
                s3_upload_headers={},
                tencent_speaker_diarization=1 if req.speaker_diarization else 0,
                tencent_status="failed" if asr_failed else "finished",
                tencent_task_response=raw_response,
                tencent_result_response=raw_response,
                upload_status="uploaded",
                process_status=(
                    "failed" if asr_failed else ("asr_done" if text else "done")
                ),
                asr_provider=asr_provider,
                asr_text=text,
                asr_segments=segments,
                asr_error=terminal_message if asr_failed else None,
                error_message=terminal_message or None,
                tencent_error_message=terminal_message or None,
                result_summary="" if no_content or asr_failed else None,
                result_cards=[] if no_content or asr_failed else None,
                accepted_at=_now(),
                processed_at=_now() if no_content or asr_failed else None,
            )
            db.add(recording)
            await db.commit()
            await db.refresh(recording)
            logger.info(
                "%s client sync ASR committed new recording=%s file_id=%s process_status=%s asr_status=%s message=%s",
                LOG_TAG,
                recording.id,
                file.id,
                recording.process_status,
                asr_status,
                terminal_message,
            )

    publish_flash_file_status(recording, "accepted", "上传完成")
    if recording.process_status == "asr_done":
        publish_flash_file_status(recording, "asr_done", "语音识别完成")
        logger.info("%s client sync ASR enqueue pipeline recording=%s", LOG_TAG, recording.id)
        await enqueue(recording.id)
    else:
        logger.info(
            "%s client sync ASR record only no pipeline recording=%s asr_status=%s message=%s",
            LOG_TAG,
            recording.id,
            asr_status,
            terminal_message,
        )
        if recording.process_status == "failed":
            publish_flash_file_status(recording, "failed", terminal_message or "识别失败已记录")
        else:
            publish_flash_file_status(recording, "done", terminal_message or "文件没内容")
    logger.info(
        "%s client sync ASR response recording=%s file_id=%s duplicate=%s process_status=%s asr_status=%s text_len=%s message=%s",
        LOG_TAG,
        recording.id,
        recording.file_id,
        duplicate,
        recording.process_status,
        asr_status,
        len(text),
        terminal_message,
    )
    return _upload_response(
        recording,
        file,
        duplicate=duplicate,
        message=terminal_message or "上传完成",
    )


@router.get("/flash/recordings/{recording_id}")
async def get_flash_recording(recording_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        rid = uuid.UUID(recording_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid recording id")
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid, FlashRecording.user_id == user_id)
        )).scalar_one_or_none()
        if recording is None:
            raise HTTPException(status_code=404, detail="recording not found")
        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
    logger.info(
        "%s get recording user=%s recording=%s process=%s asr=%s tencent=%s",
        LOG_TAG,
        user_id,
        recording.id,
        recording.process_status,
        _file_status(recording, file),
        recording.tencent_status,
    )
    return {
        "ok": True,
        "recording": {
            "id": str(recording.id),
            "file_id": str(recording.file_id),
            "card_sn": recording.card_sn,
            "device_file_name": recording.device_file_name,
            "client_task_id": recording.client_task_id,
            "source": recording.source,
            "upload_status": recording.upload_status,
            "process_status": recording.process_status,
            "asr_status": _file_status(recording, file),
            "asr_provider": recording.asr_provider,
            "asr_mode": recording.asr_mode or "",
            "audio_format": recording.audio_format or "",
            "s3_key": recording.s3_key,
            "tencent_asr_task_id": recording.tencent_asr_task_id,
            "tencent_status": recording.tencent_status,
            "tencent_error_message": recording.tencent_error_message or "",
            "asr_text": recording.asr_text or "",
            "asr_error": recording.asr_error or "",
            "session_id": str(recording.session_id) if recording.session_id else None,
            "input_turn_id": str(recording.input_turn_id) if recording.input_turn_id else None,
            "result_summary": recording.result_summary or "",
            "result_cards": recording.result_cards or [],
            "created_at": recording.created_at.isoformat() if recording.created_at else None,
            "updated_at": recording.updated_at.isoformat() if recording.updated_at else None,
        },
    }


@router.post("/flash/recordings/{recording_id}/retry")
async def retry_flash_recording(recording_id: str, user_id: str = Depends(get_current_user_id)):
    try:
        rid = uuid.UUID(recording_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid recording id")
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid, FlashRecording.user_id == user_id)
        )).scalar_one_or_none()
        if recording is None:
            raise HTTPException(status_code=404, detail="recording not found")
        if recording.asr_text:
            recording.process_status = "asr_done"
            recording.retry_count = (recording.retry_count or 0) + 1
            recording.updated_at = _now()
            await db.commit()
            await enqueue(recording.id)
            logger.info(
                "%s retry recording pipeline user=%s recording=%s retry_count=%s",
                LOG_TAG,
                user_id,
                recording.id,
                recording.retry_count,
            )
            return {"ok": True, "queued": True, "mode": "pipeline"}
        recording.retry_count = (recording.retry_count or 0) + 1
        recording.process_status = "asr_processing"
        recording.tencent_status = recording.tencent_status or ("submitted" if recording.tencent_asr_task_id else "pending")
        recording.updated_at = _now()
        await db.commit()
        await enqueue(recording.id)
        logger.info(
            "%s retry recording ASR user=%s recording=%s task_id=%s retry_count=%s",
            LOG_TAG,
            user_id,
            recording.id,
            recording.tencent_asr_task_id,
            recording.retry_count,
        )
    return {
        "ok": True,
        "queued": True,
        "mode": "asr",
        "recording_id": str(rid),
        "error": "",
    }


@router.post("/flash/listening")
async def flash_listening(
    req: ListeningRequest,
    user_id: str = Depends(get_current_user_id),
):
    """
    Live mic state from the hardware capture layer (the W1/W2 card's
    flash-memo button). The host-side listen-watcher posts `on` when the
    button is held + recording starts and `off` on release. We just fan it
    out over the SSE channel so the UI can show a global「正在聆听」overlay.
    Ephemeral — no persistence.
    """
    state = "on" if req.state == "on" else "off"
    logger.info("%s listening state user=%s state=%s", LOG_TAG, user_id, state)
    publish_event(user_id, "listening", state=state)
    return {"ok": True, "state": state}
