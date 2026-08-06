from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import datetime, timedelta
import re

from app.domains.capture.agent import (
    CaptureAgentResult,
    CaptureRecordCommand,
    CaptureSkill,
)
from app.domains.capture.dispatcher import FlashIntent
from app.domains.capture.execution import FlashExecutionItem, FlashExecutionResult
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


_PERIODS: tuple[tuple[str, str], ...] = (
    ("凌晨", "凌晨"),
    ("早上", "上午"),
    ("上午", "上午"),
    ("中午", "中午"),
    ("下午", "下午"),
    ("晚上", "晚上"),
    ("今晚", "晚上"),
    ("夜里", "晚上"),
)
_CLOCK_RE = re.compile(
    r"(凌晨|早上|上午|中午|下午|晚上|今晚)?\s*"
    r"(\d{1,2})(?:[:：点时])(\d{1,2})?分?"
)


def _temporal_hints(
    source_text: str,
    reference_datetime: datetime | None,
) -> tuple[str | None, datetime | None, datetime | None]:
    period = next(
        (value for keyword, value in _PERIODS if keyword in source_text),
        None,
    )
    if reference_datetime is None or reference_datetime.tzinfo is None:
        return period, None, None

    day = reference_datetime.date()
    date_mentioned = False
    for keyword, offset in (
        ("前天", -2),
        ("昨天", -1),
        ("昨日", -1),
        ("今天", 0),
        ("明天", 1),
        ("后天", 2),
    ):
        if keyword in source_text:
            day = (reference_datetime + timedelta(days=offset)).date()
            date_mentioned = True
            break

    occurred_at: datetime | None = None
    if any(word in source_text for word in ("刚刚", "刚才", "现在", "这会儿")):
        occurred_at = reference_datetime
    match = _CLOCK_RE.search(source_text)
    if match:
        hour = int(match.group(2))
        minute = int(match.group(3) or 0)
        marker = match.group(1) or ""
        if marker in {"下午", "晚上", "今晚"} and 1 <= hour <= 11:
            hour += 12
        elif marker == "凌晨" and hour == 12:
            hour = 0
        if 0 <= hour <= 23 and 0 <= minute <= 59:
            occurred_at = datetime(
                day.year,
                day.month,
                day.day,
                hour,
                minute,
                tzinfo=reference_datetime.tzinfo,
            )

    effective_at = None
    if date_mentioned and occurred_at is None:
        effective_at = datetime(
            day.year,
            day.month,
            day.day,
            tzinfo=reference_datetime.tzinfo,
        )
    return period, occurred_at, effective_at


def _custom_string_field(skill: CaptureSkill) -> str | None:
    schema = skill.schema_definition or {}
    properties = schema.get("properties")
    if not isinstance(properties, dict):
        properties = {
            name: value
            for name, value in schema.items()
            if isinstance(value, dict)
        }
    primary = schema.get("x-primary-field")
    if isinstance(primary, str):
        metadata = properties.get(primary)
        if isinstance(metadata, dict) and metadata.get("type", "string") == "string":
            return primary
    for name, metadata in properties.items():
        if isinstance(metadata, dict) and metadata.get("type", "string") == "string":
            return str(name)
    return None


def _item_from_skill_result(
    intent: FlashIntent,
    execution: FlashSkillResult,
) -> FlashExecutionItem:
    result = dict(execution.snapshot)
    if execution.snapshots:
        plural = {
            "asset": "assets",
            "event": "events",
            "contact": "contacts",
        }.get(execution.kind, "items")
        result[plural] = [dict(item) for item in execution.snapshots]
    if execution.candidates:
        result["candidates"] = [dict(item) for item in execution.candidates]
    entity_key = {
        "asset": "asset_id",
        "event": "event_id",
        "contact": "contact_id",
    }.get(execution.kind)
    if entity_key and execution.entity_id:
        result.setdefault(entity_key, execution.entity_id)
    if execution.action:
        result.setdefault("action", execution.action)
    return FlashExecutionItem(
        intent=intent,
        status=execution.status,
        result=result,
        error_code=(
            "intent_tool_rejected" if execution.status == "error" else None
        ),
    )


async def run_custom_skill_fallback(
    *,
    intent: FlashIntent,
    skill: CaptureSkill,
    executor: SessionToolExecutor,
    tool_call_prefix: str,
    reference_datetime: datetime | None = None,
) -> FlashExecutionItem:
    field = _custom_string_field(skill)
    if field is None:
        return FlashExecutionItem(
            intent=intent,
            status="error",
            error_code="intent_fallback_unsupported",
        )
    period, occurred_at, effective_at = _temporal_hints(
        intent.source_text,
        reference_datetime,
    )
    command = CaptureRecordCommand(
        kind="asset",
        operation="create",
        skill_machine_name=skill.machine_name,
        payload={field: intent.source_text},
        source_text=intent.source_text,
        domain=intent.domain,
        period=period,
        occurred_at=occurred_at,
        effective_at=effective_at,
    )
    execution = await execute_capture_command(
        command,
        executor,
        tool_call_prefix=tool_call_prefix,
    )
    return _item_from_skill_result(intent, execution)


async def run_event_to_todo_fallback(
    *,
    intent: FlashIntent,
    executor: SessionToolExecutor,
    tool_call_prefix: str,
    reference_datetime: datetime | None = None,
) -> FlashExecutionItem:
    todo_intent = intent.model_copy(update={"type": "todo"})
    period, occurred_at, effective_at = _temporal_hints(
        intent.source_text,
        reference_datetime,
    )
    due_date = occurred_at.isoformat() if occurred_at is not None else ""
    if not due_date and effective_at is not None:
        due_date = effective_at.date().isoformat()
    command = CaptureRecordCommand(
        kind="asset",
        operation="create",
        skill_machine_name="todo",
        payload={
            "title": intent.source_text,
            "content": intent.source_text,
            "due_date": due_date,
        },
        source_text=intent.source_text,
        domain=intent.domain,
        period=period,
        occurred_at=occurred_at,
    )
    execution = await execute_capture_command(
        command,
        executor,
        tool_call_prefix=tool_call_prefix,
    )
    return _item_from_skill_result(todo_intent, execution)


def aggregate_execution(
    items: list[FlashExecutionItem] | tuple[FlashExecutionItem, ...],
    *,
    usage_tokens: int = 0,
) -> FlashExecutionResult:
    stable_items = tuple(items)
    succeeded = sum(item.status == "success" for item in stable_items)
    pending = sum(item.status == "pending_confirmation" for item in stable_items)
    failed = sum(item.status == "error" for item in stable_items)
    replies = [
        str(item.result.get("answer") or "").strip()
        for item in stable_items
        if item.status == "reply"
    ]
    replies = [reply for reply in replies if reply]

    parts: list[str] = []
    if succeeded:
        parts.append(f"已完成 {succeeded} 项")
    if pending:
        parts.append(
            f"另有 {pending} 项需要确认" if parts else f"有 {pending} 项需要确认"
        )
    if failed:
        parts.append(f"另有 {failed} 项未完成" if parts else f"有 {failed} 项未完成")
    summary = "，".join(parts) + ("。" if parts else "")
    reply_text = "\n\n".join(replies)
    if reply_text:
        summary = f"{summary}\n\n{reply_text}" if summary else reply_text
    if not summary:
        summary = "本次闪念未识别到可保存的内容。"

    warnings = tuple(
        dict.fromkeys(
            item.error_code
            for item in stable_items
            if item.status == "error" and item.error_code
        )
    )
    return FlashExecutionResult(
        summary=summary,
        items=stable_items,
        warnings=warnings,
        usage_tokens=usage_tokens,
    )
