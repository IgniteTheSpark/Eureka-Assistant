from collections.abc import Callable
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import select

from app.config import get_settings
from app.db.base import utc_now
from app.db.models import UserSkill, WorkflowJob
from app.db.session import session_scope
from app.domains.assets.service import (
    ensure_capture_skills,
)
from app.domains.capture.agent import capture_skill_from_model
from app.domains.capture.execution import (
    FlashExecutionContext,
    FlashExecutionProvider,
    FlashExecutionResult,
    PermanentFlashExecutionError,
    RetryableFlashExecutionError,
)
from app.domains.capture.presenter import present_capture_references
from app.domains.capture.asr import (
    AsrPollResult,
    AsrProvider,
    PermanentAsrError,
    RetryableAsrError,
)
from app.domains.capture.models import CaptureFile, CaptureRecording
from app.domains.capture.service import (
    materialize_final_capture,
    publish_capture_status,
)
from app.domains.sessions import service as session_service
from app.domains.sessions.models import (
    AgentPendingAction,
    ChatSession,
    SessionMessage,
)
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
        if recording.agent_message_id:
            agent_message = await session.get(
                SessionMessage,
                recording.agent_message_id,
            )
            if agent_message is not None:
                agent_message.status = "failed"
                agent_message.text = safe_message
                agent_message.updated_at = now
        if recording.session_id:
            daily_session = await session.get(ChatSession, recording.session_id)
            if daily_session is not None:
                await session_service.publish_session_changed(
                    session,
                    daily_session,
                    reason="capture_asr_failed",
                )
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
        await materialize_final_capture(
            session,
            recording,
            timezone_name=get_settings().default_user_timezone,
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
        except RetryableAsrError as exc:
            if job.attempt >= job.max_attempts:
                await _fail_capture(
                    recording_id=recording_id,
                    message=str(exc),
                    raw_response=None,
                    now=now,
                )
                raise JobPermanentFailure(
                    "capture_asr_retries_exhausted",
                    "Tencent ASR retry budget exhausted",
                ) from exc
            raise

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
) -> tuple[str, str, list, datetime, str, str] | None:
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
        materialized = await materialize_final_capture(
            session,
            recording,
            timezone_name=get_settings().default_user_timezone,
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
            materialized.agent_message.status = "running"
            materialized.agent_message.text = ""
            materialized.agent_message.cards_json = []
            materialized.agent_message.updated_at = utc_now()
            await publish_capture_status(
                session,
                recording,
                status="agent_processing",
                message="正在整理语音内容",
            )
            await session_service.publish_session_changed(
                session,
                materialized.session,
                reason="capture_agent_processing",
            )
        return (
            recording.user_id,
            transcript,
            skills,
            recording.accepted_at or recording.created_at,
            materialized.session.id,
            materialized.input_turn.id,
        )


def _reference_in_timezone(value: datetime, timezone_name: str) -> datetime:
    aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    return aware.astimezone(ZoneInfo(timezone_name))


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
        if recording.agent_message_id:
            agent_message = await session.get(
                SessionMessage,
                recording.agent_message_id,
            )
            if agent_message is not None:
                agent_message.status = "failed"
                agent_message.text = "这条闪念暂时没有整理完成，可以重试"
                agent_message.updated_at = now
        if recording.session_id:
            daily_session = await session.get(ChatSession, recording.session_id)
            if daily_session is not None:
                await session_service.publish_session_changed(
                    session,
                    daily_session,
                    reason="capture_agent_failed",
                )
        await publish_capture_status(
            session,
            recording,
            status="failed",
            message="这条闪念暂时没有整理完成，可以重试",
        )


def _result_snapshots(result: dict, plural: str) -> list[dict]:
    values = result.get(plural)
    if isinstance(values, list):
        return [dict(item) for item in values if isinstance(item, dict)]
    return [dict(result)]


def _contact_name_from_item(item) -> str:
    name = str(item.result.get("name") or "").strip()
    if name:
        return name
    for event in item.tool_events:
        if event.get("name") != "tool_query_contact":
            continue
        arguments = event.get("args")
        if isinstance(arguments, dict):
            name = str(arguments.get("name_query") or "").strip()
            if name:
                return name
    return "联系人"


async def _persist_flash_execution(
    *,
    recording_id: str,
    result: FlashExecutionResult,
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
        skill_by_name = {skill.machine_name: skill for skill in skill_models}

        references: list[dict] = []
        has_pending = False
        for item in result.items:
            source_text = item.intent.source_text.strip() or (
                recording.asr_text or ""
            ).strip()
            if item.status == "reply":
                continue
            if item.status == "error":
                skill = skill_by_name.get(item.intent.type)
                references.append(
                    {
                        "kind": "error",
                        "card_type": "error",
                        "title": (
                            getattr(skill, "display_name", None)
                            or {"event": "日程", "contact": "联系人"}.get(
                                item.intent.type,
                                "这项内容",
                            )
                        ),
                        "subtitle": "这项内容未能完成，可以重试",
                        "error_code": item.error_code or "intent_failed",
                        "source_text": source_text,
                    }
                )
                continue

            if item.status == "pending_confirmation":
                if item.intent.type == "contact":
                    candidates = [
                        dict(candidate)
                        for candidate in item.result.get("candidates") or []
                        if isinstance(candidate, dict)
                    ]
                    extracted_update = item.result.get("extracted_update")
                    if not isinstance(extracted_update, dict):
                        extracted_update = {}
                    contact_name = _contact_name_from_item(item)
                    pending = AgentPendingAction(
                        user_id=recording.user_id,
                        session_id=recording.session_id or "",
                        input_turn_id=recording.input_turn_id,
                        agent_message_id=recording.agent_message_id,
                        kind="contact",
                        operation=str(item.result.get("operation") or "create_or_update"),
                        status="pending",
                        candidates_json=candidates,
                        intent_json={
                            "name": contact_name,
                            "patch": extracted_update,
                            "source_text": source_text,
                        },
                    )
                    session.add(pending)
                    await session.flush()
                    has_pending = True
                    references.append(
                        {
                            "kind": "pending_contact",
                            "card_type": "pending_contact",
                            "pending_action_id": pending.id,
                            "title": contact_name,
                            "subtitle": (
                                f"找到 {len(candidates)} 个同名联系人，请确认"
                            ),
                            "icon": "👤",
                            "accent_color": "neutral",
                            "candidates": candidates,
                            "source_text": source_text,
                        }
                    )
                continue

            if item.intent.type == "event":
                for snapshot in _result_snapshots(item.result, "events"):
                    references.append(
                        {
                            **{key: value for key, value in snapshot.items() if key != "ok"},
                            "kind": "event",
                            "event_id": snapshot.get("event_id"),
                            "source_text": source_text,
                        }
                    )
                continue

            if item.intent.type == "contact":
                for contact in _result_snapshots(item.result, "contacts"):
                    references.append(
                        {
                            **{key: value for key, value in contact.items() if key != "ok"},
                            "kind": "contact",
                            "card_type": "contact",
                            "contact_id": contact.get("contact_id"),
                            "contact_action": contact.get("contact_action"),
                            "name": contact.get("name") or _contact_name_from_item(item),
                            "source_text": source_text,
                            "icon": "👤",
                            "accent_color": "neutral",
                        }
                    )
                continue

            machine_name = str(
                item.result.get("user_skill_name") or item.intent.type
            )
            skill = skill_by_name.get(machine_name)
            if skill is None:
                references.append(
                    {
                        "kind": "error",
                        "card_type": "error",
                        "title": "这项内容",
                        "subtitle": "记录类型不可用",
                        "error_code": "intent_skill_unavailable",
                        "source_text": source_text,
                    }
                )
                continue
            for snapshot in _result_snapshots(item.result, "assets"):
                references.append(
                    {
                        **{key: value for key, value in snapshot.items() if key != "ok"},
                        "kind": "asset",
                        "asset_id": snapshot.get("asset_id"),
                        "user_skill_id": skill.id,
                        "skill_machine_name": machine_name,
                        "source_text": source_text,
                    }
                )

        references = present_capture_references(references, skills=skill_models)
        recording.process_status = "done"
        recording.result_summary = result.summary.strip()
        recording.result_records_json = references
        recording.error_message = None
        recording.processed_at = now
        recording.updated_at = now
        if recording.agent_message_id:
            agent_message = await session.get(
                SessionMessage,
                recording.agent_message_id,
            )
            if agent_message is not None:
                agent_message.status = (
                    "waiting_confirmation" if has_pending else "done"
                )
                agent_message.text = recording.result_summary
                agent_message.cards_json = references
                agent_message.updated_at = now
        if recording.session_id:
            daily_session = await session.get(ChatSession, recording.session_id)
            if daily_session is not None:
                await session_service.publish_session_changed(
                    session,
                    daily_session,
                    reason="capture_agent_done",
                )
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
            result_count=len(references),
        )


async def _publish_organizing_phase(*, recording_id: str) -> None:
    async with session_scope() as session:
        recording = await session.scalar(
            select(CaptureRecording).where(CaptureRecording.id == recording_id)
        )
        if recording is None or recording.process_status != "agent_processing":
            return
        await publish_capture_status(
            session,
            recording,
            status="agent_processing",
            display_phase="organizing",
            message="正在整理语音内容",
        )


def capture_process_handler(
    provider: FlashExecutionProvider,
    *,
    clock: Callable[[], datetime] = utc_now,
    timezone_name: str = "Asia/Shanghai",
    tool_runtime=None,
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
        (
            user_id,
            transcript,
            skills,
            captured_at,
            session_id,
            input_turn_id,
        ) = prepared
        now = clock()
        reference_datetime = _reference_in_timezone(captured_at, timezone_name)
        try:
            result = await provider.execute(
                context=FlashExecutionContext(
                    recording_id=recording_id,
                    user_id=user_id,
                    session_id=session_id,
                    input_turn_id=input_turn_id,
                    transcript=transcript,
                    reference_datetime=reference_datetime,
                    skills=tuple(skills),
                ),
                tool_runtime=tool_runtime,
            )
            if not isinstance(result, FlashExecutionResult):
                raise PermanentFlashExecutionError(
                    "capture provider returned invalid execution"
                )
            await _publish_organizing_phase(recording_id=recording_id)
        except PermanentFlashExecutionError as exc:
            await _fail_agent_capture(
                recording_id=recording_id,
                message=str(exc),
                now=now,
            )
            raise JobPermanentFailure(
                "capture_agent_permanent",
                "capture agent permanently failed",
            ) from exc
        except RetryableFlashExecutionError as exc:
            if job.attempt >= job.max_attempts:
                await _fail_agent_capture(
                    recording_id=recording_id,
                    message=str(exc),
                    now=now,
                )
                raise JobPermanentFailure(
                    "capture_agent_retries_exhausted",
                    "capture agent retry budget exhausted",
                ) from exc
            raise
        await _persist_flash_execution(
            recording_id=recording_id,
            result=result,
            now=now,
        )

    return handle
