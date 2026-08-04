from app.domains.sessions.chat import LiteLLMSessionChatProvider
from app.domains.sessions.tools import ToolOutcome


class _Executor:
    async def execute(self, name, arguments):
        assert name == "query_assets"
        assert arguments == {"limit": 3}
        return ToolOutcome(
            response={"count": 1, "assets": [{"id": "asset-1"}]},
            cards=[{"id": "asset-1", "user_skill_name": "notes", "payload": {}}],
        )


async def test_provider_executes_at_most_one_bounded_tool_round():
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
                                        "name": "query_assets",
                                        "arguments": '{"limit":3}',
                                    },
                                }
                            ],
                        }
                    }
                ],
                "usage": {"total_tokens": 5},
            }
        return {
            "choices": [{"message": {"content": "找到一条随记。"}}],
            "usage": {"total_tokens": 7},
        }

    provider = LiteLLMSessionChatProvider(
        model="deepseek/chat",
        api_key="test-key",
        timeout_seconds=3,
        completion=completion,
    )
    result = await provider.answer(
        context="records",
        history=[{"role": "user", "text": "previous"}],
        question="今天记录了什么？",
        tool_executor=_Executor(),
    )

    assert result.text == "找到一条随记。"
    assert result.total_tokens == 12
    assert [event["event"] for event in result.tool_events] == [
        "tool_call",
        "tool_result",
    ]
    assert len(result.cards) == 1
    assert "BEGIN_UNTRUSTED_USER_QUESTION" in calls[0]["messages"][-1]["content"]
    assert "tools" not in calls[1]
