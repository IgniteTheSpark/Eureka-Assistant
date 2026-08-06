from __future__ import annotations

import asyncio
from dataclasses import dataclass

from app.domains.capture.agent import CaptureAgentResult, CaptureRecordCommand
from app.domains.capture.skills import FlashSkillResult, execute_capture_command
from app.domains.sessions.tools import SessionToolExecutor


@dataclass(frozen=True)
class FlashPipelineItem:
    command: CaptureRecordCommand
    execution: FlashSkillResult


@dataclass(frozen=True)
class FlashPipelineResult:
    summary: str
    items: list[FlashPipelineItem]

    @property
    def executions(self) -> list[FlashSkillResult]:
        return [item.execution for item in self.items]


class LegacyFlashPipeline:
    """Executes normalized Flash records through trusted MCP in stable order."""

    def __init__(self, executor: SessionToolExecutor) -> None:
        self._executor = executor

    async def run(
        self,
        result: CaptureAgentResult,
        *,
        tool_call_prefix: str = "capture",
    ) -> FlashPipelineResult:
        executions = await asyncio.gather(
            *[
                execute_capture_command(
                    command,
                    self._executor,
                    tool_call_prefix=f"{tool_call_prefix}-{index}",
                )
                for index, command in enumerate(result.records)
            ]
        )
        return FlashPipelineResult(
            summary=_aggregate_summary(result.summary, executions),
            items=[
                FlashPipelineItem(command=command, execution=execution)
                for command, execution in zip(
                    result.records,
                    executions,
                    strict=True,
                )
            ],
        )


def _aggregate_summary(
    model_summary: str,
    executions: list[FlashSkillResult],
) -> str:
    if not executions or all(item.status == "success" for item in executions):
        return model_summary
    succeeded = sum(item.status == "success" for item in executions)
    pending = sum(item.status == "pending_confirmation" for item in executions)
    failed = sum(item.status == "error" for item in executions)
    parts: list[str] = []
    if succeeded:
        parts.append(f"已完成 {succeeded} 项")
    if pending:
        parts.append(f"另有 {pending} 项需要你确认" if parts else f"有 {pending} 项需要你确认")
    if failed:
        parts.append(
            f"另有 {failed} 项未完成，请查看对应提示"
            if parts
            else f"有 {failed} 项未完成，请查看对应提示"
        )
    return "，".join(parts) + "。"
