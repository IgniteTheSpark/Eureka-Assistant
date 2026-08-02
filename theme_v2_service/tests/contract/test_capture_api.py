import asyncio
from types import SimpleNamespace

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import OutboxEvent
from app.domains.capture.agent import CaptureAgentResult, CaptureRecordCommand
from app.domains.capture.jobs import capture_process_handler
from app.domains.capture.models import CaptureRecording
from app.domains.notifications.subscribers import SubscriberRegistry
from app.jobs.registry import JobHandlerRegistry
from app.jobs.runner import run_worker_once
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> str:
    response = await client.post(
        "/api/auth/register",
        json={"email": email, "password": "secret1"},
    )
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _registered_bound_card(
    client: AsyncClient,
    email: str,
    card_sn: str,
) -> str:
    token = await _register(client, email)
    response = await client.post(
        "/api/cards/bindings",
        headers=_headers(token),
        json={
            "card_sn": card_sn,
            "card_device_uuid": f"device-{card_sn}",
            "card_app_uuid": f"app-{card_sn}",
            "card_mac": "AA:BB",
            "card_mac_from": "android",
            "card_name": "W2",
            "card_nick": "UReka 录音卡",
        },
    )
    assert response.status_code == 200
    return token


def _sync_payload() -> dict:
    return {
        "client_task_id": "task-001",
        "source": "realtime",
        "card_sn": "SN-001",
        "device_file_name": "F001.opus",
        "capture_started_at": 1_785_600_000_000,
        "capture_ended_at": "2026-08-01T00:00:08Z",
        "device_crc": 1234,
        "device_size_bytes": 4096,
        "local_audio_sha256": "a" * 64,
        "local_audio_size_bytes": 2048,
        "audio_format": "opus",
        "asr_mode": "sync_client",
        "asr_provider": "tencent_asr_sync_client",
        "asr_status": "completed",
        "asr_text": "明天下午三点项目会",
        "asr_segments": [{"start_ms": 0, "end_ms": 1200, "text": "明天"}],
        "raw_response": {"code": 0},
        "speaker_diarization": False,
    }


def _s3_payload() -> dict:
    return {
        "client_task_id": "task-large-001",
        "source": "offline",
        "card_sn": "SN-001",
        "device_file_name": "F002.opus",
        "capture_started_at": "2026-08-01T00:00:00Z",
        "capture_ended_at": "2026-08-01T00:05:00Z",
        "device_crc": 5678,
        "device_size_bytes": 100_000,
        "local_mp3_sha256": "b" * 64,
        "local_mp3_size_bytes": 80_000,
        "local_audio_sha256": "c" * 64,
        "local_audio_size_bytes": 100_000,
        "asr_mode": "async",
        "audio_format": "mp3",
        "s3": {
            "s3_key": "captures/F002.mp3",
            "upload_url": "https://upload.example/F002.mp3?signature=secret",
            "audio_url": "https://audio.example/F002.mp3?signature=secret",
            "content_type": "audio/mpeg",
            "headers": {"Content-Type": "audio/mpeg"},
            "upload_expires_in": 3600,
            "uploaded_at": "2026-08-01T00:05:02Z",
        },
        "engine_type": "16k_zh",
        "speaker_diarization": False,
        "hotword_list": "",
    }


async def _jobs() -> list[WorkflowJob]:
    async with AsyncSessionFactory() as session:
        return list(
            await session.scalars(
                select(WorkflowJob).order_by(WorkflowJob.created_at)
            )
        )


async def test_bound_card_sync_asr_result_is_idempotently_accepted(client):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    payload = _sync_payload()

    first = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )
    second = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )

    assert first.status_code == 200
    assert first.json()["accepted"] is True
    assert first.json()["duplicate"] is False
    assert first.json()["asr_status"] == "completed"
    assert first.json()["asr_text"] == "明天下午三点项目会"
    assert first.json()["pipeline_status"] == "asr_done"
    assert second.status_code == 200
    assert second.json()["recording_id"] == first.json()["recording_id"]
    assert second.json()["file_id"] == first.json()["file_id"]
    assert second.json()["duplicate"] is True

    recording = await client.get(
        f"/api/flash/recordings/{first.json()['recording_id']}",
        headers=_headers(token),
    )
    assert recording.status_code == 200
    assert recording.json()["recording"]["process_status"] == "asr_done"
    assert recording.json()["recording"]["asr_text"] == "明天下午三点项目会"

    jobs = await _jobs()
    assert [(job.job_type, job.run_id) for job in jobs] == [
        ("capture_process", first.json()["recording_id"])
    ]
    assert jobs[0].input_dedupe_key == (
        f"capture-process:{first.json()['recording_id']}"
    )
    async with AsyncSessionFactory() as database_session:
        events = list(
            await database_session.scalars(
                select(OutboxEvent).where(
                    OutboxEvent.aggregate_id == first.json()["recording_id"]
                )
            )
        )
    assert [event.event_type for event in events] == [
        "flash_file_status",
        "flash_file_status",
    ]
    assert {event.payload_json["status"] for event in events} == {
        "accepted",
        "asr_done",
    }


async def test_unbound_card_sync_result_is_rejected(client):
    token = await _register(client, "capture@example.com")
    response = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=_sync_payload(),
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "card not bound by current user"


async def test_conflicting_sync_duplicate_returns_409(client):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    payload = _sync_payload()
    first = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )
    assert first.status_code == 200

    changed = {**payload, "asr_text": "完全不同的内容"}
    conflict = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=changed,
    )
    assert conflict.status_code == 409


@pytest.mark.parametrize(
    ("asr_status", "asr_text", "expected_state", "expected_message"),
    [
        ("failed", "", "failed", "客户端识别失败"),
        ("completed", "  ", "empty", "文件没内容"),
    ],
)
async def test_terminal_sync_asr_result_does_not_queue_agent(
    client,
    asr_status,
    asr_text,
    expected_state,
    expected_message,
):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    payload = {
        **_sync_payload(),
        "asr_status": asr_status,
        "asr_text": asr_text,
        "asr_error": "客户端识别失败" if asr_status == "failed" else "",
        "error_message": "",
    }
    response = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )

    assert response.status_code == 200
    assert response.json()["pipeline_status"] == expected_state
    assert response.json()["message"] == expected_message
    assert await _jobs() == []


async def test_foreign_user_cannot_read_recording(client):
    owner = await _registered_bound_card(
        client,
        "capture-owner@example.com",
        "SN-001",
    )
    foreign = await _register(client, "capture-foreign@example.com")
    created = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(owner),
        json=_sync_payload(),
    )

    response = await client.get(
        f"/api/flash/recordings/{created.json()['recording_id']}",
        headers=_headers(foreign),
    )
    assert response.status_code == 404


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("local_audio_sha256", "not-a-hash"),
        ("local_audio_size_bytes", 0),
        ("asr_mode", "async"),
        ("audio_format", "mp3"),
        ("device_file_name", "recording.mp3"),
    ],
)
async def test_sync_result_rejects_malformed_payload(client, field, value):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    response = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json={**_sync_payload(), field: value},
    )
    assert response.status_code == 422


async def test_s3_upload_is_idempotently_accepted_for_async_asr(client):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    payload = _s3_payload()
    first = await client.post(
        "/api/flash/tencent-asr-s3-uploads",
        headers=_headers(token),
        json=payload,
    )
    second = await client.post(
        "/api/flash/tencent-asr-s3-uploads",
        headers=_headers(token),
        json=payload,
    )

    assert first.status_code == 200
    assert first.json()["accepted"] is True
    assert first.json()["duplicate"] is False
    assert first.json()["asr_status"] == "processing"
    assert first.json()["pipeline_status"] == "asr_processing"
    assert second.status_code == 200
    assert second.json()["duplicate"] is True
    assert second.json()["recording_id"] == first.json()["recording_id"]

    jobs = await _jobs()
    assert [(job.job_type, job.run_id) for job in jobs] == [
        ("capture_asr", first.json()["recording_id"])
    ]
    assert jobs[0].input_dedupe_key == f"capture-asr:{first.json()['recording_id']}"

    changed = {
        **payload,
        "s3": {**payload["s3"], "s3_key": "captures/different.mp3"},
    }
    conflict = await client.post(
        "/api/flash/tencent-asr-s3-uploads",
        headers=_headers(token),
        json=changed,
    )
    assert conflict.status_code == 409


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("asr_mode", "sync_client"),
        ("audio_format", "opus"),
        ("local_audio_sha256", "bad"),
        ("local_audio_size_bytes", 0),
        ("s3.audio_url", ""),
    ],
)
async def test_s3_upload_rejects_malformed_shape(client, field, value):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    payload = _s3_payload()
    if field.startswith("s3."):
        nested_field = field.split(".", 1)[1]
        payload = {**payload, "s3": {**payload["s3"], nested_field: value}}
    else:
        payload = {**payload, field: value}
    response = await client.post(
        "/api/flash/tencent-asr-s3-uploads",
        headers=_headers(token),
        json=payload,
    )
    assert response.status_code == 422


@pytest.mark.parametrize(
    ("method", "path", "payload"),
    [
        ("POST", "/api/flash", {"text": "需要登录", "source": "typed"}),
        ("POST", "/api/flash/tencent-asr-sync-results", _sync_payload()),
        ("POST", "/api/flash/tencent-asr-s3-uploads", _s3_payload()),
        ("POST", "/api/flash/listening", {"state": "on"}),
        (
            "POST",
            "/api/flash/recordings/00000000-0000-0000-0000-000000000001/retry",
            None,
        ),
        (
            "GET",
            "/api/flash/recordings/00000000-0000-0000-0000-000000000001",
            None,
        ),
    ],
)
async def test_capture_routes_require_authentication(client, method, path, payload):
    response = await client.request(method, path, json=payload)
    assert response.status_code == 401


class _FakeCaptureProvider:
    def __init__(self, result: CaptureAgentResult):
        self.result = result
        self.calls = []

    async def organize(self, **command):
        self.calls.append(command)
        return self.result


async def _run_capture_process_when_queued(provider) -> None:
    for _ in range(100):
        async with AsyncSessionFactory() as database_session:
            job = await database_session.scalar(
                select(WorkflowJob).where(
                    WorkflowJob.job_type == "capture_process",
                    WorkflowJob.status == "queued",
                )
            )
        if job is not None:
            registry = JobHandlerRegistry()
            registry.register(
                "capture_process",
                capture_process_handler(provider),
            )
            assert await run_worker_once(
                registry,
                owner="contract-worker",
                lease_seconds=60,
            )
            return
        await asyncio.sleep(0.01)
    raise AssertionError("capture_process job was not queued")


async def test_text_flash_waits_for_durable_worker_result(client):
    token = await _register(client, "ring-owner@example.com")
    provider = _FakeCaptureProvider(
        CaptureAgentResult(
            summary="已记录产品想法。",
            records=[
                CaptureRecordCommand(
                    kind="asset",
                    skill_machine_name="notes",
                    payload={
                        "title": "客户标签系统",
                        "content": "可以做一个客户标签系统",
                        "tags": ["产品", "客户"],
                    },
                )
            ],
        )
    )

    request = asyncio.create_task(
        client.post(
            "/api/flash",
            headers=_headers(token),
            json={"text": "可以做一个客户标签系统", "source": "voice"},
        )
    )
    await _run_capture_process_when_queued(provider)
    response = await request

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["session_id"]
    assert body["input_turn_id"]
    assert body["reply"] == ""
    assert body["summary"] == "已记录产品想法。"
    assert body["has_pending"] is False
    assert body["cards"][0]["card_type"] == "notes"
    assert body["cards"][0]["asset_id"]
    assert body["derived_assets"] == body["cards"]
    assert len(provider.calls) == 1

    status = await client.get(
        f"/api/flash/recordings/{body['session_id']}",
        headers=_headers(token),
    )
    assert status.status_code == 200
    assert status.json()["recording"]["process_status"] == "done"
    assert status.json()["recording"]["input_turn_id"] == body["input_turn_id"]


async def test_text_flash_timeout_returns_controlled_pending(
    client,
    monkeypatch,
):
    token = await _register(client, "ring-owner@example.com")
    monkeypatch.setattr(
        "app.domains.capture.api.get_settings",
        lambda: SimpleNamespace(
            capture_flash_wait_seconds=0.03,
            capture_flash_poll_interval_seconds=0.005,
        ),
    )

    response = await client.post(
        "/api/flash",
        headers=_headers(token),
        json={"text": "稍后整理这条语音", "source": "voice"},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert response.json()["has_pending"] is True
    assert response.json()["session_id"]
    assert response.json()["input_turn_id"]
    assert "ApiException" not in str(response.json())


async def test_text_flash_recording_is_owner_scoped(client, monkeypatch):
    owner = await _register(client, "ring-owner@example.com")
    foreign = await _register(client, "ring-foreign@example.com")
    monkeypatch.setattr(
        "app.domains.capture.api.get_settings",
        lambda: SimpleNamespace(
            capture_flash_wait_seconds=0.01,
            capture_flash_poll_interval_seconds=0.005,
        ),
    )
    created = await client.post(
        "/api/flash",
        headers=_headers(owner),
        json={"text": "仅归属我的记录", "source": "typed"},
    )

    response = await client.get(
        f"/api/flash/recordings/{created.json()['session_id']}",
        headers=_headers(foreign),
    )
    assert response.status_code == 404

    retry = await client.post(
        f"/api/flash/recordings/{created.json()['session_id']}/retry",
        headers=_headers(foreign),
    )
    assert retry.status_code == 404


async def test_retry_with_transcript_requeues_process_job_once(client, monkeypatch):
    token = await _register(client, "ring-owner@example.com")
    monkeypatch.setattr(
        "app.domains.capture.api.get_settings",
        lambda: SimpleNamespace(
            capture_flash_wait_seconds=0.01,
            capture_flash_poll_interval_seconds=0.005,
        ),
    )
    created = await client.post(
        "/api/flash",
        headers=_headers(token),
        json={"text": "重新整理我的想法", "source": "voice"},
    )
    recording_id = created.json()["session_id"]
    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        recording.process_status = "failed"
        job = await database_session.scalar(
            select(WorkflowJob).where(WorkflowJob.run_id == recording_id)
        )
        job.status = "failed"
        job.completed_at = recording.updated_at
        await database_session.commit()
        original_job_id = job.id

    first = await client.post(
        f"/api/flash/recordings/{recording_id}/retry",
        headers=_headers(token),
    )
    second = await client.post(
        f"/api/flash/recordings/{recording_id}/retry",
        headers=_headers(token),
    )

    assert first.status_code == 200
    assert first.json() == {
        "ok": True,
        "queued": True,
        "mode": "pipeline",
        "recording_id": recording_id,
        "error": "",
    }
    assert second.json()["mode"] == "pipeline"
    async with AsyncSessionFactory() as database_session:
        jobs = list(
            await database_session.scalars(
                select(WorkflowJob).where(WorkflowJob.run_id == recording_id)
            )
        )
    assert len(jobs) == 1
    assert jobs[0].id == original_job_id
    assert jobs[0].status == "queued"


async def test_retry_without_transcript_selects_asr_job(client):
    token = await _registered_bound_card(
        client,
        "capture@example.com",
        "SN-001",
    )
    created = await client.post(
        "/api/flash/tencent-asr-s3-uploads",
        headers=_headers(token),
        json=_s3_payload(),
    )
    recording_id = created.json()["recording_id"]
    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        recording.process_status = "failed"
        job = await database_session.scalar(
            select(WorkflowJob).where(WorkflowJob.run_id == recording_id)
        )
        job.status = "failed"
        job.completed_at = recording.updated_at
        await database_session.commit()

    response = await client.post(
        f"/api/flash/recordings/{recording_id}/retry",
        headers=_headers(token),
    )

    assert response.status_code == 200
    assert response.json()["mode"] == "asr"
    async with AsyncSessionFactory() as database_session:
        job_count = await database_session.scalar(
            select(func.count())
            .select_from(WorkflowJob)
            .where(WorkflowJob.run_id == recording_id)
        )
        job = await database_session.scalar(
            select(WorkflowJob).where(WorkflowJob.run_id == recording_id)
        )
    assert job_count == 1
    assert job.job_type == "capture_asr"
    assert job.status == "queued"


async def test_listening_state_is_published_to_live_subscriber(client):
    token = await _register(client, "listener@example.com")
    registry = SubscriberRegistry()
    app.state.notification_subscribers = registry
    registered = await client.post(
        "/api/auth/login",
        json={"email": "listener@example.com", "password": "secret1"},
    )
    user_id = registered.json()["user"]["id"]
    queue = registry.subscribe(user_id)

    response = await client.post(
        "/api/flash/listening",
        headers=_headers(token),
        json={"state": "on"},
    )

    assert response.json() == {"ok": True, "state": "on"}
    frame = queue.get_nowait()
    assert frame.event == "listening"
    assert frame.payload == {"state": "on"}
