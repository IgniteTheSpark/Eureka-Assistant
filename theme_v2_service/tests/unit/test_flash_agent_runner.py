import asyncio
from types import SimpleNamespace

import pytest

from app.domains.capture.agent_runner import (
    FlashAgentDefinition,
    RetryableAgentRunError,
    run_agent_once,
    stable_capture_tool_call_id,
)
from app.internal_mcp.runtime import InternalMCPUnavailable


def _response(*, content="", tool_calls=(), tokens=0):
    return {
        "choices": [
            {
                "message": {
                    "content": content,
                    "tool_calls": list(tool_calls),
                }
            }
        ],
        "usage": {"total_tokens": tokens},
    }


def _tool_call(call_id, name, arguments):
    return {
        "id": call_id,
        "type": "function",
        "function": {"name": name, "arguments": arguments},
    }


class _FakeExecutor:
    def __init__(self, *, error=None):
        self.error = error
        self.definition_calls = 0
        self.calls = []

    async def definitions(self):
        self.definition_calls += 1
        return [
            {
                "type": "function",
                "function": {
                    "name": name,
                    "description": name,
                    "parameters": {"type": "object", "properties": {}},
                },
            }
            for name in (
                "tool_create_asset",
                "tool_create_contact",
                "tool_query_asset",
            )
        ]

    async def execute(self, name, arguments, *, tool_call_id=None):
        await asyncio.sleep(0)
        if self.error is not None:
            raise self.error
        self.calls.append((name, arguments, tool_call_id))
        identifier = "asset-1" if name == "tool_create_asset" else "contact-1"
        key = "asset_id" if name == "tool_create_asset" else "contact_id"
        return SimpleNamespace(response={"ok": True, key: identifier}, cards=[])


def test_stable_call_id_uses_canonical_model_arguments_only():
    clean = stable_capture_tool_call_id(
        recording_id="rec-1",
        intent_ordinal=2,
        tool_name="tool_create_asset",
        arguments={"payload": {"amount": 8, "currency": "CNY"}},
    )
    reordered_and_polluted = stable_capture_tool_call_id(
        recording_id="rec-1",
        intent_ordinal=2,
        tool_name="tool_create_asset",
        arguments={
            "tool_call_id": "model-key",
            "user_id": "attacker",
            "payload": {"currency": "CNY", "amount": 8},
            "session_id": "wrong",
            "source_input_turn_id": "wrong-turn",
        },
    )

    assert clean == reordered_and_polluted
    assert clean.startswith("capture:rec-1:2:tool_create_asset:")


async def test_runner_keeps_parallel_tool_results_and_trusted_ids_in_order():
    responses = iter(
        [
            _response(
                tool_calls=[
                    _tool_call(
                        "model-call-a",
                        "tool_create_asset",
                        '{"payload":{"amount":8},"user_id":"attacker"}',
                    ),
                    _tool_call(
                        "model-call-b",
                        "tool_query_asset",
                        '{"contains":"Alex","session_id":"wrong"}',
                    ),
                ],
                tokens=11,
            ),
            _response(content="已记录", tokens=7),
        ]
    )

    async def completion(**_):
        return next(responses)

    executor = _FakeExecutor()
    result = await run_agent_once(
        FlashAgentDefinition(
            name="asset",
            instruction="Create the requested records.",
            allowed_tools=frozenset(
                {"tool_create_asset", "tool_query_asset"}
            ),
        ),
        "input",
        executor,
        completion=completion,
        model="test-model",
        api_key=None,
        timeout_seconds=10,
        recording_id="rec-1",
        intent_ordinal=2,
    )

    assert result.text == "已记录"
    assert result.usage_tokens == 18
    assert [event["name"] for event in result.tool_events] == [
        "tool_create_asset",
        "tool_query_asset",
    ]
    assert "user_id" not in executor.calls[0][1]
    assert "session_id" not in executor.calls[1][1]
    assert executor.calls[0][2].startswith(
        "capture:rec-1:2:tool_create_asset:"
    )
    assert executor.calls[1][2].startswith(
        "capture:rec-1:2:tool_query_asset:"
    )
    assert result.tool_events[1]["response"]["contact_id"] == "contact-1"
    assert [event["effect"] for event in result.tool_events] == [
        "create",
        "query",
    ]


async def test_runner_executes_only_one_root_mutation_for_one_intent_round():
    responses = iter(
        [
            _response(
                tool_calls=[
                    _tool_call(
                        "model-call-a",
                        "tool_create_asset",
                        '{"payload":{"amount":8}}',
                    ),
                    _tool_call(
                        "model-call-b",
                        "tool_create_asset",
                        '{"payload":{"amount":20}}',
                    ),
                ]
            ),
            _response(content="已记录"),
        ]
    )

    async def completion(**_):
        return next(responses)

    executor = _FakeExecutor()
    result = await run_agent_once(
        FlashAgentDefinition(
            name="expense",
            instruction="Create one atomic expense.",
            allowed_tools=frozenset({"tool_create_asset"}),
        ),
        "input",
        executor,
        completion=completion,
        model="test-model",
        api_key=None,
        timeout_seconds=10,
        recording_id="rec-1",
        intent_ordinal=0,
    )

    assert len(executor.calls) == 1
    assert result.tool_events[0]["response"]["ok"] is True
    assert result.tool_events[1]["response"] == {
        "ok": False,
        "error": "one root mutation is allowed per atomic intent",
    }


async def test_runner_exposes_only_agent_allowed_tools():
    observed = {}

    async def completion(**kwargs):
        observed.update(kwargs)
        return _response(content="没有执行工具")

    await run_agent_once(
        FlashAgentDefinition(
            name="query",
            instruction="Query assets.",
            allowed_tools=frozenset({"tool_query_asset"}),
        ),
        "input",
        _FakeExecutor(),
        completion=completion,
        model="test-model",
        api_key="secret",
        timeout_seconds=10,
        recording_id="rec-1",
        intent_ordinal=1,
    )

    assert [tool["function"]["name"] for tool in observed["tools"]] == [
        "tool_query_asset"
    ]
    assert observed["api_key"] == "secret"


async def test_runner_maps_provider_failure_to_retryable_error():
    async def completion(**_):
        raise TimeoutError("provider timeout with internal details")

    with pytest.raises(RetryableAgentRunError, match="provider unavailable"):
        await run_agent_once(
            FlashAgentDefinition(name="notes", instruction="Save a note."),
            "input",
            None,
            completion=completion,
            model="test-model",
            api_key=None,
            timeout_seconds=10,
            recording_id="rec-1",
            intent_ordinal=0,
        )


async def test_runner_maps_mcp_unavailability_to_retryable_error():
    responses = iter(
        [
            _response(
                tool_calls=[
                    _tool_call(
                        "model-call-a",
                        "tool_create_asset",
                        '{"payload":{"title":"memo"}}',
                    )
                ]
            )
        ]
    )

    async def completion(**_):
        return next(responses)

    with pytest.raises(RetryableAgentRunError, match="tool runtime unavailable"):
        await run_agent_once(
            FlashAgentDefinition(
                name="notes",
                instruction="Save a note.",
                allowed_tools=frozenset({"tool_create_asset"}),
            ),
            "input",
            _FakeExecutor(error=InternalMCPUnavailable("stdio exited")),
            completion=completion,
            model="test-model",
            api_key=None,
            timeout_seconds=10,
            recording_id="rec-1",
            intent_ordinal=0,
        )
