from collections.abc import Callable
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.db.base import utc_now
from app.db.models import UserSkill, WorkflowJob
from app.db.session import session_scope
from app.domains.assets.schemas import AssetCreate, EventCreate
from app.domains.assets.service import (
    create_asset,
    create_event,
    ensure_capture_skills,
)
from app.domains.capture.agent import (
    CaptureAgentProvider,
    CaptureAgentResult,
    CaptureOutputError,
    PermanentCaptureAgentError,
    capture_skill_from_model,
    validate_capture_result,
)
from app.domains.capture.asr import (
    AsrPollResult,
    AsrProvider,
    PermanentAsrError,
)
from app.domains.capture.models import CaptureFile, CaptureRecording, CaptureTurn
from app.domains.capture.service import publish_capture_status
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.jobs.models import JobDeferred, JobPermanentFailure
from app.jobs.queue import defer_job, enqueue_job


CAPTURE_ASR_JOB_TYPE = "capture_asr"
CAPTURE_PROCESS_JOB_TYPE = "capture_process"


async def _load_recording(recording_id: str) -> CaptureRecording | None:
    async with session_scope() as session:
        return await session.get(CaptureRecording, recording_id)


async def _persist_external_task(
    *,
    recording_id: str,
    job_id: str,
    owner: str,
    task_id: str,
    raw_response: dict,
    now: datetime,
) -> None:
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        job = await session.scalar(
            select(WorkflowJob)
            .where(
                WorkflowJob.id == job_id,
                WorkflowJob.status == "running",
                WorkflowJob.lease_owner == owner,
            )
            .with_for_update()
        )
        if recording is None or job is None:
            raise RuntimeError("capture ASR lease lost while checkpointing")
        if recording.tencent_asr_task_id not in (None, task_id):
            raise JobPermanentFailure(
                "capture_asr_task_conflict",
                "capture already has another ASR task",
            )
        recording.tencent_asr_task_id = task_id
        recording.tencent_status = "submitted"
        recording.tencent_task_response_json = raw_response
        recording.updated_at = now
        job.checkpoint_json = {
            "external_task_id": task_id,
            "created_at": now.isoformat(),
        }
        job.updated_at = now


async def _fail_capture(
    *,
    recording_id: str,
    message: str,
    raw_response: dict | None,
    now: datetime,
) -> None:
    safe_message = (message or "Tencent ASR failed")[:500]
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        if recording is None:
            return
        file = await session.get(CaptureFile, recording.file_id)
        recording.tencent_status = "failed"
        recording.tencent_error_message = safe_message
        recording.tencent_result_response_json = raw_response
        recording.process_status = "failed"
        recording.asr_error = safe_message
        recording.error_message = safe_message
        recording.processed_at = now
        recording.updated_at = now
        if file is not None:
            file.asr_status = "failed"
            file.updated_at = now
        await publish_capture_status(
            session,
            recording,
            status="failed",
            message=safe_message,
        )


async def _defer_poll(
    *,
    recording_id: str,
    job: WorkflowJob,
    result: AsrPollResult,
    now: datetime,
    poll_interval_seconds: float,
) -> None:
    owner = job.lease_owner or ""
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        if recording is None:
            raise JobPermanentFailure(
                "capture_missing",
                "capture recording not found",
            )
        external_task_id = recording.tencent_asr_task_id
        if not external_task_id:
            raise JobPermanentFailure(
                "capture_asr_task_missing",
                "capture ASR task checkpoint missing",
            )
        recording.tencent_status = result.status
        recording.tencent_result_response_json = result.raw_response
        recording.updated_at = now
        deferred = await defer_job(
            session,
            job_id=job.id,
            owner=owner,
            now=now,
            available_at=now + timedelta(seconds=poll_interval_seconds),
            checkpoint={
                "external_task_id": external_task_id,
                "poll_status": result.status,
                "polled_at": now.isoformat(),
            },
        )
        if not deferred:
            raise RuntimeError("capture ASR lease lost while deferring")


async def _complete_capture(
    *,
    recording_id: str,
    result: AsrPollResult,
    now: datetime,
) -> None:
    text = result.text.strip()
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        if recording is None:
            raise JobPermanentFailure(
                "capture_missing",
                "capture recording not found",
            )
        file = await session.get(CaptureFile, recording.file_id)
        recording.tencent_status = "finished"
        recording.tencent_result_response_json = result.raw_response
        recording.asr_text = text
        recording.asr_segments_json = result.segments
        recording.asr_error = None
        recording.error_message = None
        recording.updated_at = now
        if file is not None:
            file.asr_status = "completed"
            file.updated_at = now

        if not text:
            recording.process_status = "empty"
            recording.result_summary = ""
            recording.result_records_json = []
            recording.error_message = "文件没内容"
            recording.processed_at = now
            await publish_capture_status(
                session,
                recording,
                status="empty",
                message="文件没内容",
            )
            return

        recording.process_status = "asr_done"
        existing_turn = await session.scalar(
            select(CaptureTurn).where(CaptureTurn.recording_id == recording.id)
        )
        if existing_turn is None:
            session.add(
                CaptureTurn(
                    recording_id=recording.id,
                    user_id=recording.user_id,
                    transcript=text,
                    source=recording.source,
                    provenance_json={
                        "kind": "hardware_audio",
                        "card_sn": recording.card_sn,
                        "device_file_name": recording.device_file_name,
                        "asr_provider": recording.asr_provider,
                    },
                )
            )
        await enqueue_job(
            session,
            job_type="capture_process",
            run_id=recording.id,
            dedupe_key=f"capture-process:{recording.id}",
        )
        await publish_capture_status(
            session,
            recording,
            status="asr_done",
            message="语音识别完成",
        )


def capture_asr_handler(
    provider: AsrProvider,
    *,
    poll_interval_seconds: float,
    poll_timeout_seconds: float,
    clock: Callable[[], datetime] = utc_now,
):
    async def handle(job: WorkflowJob) -> None:
        recording_id = job.run_id
        owner = job.lease_owner or ""
        if not recording_id or not owner:
            raise JobPermanentFailure(
                "capture_asr_invalid_job",
                "capture ASR job is missing recording or lease owner",
            )
        recording = await _load_recording(recording_id)
        if recording is None:
            raise JobPermanentFailure(
                "capture_missing",
                "capture recording not found",
            )
        if recording.process_status in {"asr_done", "done", "empty"}:
            return
        if recording.process_status == "failed":
            raise JobPermanentFailure(
                "capture_failed",
                "capture recording is already failed",
            )

        now = clock()
        if now - recording.accepted_at > timedelta(seconds=poll_timeout_seconds):
            await _fail_capture(
                recording_id=recording_id,
                message="Tencent ASR polling timed out",
                raw_response=None,
                now=now,
            )
            raise JobPermanentFailure(
                "capture_asr_timeout",
                "Tencent ASR polling timed out",
            )

        external_task_id = recording.tencent_asr_task_id or str(
            (job.checkpoint_json or {}).get("external_task_id") or ""
        )
        try:
            if not external_task_id:
                audio_url = (recording.s3_audio_url or "").strip()
                if not audio_url:
                    raise PermanentAsrError("capture audio URL is missing")
                task = await provider.create_task(
                    audio_url=audio_url,
                    engine_type=recording.tencent_engine_type or "16k_zh",
                    speaker_diarization=bool(
                        recording.tencent_speaker_diarization
                    ),
                    hotword_list=recording.tencent_hotword_list or "",
                )
                external_task_id = task.task_id
                await _persist_external_task(
                    recording_id=recording_id,
                    job_id=job.id,
                    owner=owner,
                    task_id=external_task_id,
                    raw_response=task.raw_response,
                    now=now,
                )
            result = await provider.get_result(external_task_id)
        except PermanentAsrError as exc:
            await _fail_capture(
                recording_id=recording_id,
                message=str(exc),
                raw_response=None,
                now=now,
            )
            raise JobPermanentFailure(
                "capture_asr_permanent",
                "Tencent ASR permanently failed",
            ) from exc

        if result.status in {"pending", "running"}:
            await _defer_poll(
                recording_id=recording_id,
                job=job,
                result=result,
                now=now,
                poll_interval_seconds=poll_interval_seconds,
            )
            raise JobDeferred()
        if result.status == "failed":
            await _fail_capture(
                recording_id=recording_id,
                message=result.error_message,
                raw_response=result.raw_response,
                now=now,
            )
            raise JobPermanentFailure(
                "capture_asr_failed",
                "Tencent ASR reported failure",
            )
        await _complete_capture(
            recording_id=recording_id,
            result=result,
            now=now,
        )

    return handle


async def _prepare_capture_processing(
    *,
    recording_id: str,
) -> tuple[str, str, list] | None:
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        if recording is None:
            raise JobPermanentFailure(
                "capture_missing",
                "capture recording not found",
            )
        if recording.process_status == "done":
            return None
        if recording.process_status not in {"asr_done", "agent_processing"}:
            raise JobPermanentFailure(
                "capture_process_invalid_state",
                f"capture cannot process from {recording.process_status}",
            )
        transcript = (recording.asr_text or "").strip()
        if not transcript:
            raise JobPermanentFailure(
                "capture_transcript_missing",
                "capture transcript is missing",
            )
        baseline = await ensure_capture_skills(session, recording.user_id)
        baseline_names = {skill.machine_name for skill in baseline}
        custom = list(
            await session.scalars(
                select(UserSkill)
                .where(
                    UserSkill.user_id == recording.user_id,
                    UserSkill.machine_name.not_in(baseline_names),
                )
                .order_by(UserSkill.created_at, UserSkill.id)
            )
        )
        skills = [capture_skill_from_model(skill) for skill in baseline]
        skills.extend(
            capture_skill
            for skill in custom
            if (capture_skill := capture_skill_from_model(skill)).enabled
        )
        if recording.process_status == "asr_done":
            recording.process_status = "agent_processing"
            recording.updated_at = utc_now()
            await publish_capture_status(
                session,
                recording,
                status="agent_processing",
                message="正在整理语音内容",
            )
        return recording.user_id, transcript, skills


async def _fail_agent_capture(
    *,
    recording_id: str,
    message: str,
    now: datetime,
) -> None:
    safe_message = (message or "capture agent failed")[:500]
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        if recording is None or recording.process_status == "done":
            return
        recording.process_status = "failed"
        recording.error_message = safe_message
        recording.processed_at = now
        recording.updated_at = now
        await publish_capture_status(
            session,
            recording,
            status="failed",
            message="语音内容整理失败",
        )


async def _persist_capture_result(
    *,
    recording_id: str,
    result: CaptureAgentResult,
    now: datetime,
) -> None:
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording)
            .where(CaptureRecording.id == recording_id)
            .with_for_update()
        )
        if recording is None:
            raise JobPermanentFailure(
                "capture_missing",
                "capture recording not found",
            )
        if recording.process_status == "done":
            return
        if recording.process_status != "agent_processing":
            raise JobPermanentFailure(
                "capture_process_invalid_state",
                f"capture cannot persist from {recording.process_status}",
            )
        skill_models = list(
            await session.scalars(
                select(UserSkill).where(UserSkill.user_id == recording.user_id)
            )
        )
        skills = [capture_skill_from_model(skill) for skill in skill_models]
        validate_capture_result(result, skills)
        skill_by_name = {skill.machine_name: skill for skill in skill_models}

        references: list[dict] = []
        for command in result.records:
            if command.kind == "asset":
                skill = skill_by_name[command.skill_machine_name or ""]
                asset = await create_asset(
                    session,
                    recording.user_id,
                    AssetCreate(
                        user_skill_id=skill.id,
                        payload=command.payload,
                        effective_at=command.effective_at,
                    ),
                )
                references.append(
                    {
                        "kind": "asset",
                        "asset_id": asset.id,
                        "user_skill_id": skill.id,
                        "skill_machine_name": skill.machine_name,
                    }
                )
            else:
                event = await create_event(
                    session,
                    recording.user_id,
                    EventCreate(
                        title=command.title or "",
                        description=command.description,
                        location=command.location,
                        start_at=command.start_at,
                        end_at=command.end_at,
                        all_day=command.all_day,
                        status="scheduled",
                    ),
                )
                references.append(
                    {
                        "kind": "event",
                        "event_id": event.id,
                    }
                )

        recording.process_status = "done"
        recording.result_summary = result.summary.strip()
        recording.result_records_json = references
        recording.error_message = None
        recording.processed_at = now
        recording.updated_at = now
        await create_notification(
            session,
            NotificationCreate(
                user_id=recording.user_id,
                type="flash_done",
                title="闪念已整理",
                body=recording.result_summary,
                link=f"/library?recording_id={recording.id}",
            ),
        )
        await publish_capture_status(
            session,
            recording,
            status="done",
            message=recording.result_summary,
        )


def _date_in_timezone(now: datetime, timezone_name: str) -> date:
    aware = now if now.tzinfo is not None else now.replace(tzinfo=timezone.utc)
    return aware.astimezone(ZoneInfo(timezone_name)).date()


def capture_process_handler(
    provider: CaptureAgentProvider,
    *,
    clock: Callable[[], datetime] = utc_now,
    timezone_name: str = "Asia/Shanghai",
):
    async def handle(job: WorkflowJob) -> None:
        recording_id = job.run_id
        if not recording_id or not job.lease_owner:
            raise JobPermanentFailure(
                "capture_process_invalid_job",
                "capture process job is missing recording or lease owner",
            )
        prepared = await _prepare_capture_processing(recording_id=recording_id)
        if prepared is None:
            return
        _, transcript, skills = prepared
        now = clock()
        try:
            result = await provider.organize(
                transcript=transcript,
                local_date=_date_in_timezone(now, timezone_name),
                skills=skills,
            )
            if not isinstance(result, CaptureAgentResult):
                raise CaptureOutputError("capture provider returned invalid result")
            validate_capture_result(result, skills)
        except PermanentCaptureAgentError as exc:
            await _fail_agent_capture(
                recording_id=recording_id,
                message=str(exc),
                now=now,
            )
            raise JobPermanentFailure(
                "capture_agent_permanent",
                "capture agent permanently failed",
            ) from exc
        except CaptureOutputError as exc:
            await _fail_agent_capture(
                recording_id=recording_id,
                message=str(exc),
                now=now,
            )
            raise JobPermanentFailure(
                "capture_agent_invalid_output",
                "capture agent returned invalid output",
            ) from exc
        await _persist_capture_result(
            recording_id=recording_id,
            result=result,
            now=now,
        )

    return handle
