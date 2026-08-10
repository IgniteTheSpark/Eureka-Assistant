import asyncio
import json
from datetime import datetime, timezone

import pytest

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.execution import FlashExecutionContext
from app.domains.capture.providers_legacy_flash import LiteLLMLegacyFlashProvider
from app.domains.capture.skill_factory import make_custom_skill_agent


CUSTOM_SKILLS = (
    CaptureSkill(
        user_skill_id="skill-water",
        machine_name="daily_water_intake",
        display_name="喝水记录",
        description="记录已经发生的饮水",
        schema_definition={
            "type": "object",
            "properties": {"amount_ml": {"type": "integer"}},
            "x-capture-enabled": True,
        },
    ),
    CaptureSkill(
        user_skill_id="skill-running",
        machine_name="running_log",
        display_name="跑步记录",
        description="记录已经完成的跑步",
        schema_definition={
            "type": "object",
            "properties": {
                "distance_km": {"type": "number"},
                "duration_minutes": {"type": "integer"},
            },
            "x-capture-enabled": True,
        },
    ),
    CaptureSkill(
        user_skill_id="skill-tennis",
        machine_name="tennis_match_log",
        display_name="网球比赛记录",
        description="记录已经结束的网球比赛",
        schema_definition={
            "type": "object",
            "properties": {
                "opponent": {"type": "string"},
                "score": {"type": "string"},
                "result": {"type": "string"},
            },
            "x-capture-enabled": True,
        },
    ),
)

EXPENSE_SKILL = CaptureSkill(
    machine_name="expense",
    display_name="消费",
    schema_definition={
        "type": "object",
        "properties": {
            "amount": {"type": "number"},
            "currency": {"type": "string"},
        },
    },
)

SKILL_IDS = {
    skill.machine_name: skill.user_skill_id for skill in CUSTOM_SKILLS
}


def _tool_call(call_id: str, arguments: dict) -> dict:
    return {
        "id": call_id,
        "type": "function",
        "function": {
            "name": "tool_create_asset",
            "arguments": json.dumps(arguments, ensure_ascii=False),
        },
    }


def _intent(index: int) -> dict:
    kind = (
        "daily_water_intake",
        "running_log",
        "tennis_match_log",
        "expense",
    )[index % 4]
    source_by_kind = {
        "daily_water_intake": f"记录 #{index}：今天上午喝了 {200 + index} 毫升水",
        "running_log": f"记录 #{index}：今天早上跑了 {index + 1} 公里",
        "tennis_match_log": (
            f"记录 #{index}：今天下午和 Kevin 打完网球，比分 6:4，结果获胜"
        ),
        "expense": f"记录 #{index}：今天午饭花了 {20 + index} 元",
    }
    return {
        "type": kind,
        "operation": "create",
        "source_text": source_by_kind[kind],
        "domain": "运动健康" if kind != "expense" else "生活",
    }


def _payload(kind: str, index: int) -> dict:
    if kind == "daily_water_intake":
        return {"amount_ml": 200 + index}
    if kind == "running_log":
        return {"distance_km": index + 1}
    if kind == "tennis_match_log":
        return {"opponent": "Kevin", "score": "6:4", "result": "获胜"}
    return {"amount": 20 + index, "currency": "CNY"}


class _ConcurrentRuntime:
    def __init__(self, expected_calls: int, *, reject_index: int | None = None):
        self.expected_calls = expected_calls
        self.reject_index = reject_index
        self.calls = []
        self.active = 0
        self.max_active = 0
        self._all_started = asyncio.Event()

    async def list_openai_tools(self):
        return [
            {
                "type": "function",
                "function": {
                    "name": "tool_create_asset",
                    "description": "create asset",
                    "parameters": {"type": "object", "properties": {}},
                },
            }
        ]

    async def call_tool(self, name, arguments, *, trusted):
        assert name == "tool_create_asset"
        source_text = str(arguments.get("source_text") or "")
        index = int(source_text.split("#", 1)[1].split("：", 1)[0])
        self.active += 1
        self.max_active = max(self.max_active, self.active)
        self.calls.append((dict(arguments), trusted))
        if len(self.calls) == self.expected_calls:
            self._all_started.set()
        await asyncio.wait_for(self._all_started.wait(), timeout=2)
        self.active -= 1
        if index == self.reject_index:
            return {"ok": False, "error": "rejected for stress test"}
        payload = arguments.get("payload")
        if isinstance(payload, str):
            payload = json.loads(payload)
        return {
            "ok": True,
            "asset_id": f"asset-{index}",
            "user_skill_name": arguments["user_skill_name"],
            "payload": payload,
        }


def _completion(intents: list[dict]):
    async def complete(**kwargs):
        messages = kwargs["messages"]
        system = messages[0]["content"]
        if "FLASH_DISPATCHER" in system:
            return {
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {"intents": intents}, ensure_ascii=False
                            )
                        }
                    }
                ]
            }
        if messages[-1]["role"] == "tool":
            return {"choices": [{"message": {"content": "not json"}}]}

        request = json.loads(messages[-1]["content"])
        index = int(
            request["source_text"].split("#", 1)[1].split("：", 1)[0]
        )
        kind = next(
            (
                name
                for name in (
                    "daily_water_intake",
                    "running_log",
                    "tennis_match_log",
                )
                if f'user_skill_name="{name}"' in system
            ),
            "expense",
        )
        arguments = {
            "user_skill_name": kind,
            "payload": _payload(kind, index),
        }
        if kind in SKILL_IDS:
            arguments["user_skill_id"] = SKILL_IDS[kind]
        return {
            "choices": [
                {
                    "message": {
                        "content": "",
                        "tool_calls": [
                            _tool_call(f"model-{index}", arguments)
                        ],
                    }
                }
            ]
        }

    return complete


async def _execute(count: int, *, reject_index: int | None = None):
    intents = [_intent(index) for index in range(count)]
    runtime = _ConcurrentRuntime(count, reject_index=reject_index)
    provider = LiteLLMLegacyFlashProvider(
        model="stress-model",
        api_key=None,
        timeout_seconds=5,
        completion=_completion(intents),
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id=f"stress-{count}-{reject_index}",
            user_id="stress-owner",
            session_id="stress-session",
            input_turn_id="stress-turn",
            transcript="；".join(intent["source_text"] for intent in intents),
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(*CUSTOM_SKILLS, EXPENSE_SKILL),
        ),
        tool_runtime=runtime,
    )
    return result, runtime


@pytest.mark.parametrize("count", [1, 3, 10, 20])
async def test_one_flash_scales_to_supported_intent_limit(count: int):
    result, runtime = await _execute(count)

    assert len(result.items) == count
    assert [item.intent.ordinal for item in result.items] == list(range(count))
    assert [item.intent.intent_id for item in result.items] == [
        f"intent-{index}" for index in range(count)
    ]
    assert [item.status for item in result.items] == ["success"] * count
    assert result.summary == f"已完成 {count} 项。"
    assert len(runtime.calls) == count
    assert runtime.max_active == count
    assert len({trusted.tool_call_id for _, trusted in runtime.calls}) == count
    for item in result.items:
        expected_id = SKILL_IDS.get(item.intent.type)
        assert item.intent.custom_skill_id == expected_id


async def test_one_failed_custom_intent_does_not_discard_nineteen_siblings():
    result, runtime = await _execute(20, reject_index=14)

    assert len(result.items) == 20
    assert sum(item.status == "success" for item in result.items) == 19
    assert result.items[14].intent.type == "tennis_match_log"
    assert result.items[14].status == "error"
    assert result.items[14].error_code == "intent_tool_rejected"
    assert result.summary == "已完成 19 项，另有 1 项未完成。"
    assert result.warnings == ("intent_tool_rejected",)
    assert runtime.max_active == 20


async def test_dispatcher_ignores_intents_above_the_explicit_twenty_item_cap():
    intents = [_intent(index) for index in range(25)]
    runtime = _ConcurrentRuntime(20)
    provider = LiteLLMLegacyFlashProvider(
        model="stress-model",
        api_key=None,
        timeout_seconds=5,
        completion=_completion(intents),
    )
    result = await provider.execute(
        context=FlashExecutionContext(
            recording_id="stress-over-limit",
            user_id="stress-owner",
            session_id="stress-session",
            input_turn_id="stress-turn-over-limit",
            transcript="；".join(intent["source_text"] for intent in intents),
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(*CUSTOM_SKILLS, EXPENSE_SKILL),
        ),
        tool_runtime=runtime,
    )

    assert len(result.items) == 20
    assert [item.intent.ordinal for item in result.items] == list(range(20))
    assert len(runtime.calls) == 20


async def test_all_capture_model_calls_disable_sampling_for_repeatable_parsing():
    captured_calls = []
    deterministic_completion = _completion([_intent(0)])

    async def capture_kwargs(**kwargs):
        captured_calls.append(kwargs)
        return await deterministic_completion(**kwargs)

    runtime = _ConcurrentRuntime(1)
    provider = LiteLLMLegacyFlashProvider(
        model="stress-model",
        api_key=None,
        timeout_seconds=5,
        completion=capture_kwargs,
    )
    await provider.execute(
        context=FlashExecutionContext(
            recording_id="stress-deterministic-sampling",
            user_id="stress-owner",
            session_id="stress-session",
            input_turn_id="stress-turn-deterministic",
            transcript=_intent(0)["source_text"],
            reference_datetime=datetime(2026, 8, 10, tzinfo=timezone.utc),
            skills=(*CUSTOM_SKILLS, EXPENSE_SKILL),
        ),
        tool_runtime=runtime,
    )

    assert captured_calls
    assert {call.get("temperature") for call in captured_calls} == {0}


def test_custom_skill_contract_forbids_derived_and_empty_payload_fields():
    instruction = make_custom_skill_agent(CUSTOM_SKILLS[1]).instruction

    assert "即使能从其他字段计算得到，也必须省略" in instruction
    assert "空字符串、null、空列表或空对象" in instruction
