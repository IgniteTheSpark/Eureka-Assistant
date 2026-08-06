import json
from datetime import datetime, timezone

import pytest

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.dispatcher import decode_dispatcher_output
from app.domains.capture.execution import FlashExecutionContext
from app.domains.capture.providers_legacy_flash import LiteLLMLegacyFlashProvider
from app.domains.capture.skill_factory import (
    make_builtin_skill_agent,
    make_custom_skill_agent,
    make_dispatcher_agent,
)


def _skill(name: str) -> CaptureSkill:
    return CaptureSkill(
        machine_name=name,
        display_name=name,
        schema_definition={
            "type": "object",
            "properties": {
                "amount": {"type": "number"},
                "currency": {"type": "string"},
                "category": {"type": "string"},
            }
            if name == "expense"
            else {"content": {"type": "string"}},
        },
    )


def _tool_call(call_id: str, name: str, arguments: dict):
    return {
        "id": call_id,
        "type": "function",
        "function": {
            "name": name,
            "arguments": json.dumps(arguments, ensure_ascii=False),
        },
    }


class _Runtime:
    def __init__(self):
        self.calls = []

    async def list_openai_tools(self):
        names = (
            "tool_create_asset",
            "tool_create_contact",
            "tool_query_asset",
        )
        return [
            {
                "type": "function",
                "function": {
                    "name": name,
                    "description": name,
                    "parameters": {"type": "object", "properties": {}},
                },
            }
            for name in names
        ]

    async def call_tool(self, name, arguments, *, trusted):
        self.calls.append((name, dict(arguments), trusted))
        if name == "tool_create_asset":
            return {
                "ok": True,
                "asset_id": "expense-1",
                "user_skill_name": "expense",
                "payload": {"amount": 28, "currency": "CNY"},
            }
        if name == "tool_create_contact":
            return {
                "ok": True,
                "contact_id": "contact-1",
                "contact_action": "created",
                "name": "Alex",
                "company": "Acme",
            }
        raise AssertionError(name)


async def test_legacy_flash_provider_dispatches_then_runs_sibling_skills_in_parallel():
    calls = []

    async def completion(**kwargs):
        calls.append(kwargs)
        messages = kwargs["messages"]
        system = messages[0]["content"]
        if "FLASH_DISPATCHER" in system:
            return {
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "intents": [
                                        {
                                            "type": "expense",
                                            "domain": "生活",
                                            "source_text": "咖啡 28 元",
                                        },
                                        {
                                            "type": "contact",
                                            "domain": "社交",
                                            "source_text": "添加 Alex 在 Acme 工作",
                                        },
                                    ]
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            }
        if messages[-1]["role"] == "tool":
            return {"choices": [{"message": {"content": "not json"}}]}
        if "flash-expense-skill" in system:
            tool_call = _tool_call(
                "model-expense",
                "tool_create_asset",
                {
                    "user_skill_name": "expense",
                    "payload": {"amount": 28, "currency": "CNY"},
                },
            )
        else:
            tool_call = _tool_call(
                "model-contact",
                "tool_create_contact",
                {"name": "Alex", "company": "Acme"},
            )
        return {
            "choices": [
                {"message": {"content": "", "tool_calls": [tool_call]}}
            ]
        }

    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key="test-key",
        timeout_seconds=5,
        completion=completion,
    )
    runtime = _Runtime()
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-1",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-1",
            transcript="咖啡 28 元，添加 Alex 在 Acme 工作",
            reference_datetime=datetime(
                2026, 8, 6, 9, 0, tzinfo=timezone.utc
            ),
            skills=(_skill("expense"), _skill("contact"), _skill("notes")),
        ),
        tool_runtime=runtime,
    )

    assert len(calls) == 5
    assert [item.status for item in result.items] == ["success", "success"]
    assert result.items[0].result["asset_id"] == "expense-1"
    assert result.items[1].result["name"] == "Alex"
    assert [call[0] for call in runtime.calls] == [
        "tool_create_asset",
        "tool_create_contact",
    ]


async def test_dispatcher_teaches_custom_skills_without_overriding_structured_types():
    captured = []

    async def completion(**kwargs):
        captured.append(kwargs)
        if "FLASH_DISPATCHER" not in kwargs["messages"][0]["content"]:
            return {
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {"ok": True, "answer": "你今天有 0 个待办。"},
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            }
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "intents": [
                                    {
                                        "type": "qa",
                                        "source_text": "今天有几个待办",
                                    }
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-1",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-1",
            transcript="今天有几个待办",
            reference_datetime=datetime(2026, 8, 6, tzinfo=timezone.utc),
            skills=(
                CaptureSkill(
                    machine_name="running_training",
                    display_name="跑步训练",
                    description="记录已经发生的跑步",
                    schema_definition={"distance": {"type": "number"}},
                ),
            ),
        ),
        tool_runtime=_Runtime(),
    )

    prompt = captured[0]["messages"][0]["content"]
    assert "running_training" in prompt
    assert "只压过 notes" in prompt
    assert result.items[0].status == "reply"


@pytest.mark.parametrize(
    ("content", "expected"),
    [
        (
            '```json\n{"intents":[{"type":"expense","source_text":"午饭8元"}]}\n```',
            "expense",
        ),
        (
            '结果如下：{"intents":[{"type":"contact","source_text":"Alex在Acme"}]}',
            "contact",
        ),
        (
            '{"intent_list":[{"type":"notes","source_text":"继续观察"}]}',
            "notes",
        ),
    ],
)
def test_decode_dispatcher_output_accepts_legacy_deepseek_shapes(
    content: str,
    expected: str,
):
    assert decode_dispatcher_output(content, fallback_text="原文")[0].type == expected


def test_decode_dispatcher_output_falls_back_to_notes_after_model_response():
    intents = decode_dispatcher_output("这不是JSON", fallback_text="保留这段原文")

    assert [intent.model_dump() for intent in intents] == [
        {
            "type": "notes",
            "source_text": "保留这段原文",
            "domain": None,
        }
    ]


def test_decode_dispatcher_output_drops_only_invalid_siblings():
    intents = decode_dispatcher_output(
        json.dumps(
            {
                "intents": [
                    {"type": "expense", "source_text": "咖啡28元"},
                    {"type": "contact", "source_text": ""},
                ]
            },
            ensure_ascii=False,
        ),
        fallback_text="原文",
    )

    assert [intent.type for intent in intents] == ["expense"]


def test_dispatcher_factory_is_toolless_and_includes_custom_skill_and_schema():
    agent = make_dispatcher_agent(
        [
            CaptureSkill(
                machine_name="running_training",
                display_name="跑步训练",
                description="记录已经完成的跑步",
                schema_definition={
                    "type": "object",
                    "properties": {"distance": {"type": "number"}},
                },
            )
        ]
    )

    assert agent.name == "flash_dispatcher"
    assert agent.allowed_tools == frozenset()
    assert "running_training" in agent.instruction
    assert "FlashDispatchResult JSON Schema" in agent.instruction
    assert '"intents"' in agent.instruction
    assert "外部产品时,统一归 `qa`" in agent.instruction


def test_builtin_factory_exposes_only_supported_skill_tools():
    notes = make_builtin_skill_agent("notes")

    assert notes.allowed_tools == frozenset({"tool_create_note"})
    assert "不生成标签" in notes.instruction
    with pytest.raises(ValueError, match="unsupported flash skill"):
        make_builtin_skill_agent("idea")
    with pytest.raises(ValueError, match="unsupported flash skill"):
        make_builtin_skill_agent("misc")


def test_custom_factory_keeps_all_fields_optional_and_never_invents_values():
    agent = make_custom_skill_agent(
        CaptureSkill(
            machine_name="running_training",
            display_name="跑步训练",
            description="记录已经发生的跑步",
            schema_definition={
                "type": "object",
                "required": ["distance", "duration"],
                "properties": {
                    "distance": {
                        "type": "number",
                        "description": "距离",
                    },
                    "duration": {
                        "type": "integer",
                        "description": "时长",
                    },
                },
            },
        )
    )

    assert agent.name == "running_training_custom_skill"
    assert agent.allowed_tools == frozenset({"tool_create_asset"})
    assert "所有字段在写入时都视为可选" in agent.instruction
    assert "未提到的字段不要补、不要猜" in agent.instruction
    assert "`distance` (number, 可选)" in agent.instruction
