import asyncio
import time
from dataclasses import dataclass
from datetime import date, datetime, time as datetime_time, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import new_uuid, utc_now
from app.config import get_settings
from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.capture.models import (
    CaptureFile,
    CaptureRecording,
    CaptureTurn,
    FlashChatMessage,
)
from app.domains.capture.schemas import (
    TencentAsrS3UploadRequest,
    TencentAsrSyncResultRequest,
    TimestampInput,
    FlashRequest,
)
from app.domains.devices.models import Card, CardBinding
from app.domains.notifications.service import publish_domain_event
from app.domains.sessions import service as session_service
from app.domains.sessions.models import ChatSession, InputTurn, SessionMessage
from app.jobs.queue import enqueue_job, enqueue_or_requeue_job


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
    turn: CaptureTurn | None = None


@dataclass(frozen=True)
class TextCaptureResult:
    recording: CaptureRecording
    file: CaptureFile
    turn: CaptureTurn


@dataclass(frozen=True)
class CaptureSessionMaterialization:
    session: ChatSession
    input_turn: InputTurn
    user_message: SessionMessage
    agent_message: SessionMessage


def _recording_timestamp(recording: CaptureRecording) -> datetime:
    return recording.capture_started_at or recording.created_at


def _as_utc_z(value: datetime | None) -> str | None:
    if value is None:
        return None
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _local_capture_date(
    recording: CaptureRecording,
    *,
    timezone_name: str,
) -> date:
    timestamp = _recording_timestamp(recording)
    if timestamp.tzinfo is None:
        timestamp = timestamp.replace(tzinfo=timezone.utc)
    return timestamp.astimezone(ZoneInfo(timezone_name)).date()


async def materialize_final_capture(
    session: AsyncSession,
    recording: CaptureRecording,
    *,
    timezone_name: str,
) -> CaptureSessionMaterialization:
    """Persist the visible Flash turn before Agent organization starts.

    The recording links are the idempotency checkpoint. All rows, the process
    job, and the Session invalidation are committed by the caller together.
    """
    text = (recording.asr_text or "").strip()
    if not text:
        raise ValueError("cannot materialize an empty capture")

    if recording.session_id and recording.input_turn_id and recording.agent_message_id:
        daily_session = await session.get(ChatSession, recording.session_id)
        input_turn = await session.get(InputTurn, recording.input_turn_id)
        agent_message = await session.get(SessionMessage, recording.agent_message_id)
        user_message = await session.scalar(
            select(SessionMessage).where(
                SessionMessage.session_id == recording.session_id,
                SessionMessage.input_turn_id == recording.input_turn_id,
                SessionMessage.role == "user",
            )
        )
        if all((daily_session, input_turn, user_message, agent_message)):
            return CaptureSessionMaterialization(
                session=daily_session,
                input_turn=input_turn,
                user_message=user_message,
                agent_message=agent_message,
            )

    local_date = _local_capture_date(recording, timezone_name=timezone_name)
    daily_session = await session_service.get_or_create_daily_flash_session(
        session,
        recording.user_id,
        local_date,
    )
    input_turn = await session_service.create_input_turn(
        session,
        daily_session,
        text=text,
        source="voice",
        file_id=recording.file_id,
        recording_id=recording.id,
        segments=recording.asr_segments_json or [],
        asr_provider=recording.asr_provider,
        provenance={
            "kind": "hardware_audio",
            "recording_id": recording.id,
            "card_sn": recording.card_sn,
            "device_capture_key": recording.device_capture_key,
            "device_kind": recording.device_kind,
            "device_id": recording.device_id,
            "device_file_name": recording.device_file_name,
            "capture_source": recording.source,
            "capture_started_at": _as_utc_z(recording.capture_started_at),
            "capture_ended_at": _as_utc_z(recording.capture_ended_at),
            "local_audio_sha256": recording.local_audio_sha256,
            "local_audio_size_bytes": recording.local_audio_size_bytes,
        },
    )
    user_message = SessionMessage(
        session_id=daily_session.id,
        user_id=recording.user_id,
        role="user",
        status="done",
        text=text,
        input_turn_id=input_turn.id,
    )
    agent_message = SessionMessage(
        session_id=daily_session.id,
        user_id=recording.user_id,
        role="agent",
        status="running",
        text="",
        input_turn_id=input_turn.id,
    )
    session.add_all([user_message, agent_message])
    await session.flush()
    recording.session_id = daily_session.id
    recording.input_turn_id = input_turn.id
    recording.agent_message_id = agent_message.id

    existing_capture_turn = await session.scalar(
        select(CaptureTurn).where(CaptureTurn.recording_id == recording.id)
    )
    if existing_capture_turn is None:
        session.add(
            CaptureTurn(
                recording_id=recording.id,
                user_id=recording.user_id,
                transcript=text,
                source=recording.source,
                provenance_json=input_turn.provenance_json,
            )
        )
    await enqueue_job(
        session,
        job_type="capture_process",
        run_id=recording.id,
        dedupe_key=f"capture-process:{recording.id}",
    )
    await session_service.publish_session_changed(
        session,
        daily_session,
        reason="capture_asr_final",
    )
    await session.flush()
    return CaptureSessionMaterialization(
        session=daily_session,
        input_turn=input_turn,
        user_message=user_message,
        agent_message=agent_message,
    )


async def publish_capture_status(
    session: AsyncSession,
    recording: CaptureRecording,
    *,
    status: str,
    message: str,
    display_phase: str | None = None,
    result_count: int | None = None,
) -> None:
    resolved_phase = display_phase or _capture_display_phase(status)
    if result_count is None and status == "done":
        result_count = len(recording.result_records_json or [])
    await publish_domain_event(
        session,
        event_type="flash_file_status",
        aggregate_type="capture_recording",
        aggregate_id=recording.id,
        user_id=recording.user_id,
        payload={
            "recording_id": recording.id,
            "file_id": recording.file_id,
            "client_task_id": recording.client_task_id,
            "device_capture_key": recording.device_capture_key,
            "card_sn": recording.card_sn,
            "device_file_name": recording.device_file_name,
            "status": status,
            "pipeline_status": recording.process_status,
            "message": message,
            "display_phase": resolved_phase,
            "source": _capture_display_source(recording),
            "is_realtime": recording.source in {"voice", "realtime"},
            "session_id": recording.session_id,
            "input_turn_id": recording.input_turn_id,
            "result_count": result_count,
        },
    )


def _capture_display_phase(status: str) -> str:
    return {
        "accepted": "receiving",
        "asr_processing": "transcribing",
        "asr_done": "understanding",
        "agent_processing": "understanding",
        "done": "done",
        "empty": "empty",
        "failed": "failed",
    }.get(status, "receiving")


def _capture_display_source(recording: CaptureRecording) -> str:
    if recording.device_kind == "ring":
        return "ring"
    if recording.device_kind == "card":
        return "card"
    if recording.device_kind == "phone":
        return "audio_upload"
    if recording.source == "voice" or recording.card_sn == "ring":
        return "ring"
    if recording.source in {"realtime", "offline"}:
        return "card"
    return "audio_upload"


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
            await materialize_final_capture(
                session,
                existing,
                timezone_name=get_settings().default_user_timezone,
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
    await publish_capture_status(
        session,
        recording,
        status="accepted",
        message="上传完成",
    )
    if process_status == "asr_done":
        await materialize_final_capture(
            session,
            recording,
            timezone_name=get_settings().default_user_timezone,
        )
    await publish_capture_status(
        session,
        recording,
        status=process_status,
        message=(
            "语音识别完成" if process_status == "asr_done" else message
        ),
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
    await publish_capture_status(
        session,
        recording,
        status="accepted",
        message="上传完成",
    )
    await publish_capture_status(
        session,
        recording,
        status="asr_processing",
        message="语音识别中",
    )
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


def _merge_text_capture_provenance(
    recording: CaptureRecording,
    *,
    device_capture_key: str | None,
    device_kind: str | None,
    device_id: str | None,
    device_file_name: str | None,
    capture_started_at: datetime | None,
    capture_ended_at: datetime | None,
    local_audio_sha256: str | None,
    local_audio_size_bytes: int | None,
) -> None:
    identity_fields = (
        ("device_capture_key", device_capture_key, "device capture key"),
        ("device_kind", device_kind, "device kind"),
        ("device_id", device_id, "device id"),
    )
    for attribute, incoming, label in identity_fields:
        if incoming is None:
            continue
        existing = getattr(recording, attribute)
        if existing is not None and existing != incoming:
            raise ConflictingCapture(
                f"capture identity already contains different {label}"
            )
        if existing is None:
            setattr(recording, attribute, incoming)

    if device_file_name is not None:
        existing_file_name = recording.device_file_name
        is_generated_placeholder = (
            existing_file_name.startswith("TEXT-")
            and existing_file_name.endswith(".txt")
        )
        if existing_file_name != device_file_name and not is_generated_placeholder:
            raise ConflictingCapture(
                "capture identity already contains different device file name"
            )
        if is_generated_placeholder:
            recording.device_file_name = device_file_name

    if local_audio_sha256 is not None:
        existing_sha256 = _lower(recording.local_audio_sha256)
        if existing_sha256 is not None and existing_sha256 != local_audio_sha256:
            raise ConflictingCapture(
                "capture identity already contains different audio sha256"
            )
        if existing_sha256 is None:
            recording.local_audio_sha256 = local_audio_sha256

    if local_audio_size_bytes is not None:
        existing_size = recording.local_audio_size_bytes
        if existing_size is not None and existing_size != local_audio_size_bytes:
            raise ConflictingCapture(
                "capture identity already contains different audio size"
            )
        if existing_size is None:
            recording.local_audio_size_bytes = local_audio_size_bytes

    if recording.capture_started_at is None and capture_started_at is not None:
        recording.capture_started_at = capture_started_at
    if recording.capture_ended_at is None and capture_ended_at is not None:
        recording.capture_ended_at = capture_ended_at


async def accept_text_capture(
    session: AsyncSession,
    user_id: str,
    command: FlashRequest,
) -> TextCaptureResult:
    now = utc_now()
    identity = new_uuid()
    client_task_id = command.client_task_id or f"text-{identity}"
    device_capture_key = command.device_capture_key or None
    device_kind = command.device_kind or None
    device_id = command.device_id or None
    device_file_name = command.device_file_name or None
    capture_started_at = _parse_timestamp(command.capture_started_at)
    capture_ended_at = _parse_timestamp(command.capture_ended_at)
    local_audio_sha256 = _lower(command.local_audio_sha256)

    existing_by_client = await session.scalar(
        select(CaptureRecording).where(
            CaptureRecording.user_id == user_id,
            CaptureRecording.client_task_id == client_task_id,
        )
    )
    existing_by_device = None
    if device_capture_key is not None:
        existing_by_device = await session.scalar(
            select(CaptureRecording).where(
                CaptureRecording.user_id == user_id,
                CaptureRecording.device_capture_key == device_capture_key,
            )
        )
    if (
        existing_by_client is not None
        and existing_by_device is not None
        and existing_by_client.id != existing_by_device.id
    ):
        raise ConflictingCapture(
            "client task and device capture key identify different captures"
        )
    existing = existing_by_client or existing_by_device
    if existing is not None:
        if (existing.asr_text or "").strip() != command.text:
            raise ConflictingCapture("capture identity already contains different text")
        _merge_text_capture_provenance(
            existing,
            device_capture_key=device_capture_key,
            device_kind=device_kind,
            device_id=device_id,
            device_file_name=device_file_name,
            capture_started_at=capture_started_at,
            capture_ended_at=capture_ended_at,
            local_audio_sha256=local_audio_sha256,
            local_audio_size_bytes=command.local_audio_size_bytes,
        )
        file = await session.get(CaptureFile, existing.file_id)
        turn = await session.scalar(
            select(CaptureTurn).where(CaptureTurn.recording_id == existing.id)
        )
        if file is None or turn is None:
            raise ConflictingCapture("client task is incomplete")
        return TextCaptureResult(recording=existing, file=file, turn=turn)
    storage_key = command.file_id.strip() or f"text-capture:{identity}"
    file = CaptureFile(
        user_id=user_id,
        storage_url=storage_key,
        file_type="text/plain",
        source_tag="flash",
        asr_status="completed",
        created_at=now,
        updated_at=now,
    )
    session.add(file)
    await session.flush()
    recording = CaptureRecording(
        user_id=user_id,
        file_id=file.id,
        card_sn="ring" if command.source == "voice" else "text",
        device_file_name=device_file_name or f"TEXT-{identity}.txt",
        client_task_id=client_task_id,
        device_capture_key=device_capture_key,
        device_kind=device_kind,
        device_id=device_id,
        source=command.source,
        capture_started_at=capture_started_at,
        capture_ended_at=capture_ended_at,
        local_audio_sha256=local_audio_sha256,
        local_audio_size_bytes=command.local_audio_size_bytes,
        audio_format="text",
        asr_mode="text_client",
        s3_key=storage_key,
        s3_upload_headers_json={},
        tencent_speaker_diarization=0,
        tencent_status="not_applicable",
        tencent_task_response_json={},
        upload_status="uploaded",
        process_status="asr_done",
        asr_provider="client_text",
        asr_text=command.text,
        asr_segments_json=[],
        result_records_json=[],
        accepted_at=now,
        created_at=now,
        updated_at=now,
    )
    session.add(recording)
    await session.flush()
    await materialize_final_capture(
        session,
        recording,
        timezone_name=get_settings().default_user_timezone,
    )
    await session.flush()
    turn = await session.scalar(
        select(CaptureTurn).where(CaptureTurn.recording_id == recording.id)
    )
    if turn is None:
        raise RuntimeError("capture compatibility turn missing")
    await publish_capture_status(
        session,
        recording,
        status="accepted",
        message="已收到语音内容",
    )
    await publish_capture_status(
        session,
        recording,
        status="asr_done",
        message="语音识别完成",
    )
    return TextCaptureResult(recording=recording, file=file, turn=turn)


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
        "physical_session_id": recording.session_id,
        "input_turn_id": recording.input_turn_id,
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
    turn = await session.scalar(
        select(CaptureTurn).where(CaptureTurn.recording_id == recording.id)
    )
    return RecordingResult(recording=recording, file=file, turn=turn)


async def wait_for_recording(
    user_id: str,
    recording_id: str,
    *,
    timeout_seconds: float,
    poll_interval_seconds: float,
) -> tuple[RecordingResult | None, int]:
    started = time.monotonic()
    deadline = started + timeout_seconds
    latest: RecordingResult | None = None
    while True:
        async with AsyncSessionFactory() as session:
            latest = await get_recording(session, user_id, recording_id)
        if latest is None or latest.recording.process_status in {
            "done",
            "empty",
            "failed",
        }:
            break
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        await asyncio.sleep(min(poll_interval_seconds, remaining))
    return latest, int((time.monotonic() - started) * 1000)


def _display_result_summary(recording: CaptureRecording) -> str:
    summary = recording.result_summary or ""
    references = recording.result_records_json or []
    migrated_to_notes = any(
        reference.get("kind") == "asset"
        and reference.get("skill_machine_name") == "notes"
        for reference in references
        if isinstance(reference, dict)
    )
    if migrated_to_notes:
        return summary.replace("已记为其他类型", "已记为随记")
    return summary


def flash_response_payload(
    result: RecordingResult,
    *,
    elapsed_ms: int,
) -> dict:
    recording = result.recording
    references = recording.result_records_json or []
    cards = [
        dict(reference)
        for reference in references
        if reference.get("entity_kind") in {"asset", "event", "contact"}
        or reference.get("card_type") in {"pending_contact", "error"}
    ]
    pending = recording.process_status not in {"done", "empty", "failed"} or any(
        isinstance(reference, dict)
        and reference.get("card_type") == "pending_contact"
        for reference in references
    )
    failed = recording.process_status == "failed"
    summary = _display_result_summary(recording)
    return {
        "ok": not failed,
        "session_id": recording.id,
        "recording_id": recording.id,
        "physical_session_id": recording.session_id or "",
        "input_turn_id": (
            recording.input_turn_id
            or (result.turn.id if result.turn is not None else "")
        ),
        "reply": summary if not references and not pending and not failed else "",
        "summary": summary,
        "cards": cards,
        "derived_assets": cards,
        "has_pending": pending,
        "elapsed_ms": elapsed_ms,
        "error": (recording.error_message or "") if failed else "",
    }


class CaptureRetryUnavailable(Exception):
    pass


async def retry_recording(
    session: AsyncSession,
    user_id: str,
    recording_id: str,
) -> str | None:
    recording = await session.scalar(
        select(CaptureRecording)
        .where(
            CaptureRecording.id == recording_id,
            CaptureRecording.user_id == user_id,
        )
        .with_for_update()
    )
    if recording is None:
        return None
    now = utc_now()
    recording.retry_count += 1
    recording.error_message = None
    recording.asr_error = None
    recording.processed_at = None
    recording.updated_at = now
    if (recording.asr_text or "").strip():
        mode = "pipeline"
        recording.process_status = "asr_done"
        job_type = "capture_process"
        dedupe_key = f"capture-process:{recording.id}"
        status = "asr_done"
        message = "已重新排队整理"
    else:
        if recording.asr_mode != "async":
            raise CaptureRetryUnavailable(
                "client ASR must be retried from the capture device"
            )
        mode = "asr"
        recording.process_status = "asr_processing"
        recording.tencent_status = (
            "submitted" if recording.tencent_asr_task_id else "pending"
        )
        file = await session.get(CaptureFile, recording.file_id)
        if file is not None:
            file.asr_status = "processing"
            file.updated_at = now
        job_type = "capture_asr"
        dedupe_key = f"capture-asr:{recording.id}"
        status = "asr_processing"
        message = "已重新排队识别"
    await enqueue_or_requeue_job(
        session,
        job_type=job_type,
        run_id=recording.id,
        dedupe_key=dedupe_key,
        available_at=now,
    )
    if mode == "pipeline" and recording.agent_message_id:
        agent_message = await session.get(SessionMessage, recording.agent_message_id)
        if agent_message is not None:
            agent_message.status = "running"
            agent_message.text = ""
            agent_message.cards_json = []
            agent_message.updated_at = now
    if recording.session_id:
        daily_session = await session.get(ChatSession, recording.session_id)
        if daily_session is not None:
            await session_service.publish_session_changed(
                session,
                daily_session,
                reason=(
                    "capture_agent_retry"
                    if mode == "pipeline"
                    else "capture_asr_retry"
                ),
            )
    await publish_capture_status(
        session,
        recording,
        status=status,
        message=message,
    )
    return mode


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
            "display_phase": _capture_display_phase(recording.process_status),
            "display_source": _capture_display_source(recording),
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
            "session_id": recording.id,
            "physical_session_id": recording.session_id,
            "session_revision": None,
            "input_turn_id": (
                recording.input_turn_id
                or (result.turn.id if result.turn is not None else None)
            ),
            "result_summary": _display_result_summary(recording),
            "result_cards": recording.result_records_json or [],
            "session_date": _local_capture_date(
                recording,
                timezone_name=get_settings().default_user_timezone,
            ).isoformat(),
            "created_at": _as_utc_z(recording.created_at),
            "updated_at": _as_utc_z(recording.updated_at),
        },
    }


def _recording_detail_item(result: RecordingResult) -> dict:
    return recording_payload(result)["recording"]


async def list_daily_sessions(
    session: AsyncSession,
    user_id: str,
    *,
    timezone_name: str,
    limit: int = 100,
) -> list[dict]:
    recordings = list(
        await session.scalars(
            select(CaptureRecording)
            .where(
                CaptureRecording.user_id == user_id,
                func.length(
                    func.trim(func.coalesce(CaptureRecording.asr_text, ""))
                )
                > 0,
            )
            .order_by(
                func.coalesce(
                    CaptureRecording.capture_started_at,
                    CaptureRecording.created_at,
                ).desc(),
                CaptureRecording.id.desc(),
            )
        )
    )
    grouped: dict[date, list[CaptureRecording]] = {}
    for recording in recordings:
        local_date = _local_capture_date(
            recording,
            timezone_name=timezone_name,
        )
        grouped.setdefault(local_date, []).append(recording)
    sessions = []
    for local_date in sorted(grouped, reverse=True)[:limit]:
        rows = grouped[local_date]
        physical_session = next(
            (row.session_id for row in rows if row.session_id),
            None,
        )
        revision = None
        if physical_session:
            model = await session.get(ChatSession, physical_session)
            revision = model.revision if model is not None else None
        sessions.append(
            {
                "id": local_date.isoformat(),
                "physical_session_id": physical_session,
                "session_revision": revision,
                "date": local_date.isoformat(),
                "title": f"{local_date.month}月{local_date.day}日 闪念",
                "recording_count": len(rows),
                "created_at": _as_utc_z(
                    min(_recording_timestamp(row) for row in rows)
                ),
                "updated_at": _as_utc_z(max(row.updated_at for row in rows)),
            }
        )
    return sessions


async def get_daily_session(
    session: AsyncSession,
    user_id: str,
    local_date: date,
    *,
    timezone_name: str,
) -> dict | None:
    zone = ZoneInfo(timezone_name)
    start_local = datetime.combine(local_date, datetime_time.min, tzinfo=zone)
    end_local = start_local + timedelta(days=1)
    start_utc = start_local.astimezone(timezone.utc).replace(tzinfo=None)
    end_utc = end_local.astimezone(timezone.utc).replace(tzinfo=None)
    timestamp = func.coalesce(
        CaptureRecording.capture_started_at,
        CaptureRecording.created_at,
    )
    recordings = list(
        await session.scalars(
            select(CaptureRecording)
            .where(
                CaptureRecording.user_id == user_id,
                func.length(
                    func.trim(func.coalesce(CaptureRecording.asr_text, ""))
                )
                > 0,
                timestamp >= start_utc,
                timestamp < end_utc,
            )
            .order_by(timestamp.asc(), CaptureRecording.id.asc())
        )
    )
    if not recordings:
        return None
    results = []
    for recording in recordings:
        file = await _file_for_recording(session, recording)
        turn = await session.scalar(
            select(CaptureTurn).where(CaptureTurn.recording_id == recording.id)
        )
        results.append(RecordingResult(recording=recording, file=file, turn=turn))
    physical_session_id = next(
        (row.session_id for row in recordings if row.session_id),
        None,
    )
    legacy_chat_messages = await list_flash_chat_messages(
        session, user_id, local_date
    )
    unified_chat_messages = (
        await list_unified_typed_chat_messages(
            session,
            user_id,
            physical_session_id,
        )
        if physical_session_id
        else []
    )
    physical_session = (
        await session.get(ChatSession, physical_session_id)
        if physical_session_id
        else None
    )
    return {
        "id": local_date.isoformat(),
        "physical_session_id": physical_session_id,
        "session_revision": (
            physical_session.revision if physical_session is not None else None
        ),
        "date": local_date.isoformat(),
        "title": f"{local_date.month}月{local_date.day}日 闪念",
        "created_at": _as_utc_z(
            min(_recording_timestamp(row) for row in recordings)
        ),
        "updated_at": _as_utc_z(
            max(
                [row.updated_at for row in recordings]
                + [message.created_at for message in legacy_chat_messages]
                + [message.created_at for message in unified_chat_messages]
            )
        ),
        "recordings": [_recording_detail_item(result) for result in results],
        "chat_messages": sorted(
            [
                flash_chat_message_payload(item)
                for item in legacy_chat_messages
            ]
            + [session_service.message_payload(item) for item in unified_chat_messages],
            key=lambda item: (item.get("created_at") or "", item.get("id") or ""),
        ),
    }


async def list_unified_typed_chat_messages(
    session: AsyncSession,
    user_id: str,
    physical_session_id: str,
    *,
    limit: int = 80,
) -> list[SessionMessage]:
    messages = list(
        await session.scalars(
            select(SessionMessage)
            .join(InputTurn, SessionMessage.input_turn_id == InputTurn.id)
            .where(
                SessionMessage.user_id == user_id,
                SessionMessage.session_id == physical_session_id,
                InputTurn.user_id == user_id,
                InputTurn.source == "typed",
            )
            .order_by(
                SessionMessage.created_at.desc(),
                SessionMessage.id.desc(),
            )
            .limit(limit)
        )
    )
    messages.reverse()
    return messages


async def list_flash_chat_messages(
    session: AsyncSession,
    user_id: str,
    local_date: date,
    *,
    limit: int = 40,
) -> list[FlashChatMessage]:
    messages = list(
        await session.scalars(
            select(FlashChatMessage)
            .where(
                FlashChatMessage.user_id == user_id,
                FlashChatMessage.session_date == local_date,
                FlashChatMessage.migrated_session_message_id.is_(None),
            )
            .order_by(FlashChatMessage.created_at.desc(), FlashChatMessage.id.desc())
            .limit(limit)
        )
    )
    messages.reverse()
    return messages


def flash_chat_message_payload(message: FlashChatMessage) -> dict:
    return {
        "id": message.id,
        "role": message.role,
        "text": message.text,
        "status": message.status,
        "created_at": _as_utc_z(message.created_at),
    }


async def delete_daily_session(
    session: AsyncSession,
    user_id: str,
    local_date: date,
    *,
    timezone_name: str,
) -> int:
    zone = ZoneInfo(timezone_name)
    start_local = datetime.combine(local_date, datetime_time.min, tzinfo=zone)
    end_local = start_local + timedelta(days=1)
    start_utc = start_local.astimezone(timezone.utc).replace(tzinfo=None)
    end_utc = end_local.astimezone(timezone.utc).replace(tzinfo=None)
    timestamp = func.coalesce(
        CaptureRecording.capture_started_at,
        CaptureRecording.created_at,
    )
    recording_ids = list(
        await session.scalars(
            select(CaptureRecording.id).where(
                CaptureRecording.user_id == user_id,
                timestamp >= start_utc,
                timestamp < end_utc,
            )
        )
    )
    for recording_id in recording_ids:
        await delete_recording(session, user_id, recording_id)
    await session.execute(
        delete(FlashChatMessage).where(
            FlashChatMessage.user_id == user_id,
            FlashChatMessage.session_date == local_date,
        )
    )
    return len(recording_ids)


async def list_recordings(
    session: AsyncSession,
    user_id: str,
    *,
    limit: int = 100,
) -> list[CaptureRecording]:
    return list(
        await session.scalars(
            select(CaptureRecording)
            .where(CaptureRecording.user_id == user_id)
            .order_by(CaptureRecording.created_at.desc(), CaptureRecording.id.desc())
            .limit(limit)
        )
    )


def recording_archive_item(recording: CaptureRecording) -> dict:
    transcript = (recording.asr_text or "").strip().splitlines()
    title = transcript[0][:36] if transcript else "闪念"
    captured_at = _recording_timestamp(recording)
    return {
        "id": recording.id,
        "title": title or "闪念",
        "session_date": _local_capture_date(
            recording,
            timezone_name=get_settings().default_user_timezone,
        ).isoformat(),
        "captured_at": _as_utc_z(captured_at),
        "created_at": _as_utc_z(recording.created_at),
        "process_status": recording.process_status,
    }


async def delete_recording(
    session: AsyncSession,
    user_id: str,
    recording_id: str,
) -> bool:
    recording = await session.scalar(
        select(CaptureRecording).where(
            CaptureRecording.id == recording_id,
            CaptureRecording.user_id == user_id,
        )
    )
    if recording is None:
        return False
    file = await session.get(CaptureFile, recording.file_id)
    await session.execute(
        delete(WorkflowJob).where(WorkflowJob.run_id == recording.id)
    )
    await session.delete(recording)
    await session.flush()
    if file is not None:
        await session.delete(file)
        await session.flush()
    return True
