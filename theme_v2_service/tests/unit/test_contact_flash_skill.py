from app.domains.capture.agent import CaptureRecordCommand
from app.domains.capture.contact_skill import execute_contact_command
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


async def test_zero_exact_alex_creates_one_first_class_contact():
    runtime = _Runtime(
        [
            {"ok": True, "contacts": [], "exact_contacts": []},
            {
                "ok": True,
                "contact_action": "created",
                "contact_id": "alex-1",
                "name": "Alex",
                "company": "Acme",
                "title": None,
            },
        ]
    )

    result = await execute_contact_command(
        CaptureRecordCommand(
            kind="contact",
            operation="create_or_update",
            name="Alex",
            contact_patch={"company": "Acme"},
            source_text="添加 Alex，他在 Acme 工作",
        ),
        _executor(runtime),
    )

    assert result.status == "success"
    assert result.contact_id == "alex-1"
    assert [call[0] for call in runtime.calls] == [
        "tool_query_contact",
        "tool_create_contact",
    ]


async def test_one_exact_alex_updates_the_existing_contact():
    runtime = _Runtime(
        [
            {
                "ok": True,
                "contacts": [{"contact_id": "alex-1", "name": "Alex"}],
                "exact_contacts": [
                    {"contact_id": "alex-1", "name": "Alex"}
                ],
            },
            {
                "ok": True,
                "contact_action": "updated",
                "contact_id": "alex-1",
                "name": "Alex",
                "title": "设计师",
            },
        ]
    )

    result = await execute_contact_command(
        CaptureRecordCommand(
            kind="contact",
            operation="create_or_update",
            name="Alex",
            contact_patch={"title": "设计师"},
            source_text="Alex 的职业改成设计师",
        ),
        _executor(runtime),
    )

    assert result.status == "success"
    assert result.contact_action == "updated"
    assert [call[0] for call in runtime.calls] == [
        "tool_query_contact",
        "tool_update_contact",
    ]
    assert runtime.calls[1][1] == {
        "contact_id": "alex-1",
        "field": "title",
        "value": "设计师",
    }


async def test_multiple_exact_alex_candidates_never_mutate():
    candidates = [
        {"contact_id": "alex-acme", "name": "Alex", "company": "Acme"},
        {"contact_id": "alex-byte", "name": "Alex", "company": "字节"},
    ]
    runtime = _Runtime(
        [{"ok": True, "contacts": candidates, "exact_contacts": candidates}]
    )

    result = await execute_contact_command(
        CaptureRecordCommand(
            kind="contact",
            operation="create_or_update",
            name="Alex",
            contact_patch={"title": "设计师"},
            source_text="Alex 的职业改成设计师",
        ),
        _executor(runtime),
    )

    assert result.status == "pending_confirmation"
    assert result.candidates == candidates
    assert [call[0] for call in runtime.calls] == ["tool_query_contact"]
