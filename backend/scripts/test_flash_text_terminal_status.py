"""
Regression test for inline /api/flash terminal status events.

Run:
    cd backend && python -m scripts.test_flash_text_terminal_status
"""
import asyncio
import uuid
from types import SimpleNamespace

import core.flash_service as flash_service
from db.database import async_engine


def check(name: str, cond: bool) -> bool:
    print(f"  {'✓' if cond else '✗'} {name}")
    return cond


class _FakeSessionCtx:
    async def __aenter__(self):
        return object()

    async def __aexit__(self, exc_type, exc, tb):
        return False


async def _run_case(*, pipeline_result=None, pipeline_error=None, hardware=False):
    events = []
    session_id = uuid.uuid4()
    turn_id = uuid.uuid4()

    originals = {
        "AsyncSessionLocal": flash_service.AsyncSessionLocal,
        "get_or_create_capture_session_today": flash_service.get_or_create_capture_session_today,
        "create_input_turn_for_message": flash_service.create_input_turn_for_message,
        "persist_user_message": flash_service.persist_user_message,
        "persist_agent_message": flash_service.persist_agent_message,
        "run_flash_pipeline": flash_service.run_flash_pipeline,
        "create_notification": flash_service.create_notification,
        "publish_event": flash_service.publish_event,
    }

    async def fake_get_or_create(*args, **kwargs):
        return SimpleNamespace(id=session_id)

    async def fake_create_input_turn(*args, **kwargs):
        return SimpleNamespace(id=turn_id)

    async def fake_noop(*args, **kwargs):
        return None

    async def fake_run_pipeline(*args, **kwargs):
        if pipeline_error is not None:
            raise pipeline_error
        return pipeline_result or {
            "ok": True,
            "reply": "已记录",
            "summary": "",
            "cards": [{"card_type": "todo", "asset_id": "asset-1"}],
            "derived_assets": [{"id": "asset-1"}],
        }

    def fake_publish_event(user_id, event_name, **payload):
        events.append((event_name, payload))

    flash_service.AsyncSessionLocal = lambda: _FakeSessionCtx()
    flash_service.get_or_create_capture_session_today = fake_get_or_create
    flash_service.create_input_turn_for_message = fake_create_input_turn
    flash_service.persist_user_message = fake_noop
    flash_service.persist_agent_message = fake_noop
    flash_service.run_flash_pipeline = fake_run_pipeline
    flash_service.create_notification = fake_noop
    flash_service.publish_event = fake_publish_event

    try:
        result = await flash_service.process_flash_text(
            user_id="user-1",
            text="明天上午10点提醒我提交报告",
            source="typed",
            recording_id="rec-1" if hardware else None,
            client_task_id="task-1" if hardware else None,
            device_file_name="F20260614-100000.opus" if hardware else None,
        )
        return result, events
    finally:
        for name, value in originals.items():
            setattr(flash_service, name, value)


def _status_sequence(events):
    return [
        payload.get("status")
        for event_name, payload in events
        if event_name == "flash_file_status"
    ]


async def main() -> int:
    ok = True

    print("[inline flash success]")
    result, events = await _run_case()
    ok &= check("result ok", result.get("ok") is True)
    ok &= check(
        "capture -> processing_flash -> done",
        [events[0][0], *_status_sequence(events)]
        == ["capture", "processing_flash", "done"],
    )
    ok &= check(
        "terminal event includes session/input_turn",
        bool(events[-1][1].get("session_id"))
        and bool(events[-1][1].get("input_turn_id")),
    )

    print("[inline flash pipeline exception]")
    result, events = await _run_case(pipeline_error=RuntimeError("boom"))
    ok &= check("result failed", result.get("ok") is False)
    ok &= check(
        "processing_flash -> failed",
        _status_sequence(events) == ["processing_flash", "failed"],
    )

    print("[hardware path remains queue-owned]")
    result, events = await _run_case(hardware=True)
    ok &= check("hardware result ok", result.get("ok") is True)
    ok &= check(
        "no inline terminal status for hardware",
        _status_sequence(events) == ["processing_flash"],
    )

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    async def _entrypoint() -> int:
        try:
            return await main()
        finally:
            await async_engine.dispose()

    raise SystemExit(asyncio.run(_entrypoint()))
