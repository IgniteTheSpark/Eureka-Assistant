"""In-process queue for flash-file post-ASR processing."""
from __future__ import annotations

import asyncio
import logging
import re
import time
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import and_, or_, select

from config import settings
from core.asr.base import AsrError
from core.asr.tencent_s3_async import (
    TencentS3AsyncAsrClient,
    TencentSyncAsrClient,
    parse_finished_result,
    parse_sync_result,
)
from core.flash_service import process_flash_text
from core.notifications import publish_event
from db.database import AsyncSessionLocal
from db.models import File, FlashRecording

_queue: asyncio.Queue[str] = asyncio.Queue()
_workers: list[asyncio.Task] = []
logger = logging.getLogger("flash_file")
LOG_TAG = "[FlashFile]"


def _now():
    return datetime.now(timezone.utc)


def publish_flash_file_status(recording: FlashRecording, status: str, message: str = "") -> None:
    logger.info(
        "%s publish status user=%s recording=%s client_task=%s file=%s status=%s message=%s",
        LOG_TAG,
        recording.user_id,
        recording.id,
        recording.client_task_id,
        recording.device_file_name,
        status,
        message,
    )
    publish_event(
        recording.user_id,
        "flash_file_status",
        type="flash_file_status",
        recording_id=str(recording.id),
        client_task_id=recording.client_task_id,
        device_file_name=recording.device_file_name,
        session_id=str(recording.session_id) if recording.session_id else "",
        input_turn_id=str(recording.input_turn_id) if recording.input_turn_id else "",
        status=status,
        message=message,
    )


async def enqueue(recording_id: str | uuid.UUID) -> None:
    await _queue.put(str(recording_id))
    logger.info("%s queue enqueue recording=%s size=%s", LOG_TAG, recording_id, _queue.qsize())


def start_flash_file_workers(concurrency: int = 2) -> None:
    if _workers:
        logger.info("%s workers already started count=%s", LOG_TAG, len(_workers))
        return
    for i in range(max(1, concurrency)):
        _workers.append(asyncio.create_task(_worker_loop(i)))
    logger.info("%s workers started count=%s", LOG_TAG, len(_workers))
    asyncio.create_task(recover_pending_on_startup())


async def stop_flash_file_workers() -> None:
    logger.info("%s stopping workers count=%s", LOG_TAG, len(_workers))
    for task in _workers:
        task.cancel()
    for task in list(_workers):
        try:
            await task
        except asyncio.CancelledError:
            pass
    _workers.clear()
    logger.info("%s workers stopped", LOG_TAG)


async def recover_pending_on_startup() -> None:
    stale_processing_cutoff = _now() - timedelta(minutes=10)
    async with AsyncSessionLocal() as db:
        ids = (await db.execute(
            select(FlashRecording.id).where(
                or_(
                    FlashRecording.process_status.in_(["pending", "asr_processing", "asr_done"]),
                    and_(
                        FlashRecording.process_status == "processing_flash",
                        FlashRecording.updated_at <= stale_processing_cutoff,
                    ),
                )
            )
        )).scalars().all()
    for rid in ids:
        await enqueue(rid)
    logger.info("%s recovered pending recordings count=%s", LOG_TAG, len(ids))


async def _worker_loop(index: int) -> None:
    while True:
        recording_id = await _queue.get()
        logger.info("%s worker=%s picked recording=%s", LOG_TAG, index, recording_id)
        try:
            await process_recording(recording_id)
        except Exception as e:
            logger.exception("%s worker=%s unhandled error recording=%s", LOG_TAG, index, recording_id)
            try:
                await _mark_processing_failed(
                    uuid.UUID(str(recording_id)),
                    f"flash file worker failed: {str(e)[:900]}",
                )
            except Exception:
                pass
        finally:
            _queue.task_done()
            logger.info("%s worker=%s done recording=%s queue_size=%s", LOG_TAG, index, recording_id, _queue.qsize())


async def process_recording(recording_id: str | uuid.UUID) -> None:
    rid = uuid.UUID(str(recording_id))
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status == "done":
            logger.info("%s process skip recording=%s reason=%s", LOG_TAG, rid, "missing_or_done")
            return
        status = recording.process_status
        logger.info(
            "%s process recording=%s status=%s task_id=%s file=%s",
            LOG_TAG,
            rid,
            status,
            recording.tencent_asr_task_id,
            recording.device_file_name,
        )
    if status in {"pending", "asr_processing"}:
        async with AsyncSessionLocal() as db:
            asr_mode = (await db.execute(
                select(FlashRecording.asr_mode).where(FlashRecording.id == rid)
            )).scalar_one_or_none()
        if asr_mode == "sync":
            await recognize_tencent_sync_asr(rid)
        else:
            await poll_tencent_asr_until_terminal(rid)
    async with AsyncSessionLocal() as db:
        latest_status = (await db.execute(
            select(FlashRecording.process_status).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
    if latest_status in {"asr_done", "processing_flash"}:
        if await _has_prior_unfinished_recording(rid):
            logger.info("%s process recording=%s waits for prior flash recording", LOG_TAG, rid)
            await asyncio.sleep(3)
            await enqueue(rid)
            return
        await process_recording_after_asr(rid)
    else:
        logger.info("%s process recording=%s latest_status=%s no pipeline run", LOG_TAG, rid, latest_status)


async def poll_tencent_asr_until_terminal(recording_id: str | uuid.UUID) -> None:
    rid = uuid.UUID(str(recording_id))
    deadline = time.monotonic() + max(30, settings.tencent_asr_result_poll_timeout_seconds)
    interval = max(1, settings.tencent_asr_result_poll_interval_seconds)
    client = TencentS3AsyncAsrClient()

    try:
        await create_tencent_asr_task_if_needed(rid, client=client)
    except AsrError:
        return

    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s ASR poll skip recording=%s reason=missing_or_status", LOG_TAG, rid)
            return
        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
        recording.process_status = "asr_processing"
        recording.tencent_status = recording.tencent_status or "submitted"
        recording.updated_at = _now()
        if file:
            file.asr_status = "processing"
        await db.commit()
        await db.refresh(recording)
        publish_flash_file_status(recording, "asr_processing", "语音识别任务处理中")
        task_id = recording.tencent_asr_task_id
        if not task_id:
            await _mark_asr_failed(rid, "Tencent ASR task_id missing", raw=None)
            return
        logger.info(
            "%s ASR poll start recording=%s task_id=%s timeout=%ss interval=%ss",
            LOG_TAG,
            rid,
            task_id,
            settings.tencent_asr_result_poll_timeout_seconds,
            interval,
        )

    poll_count = 0
    while True:
        delay = 2 if poll_count == 0 else (3 if poll_count == 1 else interval)
        if time.monotonic() + delay > deadline:
            logger.info("%s ASR poll timeout before next request recording=%s task_id=%s", LOG_TAG, rid, task_id)
            await _mark_asr_no_content(rid, raw=None)
            return
        await asyncio.sleep(delay)
        poll_count += 1
        try:
            data = await client.fetch_task_result(task_id)
        except AsrError as e:
            logger.info(
                "%s ASR poll request error recording=%s task_id=%s poll=%s error=%s",
                LOG_TAG,
                rid,
                task_id,
                poll_count,
                str(e)[:300],
            )
            if time.monotonic() >= deadline:
                await _mark_asr_no_content(rid, raw=None)
                return
            continue

        status = str(data.get("status") or "").lower()
        raw = data.get("_raw_response") or data
        logger.info(
            "%s ASR poll result recording=%s task_id=%s poll=%s status=%s text_len=%s segments=%s",
            LOG_TAG,
            rid,
            task_id,
            poll_count,
            status,
            len(data.get("text") or ""),
            len(data.get("segments") or []),
        )
        if status in {"pending", "running"}:
            async with AsyncSessionLocal() as db:
                recording = (await db.execute(
                    select(FlashRecording).where(FlashRecording.id == rid)
                )).scalar_one_or_none()
                if recording is None or recording.process_status not in {"pending", "asr_processing"}:
                    return
                recording.tencent_status = status
                recording.tencent_result_response = raw
                recording.updated_at = _now()
                await db.commit()
            if time.monotonic() >= deadline:
                await _mark_asr_no_content(rid, raw=raw)
                return
            continue

        if status == "finished":
            if not (data.get("text") or "").strip():
                await _mark_asr_no_content(rid, raw=raw)
                return
            try:
                result = parse_finished_result(data)
            except AsrError as e:
                await _mark_asr_failed(rid, str(e)[:1000], raw=raw)
                return
            async with AsyncSessionLocal() as db:
                recording = (await db.execute(
                    select(FlashRecording).where(FlashRecording.id == rid)
                )).scalar_one_or_none()
                if recording is None or recording.process_status not in {"pending", "asr_processing"}:
                    return
                file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
                recording.tencent_status = "finished"
                recording.tencent_error_message = None
                recording.tencent_result_response = raw
                recording.process_status = "asr_done"
                recording.asr_provider = TencentS3AsyncAsrClient.provider_name
                recording.asr_text = result.text
                recording.asr_segments = result.segments
                recording.asr_error = None
                recording.updated_at = _now()
                if file:
                    file.asr_status = "completed"
                    if result.duration_sec is not None:
                        file.duration_sec = int(round(result.duration_sec))
                await db.commit()
                await db.refresh(recording)
            publish_flash_file_status(recording, "asr_done", "语音识别完成")
            logger.info(
                "%s ASR completed recording=%s task_id=%s text_len=%s segments=%s duration=%s",
                LOG_TAG,
                rid,
                task_id,
                len(result.text),
                len(result.segments),
                result.duration_sec,
            )
            return

        if status == "failed":
            logger.info(
                "%s ASR failed status from provider recording=%s task_id=%s error=%s",
                LOG_TAG,
                rid,
                task_id,
                data.get("error_message"),
            )
            await _mark_asr_no_content(rid, raw=raw)
            return

        logger.info("%s ASR unknown status recording=%s task_id=%s status=%s", LOG_TAG, rid, task_id, status)
        await _mark_asr_failed(rid, f"unknown Tencent ASR status: {status}", raw=raw)
        return


async def create_tencent_asr_task_if_needed(
    recording_id: str | uuid.UUID,
    *,
    client: TencentS3AsyncAsrClient | None = None,
) -> FlashRecording | None:
    rid = uuid.UUID(str(recording_id))
    client = client or TencentS3AsyncAsrClient()

    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s ASR task create skip recording=%s reason=missing_or_status", LOG_TAG, rid)
            return recording
        if recording.tencent_asr_task_id:
            logger.info("%s ASR task already exists recording=%s task_id=%s", LOG_TAG, rid, recording.tencent_asr_task_id)
            return recording
        if not (recording.s3_audio_url or "").strip():
            recording.tencent_status = "failed"
            recording.tencent_error_message = "S3 audio_url missing"
            recording.process_status = "failed"
            recording.asr_error = "S3 audio_url missing"
            recording.error_message = "S3 audio_url missing"
            recording.updated_at = _now()
            file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
            if file:
                file.asr_status = "failed"
            await db.commit()
            await db.refresh(recording)
            publish_flash_file_status(recording, "failed", "S3 audio_url missing")
            raise AsrError("S3 audio_url missing")

        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
        recording.process_status = "asr_processing"
        recording.tencent_status = "submitting"
        recording.updated_at = _now()
        if file:
            file.asr_status = "processing"
        await db.commit()
        await db.refresh(recording)
        audio_url = recording.s3_audio_url
        engine_type = recording.tencent_engine_type or "16k_zh"
        speaker_diarization = bool(recording.tencent_speaker_diarization if recording.tencent_speaker_diarization is not None else 0)
        hotword_list = recording.tencent_hotword_list or ""

    try:
        data = await client.create_s3_task(
            audio_url=audio_url,
            engine_type=engine_type,
            speaker_diarization=speaker_diarization,
            hotword_list=hotword_list,
        )
    except AsrError as e:
        await _mark_asr_failed(rid, str(e)[:1000], raw=None)
        raise

    task_id = str(data.get("task_id") or "").strip()
    raw = data.get("_raw_response") or data
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s ASR task save skip recording=%s reason=missing_or_status", LOG_TAG, rid)
            return recording
        recording.tencent_asr_task_id = task_id
        recording.tencent_status = "submitted"
        recording.tencent_task_response = raw
        recording.updated_at = _now()
        await db.commit()
        await db.refresh(recording)
    publish_flash_file_status(recording, "accepted", "任务已添加")
    logger.info("%s ASR task created recording=%s task_id=%s", LOG_TAG, rid, task_id)
    return recording


async def recognize_tencent_sync_asr(
    recording_id: str | uuid.UUID,
    *,
    client: TencentSyncAsrClient | None = None,
) -> FlashRecording | None:
    rid = uuid.UUID(str(recording_id))
    client = client or TencentSyncAsrClient()

    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s sync ASR skip recording=%s reason=missing_or_status", LOG_TAG, rid)
            return recording
        if not (recording.s3_audio_url or "").strip():
            await _mark_asr_failed(rid, "S3 audio_url missing", raw=None)
            raise AsrError("S3 audio_url missing")

        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
        recording.process_status = "asr_processing"
        recording.tencent_status = "submitting"
        recording.asr_provider = TencentSyncAsrClient.provider_name
        recording.updated_at = _now()
        if file:
            file.asr_status = "processing"
        await db.commit()
        await db.refresh(recording)
        audio_url = recording.s3_audio_url
        speaker_diarization = bool(recording.tencent_speaker_diarization if recording.tencent_speaker_diarization is not None else 0)
        publish_flash_file_status(recording, "asr_processing", "语音识别处理中")

    try:
        data = await client.recognize_audio_url(
            audio_url=audio_url,
            speaker_diarization=speaker_diarization,
        )
    except AsrError as e:
        await _mark_asr_failed(rid, str(e)[:1000], raw=None)
        raise

    raw = data.get("_raw_response") or data
    if not (data.get("text") or "").strip():
        await _mark_asr_no_content(rid, raw=raw)
        return None

    try:
        result = parse_sync_result(data)
    except AsrError:
        await _mark_asr_no_content(rid, raw=raw)
        return None

    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s sync ASR save skip recording=%s reason=missing_or_status", LOG_TAG, rid)
            return recording
        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
        recording.tencent_status = "finished"
        recording.tencent_error_message = None
        recording.tencent_result_response = raw
        recording.tencent_task_response = raw
        recording.process_status = "asr_done"
        recording.asr_provider = TencentSyncAsrClient.provider_name
        recording.asr_text = result.text
        recording.asr_segments = result.segments
        recording.asr_error = None
        recording.updated_at = _now()
        if file:
            file.asr_status = "completed"
            if result.duration_sec is not None:
                file.duration_sec = int(round(result.duration_sec))
        await db.commit()
        await db.refresh(recording)
    publish_flash_file_status(recording, "asr_done", "语音识别完成")
    logger.info(
        "%s sync ASR completed recording=%s text_len=%s segments=%s duration=%s",
        LOG_TAG,
        rid,
        len(result.text),
        len(result.segments),
        result.duration_sec,
    )
    return recording


async def _mark_asr_failed(recording_id: uuid.UUID, message: str, raw: dict | None = None) -> None:
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == recording_id)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s mark ASR failed skip recording=%s", LOG_TAG, recording_id)
            return
        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
        recording.tencent_status = "failed"
        recording.tencent_error_message = message
        if raw is not None:
            recording.tencent_result_response = raw
        recording.process_status = "failed"
        recording.asr_error = message
        recording.error_message = message
        recording.updated_at = _now()
        if file:
            file.asr_status = "failed"
        await db.commit()
        await db.refresh(recording)
    publish_flash_file_status(recording, "failed", message)
    logger.info("%s ASR marked failed recording=%s message=%s", LOG_TAG, recording_id, message)


async def _mark_asr_no_content(recording_id: uuid.UUID, raw: dict | None = None) -> None:
    message = "文件没内容"
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == recording_id)
        )).scalar_one_or_none()
        if recording is None or recording.process_status not in {"pending", "asr_processing"}:
            logger.info("%s mark ASR no-content skip recording=%s", LOG_TAG, recording_id)
            return
        file = (await db.execute(select(File).where(File.id == recording.file_id))).scalar_one_or_none()
        recording.tencent_status = "finished"
        recording.tencent_error_message = message
        if raw is not None:
            recording.tencent_result_response = raw
        recording.process_status = "done"
        recording.asr_text = ""
        recording.asr_segments = []
        recording.asr_error = None
        recording.error_message = message
        recording.result_summary = ""
        recording.result_cards = []
        recording.updated_at = _now()
        recording.processed_at = _now()
        if file:
            file.asr_status = "completed"
        await db.commit()
        await db.refresh(recording)
    publish_flash_file_status(recording, "done", message)
    logger.info("%s ASR no content completed recording=%s", LOG_TAG, recording_id)


def _recording_file_time(device_file_name: str | None) -> datetime | None:
    match = re.match(r"^F(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})", (device_file_name or "").strip(), re.I)
    if not match:
        return None
    try:
        return datetime(
            int(match.group(1)),
            int(match.group(2)),
            int(match.group(3)),
            int(match.group(4)),
            int(match.group(5)),
            int(match.group(6)),
            tzinfo=timezone.utc,
        )
    except ValueError:
        return None


def _normalize_dt(value: datetime | None) -> datetime:
    if value is None:
        return datetime.max.replace(tzinfo=timezone.utc)
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _recording_order_key(recording: FlashRecording) -> tuple[datetime, str]:
    order_time = (
        recording.capture_started_at
        or _recording_file_time(recording.device_file_name)
        or recording.created_at
    )
    return (_normalize_dt(order_time), str(recording.id))


async def _has_prior_unfinished_recording(recording_id: uuid.UUID) -> bool:
    async with AsyncSessionLocal() as db:
        current = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == recording_id)
        )).scalar_one_or_none()
        if current is None:
            return False
        candidates = (await db.execute(
            select(FlashRecording).where(
                FlashRecording.user_id == current.user_id,
                FlashRecording.id != current.id,
                FlashRecording.process_status.in_(["pending", "asr_processing", "asr_done", "processing_flash"]),
            )
        )).scalars().all()

    current_key = _recording_order_key(current)
    for candidate in candidates:
        if _recording_order_key(candidate) < current_key:
            logger.info(
                "%s prior unfinished recording blocks pipeline current=%s prior=%s prior_status=%s",
                LOG_TAG,
                recording_id,
                candidate.id,
                candidate.process_status,
            )
            return True
    return False


async def process_recording_after_asr(recording_id: str | uuid.UUID) -> None:
    rid = uuid.UUID(str(recording_id))
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None or recording.process_status in {"done", "failed"}:
            logger.info("%s pipeline skip recording=%s reason=missing_done_failed", LOG_TAG, rid)
            return
        if recording.process_status == "processing_flash" and _is_recent(recording.updated_at):
            logger.info("%s pipeline skip recent processing recording=%s", LOG_TAG, rid)
            return
        if not (recording.asr_text or "").strip():
            recording.process_status = "failed"
            recording.error_message = "asr_text empty"
            recording.updated_at = _now()
            await db.commit()
            publish_flash_file_status(recording, "failed", "ASR 文本为空")
            logger.info("%s pipeline failed empty ASR text recording=%s", LOG_TAG, rid)
            return

        recording.process_status = "processing_flash"
        recording.updated_at = _now()
        await db.commit()
        publish_flash_file_status(recording, "processing_flash", "正在整理闪念")
        logger.info(
            "%s pipeline start recording=%s file_id=%s text_len=%s segments=%s",
            LOG_TAG,
            rid,
            recording.file_id,
            len(recording.asr_text or ""),
            len(recording.asr_segments or []),
        )

        user_id = recording.user_id
        text = recording.asr_text
        file_id = str(recording.file_id)
        provider = recording.asr_provider
        segments = recording.asr_segments
        client_task_id = recording.client_task_id
        device_file_name = recording.device_file_name

    try:
        result = await process_flash_text(
            user_id=user_id,
            text=text,
            source="voice",
            file_id=file_id,
            recording_id=str(rid),
            asr_provider=provider,
            segments=segments if isinstance(segments, list) else None,
            client_task_id=client_task_id,
            device_file_name=device_file_name,
        )
    except Exception as e:
        logger.exception("%s pipeline exception recording=%s", LOG_TAG, rid)
        await _mark_processing_failed(rid, f"flash pipeline failed: {str(e)[:900]}")
        return

    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == rid)
        )).scalar_one_or_none()
        if recording is None:
            return
        if result.get("ok"):
            recording.process_status = "done"
            recording.session_id = uuid.UUID(result["session_id"]) if result.get("session_id") else None
            recording.input_turn_id = uuid.UUID(result["input_turn_id"]) if result.get("input_turn_id") else None
            recording.result_summary = result.get("summary") or ""
            recording.result_cards = result.get("cards") or []
            recording.error_message = None
            recording.processed_at = _now()
            recording.updated_at = _now()
            await db.commit()
            publish_flash_file_status(recording, "done", "闪念已整理")
            logger.info(
                "%s pipeline completed recording=%s session=%s input_turn=%s cards=%s",
                LOG_TAG,
                rid,
                recording.session_id,
                recording.input_turn_id,
                len(recording.result_cards or []),
            )
            return

        recording.process_status = "failed"
        recording.session_id = uuid.UUID(result["session_id"]) if result.get("session_id") else recording.session_id
        recording.input_turn_id = uuid.UUID(result["input_turn_id"]) if result.get("input_turn_id") else recording.input_turn_id
        recording.error_message = result.get("error") or "flash pipeline failed"
        recording.updated_at = _now()
        await db.commit()
        await db.refresh(recording)
        publish_flash_file_status(recording, "failed", recording.error_message or "处理失败")
        logger.info("%s pipeline failed recording=%s error=%s", LOG_TAG, rid, recording.error_message)


async def _mark_processing_failed(recording_id: uuid.UUID, message: str) -> None:
    async with AsyncSessionLocal() as db:
        recording = (await db.execute(
            select(FlashRecording).where(FlashRecording.id == recording_id)
        )).scalar_one_or_none()
        if recording is None or recording.process_status == "done":
            logger.info("%s mark processing failed skip recording=%s", LOG_TAG, recording_id)
            return
        recording.process_status = "failed"
        recording.error_message = message
        recording.updated_at = _now()
        await db.commit()
        await db.refresh(recording)
    publish_flash_file_status(recording, "failed", message)
    logger.info("%s processing marked failed recording=%s message=%s", LOG_TAG, recording_id, message)


def _is_recent(value: datetime | None, window: timedelta = timedelta(minutes=10)) -> bool:
    if value is None:
        return False
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return (_now() - value) < window
