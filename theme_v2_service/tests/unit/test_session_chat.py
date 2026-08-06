from app.domains.sessions.chat import LiteLLMSessionChatProvider
from app.domains.sessions.legacy_assistant import LegacyChatContext
from app.domains.sessions.tools import ToolOutcome


class _Executor:
    def __init__(self):
        self.calls = []

    async def definitions(self):
        return [
            {
                "type": "function",
                "function": {
                    "name": "tool_query_asset",
                    "description": "Query assets",
                    "parameters": {"type": "object", "properties": {}},
                },
            },
            {
                "type": "function",
                "function": {
                    "name": "tool_update_asset",
                    "description": "Update asset",
                    "parameters": {"type": "object", "properties": {}},
                },
            },
        ]

    async def execute(self, name, arguments, *, tool_call_id=None):
        self.calls.append((name, arguments, tool_call_id))
        if name == "tool_query_asset":
            return ToolOutcome(
                response={
                    "ok": True,
                    "assets": [
                        {
                            "asset_id": "asset-1",
                            "user_skill_name": "running",
                            "payload": {"distance": 5},
                        }
                    ],
                },
                cards=[
                    {
                        "asset_id": "asset-1",
                        "user_skill_name": "running",
                        "payload": {"distance": 5},
                    }
                ],
            )
        assert name == "tool_update_asset"
        return ToolOutcome(
            response={
                "ok": True,
                "asset_id": "asset-1",
                "user_skill_name": "running",
                "payload": {"distance": 8},
            },
            cards=[
                {
                    "asset_id": "asset-1",
                    "user_skill_name": "running",
                    "payload": {"distance": 8},
                }
            ],
        )


async def test_provider_executes_dependent_legacy_tool_rounds():
    calls = []

    async def completion(**kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            return {
                "choices": [
                    {
                        "message": {
                            "content": None,
                            "tool_calls": [
                                {
                                    "id": "call-1",
                                    "function": {
                                        "name": "tool_query_asset",
                                        "arguments": '{"contains":"跑步"}',
                                    },
                                }
                            ],
                        }
                    }
                ],
                "usage": {"total_tokens": 5},
            }
        if len(calls) == 2:
            assert '"asset_id": "asset-1"' in calls[1]["messages"][-1]["content"]
            return {
                "choices": [
                    {
                        "message": {
                            "content": None,
                            "tool_calls": [
                                {
                                    "id": "call-2",
                                    "function": {
                                        "name": "tool_update_asset",
                                        "arguments": (
                                            '{"asset_id":"asset-1",'
                                            '"payload_patch":"{\\"distance\\":8}"}'
                                        ),
                                    },
                                }
                            ],
                        }
                    }
                ],
                "usage": {"total_tokens": 7},
            }
        assert '"distance": 8' in calls[2]["messages"][-1]["content"]
        return {
            "choices": [{"message": {"content": "改好啦，跑步距离是 8 公里。"}}],
            "usage": {"total_tokens": 11},
        }

    provider = LiteLLMSessionChatProvider(
        model="deepseek/chat",
        api_key="test-key",
        timeout_seconds=3,
        completion=completion,
    )
    executor = _Executor()
    result = await provider.answer(
        context=LegacyChatContext(
            session_id="session-1",
            input_turn_id="turn-1",
            session_type="chat",
            now_local="2026-08-05T15:30:00+08:00",
            records_json='{"enabled_skills": []}',
        ),
        history=[
            {
                "role": "agent",
                "text": "之前记录了 5 公里。",
                "tool_result": {
                    "results": [{"response": {"asset_id": "asset-1"}}]
                },
            }
        ],
        question="把刚才那个改成 8 公里",
        tool_executor=executor,
    )

    assert result.text == "改好啦，跑步距离是 8 公里。"
    assert result.total_tokens == 23
    assert [event["event"] for event in result.tool_events] == [
        "tool_call",
        "tool_result",
        "tool_call",
        "tool_result",
    ]
    assert len(result.cards) == 2
    assert executor.calls == [
        ("tool_query_asset", {"contains": "跑步"}, "call-1"),
        (
            "tool_update_asset",
            {"asset_id": "asset-1", "payload_patch": '{"distance":8}'},
            "call-2",
        ),
    ]
    definitions = await executor.definitions()
    assert all(call["tools"] == definitions for call in calls)
    assert "BEGIN_UNTRUSTED_USER_QUESTION" in calls[0]["messages"][-1]["content"]


async def test_provider_can_resolve_a_stored_pending_contact_from_chat():
    calls = []

    async def completion(**kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            return {
                "choices": [
                    {
                        "message": {
                            "content": None,
                            "tool_calls": [
                                {
                                    "id": "resolve-1",
                                    "function": {
                                        "name": "resolve_pending_contact",
                                        "arguments": (
                                            '{"pending_action_id":"pending-1",'
                                            '"contact_id":"contact-acme"}'
                                        ),
                                    },
                                }
                            ],
                        }
                    }
                ]
            }
        return {
            "choices": [{"message": {"content": "好的，已更新 Acme 的 Alex。"}}]
        }

    class _PendingExecutor:
        def __init__(self):
            self.calls = []

        async def definitions(self):
            return [
                {
                    "type": "function",
                    "function": {
                        "name": "resolve_pending_contact",
                        "description": "Resolve a pending contact action",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ]

        async def execute(self, name, arguments, *, tool_call_id=None):
            self.calls.append((name, arguments, tool_call_id))
            return ToolOutcome(
                response={
                    "ok": True,
                    "pending_action": {"id": "pending-1", "status": "resolved"},
                }
            )

    provider = LiteLLMSessionChatProvider(
        model="deepseek/chat",
        api_key="test-key",
        timeout_seconds=3,
        completion=completion,
    )
    executor = _PendingExecutor()
    result = await provider.answer(
        context=LegacyChatContext(
            session_id="session-1",
            input_turn_id="turn-1",
            session_type="flash",
            now_local="2026-08-06T10:00:00+08:00",
            records_json=(
                '{"pending_actions":[{"id":"pending-1",'
                '"candidates":[{"contact_id":"contact-acme",'
                '"name":"Alex","company":"Acme"}]}]}'
            ),
        ),
        history=[],
        question="选 Acme 的 Alex",
        tool_executor=executor,
    )

    assert result.text == "好的，已更新 Acme 的 Alex。"
    assert executor.calls == [
        (
            "resolve_pending_contact",
            {"pending_action_id": "pending-1", "contact_id": "contact-acme"},
            "resolve-1",
        )
    ]
