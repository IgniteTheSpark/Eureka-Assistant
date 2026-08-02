from datetime import datetime, timedelta

from sqlalchemy import select

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.capture.asr import (
    AsrPollResult,
    AsrTask,
    PermanentAsrError,
    RetryableAsrError,
)
from app.domains.capture.jobs import capture_asr_handler
from app.domains.capture.models import CaptureFile, CaptureRecording, CaptureTurn
from app.domains.notifications.models import OutboxEvent
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
