import json
from datetime import datetime, timedelta, timezone

import pytest

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.execution import (
    FlashExecutionContext,
    RetryableFlashExecutionError,
)
from app.domains.capture.intent_normalizer import normalize_intents
from app.domains.capture.providers_legacy_flash import LiteLLMLegacyFlashProvider


BEIJING = timezone(timedelta(hours=8))


def _skill(name: str, *, properties=None) -> CaptureSkill:
    return CaptureSkill(
        machine_name=name,
        display_name=name,
        schema_definition={
            "type": "object",
            "properties": properties
            or {
                "title": {"type": "string"},
                "content": {"type": "string"},
            },
            "x-capture-enabled": True,
        },
    )


BASE_SKILLS = (
    _skill(
        "expense",
        properties={
            "amount": {"type": "number"},
            "currency": {"type": "string"},
        },
    ),
    _skill("contact", properties={"name": {"type": "string"}}),
    _skill("todo"),
    _skill("notes"),
)


def _context(transcript: str, *, recording_id="rec-1", skills=BASE_SKILLS):
    return FlashExecutionContext(
        recording_id=recording_id,
        user_id="owner",
        session_id="session-1",
        input_turn_id="turn-1",
        transcript=transcript,
        reference_datetime=datetime(2026, 8, 6, 9, 30, tzinfo=BEIJING),
        skills=tuple(skills),
    )


def _response(*, content="", tool_calls=()):
    return {
        "choices": [
            {
                "message": {
                    "content": content,
                    "tool_calls": list(tool_calls),
                }
            }
        ]
    }


def _tool_call(name: str, arguments: dict):
    return {
        "id": f"model-{name}",
        "type": "function",
        "function": {
            "name": name,
            "arguments": json.dumps(arguments, ensure_ascii=False),
        },
    }


class _Runtime:
    def __init__(self, *, reject_tool: str | None = None):
        self.reject_tool = reject_tool
        self.calls = []
        self._entity_by_call_id = {}

    async def list_openai_tools(self):
        names = (
            "tool_create_asset",
            "tool_create_todo",
            "tool_create_note",
            "tool_create_event",
            "tool_create_contact",
            "tool_query_asset",
            "tool_query_contact",
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
        self.calls.append((name, dict(arguments), trusted.tool_call_id))
        if name == self.reject_tool:
            return {"ok": False, "error": "private database/provider details"}
        entity_id = self._entity_by_call_id.setdefault(
            trusted.tool_call_id,
            f"entity-{len(self._entity_by_call_id) + 1}",
        )
        if name in {"tool_create_asset", "tool_create_todo", "tool_create_note"}:
            payload = arguments.get("payload")
            if isinstance(payload, str):
                payload = json.loads(payload)
            if name == "tool_create_todo":
                payload = {
                    "title": arguments.get("title"),
                    "content": arguments.get("content"),
                    "due_date": arguments.get("due_date"),
                }
            if name == "tool_create_note":
                payload = {
                    "title": arguments.get("title"),
                    "content": arguments.get("content"),
                }
            return {
                "ok": True,
                "asset_id": entity_id,
                "user_skill_name": arguments.get("user_skill_name")
                or ("todo" if name == "tool_create_todo" else "notes"),
                "payload": payload or {},
                "period": arguments.get("period"),
                "occurred_at": arguments.get("occurred_at"),
                "effective_at": arguments.get("effective_at"),
            }
        if name == "tool_create_contact":
            return {
                "ok": True,
                "contact_id": entity_id,
                "contact_action": "created",
                "name": arguments.get("name"),
                "company": arguments.get("company"),
            }
        if name == "tool_create_event":
            return {
                "ok": True,
                "event_id": entity_id,
                "title": arguments.get("title"),
                "start_at": arguments.get("start_at"),
                "end_at": arguments.get("end_at"),
            }
        raise AssertionError(name)


def _completion(dispatch_content: str):
    async def complete(**kwargs):
        messages = kwargs["messages"]
        system = messages[0]["content"]
        if "FLASH_DISPATCHER" in system:
            return _response(content=dispatch_content)
        if messages[-1]["role"] == "tool":
            return _response(content="malformed final text")
        if "flash-expense-skill" in system:
            return _response(
                tool_calls=[
                    _tool_call(
                        "tool_create_asset",
                        {
                            "user_skill_name": "expense",
                            "payload": {"amount": 28, "currency": "CNY"},
                        },
                    )
                ]
            )
        if "flash-contact-skill" in system:
            return _response(
                tool_calls=[
                    _tool_call(
                        "tool_create_contact",
                        {"name": "Alex", "company": "Acme"},
                    )
                ]
            )
        if "flash-notes-skill" in system:
            return _response(
                tool_calls=[
                    _tool_call(
                        "tool_create_note",
                        {"title": "安静一点", "content": "产品应该更安静一点"},
                    )
                ]
            )
        if "flash-qa-skill" in system:
            return _response(
                content='{"ok":true,"answer":"拿铁加牛奶，美式加水。"}'
            )
        if "所有字段在写入时都视为可选" in system:
            return _response(content="custom extraction missed")
        raise AssertionError(system[:100])

    return complete


def _provider(dispatch_content: str) -> LiteLLMLegacyFlashProvider:
    return LiteLLMLegacyFlashProvider(
        model="test-model",
        api_key=None,
        timeout_seconds=5,
        completion=_completion(dispatch_content),
    )


@pytest.mark.parametrize("alias", ["idea", "misc", "other", "note"])
def test_free_text_aliases_converge_on_notes(alias: str):
    normalized = normalize_intents(
        [FlashIntent(type=alias, source_text="自由文本")],
        custom_skill_names=set(),
    )
    assert [intent.type for intent in normalized] == ["notes"]


async def test_production_kernel_preserves_atomic_order_and_retry_ids():
    dispatch = json.dumps(
        {
            "intents": [
                {
                    "type": "expense",
                    "source_text": "咖啡28元",
                    "domain": "生活",
                },
                {
                    "type": "contact",
                    "source_text": "保存Alex，他在Acme工作",
                    "domain": "社交",
                },
            ]
        },
        ensure_ascii=False,
    )
    runtime = _Runtime()
    context = _context("咖啡28元，保存Alex，他在Acme工作")

    first = await _provider(dispatch).execute(context=context, tool_runtime=runtime)
    second = await _provider(dispatch).execute(context=context, tool_runtime=runtime)

    assert [item.intent.type for item in first.items] == ["expense", "contact"]
    assert [item.status for item in first.items] == ["success", "success"]
    assert [
        "asset" if item.result.get("asset_id") else "contact"
        for item in first.items
    ] == ["asset", "contact"]
    first_ids = {
        item.result.get("asset_id") or item.result.get("contact_id")
        for item in first.items
    }
    second_ids = {
        item.result.get("asset_id") or item.result.get("contact_id")
        for item in second.items
    }
    assert first_ids == second_ids
    assert len(first_ids) == 2


async def test_invalid_dispatch_is_retried_instead_of_writing_a_note():
    notes_runtime = _Runtime()
    with pytest.raises(
        RetryableFlashExecutionError,
        match="dispatcher response invalid",
    ):
        await _provider("not json").execute(
            context=_context("产品应该更安静一点"),
            tool_runtime=notes_runtime,
        )
    assert notes_runtime.calls == []


async def test_qa_never_writes():

    qa_dispatch = (
        '{"intents":[{"type":"qa","source_text":"拿铁和美式有什么区别"}]}'
    )
    qa_runtime = _Runtime()
    qa = await _provider(qa_dispatch).execute(
        context=_context("拿铁和美式有什么区别"),
        tool_runtime=qa_runtime,
    )
    assert qa.items[0].status == "reply"
    assert qa_runtime.calls == []


async def test_custom_fallback_preserves_period_without_inventing_clock():
    dispatch = (
        '{"intents":[{"type":"hydration","source_text":'
        '"昨天早上喝水200毫升","domain":"健康"}]}'
    )
    hydration = _skill(
        "hydration",
        properties={"summary": {"type": "string"}},
    )
    runtime = _Runtime()
    result = await _provider(dispatch).execute(
        context=_context(
            "昨天早上喝水200毫升",
            skills=(*BASE_SKILLS, hydration),
        ),
        tool_runtime=runtime,
    )

    assert result.items[0].status == "success"
    name, arguments, _call_id = runtime.calls[0]
    assert name == "tool_create_asset"
    assert arguments["period"] == "上午"
    assert arguments["occurred_at"] == ""
    assert arguments["effective_at"] == "2026-08-05T00:00:00+08:00"


async def test_tool_rejection_exposes_only_generic_warning_code():
    dispatch = (
        '{"intents":[{"type":"expense","source_text":"咖啡28元",'
        '"domain":"生活"}]}'
    )
    result = await _provider(dispatch).execute(
        context=_context("咖啡28元"),
        tool_runtime=_Runtime(reject_tool="tool_create_asset"),
    )

    assert result.items[0].status == "error"
    assert result.warnings == ("intent_tool_rejected",)
    assert "private" not in json.dumps(result.items[0].result)


async def test_each_intent_executor_cannot_see_sibling_intent_text():
    dispatch = json.dumps(
        {
            "intents": [
                {"type": "expense", "source_text": "早餐花了25元"},
                {"type": "expense", "source_text": "晚餐花了40元"},
            ]
        },
        ensure_ascii=False,
    )
    seen_messages: list[dict] = []

    async def completion(**kwargs):
        messages = kwargs["messages"]
        if "FLASH_DISPATCHER" in messages[0]["content"]:
            return _response(content=dispatch)
        if messages[-1]["role"] == "tool":
            return _response(content='{"ok":true}')
        payload = json.loads(messages[-1]["content"])
        seen_messages.append(payload)
        amount = 25 if "早餐" in payload["source_text"] else 40
        return _response(
            tool_calls=[
                _tool_call(
                    "tool_create_asset",
                    {
                        "user_skill_name": "expense",
                        "payload": {"amount": amount},
                    },
                )
            ]
        )

    provider = LiteLLMLegacyFlashProvider(
        model="test-model",
        api_key=None,
        timeout_seconds=5,
        completion=completion,
    )
    result = await provider.execute(
        context=_context("早餐花了25元，晚餐花了40元"),
        tool_runtime=_Runtime(),
    )

    assert [item.status for item in result.items] == ["success", "success"]
    assert [message["source_text"] for message in seen_messages] == [
        "早餐花了25元",
        "晚餐花了40元",
    ]
    assert [message["user_text"] for message in seen_messages] == [
        "早餐花了25元",
        "晚餐花了40元",
    ]
