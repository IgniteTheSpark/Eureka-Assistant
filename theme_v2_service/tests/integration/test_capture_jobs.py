from datetime import datetime, timedelta

import pytest
from sqlalchemy import func, select

from app.db.models import Asset, Event, EventAttendee, UserSkill, WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.capture.asr import (
    AsrPollResult,
    AsrTask,
    PermanentAsrError,
    RetryableAsrError,
)
from app.domains.capture.agent import (
    CaptureAgentResult,
    CaptureRecordCommand,
    PermanentCaptureAgentError,
    RetryableCaptureAgentError,
)
from app.domains.capture.jobs import capture_asr_handler, capture_process_handler
from app.domains.capture.models import CaptureFile, CaptureRecording, CaptureTurn
from app.domains.notifications.models import Notification, OutboxEvent
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

    async def organize(self, **command):
        self.calls.append(command)
        if isinstance(self.result, Exception):
            raise self.result
        return self.result


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


def _process_registry(provider: FakeCaptureAgentProvider) -> JobHandlerRegistry:
    registry = JobHandlerRegistry()
    registry.register(
        "capture_process",
        capture_process_handler(provider, clock=lambda: NOW),
    )
    return registry


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
    recording_id, job_id = await _seed_transcribed_capture()

    assert await run_worker_once(
        _process_registry(provider),
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        job = await database_session.get(WorkflowJob, job_id)
        assets = list(await database_session.scalars(select(Asset)))
        events = list(await database_session.scalars(select(Event)))
        attendees = list(await database_session.scalars(select(EventAttendee)))
        notifications = list(
            await database_session.scalars(
                select(Notification).where(Notification.type == "flash_done")
            )
        )
        skills = list(
            await database_session.scalars(
                select(UserSkill).order_by(UserSkill.created_at, UserSkill.id)
            )
        )
    assert recording.process_status == "done"
    assert recording.result_summary == "已记录项目会和 28 元咖啡消费。"
    assert len(recording.result_records_json) == 2
    assert len(assets) == 1
    assert len(events) == 1
    assert [(item.event_id, item.name_raw, item.contact_id) for item in attendees] == [
        (events[0].id, "冯总", None)
    ]
    assert len(notifications) == 1
    assert notifications[0].body == recording.result_summary
    assert job.status == "succeeded"
    assert [skill.machine_name for skill in provider.calls[0]["skills"]] == [
        "todo",
        "expense",
        "contact",
        "notes",
    ]
    assert {skill.machine_name for skill in skills} == {
        "todo",
        "expense",
        "contact",
        "notes",
    }


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
        notification_count = await database_session.scalar(
            select(func.count())
            .select_from(Notification)
            .where(Notification.type == "flash_done")
        )
    assert recording.process_status == "done"
    assert recording.result_records_json == []
    assert asset_count == 0
    assert event_count == 0
    assert notification_count == 1


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

    assert provider.calls[0]["reference_datetime"].isoformat() == (
        "2026-08-02T17:00:00+08:00"
    )
    assert "local_date" not in provider.calls[0]
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


async def test_permanent_capture_provider_error_fails_without_retry(session):
    provider = FakeCaptureAgentProvider(
        PermanentCaptureAgentError("invalid output")
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
    assert recording.process_status == "failed"
    assert job.status == "failed"
    assert job.attempt == 1


async def test_capture_output_transaction_rolls_back_all_records(
    session,
    monkeypatch,
):
    provider = FakeCaptureAgentProvider(_event_and_expense_result())
    recording_id, job_id = await _seed_transcribed_capture()

    async def fail_notification(*args, **kwargs):
        raise RuntimeError("notification storage unavailable")

    monkeypatch.setattr(
        "app.domains.capture.jobs.create_notification",
        fail_notification,
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
        ) == 0
        assert await database_session.scalar(
            select(func.count()).select_from(Event)
        ) == 0
        assert await database_session.scalar(
            select(func.count()).select_from(Notification)
        ) == 0
    assert recording.process_status == "agent_processing"
    assert recording.result_records_json == []
    assert job.status == "queued"
