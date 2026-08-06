import asyncio

from app.domains.capture.agent import CaptureAgentResult, CaptureRecordCommand
from app.domains.capture.pipeline import LegacyFlashPipeline
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
