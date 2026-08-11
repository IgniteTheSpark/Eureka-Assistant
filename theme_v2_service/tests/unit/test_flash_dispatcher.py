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
    assert "优先于 notes" in prompt
    assert "已经完成的历史事实" in prompt
    assert "提醒、未来计划仍归 todo" in prompt
    assert result.items[0].status == "reply"


async def test_read_only_expense_capture_returns_answer_without_mutation_receipt():
    class QueryRuntime(_Runtime):
        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, dict(arguments), trusted))
            assert name == "tool_query_asset"
            return {
                "ok": True,
                "assets": [
                    {"asset_id": "expense-1", "payload": {"amount": 8}},
                    {"asset_id": "expense-2", "payload": {"amount": 20}},
                ],
            }

    async def completion(**kwargs):
        messages = kwargs["messages"]
        if "FLASH_DISPATCHER" in messages[0]["content"]:
            return {
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "intents": [
                                        {
                                            "type": "expense",
                                            "operation": "query",
                                            "source_text": "最近花了多少钱",
                                        }
                                    ]
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            }
        if messages[-1]["role"] == "tool":
            return {
                "choices": [
                    {
                        "message": {
                            "content": '{"ok":true,"answer":"最近共消费 28 元。"}'
                        }
                    }
                ]
            }
        assert [tool["function"]["name"] for tool in kwargs["tools"]] == [
            "tool_query_asset"
        ]
        return {
            "choices": [
                {
                    "message": {
                        "content": "",
                        "tool_calls": [
                            _tool_call(
                                "model-query",
                                "tool_query_asset",
                                {"user_skill_name": "expense"},
                            )
                        ],
                    }
                }
            ]
        }

    runtime = QueryRuntime()
    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-query",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-query",
            transcript="最近花了多少钱",
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(_skill("expense"),),
        ),
        tool_runtime=runtime,
    )

    assert result.summary == "最近共消费 28 元。"
    assert result.items[0].status == "reply"
    assert result.items[0].intent.operation == "query"
    assert [call[0] for call in runtime.calls] == ["tool_query_asset"]


async def test_update_capture_resolves_target_before_running_mutation_agent():
    class UpdateRuntime(_Runtime):
        async def list_openai_tools(self):
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
                    "tool_resolve_capture_target",
                    "tool_query_asset",
                    "tool_update_asset",
                )
            ]

        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, dict(arguments), trusted))
            if name == "tool_resolve_capture_target":
                return {
                    "ok": True,
                    "status": "resolved",
                    "entity_id": "expense-1",
                    "entity_type": "expense",
                    "resolution_source": "prior_input_turn",
                    "candidates": [],
                }
            if name == "tool_update_asset":
                assert arguments["asset_id"] == "expense-1"
                return {
                    "ok": True,
                    "asset_id": "expense-1",
                    "user_skill_name": "expense",
                    "payload": {"amount": 8},
                }
            raise AssertionError(name)

    async def completion(**kwargs):
        messages = kwargs["messages"]
        if "FLASH_DISPATCHER" in messages[0]["content"]:
            return {
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "intents": [
                                        {
                                            "type": "expense",
                                            "operation": "update",
                                            "source_text": "把刚刚账单从10元改成8元",
                                        }
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
        request = json.loads(messages[-1]["content"])
        assert request["resolved_target"] == {
            "entity_id": "expense-1",
            "entity_type": "expense",
            "resolution_source": "prior_input_turn",
        }
        return {
            "choices": [
                {
                    "message": {
                        "content": "",
                        "tool_calls": [
                            _tool_call(
                                "model-update",
                                "tool_update_asset",
                                {
                                    "asset_id": "model-invented-expense",
                                    "payload_patch": {"amount": 8},
                                },
                            )
                        ],
                    }
                }
            ]
        }

    runtime = UpdateRuntime()
    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-update",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-2",
            transcript="把刚刚账单从10元改成8元",
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(_skill("expense"),),
        ),
        tool_runtime=runtime,
    )

    assert result.items[0].status == "success"
    assert result.items[0].result["asset_id"] == "expense-1"
    assert [call[0] for call in runtime.calls] == [
        "tool_resolve_capture_target",
        "tool_update_asset",
    ]


async def test_resolved_custom_delete_executes_deterministically_without_second_agent():
    class DeleteRuntime(_Runtime):
        async def list_openai_tools(self):
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
                    "tool_resolve_capture_target",
                    "tool_delete_asset",
                )
            ]

        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, dict(arguments), trusted))
            if name == "tool_resolve_capture_target":
                return {
                    "ok": True,
                    "status": "resolved",
                    "entity_id": "running-1",
                    "entity_type": "running_log",
                    "resolution_source": "prior_input_turn",
                    "candidates": [],
                }
            if name == "tool_delete_asset":
                assert arguments["asset_id"] == "running-1"
                return {
                    "ok": True,
                    "status": "deleted",
                    "asset_id": "running-1",
                    "user_skill_name": "running_log",
                }
            raise AssertionError(name)

    async def completion(**kwargs):
        if "FLASH_DISPATCHER" not in kwargs["messages"][0]["content"]:
            raise AssertionError("resolved deletes must not invoke a second agent")
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "intents": [
                                    {
                                        "type": "running_log",
                                        "operation": "delete",
                                        "source_text": "删除刚才的跑步记录",
                                    }
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    runtime = DeleteRuntime()
    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-running-delete",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-running-delete",
            transcript="删除刚才的跑步记录",
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(_skill("running_log"),),
        ),
        tool_runtime=runtime,
    )

    item = result.items[0]
    assert item.status == "success"
    assert item.result["asset_id"] == "running-1"
    assert item.result["operation_tool"] == "tool_delete_asset"
    assert [call[0] for call in runtime.calls] == [
        "tool_resolve_capture_target",
        "tool_delete_asset",
    ]


async def test_ambiguous_asset_delete_is_an_error_until_asset_confirmation_exists():
    class AmbiguousAssetRuntime(_Runtime):
        async def list_openai_tools(self):
            return [
                {
                    "type": "function",
                    "function": {
                        "name": "tool_resolve_capture_target",
                        "description": "resolve",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ]

        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, dict(arguments), trusted))
            assert name == "tool_resolve_capture_target"
            return {
                "ok": True,
                "status": "ambiguous",
                "entity_id": None,
                "entity_type": None,
                "resolution_source": "prior_input_turn",
                "candidates": [
                    {
                        "entity_id": "expense-1",
                        "entity_type": "expense",
                        "source": "prior_input_turn",
                        "snapshot": {"asset_id": "expense-1"},
                    },
                    {
                        "entity_id": "expense-2",
                        "entity_type": "expense",
                        "source": "prior_input_turn",
                        "snapshot": {"asset_id": "expense-2"},
                    },
                ],
            }

    async def completion(**kwargs):
        assert "FLASH_DISPATCHER" in kwargs["messages"][0]["content"]
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "intents": [
                                    {
                                        "type": "expense",
                                        "operation": "delete",
                                        "source_text": "删除刚刚那个账单",
                                    }
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    runtime = AmbiguousAssetRuntime()
    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-expense-delete-ambiguous",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-delete",
            transcript="删除刚刚那个账单",
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(_skill("expense"),),
        ),
        tool_runtime=runtime,
    )

    item = result.items[0]
    assert item.status == "error"
    assert item.error_code == "intent_target_ambiguous"
    assert result.summary == "有 1 项未完成。"
    assert [call[0] for call in runtime.calls] == [
        "tool_resolve_capture_target"
    ]


async def test_ambiguous_contact_preserves_patch_and_flat_candidates_for_confirmation():
    class AmbiguousRuntime(_Runtime):
        async def list_openai_tools(self):
            return [
                {
                    "type": "function",
                    "function": {
                        "name": "tool_resolve_capture_target",
                        "description": "resolve",
                        "parameters": {"type": "object", "properties": {}},
                    },
                }
            ]

        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, dict(arguments), trusted))
            assert name == "tool_resolve_capture_target"
            return {
                "ok": True,
                "status": "ambiguous",
                "entity_id": None,
                "entity_type": None,
                "resolution_source": "exact_match",
                "candidates": [
                    {
                        "entity_id": "alex-acme",
                        "entity_type": "contact",
                        "source": "exact_match",
                        "snapshot": {
                            "contact_id": "alex-acme",
                            "name": "Alex",
                            "company": "Acme",
                            "title": "工程师",
                        },
                    },
                    {
                        "entity_id": "alex-byte",
                        "entity_type": "contact",
                        "source": "exact_match",
                        "snapshot": {
                            "contact_id": "alex-byte",
                            "name": "Alex",
                            "company": "字节",
                            "title": None,
                        },
                    },
                ],
            }

    async def completion(**kwargs):
        assert "FLASH_DISPATCHER" in kwargs["messages"][0]["content"]
        return {
            "choices": [
                {
                    "message": {
                        "content": json.dumps(
                            {
                                "intents": [
                                    {
                                        "type": "contact",
                                        "operation": "update",
                                        "source_text": "Alex的职业改成设计师",
                                        "target_query": "Alex",
                                        "contact_patch": {"title": "设计师"},
                                    }
                                ]
                            },
                            ensure_ascii=False,
                        )
                    }
                }
            ]
        }

    runtime = AmbiguousRuntime()
    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="rec-contact-ambiguous",
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-contact",
            transcript="Alex的职业改成设计师",
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(_skill("contact"),),
        ),
        tool_runtime=runtime,
    )

    item = result.items[0]
    assert item.status == "pending_confirmation"
    assert item.result == {
        "operation": "update",
        "name": "Alex",
        "candidates": [
            {
                "contact_id": "alex-acme",
                "name": "Alex",
                "company": "Acme",
                "title": "工程师",
            },
            {
                "contact_id": "alex-byte",
                "name": "Alex",
                "company": "字节",
                "title": None,
            },
        ],
        "extracted_update": {"title": "设计师"},
    }
    assert [call[0] for call in runtime.calls] == [
        "tool_resolve_capture_target"
    ]


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
            "operation": "create",
            "source_text": "保留这段原文",
            "domain": None,
            "ordinal": 0,
            "intent_id": "",
            "target_id": None,
            "target_query": None,
            "contact_patch": {},
            "custom_skill_id": None,
            "routing_error": None,
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


@pytest.mark.parametrize(
    ("source_text", "intent_type", "operation"),
    [
        ("明天提醒我吃药", "todo", "create"),
        ("帮我看看最近花了多少钱", "expense", "query"),
        ("把刚刚账单从 10 块改成 8 块", "expense", "update"),
        ("删除刚刚那个代办", "todo", "delete"),
        ("地球为什么是圆的", "qa", "answer"),
    ],
)
def test_decode_dispatcher_output_preserves_first_class_operation(
    source_text: str,
    intent_type: str,
    operation: str,
):
    intents = decode_dispatcher_output(
        json.dumps(
            {
                "intents": [
                    {
                        "type": intent_type,
                        "operation": operation,
                        "source_text": source_text,
                    }
                ]
            },
            ensure_ascii=False,
        ),
        fallback_text=source_text,
    )

    assert intents[0].operation == operation


def test_dispatcher_schema_requires_operation_as_a_bounded_enum():
    agent = make_dispatcher_agent()

    assert '"operation"' in agent.instruction
    for operation in ("create", "query", "update", "delete", "answer"):
        assert f'"{operation}"' in agent.instruction


def test_dispatcher_preserves_optional_mutation_target_hints():
    intent = decode_dispatcher_output(
        json.dumps(
            {
                "intents": [
                    {
                        "type": "expense",
                        "operation": "update",
                        "source_text": "把咖啡账单改成 8 元",
                        "target_id": "asset-explicit",
                        "target_query": "咖啡",
                    }
                ]
            },
            ensure_ascii=False,
        ),
        fallback_text="把咖啡账单改成 8 元",
    )[0]

    assert intent.target_id == "asset-explicit"
    assert intent.target_query == "咖啡"


def test_dispatcher_factory_is_toolless_and_includes_custom_skill_and_schema():
    agent = make_dispatcher_agent(
        [
            CaptureSkill(
                machine_name="running_training",
                display_name="跑步训练",
                description="记录已经完成的跑步",
                schema_definition={
                    "type": "object",
                    "properties": {
                        "distance": {
                            "type": "number",
                            "title": "距离",
                            "description": "本次跑步公里数",
                        }
                    },
                    "x-routing": {
                        "intent": "记录用户已经完成的跑步活动",
                        "aliases": ["跑步", "晨跑"],
                        "include": ["实际完成的跑步"],
                        "exclude": ["未来跑步计划"],
                        "positive_examples": ["刚跑完五公里"],
                        "negative_examples": ["明早去跑五公里"],
                    },
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
    assert "不能只做字面连续匹配" in agent.instruction
    assert "用途=记录用户已经完成的跑步活动" in agent.instruction
    assert "别名=跑步 / 晨跑" in agent.instruction
    assert "包含=实际完成的跑步" in agent.instruction
    assert "排除=未来跑步计划" in agent.instruction
    assert "正例=刚跑完五公里" in agent.instruction
    assert "反例=明早去跑五公里" in agent.instruction
    assert "字段=距离(distance, number): 本次跑步公里数" in agent.instruction
    assert "schema={" not in agent.instruction


def test_builtin_factory_exposes_only_supported_skill_tools():
    notes = make_builtin_skill_agent("notes")

    assert notes.allowed_tools == frozenset({"tool_create_note"})
    assert "不生成标签" in notes.instruction
    with pytest.raises(ValueError, match="unsupported flash skill"):
        make_builtin_skill_agent("idea")
    with pytest.raises(ValueError, match="unsupported flash skill"):
        make_builtin_skill_agent("misc")


def test_builtin_factory_restricts_tools_to_the_requested_operation():
    query = make_builtin_skill_agent("expense", operation="query")
    update = make_builtin_skill_agent("expense", operation="update")
    delete = make_builtin_skill_agent("expense", operation="delete")

    assert query.allowed_tools == frozenset({"tool_query_asset"})
    assert update.allowed_tools == frozenset(
        {"tool_query_asset", "tool_update_asset"}
    )
    assert delete.allowed_tools == frozenset(
        {"tool_query_asset", "tool_delete_asset"}
    )
    assert "tool_create_asset" not in query.allowed_tools
    assert "operation=query" in query.instruction


def test_custom_factory_keeps_all_fields_optional_and_never_invents_values():
    agent = make_custom_skill_agent(
        CaptureSkill(
            user_skill_id="skill-running",
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
    assert 'user_skill_id="skill-running"' in agent.instruction


def test_custom_factory_query_is_read_only():
    agent = make_custom_skill_agent(
        CaptureSkill(
            machine_name="running_training",
            display_name="跑步训练",
            schema_definition={"summary": {"type": "string"}},
        ),
        operation="query",
    )

    assert agent.allowed_tools == frozenset({"tool_query_asset"})
    assert "不得创建、修改或删除资产" in agent.instruction
