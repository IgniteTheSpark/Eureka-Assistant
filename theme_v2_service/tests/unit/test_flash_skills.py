import json

from app.domains.capture.agent import CaptureRecordCommand
from app.domains.capture.skills import execute_capture_command
from app.domains.sessions.tools import SessionToolExecutor


class _Runtime:
    def __init__(self, results):
        self.results = list(results)
        self.calls = []

    async def call_tool(self, name, arguments, *, trusted):
        self.calls.append((name, arguments, trusted))
        return self.results.pop(0)


def _executor(runtime):
    return SessionToolExecutor(
        user_id="owner",
        session_id="session-1",
        input_turn_id="turn-1",
        runtime=runtime,
    )


async def test_todo_and_notes_use_typed_create_tools_with_provenance():
    runtime = _Runtime(
        [
            {
                "ok": True,
                "asset_id": "todo-1",
                "user_skill_name": "todo",
                "payload": {"title": "交方案", "status": "pending"},
            },
            {
                "ok": True,
                "asset_id": "note-1",
                "user_skill_name": "notes",
                "payload": {"content": "客户更关注交付节奏"},
            },
        ]
    )
    executor = _executor(runtime)

    todo = await execute_capture_command(
        CaptureRecordCommand(
            kind="asset",
            skill_machine_name="todo",
            payload={"title": "交方案", "due_date": "2026-08-07T18:00:00+08:00"},
            source_text="明天下午六点前交方案",
        ),
        executor,
        tool_call_prefix="flash-0",
    )
    note = await execute_capture_command(
        CaptureRecordCommand(
            kind="asset",
            skill_machine_name="notes",
            payload={"content": "客户更关注交付节奏"},
            source_text="客户更关注交付节奏",
        ),
        executor,
        tool_call_prefix="flash-1",
    )

    assert todo.status == "success"
    assert note.status == "success"
    assert [call[0] for call in runtime.calls] == [
        "tool_create_todo",
        "tool_create_note",
    ]
    assert all(call[2].user_id == "owner" for call in runtime.calls)
    assert all(call[2].session_id == "session-1" for call in runtime.calls)
    assert all(call[2].input_turn_id == "turn-1" for call in runtime.calls)


async def test_expense_update_queries_then_updates_exactly_one_asset():
    runtime = _Runtime(
        [
            {
                "ok": True,
                "assets": [
                    {
                        "asset_id": "expense-1",
                        "user_skill_name": "expense",
                        "payload": {"amount": 28, "category": "餐饮"},
                    }
                ],
            },
            {
                "ok": True,
                "asset_id": "expense-1",
                "user_skill_name": "expense",
                "payload": {"amount": 38, "category": "餐饮"},
            },
        ]
    )

    result = await execute_capture_command(
        CaptureRecordCommand(
            kind="asset",
            operation="update",
            skill_machine_name="expense",
            match_text="咖啡",
            payload={"amount": 38},
            source_text="刚才咖啡不是二十八，是三十八",
        ),
        _executor(runtime),
        tool_call_prefix="flash-0",
    )

    assert result.status == "success"
    assert result.operation == "update"
    assert [call[0] for call in runtime.calls] == [
        "tool_query_asset",
        "tool_update_asset",
    ]
    assert runtime.calls[0][1] == {
        "user_skill_name": "expense",
        "contains": "咖啡",
        "limit": 20,
    }
    assert runtime.calls[1][1]["asset_id"] == "expense-1"
    assert json.loads(runtime.calls[1][1]["payload_patch"]) == {"amount": 38}


async def test_ambiguous_asset_update_never_mutates():
    runtime = _Runtime(
        [
            {
                "ok": True,
                "assets": [
                    {"asset_id": "expense-1", "payload": {"amount": 28}},
                    {"asset_id": "expense-2", "payload": {"amount": 28}},
                ],
            }
        ]
    )

    result = await execute_capture_command(
        CaptureRecordCommand(
            kind="asset",
            operation="delete",
            skill_machine_name="expense",
            match_text="咖啡",
            source_text="删除咖啡那笔",
        ),
        _executor(runtime),
    )

    assert result.status == "error"
    assert "多个" in result.error
    assert [call[0] for call in runtime.calls] == ["tool_query_asset"]


async def test_event_create_uses_first_class_event_and_resolves_attendee():
    runtime = _Runtime(
        [
            {
                "ok": True,
                "event_id": "event-1",
                "title": "项目会",
                "start_at": "2026-08-07T15:00:00+08:00",
                "end_at": "2026-08-07T16:00:00+08:00",
                "attendees": [],
            },
            {
                "ok": True,
                "contacts": [{"contact_id": "feng-1", "name": "冯总"}],
                "exact_contacts": [{"contact_id": "feng-1", "name": "冯总"}],
            },
            {
                "ok": True,
                "event_id": "event-1",
                "attendee_id": "attendee-1",
                "attendee": {
                    "contact_id": "feng-1",
                    "display_name": "冯总",
                },
            },
            {
                "ok": True,
                "event_id": "event-1",
                "title": "项目会",
                "start_at": "2026-08-07T15:00:00+08:00",
                "end_at": "2026-08-07T16:00:00+08:00",
                "attendees": [
                    {"contact_id": "feng-1", "display_name": "冯总"}
                ],
            },
        ]
    )

    result = await execute_capture_command(
        CaptureRecordCommand(
            kind="event",
            title="项目会",
            start_at="2026-08-07T15:00:00+08:00",
            end_at="2026-08-07T16:00:00+08:00",
            attendees=["冯总"],
            source_text="明天下午三点到四点和冯总开项目会",
        ),
        _executor(runtime),
        tool_call_prefix="flash-event",
    )

    assert result.status == "success"
    assert result.entity_id == "event-1"
    assert [call[0] for call in runtime.calls] == [
        "tool_create_event",
        "tool_query_contact",
        "tool_add_event_attendee",
        "tool_get_event",
    ]
    assert runtime.calls[2][1]["contact_id"] == "feng-1"


async def test_custom_skill_create_uses_generic_asset_tool():
    runtime = _Runtime(
        [
            {
                "ok": True,
                "asset_id": "run-1",
                "user_skill_name": "running_training_log",
                "payload": {"distance": 2},
            }
        ]
    )

    result = await execute_capture_command(
        CaptureRecordCommand(
            kind="asset",
            skill_machine_name="running_training_log",
            payload={"distance": 2},
            source_text="跑了两公里",
        ),
        _executor(runtime),
    )

    assert result.status == "success"
    assert runtime.calls[0][0] == "tool_create_asset"
    assert runtime.calls[0][1]["user_skill_name"] == "running_training_log"
