import asyncio
import json

import pytest

from app.domains.capture.agent import (
    CaptureAgentResult,
    CaptureRecordCommand,
    CaptureSkill,
)
from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.execution import FlashExecutionItem
from app.domains.capture.pipeline import (
    LegacyFlashPipeline,
    aggregate_execution,
    run_custom_skill_fallback,
    run_event_to_todo_fallback,
)
from app.internal_mcp.runtime import InternalMCPUnavailable
from app.domains.sessions.tools import SessionToolExecutor


class _Runtime:
    def __init__(self):
        self.active = 0
        self.max_active = 0

    async def call_tool(self, name, arguments, *, trusted):
        self.active += 1
        self.max_active = max(self.max_active, self.active)
        skill_name = arguments.get("user_skill_name")
        await asyncio.sleep(0.01 if skill_name == "expense" else 0)
        self.active -= 1
        return {
            "ok": True,
            "asset_id": f"{skill_name}-1",
            "user_skill_name": skill_name,
            "payload": {},
        }


async def test_pipeline_executes_siblings_in_parallel_and_keeps_result_order():
    runtime = _Runtime()
    pipeline = LegacyFlashPipeline(
        SessionToolExecutor(
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-1",
            runtime=runtime,
        )
    )
    result = CaptureAgentResult(
        summary="已记录消费和跑步。",
        records=[
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="expense",
                payload={"amount": 28, "currency": "CNY"},
            ),
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="running_log",
                payload={"distance": 2},
            ),
        ],
    )

    executed = await pipeline.run(result, tool_call_prefix="capture-1")

    assert executed.summary == "已记录消费和跑步。"
    assert runtime.max_active == 2
    assert [item.entity_id for item in executed.executions] == [
        "expense-1",
        "running_log-1",
    ]
    assert [item.command.skill_machine_name for item in executed.items] == [
        "expense",
        "running_log",
    ]


async def test_pipeline_keeps_successful_sibling_when_one_tool_is_rejected():
    class PartialRuntime:
        async def call_tool(self, name, arguments, *, trusted):
            if arguments.get("user_skill_name") == "expense":
                return {"ok": False, "error": "金额格式错误"}
            return {
                "ok": True,
                "asset_id": "note-1",
                "user_skill_name": "notes",
                "payload": {"content": "继续观察"},
            }

    pipeline = LegacyFlashPipeline(
        SessionToolExecutor(
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-1",
            runtime=PartialRuntime(),
        )
    )
    result = CaptureAgentResult(
        summary="已整理。",
        records=[
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="expense",
                payload={"amount": 28, "currency": "CNY"},
            ),
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="notes",
                payload={"title": "观察", "content": "继续观察"},
            ),
        ],
    )

    executed = await pipeline.run(result)

    assert [item.status for item in executed.executions] == ["error", "success"]
    assert executed.summary == "已完成 1 项，另有 1 项未完成，请查看对应提示。"
    assert executed.executions[0].error == "金额格式错误"
    assert executed.executions[1].entity_id == "note-1"


def test_rejected_sibling_does_not_erase_success():
    success = FlashExecutionItem(
        intent=FlashIntent(type="expense", source_text="午饭8元"),
        status="success",
        result={"asset_id": "expense-1"},
    )
    rejected = FlashExecutionItem(
        intent=FlashIntent(type="contact", source_text="更新Alex"),
        status="error",
        error_code="intent_tool_rejected",
    )

    aggregate = aggregate_execution([success, rejected], usage_tokens=19)

    assert aggregate.summary == "已完成 1 项，另有 1 项未完成。"
    assert aggregate.items == (success, rejected)
    assert aggregate.warnings == ("intent_tool_rejected",)
    assert aggregate.usage_tokens == 19


def test_aggregation_joins_qa_replies_without_counting_them_as_assets():
    reply = FlashExecutionItem(
        intent=FlashIntent(type="qa", source_text="拿铁是什么"),
        status="reply",
        result={"answer": "拿铁是浓缩咖啡加牛奶。"},
    )
    success = FlashExecutionItem(
        intent=FlashIntent(type="notes", source_text="继续观察"),
        status="success",
        result={"asset_id": "note-1"},
    )

    aggregate = aggregate_execution([reply, success])

    assert aggregate.summary == "已完成 1 项。\n\n拿铁是浓缩咖啡加牛奶。"


async def test_custom_fallback_writes_source_text_once_to_optional_string_field():
    class Runtime:
        def __init__(self):
            self.calls = []

        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, arguments, trusted.tool_call_id))
            return {
                "ok": True,
                "asset_id": "run-1",
                "user_skill_name": arguments["user_skill_name"],
                "payload": {"summary": "昨天下午跑了5公里"},
            }

    runtime = Runtime()
    executor = SessionToolExecutor(
        user_id="owner",
        session_id="session-1",
        input_turn_id="turn-1",
        runtime=runtime,
    )
    result = await run_custom_skill_fallback(
        intent=FlashIntent(
            type="running_training",
            source_text="昨天下午跑了5公里",
            domain="运动",
        ),
        skill=CaptureSkill(
            machine_name="running_training",
            display_name="跑步训练",
            schema_definition={
                "type": "object",
                "properties": {
                    "distance": {"type": "number"},
                    "summary": {"type": "string"},
                },
            },
        ),
        executor=executor,
        tool_call_prefix="capture:rec-1:0:fallback",
    )

    assert result.status == "success"
    assert result.result["asset_id"] == "run-1"
    assert len(runtime.calls) == 1
    assert json.loads(runtime.calls[0][1]["payload"]) == {
        "summary": "昨天下午跑了5公里"
    }


async def test_event_without_real_event_id_falls_back_to_todo_once():
    class Runtime:
        def __init__(self):
            self.calls = []

        async def call_tool(self, name, arguments, *, trusted):
            self.calls.append((name, arguments))
            return {
                "ok": True,
                "asset_id": "todo-1",
                "user_skill_name": "todo",
                "payload": {
                    "title": arguments["title"],
                    "content": arguments["content"],
                },
            }

    runtime = Runtime()
    result = await run_event_to_todo_fallback(
        intent=FlashIntent(
            type="event",
            source_text="明天下午三点跟Alex开会",
            domain="工作",
        ),
        executor=SessionToolExecutor(
            user_id="owner",
            session_id="session-1",
            input_turn_id="turn-1",
            runtime=runtime,
        ),
        tool_call_prefix="capture:rec-1:0:event-fallback",
    )

    assert result.status == "success"
    assert result.intent.type == "todo"
    assert result.result["asset_id"] == "todo-1"
    assert [call[0] for call in runtime.calls] == ["tool_create_todo"]


async def test_event_fallback_does_not_swallow_mcp_unavailability():
    class Executor:
        async def execute(self, *_args, **_kwargs):
            raise InternalMCPUnavailable("stdio exited")

    with pytest.raises(InternalMCPUnavailable):
        await run_event_to_todo_fallback(
            intent=FlashIntent(type="event", source_text="明天三点开会"),
            executor=Executor(),
            tool_call_prefix="capture:rec-1:0:event-fallback",
        )
