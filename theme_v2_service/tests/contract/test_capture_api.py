import asyncio
from types import SimpleNamespace

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import OutboxEvent
from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.execution import FlashExecutionItem, FlashExecutionResult
from app.domains.capture.jobs import capture_process_handler
from app.domains.capture.models import CaptureRecording, FlashChatMessage
from app.domains.sessions.chat import SessionChatResult, get_session_chat_provider
from app.domains.sessions.models import InputTurn, SessionMessage
from app.domains.sessions.tools import SessionToolExecutor
from app.internal_mcp.runtime import InternalMCPTrustedContext
from app.internal_mcp.tools import EurekaToolContext, execute_tool
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
    physical_session_id = first.json()["physical_session_id"]
    assert physical_session_id
    assert first.json()["input_turn_id"]
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
    assert (
        recording.json()["recording"]["physical_session_id"]
        == physical_session_id
    )
    sessions = await client.get("/api/sessions", headers=_headers(token))
    physical = next(
        item
        for item in sessions.json()["sessions"]
        if item["id"] == physical_session_id
    )
    assert physical["session_type"] == "flash"
    assert physical["session_date"] == "2026-08-02"
    assert physical["revision"] == 1

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
                ).order_by(OutboxEvent.created_at, OutboxEvent.id)
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
    assert [event.payload_json["display_phase"] for event in events] == [
        "receiving",
        "understanding",
    ]
    assert all(
        event.payload_json["source"] == "card" for event in events
    )
    assert all(
        event.payload_json["client_task_id"] == "task-001"
        for event in events
    )
    assert all(
        event.payload_json["recording_id"] == first.json()["recording_id"]
        for event in events
    )
    assert events[-1].payload_json["session_id"] == physical_session_id
    assert events[-1].payload_json["input_turn_id"] == first.json()["input_turn_id"]


async def test_flash_sessions_group_recordings_by_local_capture_day(client):
    token = await _registered_bound_card(
        client,
        "daily-capture@example.com",
        "SN-001",
    )
    capture_times = [
        "2026-08-02T01:00:00Z",
        "2026-08-02T10:00:00Z",
        "2026-08-03T01:00:00Z",
    ]
    recording_ids = []
    for index, capture_started_at in enumerate(capture_times, start=1):
        payload = {
            **_sync_payload(),
            "client_task_id": f"daily-task-{index}",
            "device_file_name": f"F00{index}.opus",
            "device_crc": 2000 + index,
            "capture_started_at": capture_started_at,
            "capture_ended_at": capture_started_at,
            "local_audio_sha256": f"{index}" * 64,
            "asr_text": f"第 {index} 条闪念",
        }
        response = await client.post(
            "/api/flash/tencent-asr-sync-results",
            headers=_headers(token),
            json=payload,
        )
        assert response.status_code == 200
        recording_ids.append(response.json()["recording_id"])

    history = await client.get("/api/flash/sessions", headers=_headers(token))

    assert history.status_code == 200
    assert [item["id"] for item in history.json()["sessions"]] == [
        "2026-08-03",
        "2026-08-02",
    ]
    assert history.json()["sessions"][1]["title"] == "8月2日 闪念"
    assert history.json()["sessions"][1]["recording_count"] == 2
    assert history.json()["sessions"][1]["physical_session_id"]
    assert history.json()["sessions"][1]["created_at"].endswith("Z")
    assert history.json()["sessions"][1]["updated_at"].endswith("Z")

    detail = await client.get(
        "/api/flash/sessions/2026-08-02",
        headers=_headers(token),
    )
    assert detail.status_code == 200
    assert detail.json()["session"]["id"] == "2026-08-02"
    assert (
        detail.json()["session"]["physical_session_id"]
        == history.json()["sessions"][1]["physical_session_id"]
    )
    assert [item["id"] for item in detail.json()["session"]["recordings"]] == [
        recording_ids[0],
        recording_ids[1],
    ]
    assert detail.json()["session"]["created_at"].endswith("Z")
    assert detail.json()["session"]["updated_at"].endswith("Z")
    assert all(
        item["created_at"].endswith("Z")
        for item in detail.json()["session"]["recordings"]
    )

    archive = await client.get(
        "/api/flash/recordings",
        headers=_headers(token),
    )
    assert archive.status_code == 200
    archived_by_id = {
        item["id"]: item for item in archive.json()["recordings"]
    }
    assert archived_by_id[recording_ids[0]]["session_date"] == "2026-08-02"
    assert archived_by_id[recording_ids[2]]["session_date"] == "2026-08-03"
    assert archived_by_id[recording_ids[0]]["captured_at"] == (
        "2026-08-02T01:00:00Z"
    )
    assert archived_by_id[recording_ids[0]]["created_at"].endswith("Z")

    deleted = await client.delete(
        "/api/flash/sessions/2026-08-02",
        headers=_headers(token),
    )
    assert deleted.status_code == 200
    assert deleted.json()["deleted_recording_count"] == 2
    missing = await client.get(
        "/api/flash/sessions/2026-08-02",
        headers=_headers(token),
    )
    assert missing.status_code == 404


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
    assert first.json()["physical_session_id"] is None
    assert first.json()["input_turn_id"] is None
    history = await client.get("/api/flash/sessions", headers=_headers(token))
    assert history.json() == {"sessions": []}

    jobs = await _jobs()
    assert [(job.job_type, job.run_id) for job in jobs] == [
        ("capture_asr", first.json()["recording_id"])
    ]
    assert jobs[0].input_dedupe_key == f"capture-asr:{first.json()['recording_id']}"

    async with AsyncSessionFactory() as database_session:
        events = list(
            await database_session.scalars(
                select(OutboxEvent)
                .where(OutboxEvent.aggregate_id == first.json()["recording_id"])
                .order_by(OutboxEvent.created_at, OutboxEvent.id)
            )
        )
    assert [event.payload_json["display_phase"] for event in events] == [
        "receiving",
        "transcribing",
    ]

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
        (
            "POST",
            "/api/flash/sessions/2026-08-03/chat",
            {"user_text": "今天有什么待办？"},
        ),
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
    def __init__(self, *, summary: str):
        self.summary = summary
        self.calls = []

    async def execute(self, *, context, tool_runtime=None):
        self.calls.append(context)
        outcome = await SessionToolExecutor(
            user_id=context.user_id,
            session_id=context.session_id,
            input_turn_id=context.input_turn_id,
            runtime=tool_runtime,
        ).execute(
            "tool_create_note",
            {
                "title": "客户标签系统",
                "content": "可以做一个客户标签系统",
            },
            tool_call_id=f"capture:{context.recording_id}:0:notes:contract",
        )
        return FlashExecutionResult(
            summary=self.summary,
            items=(
                FlashExecutionItem(
                    intent=FlashIntent(
                        type="notes",
                        source_text=context.transcript,
                        domain="灵感",
                    ),
                    status="success",
                    result=outcome.response,
                ),
            ),
        )


class _InProcessToolRuntime:
    async def call_tool(
        self,
        name: str,
        arguments: dict,
        *,
        trusted: InternalMCPTrustedContext,
    ) -> dict:
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
                capture_process_handler(
                    provider,
                    tool_runtime=_InProcessToolRuntime(),
                ),
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
        summary="已记录产品想法。",
    )

    request = asyncio.create_task(
        client.post(
            "/api/flash",
            headers=_headers(token),
            json={
                "text": "可以做一个客户标签系统",
                "source": "voice",
                "client_task_id": "ring-local-task-001",
            },
        )
    )
    await _run_capture_process_when_queued(provider)
    response = await request

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["session_id"]
    assert body["recording_id"] == body["session_id"]
    assert body["input_turn_id"]
    assert body["reply"] == ""
    assert body["summary"] == "已记录产品想法。"
    assert body["has_pending"] is False
    assert body["cards"][0]["entity_kind"] == "asset"
    assert body["cards"][0]["skill_machine_name"] == "notes"
    assert body["cards"][0]["entity_id"]
    assert body["cards"][0]["source"] == {
        "session_id": body["physical_session_id"],
        "input_turn_id": body["input_turn_id"],
        "kind": "capture",
    }
    assert body["derived_assets"] == body["cards"]
    assert len(provider.calls) == 1

    async with AsyncSessionFactory() as database_session:
        events = list(
            await database_session.scalars(
                select(OutboxEvent)
                .where(OutboxEvent.aggregate_id == body["recording_id"])
                .order_by(OutboxEvent.created_at, OutboxEvent.id)
            )
        )
    assert [event.payload_json["display_phase"] for event in events] == [
        "receiving",
        "understanding",
        "understanding",
        "organizing",
        "done",
    ]
    assert all(
        event.payload_json["client_task_id"] == "ring-local-task-001"
        for event in events
    )
    assert events[-1].payload_json["result_count"] == 1

    derived = await client.get(
        f"/api/assets/{body['cards'][0]['entity_id']}",
        headers=_headers(token),
    )
    assert derived.status_code == 200
    assert derived.json()["source_recording_id"] == body["session_id"]
    assert derived.json()["source_input_turn_id"] == body["input_turn_id"]

    status = await client.get(
        f"/api/flash/recordings/{body['session_id']}",
        headers=_headers(token),
    )
    assert status.status_code == 200
    assert status.json()["recording"]["process_status"] == "done"
    assert status.json()["recording"]["input_turn_id"] == body["input_turn_id"]


async def test_daily_flash_session_chat_answers_and_persists(client):
    token = await _registered_bound_card(
        client,
        "daily-chat@example.com",
        "SN-001",
    )
    payload = {
        **_sync_payload(),
        "capture_started_at": "2026-08-03T01:00:00Z",
        "capture_ended_at": "2026-08-03T01:00:08Z",
        "asr_text": "今天要提交评审稿",
    }
    capture = await client.post(
        "/api/flash/tencent-asr-sync-results",
        headers=_headers(token),
        json=payload,
    )
    assert capture.status_code == 200

    physical_session_id = capture.json()["physical_session_id"]
    assert physical_session_id

    class FakeSessionChatProvider:
        def __init__(self):
            self.calls = []

        async def answer(self, **command):
            self.calls.append(command)
            return SessionChatResult(text="今天有一项待办：提交评审稿。")

    provider = FakeSessionChatProvider()
    app.dependency_overrides[get_session_chat_provider] = lambda: provider
    try:
        response = await client.post(
            "/api/flash/sessions/2026-08-03/chat",
            headers=_headers(token),
            json={"user_text": "今天有什么待办？"},
        )
    finally:
        app.dependency_overrides.pop(get_session_chat_provider, None)

    assert response.status_code == 200
    assert response.json()["session_id"] == physical_session_id
    assert response.json()["reply"] == "今天有一项待办：提交评审稿。"
    assert response.json()["input_turn_id"]
    assert response.json()["message_id"]
    assert provider.calls[0]["question"] == "今天有什么待办？"
    assert provider.calls[0]["context"].session_id == physical_session_id
    assert provider.calls[0]["context"].session_type == "flash"
    assert "今天要提交评审稿" in provider.calls[0]["context"].records_json

    async with AsyncSessionFactory() as database:
        typed_turn = await database.scalar(
            select(InputTurn)
            .where(InputTurn.session_id == physical_session_id)
            .order_by(InputTurn.created_at.desc())
        )
        capture_count = await database.scalar(
            select(func.count()).select_from(CaptureRecording)
        )
        legacy_chat_count = await database.scalar(
            select(func.count()).select_from(FlashChatMessage)
        )
        persisted_agent = await database.get(
            SessionMessage, response.json()["message_id"]
        )
    assert typed_turn is not None
    assert typed_turn.source == "typed"
    assert typed_turn.session_id == physical_session_id
    assert capture_count == 1
    assert legacy_chat_count == 0
    assert persisted_agent is not None
    assert persisted_agent.text == response.json()["reply"]

    daily = await client.get(
        "/api/flash/sessions/2026-08-03",
        headers=_headers(token),
    )
    assert daily.status_code == 200
    messages = daily.json()["session"]["chat_messages"]
    assert [(message["role"], message["text"]) for message in messages] == [
        ("user", "今天有什么待办？"),
        ("agent", "今天有一项待办：提交评审稿。"),
    ]


async def test_daily_flash_session_chat_rejects_missing_session(client):
    token = await _register(client, "missing-daily-chat@example.com")

    response = await client.post(
        "/api/flash/sessions/2026-08-03/chat",
        headers=_headers(token),
        json={"user_text": "今天有什么待办？"},
    )

    assert response.status_code == 404


async def test_capture_recording_archive_can_be_listed_and_deleted(client, monkeypatch):
    token = await _register(client, "archive@example.com")
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
        json={"text": "需要归档的闪念", "source": "typed"},
    )
    recording_id = created.json()["session_id"]

    listed = await client.get(
        "/api/flash/recordings",
        headers=_headers(token),
    )
    assert listed.status_code == 200
    assert listed.json()["recordings"][0]["id"] == recording_id
    assert listed.json()["recordings"][0]["title"]

    deleted = await client.delete(
        f"/api/flash/recordings/{recording_id}",
        headers=_headers(token),
    )
    assert deleted.status_code == 200
    assert deleted.json() == {"ok": True}
    assert (
        await client.get(
            f"/api/flash/recordings/{recording_id}",
            headers=_headers(token),
        )
    ).status_code == 404


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
