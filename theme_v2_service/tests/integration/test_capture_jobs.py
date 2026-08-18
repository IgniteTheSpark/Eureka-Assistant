from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select

from app.db.models import Asset, Contact, Event, EventAttendee, UserSkill, WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.assets.service import ensure_capture_skills
from app.domains.capture.asr import (
    AsrPollResult,
    AsrTask,
    PermanentAsrError,
    RetryableAsrError,
)
from app.domains.capture.agent import (
    CaptureAgentResult,
    CaptureRecordCommand,
    CaptureOutputError,
    PermanentCaptureAgentError,
    RetryableCaptureAgentError,
    validate_capture_result,
)
from app.domains.capture.jobs import capture_asr_handler, capture_process_handler
from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.execution import (
    FlashExecutionItem,
    FlashExecutionResult,
    PermanentFlashExecutionError,
    RetryableFlashExecutionError,
)
from app.domains.capture.pipeline import LegacyFlashPipeline, _item_from_skill_result
from app.domains.capture.temporal import date_anchor_field, extract_temporal_hints
from app.domains.capture.models import CaptureFile, CaptureRecording, CaptureTurn
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.sessions.models import SessionMessage
from app.domains.sessions.models import AgentPendingAction
from app.domains.sessions.tools import SessionToolExecutor
from app.internal_mcp.runtime import InternalMCPTrustedContext
from app.internal_mcp.tools import EurekaToolContext, execute_tool
from app.jobs.queue import enqueue_job
from app.jobs.registry import JobHandlerRegistry
from app.jobs.runner import run_worker_once


NOW = datetime(2026, 8, 2, 9, 0, 0)


class FakeAsrProvider:
    def __init__(self, results):
        self.results = list(results)
        self.created = []
        self.polled = []

    async def create_task(self, **command):
        self.created.append(command)
        return AsrTask(task_id="tencent-7", raw_response={"created": True})

    async def get_result(self, task_id):
        self.polled.append(task_id)
        result = self.results.pop(0)
        if isinstance(result, Exception):
            raise result
        return result


class FakeCaptureAgentProvider:
    def __init__(self, result):
        self.result = result
        self.calls = []

    async def execute(self, *, context, tool_runtime=None):
        self.calls.append(
            {
                "transcript": context.transcript,
                "reference_datetime": context.reference_datetime,
                "skills": list(context.skills),
            }
        )
        if isinstance(self.result, Exception):
            if isinstance(self.result, RetryableCaptureAgentError):
                raise RetryableFlashExecutionError(str(self.result))
            if isinstance(self.result, PermanentCaptureAgentError):
                raise PermanentFlashExecutionError(str(self.result))
            raise self.result
        try:
            validate_capture_result(self.result, list(context.skills))
        except CaptureOutputError as exc:
            raise PermanentFlashExecutionError(str(exc)) from exc
        skill_by_name = {skill.machine_name: skill for skill in context.skills}
        for command in self.result.records:
            if command.kind != "asset":
                continue
            source_text = command.source_text.strip() or context.transcript
            hints = extract_temporal_hints(
                source_text,
                context.reference_datetime,
            )
            command.period = command.period or hints.period
            command.occurred_at = command.occurred_at or hints.occurred_at
            skill = skill_by_name.get(command.skill_machine_name or "")
            anchor = date_anchor_field(skill.schema_definition) if skill else None
            if anchor and hints.anchor_date and not command.payload.get(anchor):
                command.payload[anchor] = hints.anchor_date.isoformat()
        pipeline = await LegacyFlashPipeline(
            SessionToolExecutor(
                user_id=context.user_id,
                session_id=context.session_id,
                input_turn_id=context.input_turn_id,
                runtime=tool_runtime,
            )
        ).run(
            self.result,
            tool_call_prefix=f"capture-{context.recording_id}",
        )
        items = []
        for pipeline_item in pipeline.items:
            command = pipeline_item.command
            intent_type = (
                "contact"
                if command.kind == "contact"
                else "event"
                if command.kind == "event"
                else command.skill_machine_name or "notes"
            )
            intent = FlashIntent(
                type=intent_type,
                source_text=command.source_text or context.transcript,
                domain=command.domain,
            )
            item = _item_from_skill_result(intent, pipeline_item.execution)
            if item.status == "pending_confirmation":
                item = FlashExecutionItem(
                    intent=item.intent,
                    status=item.status,
                    result={
                        **item.result,
                        "name": command.name,
                        "operation": command.operation or "create_or_update",
                        "extracted_update": command.contact_patch,
                    },
                    error_code=item.error_code,
                )
            items.append(item)
        return FlashExecutionResult(
            summary=pipeline.summary,
            items=tuple(items),
            warnings=tuple(
                item.error_code for item in items if item.error_code
            ),
        )


async def _seed_s3_recording(*, external_task_id: str | None = None) -> tuple[str, str]:
    async with AsyncSessionFactory() as session:
        file = CaptureFile(
            user_id="user-1",
            storage_url="captures/F002.mp3",
            file_type="audio/mpeg",
            source_tag="flash",
            asr_status="processing",
        )
        session.add(file)
        await session.flush()
        recording = CaptureRecording(
            user_id="user-1",
            file_id=file.id,
            card_sn="SN-001",
            device_file_name="F002.opus",
            client_task_id="task-large-001",
            source="offline",
            device_crc=5678,
            local_audio_sha256="a" * 64,
            local_audio_size_bytes=100_000,
            audio_format="mp3",
            asr_mode="async",
            s3_key="captures/F002.mp3",
            s3_content_type="audio/mpeg",
            s3_upload_url="https://upload.example/F002.mp3?signature=secret",
            s3_audio_url="https://audio.example/F002.mp3?signature=secret",
            s3_upload_headers_json={"Content-Type": "audio/mpeg"},
            tencent_asr_task_id=external_task_id,
            tencent_engine_type="16k_zh",
            tencent_speaker_diarization=0,
            tencent_hotword_list="",
            tencent_status="submitted" if external_task_id else "pending",
            tencent_task_response_json={"task_id": external_task_id}
            if external_task_id
            else {},
            upload_status="uploaded",
            process_status="asr_processing",
            asr_provider="tencent_asr_s3_async",
            asr_segments_json=[],
            result_records_json=[],
            accepted_at=NOW,
        )
        session.add(recording)
        await session.flush()
        job = await enqueue_job(
            session,
            job_type="capture_asr",
            run_id=recording.id,
            dedupe_key=f"capture-asr:{recording.id}",
            available_at=NOW,
        )
        await session.commit()
        return recording.id, job.id


async def _seed_transcribed_capture(
    transcript: str = "明天下午三点到四点开项目会，咖啡二十八元",
) -> tuple[str, str]:
    async with AsyncSessionFactory() as session:
        file = CaptureFile(
            user_id="user-1",
            storage_url="client-sync-asr:task-sync-001",
            file_type="audio/opus",
            source_tag="flash",
            asr_status="completed",
        )
        session.add(file)
        await session.flush()
        recording = CaptureRecording(
            user_id="user-1",
            file_id=file.id,
            card_sn="SN-001",
            device_file_name="F001.opus",
            client_task_id="task-sync-001",
            source="realtime",
            local_audio_sha256="b" * 64,
            local_audio_size_bytes=2048,
            audio_format="opus",
            asr_mode="sync_client",
            s3_key="client-sync-asr:task-sync-001",
            s3_upload_headers_json={},
            tencent_speaker_diarization=0,
            tencent_status="finished",
            tencent_task_response_json={"code": 0},
            tencent_result_response_json={"code": 0},
            upload_status="uploaded",
            process_status="asr_done",
            asr_provider="tencent_asr_sync_client",
            asr_text=transcript,
            asr_segments_json=[],
            result_records_json=[],
            accepted_at=NOW,
        )
        session.add(recording)
        await session.flush()
        session.add(
            CaptureTurn(
                recording_id=recording.id,
                user_id="user-1",
                transcript=transcript,
                source="realtime",
                provenance_json={"kind": "hardware_audio"},
            )
        )
        job = await enqueue_job(
            session,
            job_type="capture_process",
            run_id=recording.id,
            dedupe_key=f"capture-process:{recording.id}",
            available_at=NOW,
        )
        await session.commit()
        return recording.id, job.id


def _registry(provider: FakeAsrProvider) -> JobHandlerRegistry:
    registry = JobHandlerRegistry()
    registry.register(
        "capture_asr",
        capture_asr_handler(
            provider,
            poll_interval_seconds=5,
            poll_timeout_seconds=60,
            clock=lambda: NOW,
        ),
    )
    return registry


def _process_registry(
    provider: FakeCaptureAgentProvider,
    *,
    tool_runtime=None,
    monotonic_clock=None,
) -> JobHandlerRegistry:
    registry = JobHandlerRegistry()
    options = {
        "clock": lambda: NOW,
        "tool_runtime": tool_runtime,
    }
    if monotonic_clock is not None:
        options["monotonic_clock"] = monotonic_clock
    registry.register(
        "capture_process",
        capture_process_handler(provider, **options),
    )
    return registry


def _monotonic_sequence(*values: float):
    iterator = iter(values)
    return lambda: next(iterator)


class _InProcessToolRuntime:
    def __init__(self):
        self.calls = []

    async def call_tool(
        self,
        name: str,
        arguments: dict,
        *,
        trusted: InternalMCPTrustedContext,
    ) -> dict:
        self.calls.append((name, dict(arguments), trusted))
        return await execute_tool(
            name,
            arguments,
            context=EurekaToolContext(
                user_id=trusted.user_id,
                session_id=trusted.session_id,
                input_turn_id=trusted.input_turn_id,
                idempotency_prefix=f"turn:{trusted.input_turn_id}",
            ),
            tool_call_id=trusted.tool_call_id,
        )


class _ExecutedFlashProvider:
    def __init__(self, *, partial: bool = False):
        self.partial = partial
        self.calls = []

    async def execute(self, *, context, tool_runtime=None):
        self.calls.append(context)
        executor = SessionToolExecutor(
            user_id=context.user_id,
            session_id=context.session_id,
            input_turn_id=context.input_turn_id,
            runtime=tool_runtime,
        )
        outcome = await executor.execute(
            "tool_create_asset",
            {
                "user_skill_name": "expense",
                "payload": {
                    "amount": 28,
                    "currency": "CNY",
                    "category": "餐饮",
                },
                "domain": "生活",
            },
            tool_call_id=f"capture:{context.recording_id}:0:expense:test",
        )
        items = [
            FlashExecutionItem(
                intent=FlashIntent(
                    type="expense",
                    source_text="咖啡二十八元",
                    domain="生活",
                ),
                status="success",
                result=outcome.response,
            )
        ]
        if self.partial:
            items.append(
                FlashExecutionItem(
                    intent=FlashIntent(
                        type="contact",
                        source_text="更新Alex",
                        domain="社交",
                    ),
                    status="error",
                    error_code="intent_tool_rejected",
                )
            )
        return FlashExecutionResult(
            summary=(
                "已完成 1 项，另有 1 项未完成。"
                if self.partial
                else "已完成 1 项。"
            ),
            items=tuple(items),
            warnings=("intent_tool_rejected",) if self.partial else (),
        )


class _PhantomAssetProvider:
    async def execute(self, *, context, tool_runtime=None):
        return FlashExecutionResult(
            summary="声称记录但没有落库。",
            items=(
                FlashExecutionItem(
                    intent=FlashIntent(
                        type="expense",
                        source_text="咖啡二十八元",
                        domain="生活",
                    ),
                    status="success",
                    result={
                        "asset_id": "phantom-asset",
                        "user_skill_name": "expense",
                        "payload": {"amount": 28, "currency": "CNY"},
                    },
                ),
            ),
        )


class _ExistingAssetProvider:
    def __init__(self, asset_id: str):
        self.asset_id = asset_id

    async def execute(self, *, context, tool_runtime=None):
        return FlashExecutionResult(
            summary="引用了一条既有记录。",
            items=(
                FlashExecutionItem(
                    intent=FlashIntent(
                        type="expense",
                        source_text="咖啡二十八元",
                        domain="生活",
                    ),
                    status="success",
                    result={
                        "asset_id": self.asset_id,
                        "user_skill_name": "expense",
                        "payload": {"amount": 28, "currency": "CNY"},
                    },
                ),
            ),
        )


class _ExecutedMutationProvider:
    def __init__(self, *, tool_name: str, arguments: dict, intent_type: str):
        self.tool_name = tool_name
        self.arguments = arguments
        self.intent_type = intent_type

    async def execute(self, *, context, tool_runtime=None):
        executor = SessionToolExecutor(
            user_id=context.user_id,
            session_id=context.session_id,
            input_turn_id=context.input_turn_id,
            runtime=tool_runtime,
        )
        outcome = await executor.execute(
            self.tool_name,
            self.arguments,
            tool_call_id=f"capture:{context.recording_id}:update:test",
        )
        return FlashExecutionResult(
            summary="已更新记录。",
            items=(
                FlashExecutionItem(
                    intent=FlashIntent(
                        type=self.intent_type,
                        source_text="更新记录",
                        domain="生活",
                    ),
                    status="success",
                    result=outcome.response,
                ),
            ),
        )


def _event_and_expense_result() -> CaptureAgentResult:
    return CaptureAgentResult(
        summary="已记录项目会和 28 元咖啡消费。",
        records=[
            CaptureRecordCommand(
                kind="event",
                title="项目会",
                start_at="2026-08-03T15:00:00+08:00",
                end_at="2026-08-03T16:00:00+08:00",
                location="会议室 A",
                attendees=["冯总"],
            ),
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="expense",
                payload={
                    "amount": 28,
                    "currency": "CNY",
                    "category": "餐饮",
                },
                effective_at="2026-08-02T09:00:00+08:00",
            ),
        ],
    )


async def test_asr_job_reuses_checkpointed_external_task(session):
    provider = FakeAsrProvider(
        [AsrPollResult.finished("记下咖啡二十八元")]
    )
    recording_id, job_id = await _seed_s3_recording(
        external_task_id="tencent-7"
    )

    assert await run_worker_once(
        _registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    assert provider.created == []
    assert provider.polled == ["tencent-7"]
    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        process_job = await database_session.scalar(
            select(WorkflowJob).where(WorkflowJob.job_type == "capture_process")
        )
        turn = await database_session.scalar(
            select(CaptureTurn).where(CaptureTurn.recording_id == recording_id)
        )
        events = list(
            await database_session.scalars(
                select(OutboxEvent).where(OutboxEvent.aggregate_id == recording_id)
            )
        )
    assert recording.process_status == "asr_done"
    assert recording.asr_text == "记下咖啡二十八元"
    assert job.status == "succeeded"
    assert process_job.input_dedupe_key == f"capture-process:{recording_id}"
    assert turn.transcript == "记下咖啡二十八元"
    assert [event.payload_json["status"] for event in events] == ["asr_done"]


async def test_pending_asr_requeues_without_holding_lease_and_reuses_task(session):
    provider = FakeAsrProvider(
        [
            AsrPollResult.pending(raw_response={"status": "running"}),
            AsrPollResult.finished("预约周五下午复诊"),
        ]
    )
    recording_id, job_id = await _seed_s3_recording()
    registry = _registry(provider)

    assert await run_worker_once(
        registry,
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )
    async with AsyncSessionFactory() as database_session:
        deferred = await database_session.get(WorkflowJob, job_id)
        recording = await database_session.get(CaptureRecording, recording_id)
        assert deferred.status == "queued"
        assert deferred.available_at == NOW + timedelta(seconds=5)
        assert deferred.lease_owner is None
        assert deferred.checkpoint_json["external_task_id"] == "tencent-7"
        assert recording.tencent_asr_task_id == "tencent-7"

    assert await run_worker_once(
        registry,
        owner="worker-b",
        lease_seconds=60,
        now=NOW + timedelta(seconds=5),
    )
    assert len(provider.created) == 1
    assert provider.polled == ["tencent-7", "tencent-7"]


async def test_provider_failed_result_permanently_fails_capture_job(session):
    provider = FakeAsrProvider(
        [AsrPollResult.failed("音频格式不支持", raw_response={"status": "failed"})]
    )
    recording_id, job_id = await _seed_s3_recording(
        external_task_id="tencent-7"
    )

    await run_worker_once(
        _registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        file = await database_session.get(CaptureFile, recording.file_id)
        job = await database_session.get(WorkflowJob, job_id)
    assert recording.process_status == "failed"
    assert recording.error_message == "音频格式不支持"
    assert file.asr_status == "failed"
    assert job.status == "failed"
    assert job.attempt == 1


async def test_retryable_transport_error_uses_queue_backoff(session):
    provider = FakeAsrProvider([RetryableAsrError("temporary")])
    recording_id, job_id = await _seed_s3_recording(
        external_task_id="tencent-7"
    )

    await run_worker_once(
        _registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
    assert recording.process_status == "asr_processing"
    assert job.status == "queued"
    assert job.attempt == 1
    assert job.available_at > NOW


async def test_exhausted_asr_retry_persists_terminal_capture_failure(session):
    provider = FakeAsrProvider([RetryableAsrError("temporary ASR outage")])
    recording_id, job_id = await _seed_s3_recording(
        external_task_id="tencent-7"
    )
    async with AsyncSessionFactory() as database_session:
        job = await database_session.get(WorkflowJob, job_id)
        job.max_attempts = 1
        await database_session.commit()

    await run_worker_once(
        _registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
    assert recording.process_status == "failed"
    assert recording.error_message == "temporary ASR outage"
    assert recording.session_id is None
    assert job.status == "failed"


async def test_permanent_invalid_provider_response_does_not_retry(session):
    provider = FakeAsrProvider([PermanentAsrError("invalid provider response")])
    recording_id, job_id = await _seed_s3_recording(
        external_task_id="tencent-7"
    )

    await run_worker_once(
        _registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
    assert recording.process_status == "failed"
    assert job.status == "failed"
    assert job.attempt == 1


async def test_capture_job_creates_multiple_records_and_notification(session):
    provider = FakeCaptureAgentProvider(_event_and_expense_result())
    tool_runtime = _InProcessToolRuntime()
    recording_id, job_id = await _seed_transcribed_capture()

    assert await run_worker_once(
        _process_registry(
            provider,
            tool_runtime=tool_runtime,
            monotonic_clock=_monotonic_sequence(100.0, 101.25),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
        assets = list(await database_session.scalars(select(Asset)))
        events = list(await database_session.scalars(select(Event)))
        attendees = list(await database_session.scalars(select(EventAttendee)))
        notifications = list(
            await database_session.scalars(
                select(Notification).where(Notification.type == "flash_done")
            )
        )
        notification_outbox = await database_session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_type == "notification",
                OutboxEvent.aggregate_id == notifications[0].id,
            )
        )
        skills = list(
            await database_session.scalars(
                select(UserSkill).order_by(UserSkill.created_at, UserSkill.id)
            )
        )
    assert recording.process_status == "done"
    assert agent_message.elapsed_ms == 1250
    assert recording.result_summary == "已记录项目会和 28 元咖啡消费。"
    assert len(recording.result_records_json) == 2
    assert {card["entity_kind"] for card in recording.result_records_json} == {
        "asset",
        "event",
    }
    assert all(
        card["source"]
        == {
            "session_id": recording.session_id,
            "input_turn_id": recording.input_turn_id,
            "kind": "capture",
        }
        for card in recording.result_records_json
    )
    assert all(
        not {"title", "subtitle", "icon", "accent_color", "meta_fields"}
        .intersection(card)
        for card in recording.result_records_json
    )
    assert len(assets) == 1
    assert len(events) == 1
    assert [(item.event_id, item.name_raw, item.contact_id) for item in attendees] == [
        (events[0].id, "冯总", None)
    ]
    assert len(notifications) == 1
    assert notifications[0].body == recording.result_summary
    assert notification_outbox.payload_json == {
        "notification_id": notifications[0].id,
        "confirmed_mutation": True,
    }
    assert job.status == "succeeded"
    assert [skill.machine_name for skill in provider.calls[0]["skills"]] == [
        "todo",
        "expense",
        "contact",
        "notes",
        "event",
    ]
    assert {skill.machine_name for skill in skills} == {
        "todo",
        "expense",
        "contact",
        "notes",
        "event",
    }
    tool_names = [call[0] for call in tool_runtime.calls]
    assert tool_names.count("tool_create_asset") == 1
    assert [name for name in tool_names if name != "tool_create_asset"] == [
        "tool_create_event",
        "tool_query_contact",
        "tool_add_event_attendee",
        "tool_get_event",
    ]
    assert all(call[2].session_id == recording.session_id for call in tool_runtime.calls)
    assert all(
        call[2].input_turn_id == recording.input_turn_id
        for call in tool_runtime.calls
    )


async def test_capture_job_persists_preexecuted_flash_facts_without_replay(session):
    provider = _ExecutedFlashProvider()
    tool_runtime = _InProcessToolRuntime()
    recording_id, _ = await _seed_transcribed_capture("咖啡二十八元")

    await run_worker_once(
        _process_registry(provider, tool_runtime=tool_runtime),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
        asset_count = await database_session.scalar(
            select(func.count()).select_from(Asset)
        )
    assert recording.process_status == "done"
    assert recording.result_records_json[0]["entity_kind"] == "asset"
    assert recording.result_records_json[0]["entity_id"]
    assert recording.result_records_json[0]["entity"]["asset_id"]
    assert agent_message.status == "done"
    assert asset_count == 1
    assert [call[0] for call in tool_runtime.calls] == ["tool_create_asset"]


async def test_capture_job_persists_partial_success_and_turn_local_error(session):
    provider = _ExecutedFlashProvider(partial=True)
    recording_id, _ = await _seed_transcribed_capture(
        "咖啡二十八元，更新Alex"
    )

    await run_worker_once(
        _process_registry(provider, tool_runtime=_InProcessToolRuntime()),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert recording.process_status == "done"
    assert recording.result_records_json[0]["entity_kind"] == "asset"
    assert recording.result_records_json[1]["kind"] == "error"
    assert agent_message.status == "done"
    assert agent_message.cards_json[1]["error_code"] == "intent_tool_rejected"


async def test_custom_partial_record_does_not_discard_valid_sibling_intent(session):
    async with AsyncSessionFactory() as database_session:
        database_session.add_all(
            [
                UserSkill(
                    user_id="user-1",
                    machine_name="running_training_log",
                    display_name="跑步训练",
                    description="跑步记录",
                    domain="fitness",
                    schema_json={
                        "type": "object",
                        "properties": {
                            "distance": {"type": "number"},
                            "duration": {"type": "integer"},
                            "run_date": {"type": "string"},
                        },
                        "required": ["distance", "duration", "run_date"],
                        "additionalProperties": False,
                        "x-capture-enabled": True,
                    },
                ),
                UserSkill(
                    user_id="user-1",
                    machine_name="daily_water_intake",
                    display_name="喝水记录",
                    description="每日饮水",
                    domain="fitness",
                    schema_json={
                        "type": "object",
                        "properties": {
                            "amount_ml": {"type": "integer"},
                            "date": {"type": "string"},
                        },
                        "required": ["amount_ml", "date"],
                        "additionalProperties": False,
                        "x-capture-enabled": True,
                    },
                ),
            ]
        )
        await database_session.commit()

    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(
            summary="已记录跑步和饮水。",
            records=[
                CaptureRecordCommand(
                    kind="asset",
                    skill_machine_name="running_training_log",
                    payload={
                        "distance": 2,
                        "location": "深圳湾人才公园",
                    },
                    source_text="跑了两公里，在深圳湾人才公园",
                ),
                CaptureRecordCommand(
                    kind="asset",
                    skill_machine_name="daily_water_intake",
                    payload={"amount_ml": 1000},
                    source_text="喝了一公升水",
                ),
            ],
        )
    )
    recording_id, _ = await _seed_transcribed_capture(
        "刚刚我跑了两公里，在深圳湾人才公园，然后喝了一公升水。"
    )

    await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        rows = (
            await database_session.execute(
                select(Asset, UserSkill)
                .join(UserSkill, UserSkill.id == Asset.user_skill_id)
                .where(
                    UserSkill.machine_name.in_(
                        ["running_training_log", "daily_water_intake"]
                    )
                )
            )
        ).all()
    by_skill = {skill.machine_name: asset for asset, skill in rows}
    assert recording.process_status == "done"
    assert set(by_skill) == {
        "running_training_log",
        "daily_water_intake",
    }, recording.result_records_json
    assert by_skill["running_training_log"].payload_json == {
        "distance": 2,
        "location": "深圳湾人才公园",
    }
    assert by_skill["daily_water_intake"].payload_json == {"amount_ml": 1000}
    assert all(asset.session_id == recording.session_id for asset in by_skill.values())
    assert all(
        asset.source_input_turn_id == recording.input_turn_id
        for asset in by_skill.values()
    )


async def test_capture_contact_creates_first_class_contact_not_asset(session):
    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(
            summary="已添加 Alex。",
            records=[
                CaptureRecordCommand(
                    kind="contact",
                    operation="create_or_update",
                    name="Alex",
                    contact_patch={"company": "Acme"},
                    source_text="添加 Alex，他在 Acme 工作",
                )
            ],
        )
    )
    recording_id, _ = await _seed_transcribed_capture(
        "添加 Alex，他在 Acme 工作"
    )

    await run_worker_once(
        _process_registry(provider, tool_runtime=_InProcessToolRuntime()),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        contacts = list(await database_session.scalars(select(Contact)))
        asset_count = await database_session.scalar(
            select(func.count()).select_from(Asset)
        )
    assert recording.process_status == "done"
    assert asset_count == 0
    assert len(contacts) == 1
    assert contacts[0].name == "Alex"
    assert contacts[0].company == "Acme"
    assert recording.result_records_json[0]["entity_kind"] == "contact"
    assert recording.result_records_json[0]["entity_id"] == contacts[0].id
    assert recording.result_records_json[0]["entity"]["name"] == "Alex"


async def test_capture_contact_updates_the_only_exact_alex(session):
    async with AsyncSessionFactory() as database_session:
        database_session.add(Contact(user_id="user-1", name="Alex"))
        await database_session.commit()
    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(
            summary="已更新 Alex 的职业。",
            records=[
                CaptureRecordCommand(
                    kind="contact",
                    operation="create_or_update",
                    name="Alex",
                    contact_patch={"title": "设计师"},
                    source_text="Alex 的职业改成设计师",
                )
            ],
        )
    )
    await _seed_transcribed_capture("Alex 的职业改成设计师")

    await run_worker_once(
        _process_registry(provider, tool_runtime=_InProcessToolRuntime()),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        contacts = list(await database_session.scalars(select(Contact)))
    assert len(contacts) == 1
    assert contacts[0].title == "设计师"


async def test_capture_contact_persists_pending_when_alex_is_ambiguous(session):
    async with AsyncSessionFactory() as database_session:
        database_session.add_all(
            [
                Contact(user_id="user-1", name="Alex", company="Acme"),
                Contact(user_id="user-1", name="Alex", company="字节"),
            ]
        )
        await database_session.commit()
    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(
            summary="请确认要更新哪一位 Alex。",
            records=[
                CaptureRecordCommand(
                    kind="contact",
                    operation="create_or_update",
                    name="Alex",
                    contact_patch={"title": "设计师"},
                    source_text="Alex 的职业改成设计师",
                )
            ],
        )
    )
    recording_id, _ = await _seed_transcribed_capture(
        "Alex 的职业改成设计师"
    )

    await run_worker_once(
        _process_registry(provider, tool_runtime=_InProcessToolRuntime()),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        contacts = list(
            await database_session.scalars(
                select(Contact).order_by(Contact.company)
            )
        )
        pending = await database_session.scalar(select(AgentPendingAction))
        recording = await database_session.get(CaptureRecording, recording_id)
        message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert [contact.title for contact in contacts] == [None, None]
    assert pending.status == "pending"
    assert pending.operation == "create_or_update"
    assert {item["contact_id"] for item in pending.candidates_json} == {
        contact.id for contact in contacts
    }
    assert pending.intent_json["patch"] == {"title": "设计师"}
    assert message.status == "waiting_confirmation"
    assert message.cards_json[0]["card_type"] == "pending_contact"


async def test_capture_qa_result_completes_without_records(session):
    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(summary="长白山位于吉林省。", records=[])
    )
    recording_id, _ = await _seed_transcribed_capture("长白山在哪个省？")

    await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        asset_count = await database_session.scalar(
            select(func.count()).select_from(Asset)
        )
        event_count = await database_session.scalar(
            select(func.count()).select_from(Event)
        )
        notification = await database_session.scalar(
            select(Notification).where(Notification.type == "flash_done")
        )
        notification_outbox = await database_session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_type == "notification",
                OutboxEvent.aggregate_id == notification.id,
            )
        )
    assert recording.process_status == "done"
    assert recording.result_records_json == []
    assert asset_count == 0
    assert event_count == 0
    assert notification is not None
    assert notification_outbox.payload_json == {
        "notification_id": notification.id,
    }


async def test_capture_does_not_confirm_a_phantom_asset_snapshot(session):
    recording_id, _ = await _seed_transcribed_capture("咖啡二十八元")

    await run_worker_once(
        _process_registry(_PhantomAssetProvider()),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        notification = await database_session.scalar(
            select(Notification).where(Notification.type == "flash_done")
        )
        notification_outbox = await database_session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_type == "notification",
                OutboxEvent.aggregate_id == notification.id,
            )
        )
        asset_count = await database_session.scalar(
            select(func.count()).select_from(Asset)
        )

    assert recording.result_records_json[0]["entity_id"] == "phantom-asset"
    assert asset_count == 0
    assert notification_outbox.payload_json == {
        "notification_id": notification.id,
    }


async def test_capture_does_not_confirm_a_preexisting_asset_reference(session):
    recording_id, _ = await _seed_transcribed_capture("咖啡二十八元")
    async with AsyncSessionFactory() as database_session:
        await ensure_capture_skills(database_session, "user-1")
        expense = await database_session.scalar(
            select(UserSkill).where(
                UserSkill.user_id == "user-1",
                UserSkill.machine_name == "expense",
            )
        )
        existing = Asset(
            user_id="user-1",
            user_skill_id=expense.id,
            payload_json={"amount": 28, "currency": "CNY"},
        )
        database_session.add(existing)
        await database_session.commit()
        existing_id = existing.id

    await run_worker_once(
        _process_registry(_ExistingAssetProvider(existing_id)),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        notification = await database_session.scalar(
            select(Notification).where(Notification.type == "flash_done")
        )
        notification_outbox = await database_session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_type == "notification",
                OutboxEvent.aggregate_id == notification.id,
            )
        )

    assert notification_outbox.payload_json == {
        "notification_id": notification.id,
    }


async def test_capture_confirms_a_durable_asset_update_for_the_current_turn(session):
    recording_id, _ = await _seed_transcribed_capture("把咖啡金额更新成二十九元")
    async with AsyncSessionFactory() as database_session:
        await ensure_capture_skills(database_session, "user-1")
        expense = await database_session.scalar(
            select(UserSkill).where(
                UserSkill.user_id == "user-1",
                UserSkill.machine_name == "expense",
            )
        )
        existing = Asset(
            user_id="user-1",
            user_skill_id=expense.id,
            payload_json={"amount": 28, "currency": "CNY"},
        )
        database_session.add(existing)
        await database_session.commit()
        existing_id = existing.id

    await run_worker_once(
        _process_registry(
            _ExecutedMutationProvider(
                tool_name="tool_update_asset",
                arguments={
                    "asset_id": existing_id,
                    "payload_patch": {"amount": 29},
                },
                intent_type="expense",
            ),
            tool_runtime=_InProcessToolRuntime(),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        updated = await database_session.get(Asset, existing_id)
        notification = await database_session.scalar(
            select(Notification).where(Notification.type == "flash_done")
        )
        notification_outbox = await database_session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_type == "notification",
                OutboxEvent.aggregate_id == notification.id,
            )
        )

    assert updated.payload_json["amount"] == 29
    assert notification_outbox.payload_json == {
        "notification_id": notification.id,
        "confirmed_mutation": True,
    }


async def test_capture_confirms_a_durable_event_update_for_the_current_turn(session):
    recording_id, _ = await _seed_transcribed_capture("把项目会改名为项目复盘")
    async with AsyncSessionFactory() as database_session:
        existing = Event(
            user_id="user-1",
            title="项目会",
            start_at=datetime(2026, 8, 3, 7),
            end_at=datetime(2026, 8, 3, 8),
            all_day=False,
            status="scheduled",
        )
        database_session.add(existing)
        await database_session.commit()
        existing_id = existing.id

    await run_worker_once(
        _process_registry(
            _ExecutedMutationProvider(
                tool_name="tool_update_event",
                arguments={
                    "event_id": existing_id,
                    "patch": {"title": "项目复盘"},
                },
                intent_type="event",
            ),
            tool_runtime=_InProcessToolRuntime(),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        updated = await database_session.get(Event, existing_id)
        notification = await database_session.scalar(
            select(Notification).where(Notification.type == "flash_done")
        )
        notification_outbox = await database_session.scalar(
            select(OutboxEvent).where(
                OutboxEvent.aggregate_type == "notification",
                OutboxEvent.aggregate_id == notification.id,
            )
        )

    assert updated.title == "项目复盘"
    assert notification_outbox.payload_json == {
        "notification_id": notification.id,
        "confirmed_mutation": True,
    }


async def test_completed_capture_process_job_is_idempotent(session):
    provider = FakeCaptureAgentProvider(_event_and_expense_result())
    recording_id, _ = await _seed_transcribed_capture()
    registry = _process_registry(provider)
    await run_worker_once(
        registry,
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )
    async with AsyncSessionFactory() as database_session:
        duplicate = await enqueue_job(
            database_session,
            job_type="capture_process",
            run_id=recording_id,
            dedupe_key=f"manual-duplicate:{recording_id}",
            available_at=NOW,
        )
        await database_session.commit()
        duplicate_id = duplicate.id

    await run_worker_once(
        registry,
        owner="worker-b",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        assert await database_session.scalar(
            select(func.count()).select_from(Asset)
        ) == 1
        assert await database_session.scalar(
            select(func.count()).select_from(Event)
        ) == 1
        assert await database_session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.type == "flash_done")
        ) == 1
        duplicate = await database_session.get(WorkflowJob, duplicate_id)
    assert len(provider.calls) == 1
    assert duplicate.status == "succeeded"


async def test_unknown_skill_output_permanently_fails_without_partial_records(session):
    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(
            summary="已记录跑步。",
            records=[
                CaptureRecordCommand(
                    kind="asset",
                    skill_machine_name="running",
                    payload={"distance_km": 5},
                )
            ],
        )
    )
    recording_id, job_id = await _seed_transcribed_capture("跑了五公里")

    await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        asset_count = await database_session.scalar(
            select(func.count()).select_from(Asset)
        )
    assert recording.process_status == "failed"
    assert job.status == "failed"
    assert asset_count == 0


async def test_capture_process_persists_transcript_grounded_asset_time(session):
    provider = FakeCaptureAgentProvider(
        CaptureAgentResult(
            summary="已记录昨天晚上的消费。",
            records=[
                CaptureRecordCommand(
                    kind="asset",
                    skill_machine_name="expense",
                    payload={"amount": 30, "currency": "CNY"},
                    source_text="昨天晚上8点花了30元",
                )
            ],
        )
    )
    await _seed_transcribed_capture("昨天晚上8点花了30元")

    await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        asset = await database_session.scalar(select(Asset))
        recording = await database_session.scalar(select(CaptureRecording))

    assert provider.calls[0]["reference_datetime"].isoformat() == (
        "2026-08-02T17:00:00+08:00"
    )
    assert "local_date" not in provider.calls[0]
    assert asset is not None, recording.result_records_json
    assert asset.period == "晚上"
    assert asset.occurred_at == datetime(2026, 8, 1, 12, 0)


async def test_retryable_capture_provider_error_requeues_without_outputs(session):
    provider = FakeCaptureAgentProvider(
        RetryableCaptureAgentError("temporary provider issue")
    )
    recording_id, job_id = await _seed_transcribed_capture()

    await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        asset_count = await database_session.scalar(
            select(func.count()).select_from(Asset)
        )
    assert recording.process_status == "agent_processing"
    assert job.status == "queued"
    assert asset_count == 0


async def test_exhausted_agent_retry_updates_persisted_agent_message(session):
    provider = FakeCaptureAgentProvider(
        RetryableCaptureAgentError("temporary agent outage")
    )
    recording_id, job_id = await _seed_transcribed_capture()
    async with AsyncSessionFactory() as database_session:
        job = await database_session.get(WorkflowJob, job_id)
        job.max_attempts = 1
        await database_session.commit()

    await run_worker_once(
        _process_registry(
            provider,
            monotonic_clock=_monotonic_sequence(30.0, 30.5),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert recording.process_status == "failed"
    assert recording.error_message == "temporary agent outage"
    assert agent_message.status == "failed"
    assert agent_message.text == "这条闪念暂时没有整理完成，可以重试"
    assert agent_message.elapsed_ms == 500
    assert job.status == "failed"


async def test_permanent_capture_provider_error_fails_without_retry(session):
    provider = FakeCaptureAgentProvider(
        PermanentCaptureAgentError("invalid output")
    )
    recording_id, job_id = await _seed_transcribed_capture()

    await run_worker_once(
        _process_registry(
            provider,
            monotonic_clock=_monotonic_sequence(20.0, 20.25),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert recording.process_status == "failed"
    assert agent_message.elapsed_ms == 250
    assert job.status == "failed"
    assert job.attempt == 1


async def test_exhausted_unexpected_provider_error_terminalizes_message(session):
    provider = FakeCaptureAgentProvider(RuntimeError("provider crashed"))
    recording_id, job_id = await _seed_transcribed_capture()
    async with AsyncSessionFactory() as database_session:
        job = await database_session.get(WorkflowJob, job_id)
        job.max_attempts = 1
        await database_session.commit()

    await run_worker_once(
        _process_registry(
            provider,
            monotonic_clock=_monotonic_sequence(40.0, 40.75),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert recording.process_status == "failed"
    assert agent_message.status == "failed"
    assert agent_message.elapsed_ms == 750
    assert job.status == "failed"


async def test_exhausted_post_provider_error_terminalizes_message(
    session,
    monkeypatch,
):
    provider = FakeCaptureAgentProvider(_event_and_expense_result())
    recording_id, job_id = await _seed_transcribed_capture()
    async with AsyncSessionFactory() as database_session:
        job = await database_session.get(WorkflowJob, job_id)
        job.max_attempts = 1
        await database_session.commit()

    async def fail_persist(**_kwargs):
        raise RuntimeError("persistence crashed")

    monkeypatch.setattr(
        "app.domains.capture.jobs._persist_flash_execution",
        fail_persist,
    )
    await run_worker_once(
        _process_registry(
            provider,
            monotonic_clock=_monotonic_sequence(50.0, 50.5, 50.7),
        ),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert recording.process_status == "failed"
    assert agent_message.status == "failed"
    assert agent_message.elapsed_ms == 700
    assert job.status == "failed"


async def test_capture_agent_elapsed_accumulates_compute_not_retry_queue(session):
    provider = FakeCaptureAgentProvider(
        RetryableCaptureAgentError("temporary provider issue")
    )
    recording_id, job_id = await _seed_transcribed_capture()
    registry = _process_registry(
        provider,
        monotonic_clock=_monotonic_sequence(10.0, 10.4, 20.0, 20.6),
    )

    await run_worker_once(
        registry,
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )
    async with AsyncSessionFactory() as database_session:
        job = await database_session.get(WorkflowJob, job_id)
        retry_at = job.available_at
        assert job.checkpoint_json["agent_elapsed_ms"] == 400

    provider.result = _event_and_expense_result()
    await run_worker_once(
        registry,
        owner="worker-b",
        lease_seconds=60,
        now=retry_at,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert agent_message.elapsed_ms == 1000


async def test_capture_output_retry_reuses_successful_mcp_mutations(
    session,
    monkeypatch,
):
    provider = FakeCaptureAgentProvider(_event_and_expense_result())
    recording_id, job_id = await _seed_transcribed_capture()
    from app.domains.capture import jobs as capture_jobs

    original_create_notification = capture_jobs.create_notification
    fail_notification = True

    async def maybe_fail_notification(*args, **kwargs):
        if fail_notification:
            raise RuntimeError("notification storage unavailable")
        return await original_create_notification(*args, **kwargs)

    monkeypatch.setattr(
        "app.domains.capture.jobs.create_notification",
        maybe_fail_notification,
    )
    await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        assert await database_session.scalar(
            select(func.count()).select_from(Asset)
        ) == 1
        assert await database_session.scalar(
            select(func.count()).select_from(Event)
        ) == 1
        assert await database_session.scalar(
            select(func.count()).select_from(Notification)
        ) == 0
        retry_at = job.available_at
        assert recording.process_status == "agent_processing"
        assert recording.result_records_json == []
        assert job.status == "queued"

    fail_notification = False
    await run_worker_once(
        _process_registry(provider),
        owner="worker-b",
        lease_seconds=60,
        now=retry_at,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        assert await database_session.scalar(
            select(func.count()).select_from(Asset)
        ) == 1
        assert await database_session.scalar(
            select(func.count()).select_from(Event)
        ) == 1
        assert await database_session.scalar(
            select(func.count()).select_from(Notification)
        ) == 1
    assert recording.process_status == "done"
    assert job.status == "succeeded"
