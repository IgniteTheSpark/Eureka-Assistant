from datetime import datetime

from sqlalchemy import func, select

from app.db.models import WorkflowJob
from app.domains.capture.models import CaptureFile, CaptureRecording
from app.domains.capture.service import materialize_final_capture
from app.domains.notifications.models import OutboxEvent
from app.domains.sessions.models import ChatSession, InputTurn, SessionMessage


CAPTURED_AT = datetime(2026, 8, 5, 7, 30, 0)


async def _recording(session) -> CaptureRecording:
    file = CaptureFile(
        user_id="user-1",
        storage_url="client-sync-asr:session-materialization",
        file_type="audio/opus",
        source_tag="flash",
        asr_status="completed",
    )
    session.add(file)
    await session.flush()
    recording = CaptureRecording(
        user_id="user-1",
        file_id=file.id,
        card_sn="RING-001",
        device_file_name="F100.opus",
        client_task_id="session-materialization",
        source="realtime",
        capture_started_at=CAPTURED_AT,
        audio_format="opus",
        asr_mode="sync_client",
        s3_key="client-sync-asr:session-materialization",
        s3_upload_headers_json={},
        tencent_speaker_diarization=0,
        tencent_status="finished",
        tencent_task_response_json={},
        upload_status="uploaded",
        process_status="asr_done",
        asr_provider="tencent_asr_sync_client",
        asr_text="刚刚我跑了两公里，在深圳湾人才公园。",
        asr_segments_json=[{"start_ms": 0, "text": "刚刚我跑了两公里"}],
        result_records_json=[],
    )
    session.add(recording)
    await session.flush()
    return recording


async def test_final_asr_materializes_one_physical_flash_session_idempotently(session):
    recording = await _recording(session)

    first = await materialize_final_capture(
        session,
        recording,
        timezone_name="Asia/Shanghai",
    )
    second = await materialize_final_capture(
        session,
        recording,
        timezone_name="Asia/Shanghai",
    )

    assert second.session.id == first.session.id
    assert second.input_turn.id == first.input_turn.id
    assert second.agent_message.id == first.agent_message.id
    assert first.session.session_type == "flash"
    assert first.session.session_date.isoformat() == "2026-08-05"
    assert first.session.revision == 1
    assert first.input_turn.turn_index == 0
    assert first.input_turn.source == "voice"
    assert first.input_turn.text == recording.asr_text
    assert first.input_turn.file_id == recording.file_id
    assert first.input_turn.recording_id == recording.id
    assert first.input_turn.asr_provider == recording.asr_provider
    assert first.input_turn.segments_json == recording.asr_segments_json
    assert first.input_turn.provenance_json["card_sn"] == "RING-001"
    assert first.user_message.input_turn_id == first.input_turn.id
    assert first.agent_message.input_turn_id == first.input_turn.id
    assert first.agent_message.status == "running"
    assert recording.session_id == first.session.id
    assert recording.input_turn_id == first.input_turn.id
    assert recording.agent_message_id == first.agent_message.id

    assert await session.scalar(select(func.count()).select_from(ChatSession)) == 1
    assert await session.scalar(select(func.count()).select_from(InputTurn)) == 1
    assert await session.scalar(select(func.count()).select_from(SessionMessage)) == 2
    assert await session.scalar(select(func.count()).select_from(WorkflowJob)) == 1
    event = await session.scalar(
        select(OutboxEvent).where(OutboxEvent.event_type == "session_changed")
    )
    assert event is not None
    assert event.aggregate_id == first.session.id
    assert event.payload_json == {
        "session_id": first.session.id,
        "session_date": "2026-08-05",
        "revision": 1,
        "reason": "capture_asr_final",
    }
