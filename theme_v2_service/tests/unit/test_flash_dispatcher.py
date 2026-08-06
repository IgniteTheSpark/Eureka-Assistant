import json
from datetime import datetime, timezone

import pytest

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.dispatcher import decode_dispatcher_output
from app.domains.capture.providers_legacy_flash import LiteLLMLegacyFlashProvider


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
        payload = json.loads(messages[1]["content"])
        if payload["intent"]["type"] == "expense":
            body = {
                "summary": "记下了咖啡消费。",
                "records": [
                    {
                        "kind": "asset",
                        "skill_machine_name": "expense",
                        "payload": {
                            "amount": 28,
                            "currency": "CNY",
                            "category": "餐饮",
                        },
                        "source_text": "咖啡 28 元",
                    }
                ],
            }
        else:
            body = {
                "summary": "记下了 Alex。",
                "records": [
                    {
                        "kind": "contact",
                        "operation": "create_or_update",
                        "name": "Alex",
                        "contact_patch": {"company": "Acme"},
                        "source_text": "添加 Alex 在 Acme 工作",
                    }
                ],
            }
        return {"choices": [{"message": {"content": json.dumps(body, ensure_ascii=False)}}]}

    provider = LiteLLMLegacyFlashProvider(
        model="deepseek/deepseek-chat",
        api_key="test-key",
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.organize(
        transcript="咖啡 28 元，添加 Alex 在 Acme 工作",
        reference_datetime=datetime(2026, 8, 6, 9, 0, tzinfo=timezone.utc),
        skills=[_skill("expense"), _skill("contact"), _skill("notes")],
    )

    assert len(calls) == 3
    assert [record.kind for record in result.records] == ["asset", "contact"]
    assert result.records[1].name == "Alex"
    assert "咖啡" in result.summary and "Alex" in result.summary


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
                                {"summary": "你今天有 0 个待办。", "records": []},
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
    await provider.organize(
        transcript="今天有几个待办",
        reference_datetime=datetime(2026, 8, 6, tzinfo=timezone.utc),
        skills=[
            CaptureSkill(
                machine_name="running_training",
                display_name="跑步训练",
                description="记录已经发生的跑步",
                schema_definition={"distance": {"type": "number"}},
            )
        ],
    )

    prompt = captured[0]["messages"][0]["content"]
    assert "running_training" in prompt
    assert "只压过 notes" in prompt


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
