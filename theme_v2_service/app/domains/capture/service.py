from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import utc_now
from app.domains.capture.models import CaptureFile, CaptureRecording, CaptureTurn
from app.domains.capture.schemas import (
    TencentAsrS3UploadRequest,
    TencentAsrSyncResultRequest,
    TimestampInput,
)
from app.domains.devices.models import Card, CardBinding
from app.jobs.queue import enqueue_job


class CardNotBound(Exception):
    pass


class ConflictingCapture(Exception):
    pass


@dataclass(frozen=True)
class CaptureAcceptanceResult:
    recording: CaptureRecording
    file: CaptureFile
    duplicate: bool
    message: str


@dataclass(frozen=True)
class RecordingResult:
    recording: CaptureRecording
    file: CaptureFile


def _utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _parse_timestamp(value: TimestampInput) -> datetime | None:
    if value in (None, ""):
        return None
    if isinstance(value, (int, float)):
        timestamp = float(value)
        if timestamp > 10_000_000_000:
            timestamp /= 1000
        try:
            return datetime.fromtimestamp(timestamp, tz=timezone.utc).replace(
                tzinfo=None
            )
        except (OverflowError, OSError, ValueError) as exc:
            raise ValueError("invalid capture timestamp") from exc
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError("invalid capture timestamp") from exc
        return _utc_naive(parsed)
    raise ValueError("invalid capture timestamp")


async def _ensure_card_bound(
    session: AsyncSession,
    user_id: str,
    card_sn: str,
) -> None:
    binding = await session.scalar(
        select(CardBinding)
        .join(Card, CardBinding.card_id == Card.id)
        .where(
            Card.card_sn == card_sn,
            CardBinding.user_id == user_id,
            CardBinding.bind_status == "bound",
            CardBinding.active_card_id.is_not(None),
        )
        .limit(1)
    )
    if binding is None:
        raise CardNotBound()


async def _find_existing(
    session: AsyncSession,
    *,
    user_id: str,
    client_task_id: str,
    card_sn: str,
    device_file_name: str,
    device_crc: int | None,
) -> CaptureRecording | None:
    recording = await session.scalar(
        select(CaptureRecording).where(
            CaptureRecording.user_id == user_id,
            CaptureRecording.client_task_id == client_task_id,
        )
    )
    if recording is None and device_crc is not None:
        recording = await session.scalar(
            select(CaptureRecording).where(
                CaptureRecording.user_id == user_id,
                CaptureRecording.card_sn == card_sn,
                CaptureRecording.device_file_name == device_file_name,
                CaptureRecording.device_crc == device_crc,
            )
        )
    return recording


def _assert_identity_matches(
    recording: CaptureRecording,
    *,
    card_sn: str,
    device_file_name: str,
) -> None:
    if recording.card_sn != card_sn:
        raise ConflictingCapture("duplicate key with different card_sn")
    if recording.device_file_name != device_file_name:
        raise ConflictingCapture("duplicate key with different device_file_name")


def _assert_same_sync_result(
    recording: CaptureRecording,
    command: TencentAsrSyncResultRequest,
) -> None:
    _assert_identity_matches(
        recording,
        card_sn=command.card_sn,
        device_file_name=command.device_file_name,
    )
    checks = (
        (recording.local_audio_sha256, command.local_audio_sha256.lower(), "audio sha256"),
        (recording.local_audio_size_bytes, command.local_audio_size_bytes, "audio size"),
        (recording.asr_mode, command.asr_mode, "asr_mode"),
        (recording.audio_format, command.audio_format, "audio_format"),
        ((recording.asr_text or "").strip(), command.asr_text.strip(), "asr_text"),
    )
    for existing, incoming, field in checks:
        if existing != incoming:
            raise ConflictingCapture(f"duplicate key with different {field}")
    existing_status = "failed" if recording.tencent_status == "failed" else "completed"
    if existing_status != command.asr_status:
        raise ConflictingCapture("duplicate key with different asr_status")


def _assert_same_s3_upload(
    recording: CaptureRecording,
    command: TencentAsrS3UploadRequest,
) -> None:
    _assert_identity_matches(
        recording,
        card_sn=command.card_sn,
        device_file_name=command.device_file_name,
    )
    audio_sha = (command.local_audio_sha256 or command.local_mp3_sha256 or "").lower()
    audio_size = command.local_audio_size_bytes or command.local_mp3_size_bytes
    checks = (
        (recording.s3_key, command.s3.s3_key, "s3_key"),
        (recording.s3_upload_url, command.s3.upload_url, "upload_url"),
        (recording.s3_audio_url, command.s3.audio_url, "audio_url"),
        (recording.local_mp3_sha256, _lower(command.local_mp3_sha256), "mp3 sha256"),
        (recording.local_audio_sha256 or "", audio_sha, "audio sha256"),
        (recording.local_audio_size_bytes, audio_size, "audio size"),
        (recording.asr_mode, command.asr_mode, "asr_mode"),
        (recording.audio_format, command.audio_format, "audio_format"),
    )
    for existing, incoming, field in checks:
        if existing != incoming:
            raise ConflictingCapture(f"duplicate key with different {field}")


def _lower(value: str | None) -> str | None:
    return value.lower() if value else None


async def _file_for_recording(
    session: AsyncSession,
    recording: CaptureRecording,
) -> CaptureFile:
    file = await session.get(CaptureFile, recording.file_id)
    if file is None:
        raise RuntimeError("capture file missing")
    return file


async def accept_sync_result(
    session: AsyncSession,
    user_id: str,
    command: TencentAsrSyncResultRequest,
) -> CaptureAcceptanceResult:
    await _ensure_card_bound(session, user_id, command.card_sn)
    existing = await _find_existing(
        session,
        user_id=user_id,
        client_task_id=command.client_task_id,
        card_sn=command.card_sn,
        device_file_name=command.device_file_name,
        device_crc=command.device_crc,
    )
    if existing is not None:
        _assert_same_sync_result(existing, command)
        file = await _file_for_recording(session, existing)
        if existing.process_status == "asr_done":
            await enqueue_job(
                session,
                job_type="capture_process",
                run_id=existing.id,
                dedupe_key=f"capture-process:{existing.id}",
            )
        return CaptureAcceptanceResult(
            recording=existing,
            file=file,
            duplicate=True,
            message=_message_for(existing),
        )

    text = command.asr_text.strip()
    asr_failed = command.asr_status == "failed"
    if asr_failed:
        process_status = "failed"
        message = command.error_message.strip() or command.asr_error.strip() or "识别失败已记录"
    elif not text:
        process_status = "empty"
        message = "文件没内容"
    else:
        process_status = "asr_done"
        message = "上传完成"
    now = utc_now()
    file = CaptureFile(
        user_id=user_id,
        storage_url=f"client-sync-asr:{command.client_task_id}",
        file_type="audio/opus",
        source_tag="flash",
        asr_status="failed" if asr_failed else "completed",
        created_at=now,
        updated_at=now,
    )
    session.add(file)
    await session.flush()
    recording = CaptureRecording(
        user_id=user_id,
        file_id=file.id,
        card_sn=command.card_sn,
        device_file_name=command.device_file_name,
        client_task_id=command.client_task_id,
        source=command.source,
        device_crc=command.device_crc,
        device_size_bytes=command.device_size_bytes,
        capture_started_at=_parse_timestamp(command.capture_started_at),
        capture_ended_at=_parse_timestamp(command.capture_ended_at),
        local_audio_sha256=command.local_audio_sha256.lower(),
        local_audio_size_bytes=command.local_audio_size_bytes,
        audio_format=command.audio_format,
        asr_mode=command.asr_mode,
        s3_key=f"client-sync-asr:{command.client_task_id}",
        s3_upload_headers_json={},
        tencent_speaker_diarization=1 if command.speaker_diarization else 0,
        tencent_status="failed" if asr_failed else "finished",
        tencent_error_message=message if asr_failed else None,
        tencent_task_response_json=command.raw_response,
        tencent_result_response_json=command.raw_response,
        upload_status="uploaded",
        process_status=process_status,
        asr_provider=command.asr_provider,
        asr_text=text,
        asr_segments_json=command.asr_segments,
        asr_error=message if asr_failed else None,
        result_summary="" if process_status in {"failed", "empty"} else None,
        result_records_json=[],
        error_message=message if process_status in {"failed", "empty"} else None,
        accepted_at=now,
        processed_at=now if process_status in {"failed", "empty"} else None,
        created_at=now,
        updated_at=now,
    )
    session.add(recording)
    await session.flush()
    if text:
        session.add(
            CaptureTurn(
                recording_id=recording.id,
                user_id=user_id,
                transcript=text,
                source=command.source,
                provenance_json={
                    "kind": "hardware_audio",
                    "card_sn": command.card_sn,
                    "device_file_name": command.device_file_name,
                    "asr_provider": command.asr_provider,
                },
            )
        )
    if process_status == "asr_done":
        await enqueue_job(
            session,
            job_type="capture_process",
            run_id=recording.id,
            dedupe_key=f"capture-process:{recording.id}",
        )
    await session.flush()
    return CaptureAcceptanceResult(
        recording=recording,
        file=file,
        duplicate=False,
        message=message,
    )


async def accept_s3_upload(
    session: AsyncSession,
    user_id: str,
    command: TencentAsrS3UploadRequest,
) -> CaptureAcceptanceResult:
    await _ensure_card_bound(session, user_id, command.card_sn)
    existing = await _find_existing(
        session,
        user_id=user_id,
        client_task_id=command.client_task_id,
        card_sn=command.card_sn,
        device_file_name=command.device_file_name,
        device_crc=command.device_crc,
    )
    if existing is not None:
        _assert_same_s3_upload(existing, command)
        file = await _file_for_recording(session, existing)
        await enqueue_job(
            session,
            job_type="capture_asr",
            run_id=existing.id,
            dedupe_key=f"capture-asr:{existing.id}",
        )
        return CaptureAcceptanceResult(
            recording=existing,
            file=file,
            duplicate=True,
            message="任务已添加",
        )

    now = utc_now()
    audio_sha = _lower(command.local_audio_sha256 or command.local_mp3_sha256)
    audio_size = command.local_audio_size_bytes or command.local_mp3_size_bytes
    file = CaptureFile(
        user_id=user_id,
        storage_url=command.s3.s3_key,
        file_type=command.s3.content_type,
        source_tag="flash",
        asr_status="processing",
        created_at=now,
        updated_at=now,
    )
    session.add(file)
    await session.flush()
    recording = CaptureRecording(
        user_id=user_id,
        file_id=file.id,
        card_sn=command.card_sn,
        device_file_name=command.device_file_name,
        client_task_id=command.client_task_id,
        source=command.source,
        device_crc=command.device_crc,
        device_size_bytes=command.device_size_bytes,
        capture_started_at=_parse_timestamp(command.capture_started_at),
        capture_ended_at=_parse_timestamp(command.capture_ended_at),
        local_mp3_sha256=_lower(command.local_mp3_sha256),
        local_mp3_size_bytes=command.local_mp3_size_bytes,
        local_audio_sha256=audio_sha,
        local_audio_size_bytes=audio_size,
        audio_format=command.audio_format,
        asr_mode=command.asr_mode,
        s3_key=command.s3.s3_key,
        s3_content_type=command.s3.content_type,
        s3_upload_url=command.s3.upload_url,
        s3_audio_url=command.s3.audio_url,
        s3_upload_headers_json=command.s3.headers,
        s3_upload_expires_in=command.s3.upload_expires_in,
        s3_uploaded_at=_parse_timestamp(command.s3.uploaded_at),
        tencent_engine_type=command.engine_type,
        tencent_speaker_diarization=1 if command.speaker_diarization else 0,
        tencent_hotword_list=command.hotword_list,
        tencent_status="pending",
        tencent_task_response_json={},
        upload_status="uploaded",
        process_status="asr_processing",
        asr_provider="tencent_asr_s3_async",
        asr_segments_json=[],
        result_records_json=[],
        accepted_at=now,
        created_at=now,
        updated_at=now,
    )
    session.add(recording)
    await session.flush()
    await enqueue_job(
        session,
        job_type="capture_asr",
        run_id=recording.id,
        dedupe_key=f"capture-asr:{recording.id}",
    )
    return CaptureAcceptanceResult(
        recording=recording,
        file=file,
        duplicate=False,
        message="任务已添加",
    )


def _message_for(recording: CaptureRecording) -> str:
    if recording.process_status == "empty":
        return "文件没内容"
    if recording.process_status == "failed":
        return recording.error_message or recording.asr_error or "识别失败已记录"
    return "上传完成"


def asr_status(recording: CaptureRecording, file: CaptureFile) -> str:
    if file.asr_status:
        return file.asr_status
    if recording.process_status in {
        "asr_done",
        "agent_processing",
        "done",
        "empty",
    }:
        return "completed"
    if recording.process_status == "asr_processing":
        return "processing"
    if recording.process_status == "failed":
        return "failed"
    return "pending"


def acceptance_payload(result: CaptureAcceptanceResult) -> dict:
    recording = result.recording
    return {
        "ok": True,
        "accepted": True,
        "duplicate": result.duplicate,
        "recording_id": recording.id,
        "file_id": recording.file_id,
        "asr_status": asr_status(recording, result.file),
        "asr_text": recording.asr_text or "",
        "pipeline_status": recording.process_status,
        "message": result.message,
        "error": "",
    }


async def get_recording(
    session: AsyncSession,
    user_id: str,
    recording_id: str,
) -> RecordingResult | None:
    recording = await session.scalar(
        select(CaptureRecording).where(
            CaptureRecording.id == recording_id,
            CaptureRecording.user_id == user_id,
        )
    )
    if recording is None:
        return None
    file = await _file_for_recording(session, recording)
    return RecordingResult(recording=recording, file=file)


def recording_payload(result: RecordingResult) -> dict:
    recording = result.recording
    return {
        "ok": True,
        "recording": {
            "id": recording.id,
            "file_id": recording.file_id,
            "card_sn": recording.card_sn,
            "device_file_name": recording.device_file_name,
            "client_task_id": recording.client_task_id,
            "source": recording.source,
            "upload_status": recording.upload_status,
            "process_status": recording.process_status,
            "asr_status": asr_status(recording, result.file),
            "asr_provider": recording.asr_provider,
            "asr_mode": recording.asr_mode,
            "audio_format": recording.audio_format,
            "s3_key": recording.s3_key,
            "tencent_asr_task_id": recording.tencent_asr_task_id,
            "tencent_status": recording.tencent_status,
            "tencent_error_message": recording.tencent_error_message or "",
            "asr_text": recording.asr_text or "",
            "asr_error": recording.asr_error or "",
            "session_id": None,
            "input_turn_id": None,
            "result_summary": recording.result_summary or "",
            "result_cards": recording.result_records_json or [],
            "created_at": recording.created_at,
            "updated_at": recording.updated_at,
        },
    }
