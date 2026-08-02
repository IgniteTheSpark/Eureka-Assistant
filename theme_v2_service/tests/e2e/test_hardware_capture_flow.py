import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.db.base import utc_now
from app.db.session import AsyncSessionFactory
from app.domains.capture.agent import CaptureAgentResult, CaptureRecordCommand
from app.domains.capture.asr import AsrPollResult, AsrTask
from app.domains.capture.jobs import capture_asr_handler, capture_process_handler
from app.domains.notifications.outbox import dispatch_one
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


class FakeTencentAsrProvider:
    def __init__(self) -> None:
        self.created: list[dict] = []
        self.polled: list[str] = []

    async def create_task(self, **command) -> AsrTask:
        self.created.append(command)
        return AsrTask(
            task_id="tencent-e2e",
            raw_response={"task_id": "tencent-e2e"},
        )

    async def get_result(self, task_id: str) -> AsrPollResult:
        self.polled.append(task_id)
        return AsrPollResult.finished(
            "咖啡二十八元",
            raw_response={"status": "finished"},
        )


class FakeCaptureAgentProvider:
    def __init__(self) -> None:
        self.transcripts: list[str] = []

    async def organize(self, **command) -> CaptureAgentResult:
        transcript = command["transcript"]
        self.transcripts.append(transcript)
        if "项目会" in transcript:
            return CaptureAgentResult(
                summary="已创建明天下午三点的项目会。",
                records=[
                    CaptureRecordCommand(
                        kind="event",
                        title="项目会",
                        start_at="2026-08-03T15:00:00+08:00",
                        end_at="2026-08-03T16:00:00+08:00",
                    )
                ],
            )
        return CaptureAgentResult(
            summary="已记录 28 元咖啡消费。",
            records=[
                CaptureRecordCommand(
                    kind="asset",
                    skill_machine_name="expense",
                    payload={
                        "amount": 28,
                        "currency": "CNY",
                        "category": "餐饮",
                    },
                    effective_at="2026-08-02T09:00:00+08:00",
                )
            ],
        )


def _auth_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _sync_payload() -> dict:
    return {
        "client_task_id": "e2e-short-001",
        "source": "realtime",
        "card_sn": "E2E-SN-001",
        "device_file_name": "F001.opus",
        "capture_started_at": "2026-08-02T00:00:00Z",
        "capture_ended_at": "2026-08-02T00:00:08Z",
        "device_crc": 1234,
        "device_size_bytes": 4096,
        "local_audio_sha256": "a" * 64,
        "local_audio_size_bytes": 2048,
        "audio_format": "opus",
        "asr_mode": "sync_client",
        "asr_provider": "tencent_asr_sync_client",
        "asr_status": "completed",
        "asr_text": "明天下午三点项目会",
        "asr_segments": [],
        "raw_response": {"code": 0},
        "speaker_diarization": False,
    }


def _s3_payload() -> dict:
    return {
        "client_task_id": "e2e-large-001",
        "source": "offline",
        "card_sn": "E2E-SN-001",
        "device_file_name": "F002.opus",
        "capture_started_at": "2026-08-02T00:00:00Z",
        "capture_ended_at": "2026-08-02T00:05:00Z",
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
            "uploaded_at": "2026-08-02T00:05:02Z",
        },
        "engine_type": "16k_zh",
        "speaker_diarization": False,
        "hotword_list": "",
    }


async def test_complete_hardware_capture_workflow_uses_theme_v2_only(client):
    registered = await client.post(
        "/api/auth/register",
        json={"email": "hardware-e2e@example.com", "password": "secret1"},
    )
    assert registered.status_code == 200
    token = registered.json()["token"]
    user_id = registered.json()["user"]["id"]
    headers = _auth_headers(token)

    bound = await client.post(
        "/api/cards/bindings",
        headers=headers,
        json={
            "card_sn": "E2E-SN-001",
            "card_device_uuid": "device-e2e",
            "card_app_uuid": "app-e2e",
            "card_mac": "AA:BB:CC:DD:EE:FF",
            "card_mac_from": "android",
            "card_name": "W2",
            "card_nick": "UReka 录音卡",
        },
    )
    assert bound.status_code == 200

    short_capture = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=headers,
        json=_sync_payload(),
    )
    large_capture = await client.post(
        "/api/flash/tencent-asr-s3-uploads",
        headers=headers,
        json=_s3_payload(),
    )
    assert short_capture.status_code == 200
    assert short_capture.json()["pipeline_status"] == "asr_done"
    assert large_capture.status_code == 200
    assert large_capture.json()["pipeline_status"] == "asr_processing"

    asr_provider = FakeTencentAsrProvider()
    agent_provider = FakeCaptureAgentProvider()
    registry = JobHandlerRegistry()
    registry.register(
        "capture_asr",
        capture_asr_handler(
            asr_provider,
            poll_interval_seconds=0.01,
            poll_timeout_seconds=60,
        ),
    )
    registry.register("capture_process", capture_process_handler(agent_provider))

    handled_jobs = 0
    while await run_worker_once(
        registry,
        owner="hardware-e2e-worker",
        lease_seconds=60,
    ):
        handled_jobs += 1
    assert handled_jobs == 3
    assert len(asr_provider.created) == 1
    assert asr_provider.polled == ["tencent-e2e"]
    assert set(agent_provider.transcripts) == {
        "明天下午三点项目会",
        "咖啡二十八元",
    }

    recording_ids = {
        short_capture.json()["recording_id"],
        large_capture.json()["recording_id"],
    }
    for recording_id in recording_ids:
        status = await client.get(
            f"/api/flash/recordings/{recording_id}",
            headers=headers,
        )
        assert status.status_code == 200
        assert status.json()["recording"]["process_status"] == "done"

    skills = await client.get("/api/user-skills", headers=headers)
    assets = await client.get("/api/assets", headers=headers)
    events = await client.get("/api/events", headers=headers)
    notifications = await client.get("/api/notifications", headers=headers)
    assert {skill["machine_name"] for skill in skills.json()} >= {
        "todo",
        "expense",
        "contact",
        "idea",
        "notes",
        "misc",
    }
    assert [asset["payload"]["amount"] for asset in assets.json()] == [28]
    assert [event["title"] for event in events.json()] == ["项目会"]
    assert [item["type"] for item in notifications.json()["notifications"]] == [
        "flash_done",
        "flash_done",
    ]

    subscriber_registry = SubscriberRegistry()
    queue = subscriber_registry.subscribe(user_id)
    while await dispatch_one(
        AsyncSessionFactory,
        subscriber_registry,
        now=utc_now(),
    ):
        pass
    frames = []
    while not queue.empty():
        frames.append(queue.get_nowait())
    done_recording_ids = {
        frame.payload["recording_id"]
        for frame in frames
        if frame.event == "flash_file_status"
        and frame.payload.get("status") == "done"
    }
    assert done_recording_ids == recording_ids
    assert sum(frame.event == "notification" for frame in frames) == 2
