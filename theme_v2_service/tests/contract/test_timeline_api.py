from datetime import date, datetime

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.domains.capture.models import (
    CaptureFile,
    CaptureRecording,
    CaptureTurn,
    FlashChatMessage,
)
from tests.fakes.auth_helpers import register_user
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _register(client: AsyncClient, email: str) -> tuple[str, str]:
    body = await register_user(client, email, password="Secret123!")
    return body["token"], body["user"]["id"]

async def _seed_capture(
    session,
    *,
    user_id: str,
    index: int,
    captured_at: datetime,
) -> None:
    capture_file = CaptureFile(
        user_id=user_id,
        storage_url=f"capture-{index}.opus",
        file_type="audio/opus",
        source_tag="flash",
        asr_status="completed",
        created_at=captured_at,
        updated_at=captured_at,
    )
    session.add(capture_file)
    await session.flush()
    recording = CaptureRecording(
        user_id=user_id,
        file_id=capture_file.id,
        card_sn="RING-001",
        device_file_name=f"capture-{index}.opus",
        client_task_id=f"timeline-capture-{index}",
        source="realtime",
        audio_format="opus",
        asr_mode="sync_client",
        s3_key=f"client-sync:{index}",
        s3_upload_headers_json={},
        tencent_speaker_diarization=0,
        tencent_status="finished",
        tencent_task_response_json={},
        upload_status="uploaded",
        process_status="done",
        asr_provider="tencent_asr_sync_client",
        asr_text=f"硬件闪念 {index}",
        asr_segments_json=[],
        result_records_json=[],
        accepted_at=captured_at,
        created_at=captured_at,
        updated_at=captured_at,
    )
    session.add(recording)
    await session.flush()
    session.add(
        CaptureTurn(
            recording_id=recording.id,
            user_id=user_id,
            transcript=f"硬件闪念 {index}",
            source="realtime",
            provenance_json={"kind": "hardware_audio"},
            created_at=captured_at,
        )
    )


async def test_timeline_uses_semantic_asset_time_and_capture_only_flash_count(
    client,
    session,
):
    token, user_id = await _register(client, "timeline@example.com")
    skill_response = await client.post(
        "/api/user-skills",
        headers=_headers(token),
        json={
            "machine_name": "daily_water_intake",
            "display_name": "喝水记录",
            "schema": {
                "type": "object",
                "properties": {
                    "amount_ml": {"type": "number", "title": "饮水量"},
                    "date": {"type": "string", "format": "date"},
                    "note": {"type": "string"},
                },
                "required": ["amount_ml", "date"],
                "additionalProperties": False,
            },
            "render_spec": {
                "icon": "💧",
                "primary_field": "amount_ml",
                "timeline_anchor": "date",
            },
        },
    )
    assert skill_response.status_code == 200
    skill_id = skill_response.json()["id"]

    asset_commands = [
        ({"amount_ml": 200, "date": "2026-08-05"}, None, "2026-08-05T00:13:00+08:00"),
        ({"amount_ml": 300, "date": "2026-08-04", "note": "晚上8点"}, "晚上", "2026-08-04T20:00:00+08:00"),
        ({"amount_ml": 600, "date": "2026-08-04", "note": "下午"}, "下午", None),
        ({"amount_ml": 400, "date": "2026-08-04", "note": "早上"}, "上午", None),
    ]
    for payload, period, occurred_at in asset_commands:
        response = await client.post(
            "/api/assets",
            headers=_headers(token),
            json={
                "user_skill_id": skill_id,
                "payload": payload,
                "period": period,
                "occurred_at": occurred_at,
            },
        )
        assert response.status_code == 200

    contact_response = await client.post(
        "/api/contacts",
        headers=_headers(token),
        json={
            "name": "Alex",
            "company": "Acme",
            "title": "设计师",
        },
    )
    assert contact_response.status_code == 200
    contact_id = contact_response.json()["id"]

    for index, minute in enumerate((1, 2, 3), start=1):
        await _seed_capture(
            session,
            user_id=user_id,
            index=index,
            captured_at=datetime(2026, 8, 4, 16, minute),
        )
    session.add_all(
        [
            FlashChatMessage(
                user_id=user_id,
                session_date=date(2026, 8, 5),
                role="user",
                text="今天记录了什么？",
                status="done",
                created_at=datetime(2026, 8, 4, 16, 10),
            ),
            FlashChatMessage(
                user_id=user_id,
                session_date=date(2026, 8, 5),
                role="agent",
                text="记录了三条闪念。",
                status="done",
                created_at=datetime(2026, 8, 4, 16, 11),
            ),
        ]
    )
    await session.commit()

    response = await client.get("/api/timeline", headers=_headers(token))

    assert response.status_code == 200
    items = response.json()["items"]
    assets = [item for item in items if item["kind"] == "asset"]
    contacts = [item for item in items if item["kind"] == "contact"]
    captures = [item for item in items if item["kind"] == "input_turn"]
    assert len(assets) == 4
    assert contacts == [
        {
            "kind": "contact",
            "id": contact_id,
            "contact_id": contact_id,
            "effective_at": contact_response.json()["created_at"],
            "created_at": contact_response.json()["created_at"],
            "title": "Alex",
            "subtitle": "Acme · 设计师",
            "skill_name": "contact",
            "period": "",
            "has_clock_time": False,
            "has_scheduled_time": False,
            "domain": "社交",
            "payload": {
                "name": "Alex",
                "phone": None,
                "company": "Acme",
                "title": "设计师",
                "email": None,
                "notes": [],
                "socials": {},
            },
            "session_id": None,
            "source_recording_id": None,
            "source_input_turn_id": None,
        }
    ]
    assert len(captures) == 3
    assert all("daily_water_intake" not in item["title"] for item in assets)
    assert all("喝水记录" in item["title"] for item in assets)

    exact = next(item for item in assets if item["payload"]["amount_ml"] == 300)
    afternoon = next(item for item in assets if item["payload"]["amount_ml"] == 600)
    assert exact["effective_at"] == "2026-08-04T12:00:00Z"
    assert exact["has_clock_time"] is True
    assert afternoon["effective_at"] == "2026-08-03T16:00:00Z"
    assert afternoon["period"] == "下午"
    assert afternoon["has_clock_time"] is False

    assert all(item["effective_at"].endswith("Z") for item in captures)
    assert all(item["session_id"] == "2026-08-05" for item in captures)
