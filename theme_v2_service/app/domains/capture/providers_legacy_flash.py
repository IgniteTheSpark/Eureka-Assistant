from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable
from datetime import datetime
from typing import Any

import litellm

from app.domains.capture.agent import (
    CaptureAgentResult,
    CaptureOutputError,
    CaptureRecordCommand,
    CaptureSkill,
    PermanentCaptureAgentError,
    RetryableCaptureAgentError,
    validate_capture_result,
)
from app.domains.capture.dispatcher import (
    FlashDispatchResult,
    FlashIntent,
    build_dispatcher_messages,
)
from app.domains.capture.intent_normalizer import normalize_intents


Completion = Callable[..., Awaitable[Any]]


class LiteLLMLegacyFlashProvider:
    def __init__(
        self,
        *,
        model: str,
        api_key: str | None,
        timeout_seconds: float,
        completion: Completion = litellm.acompletion,
    ) -> None:
        self.model = model
        self.api_key = api_key
        self.timeout_seconds = timeout_seconds
        self._completion = completion

    async def organize(
        self,
        *,
        transcript: str,
        reference_datetime: datetime,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult:
        normalized_transcript = transcript.strip()
        if not normalized_transcript:
            raise PermanentCaptureAgentError("capture transcript is empty")
        enabled = [skill for skill in skills if skill.enabled]
        custom = [
            {
                "machine_name": skill.machine_name,
                "display_name": skill.display_name,
                "description": skill.description,
                "schema": skill.schema_definition,
            }
            for skill in enabled
            if skill.machine_name
            not in {"todo", "expense", "contact", "notes", "event", "qa"}
        ]
        dispatched = await self._complete_model(
            messages=build_dispatcher_messages(
                transcript=normalized_transcript,
                reference_datetime=reference_datetime.isoformat(),
                custom_skills=custom,
            ),
            schema=FlashDispatchResult,
            schema_name="flash_dispatch_result",
        )
        intents = normalize_intents(
            FlashDispatchResult.model_validate(dispatched).intents,
            custom_skill_names={item["machine_name"] for item in custom},
        )
        if not intents:
            intents = [FlashIntent(type="notes", source_text=normalized_transcript)]
        results = await asyncio.gather(
            *[
                self._run_intent(
                    intent=intent,
                    transcript=normalized_transcript,
                    reference_datetime=reference_datetime,
                    skills=enabled,
                )
                for intent in intents
            ]
        )
        records = [record for result in results for record in result.records]
        summaries = list(
            dict.fromkeys(result.summary.strip() for result in results if result.summary.strip())
        )
        combined = CaptureAgentResult(
            summary=" ".join(summaries) or "已整理这条闪念。",
            records=records,
        )
        return validate_capture_result(combined, enabled)

    async def _run_intent(
        self,
        *,
        intent: FlashIntent,
        transcript: str,
        reference_datetime: datetime,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult:
        skill = next(
            (item for item in skills if item.machine_name == intent.type),
            None,
        )
        messages = _skill_messages(
            intent=intent,
            transcript=transcript,
            reference_datetime=reference_datetime,
            skill=skill,
        )
        payload = await self._complete_model(
            messages=messages,
            schema=CaptureAgentResult,
            schema_name="flash_skill_result",
        )
        try:
            result = CaptureAgentResult.model_validate(payload)
            _validate_intent_result(intent, result)
            return result
        except (CaptureOutputError, ValueError) as exc:
            raise RetryableCaptureAgentError(
                "flash skill returned incompatible output"
            ) from exc

    async def _complete_model(self, *, messages, schema, schema_name: str) -> dict:
        kwargs = {
            "model": self.model,
            "messages": messages,
            "response_format": _response_format(self.model, schema, schema_name),
            "timeout": self.timeout_seconds,
        }
        if self.api_key:
            kwargs["api_key"] = self.api_key
        try:
            response = await self._completion(**kwargs)
        except Exception as exc:
            raise RetryableCaptureAgentError("capture provider unavailable") from exc
        content = _message_content(response)
        try:
            decoded = json.loads(_strip_fence(content))
        except json.JSONDecodeError as exc:
            raise PermanentCaptureAgentError(
                "capture provider returned malformed JSON"
            ) from exc
        if not isinstance(decoded, dict):
            raise RetryableCaptureAgentError("capture provider returned non-object JSON")
        try:
            return schema.model_validate(decoded).model_dump(mode="json")
        except Exception as exc:
            raise RetryableCaptureAgentError(
                "capture provider returned incompatible JSON"
            ) from exc


def _skill_messages(
    *,
    intent: FlashIntent,
    transcript: str,
    reference_datetime: datetime,
    skill: CaptureSkill | None,
) -> list[dict[str, str]]:
    schema = skill.schema_definition if skill is not None else {}
    instruction = f"""
FLASH_SKILL_EXECUTOR
你处理一个已经分发好的 `{intent.type}` 原子意图。只抽取事实并输出 CaptureAgentResult JSON；不要调用工具，真正写入由后端执行。

通用规则：只使用 source_text 明说的事实；不得编造金额、日期、钟点、联系人字段。当前时间为 {reference_datetime.isoformat()}，时区 Asia/Shanghai。source_text 必须透传到 record。

- todo/expense/notes/自定义 Skill：kind=asset，skill_machine_name 必须是 `{intent.type}`，payload 遵守 schema={json.dumps(schema, ensure_ascii=False)}。新记录 operation=create 或省略；个人数据查询用 query；“改成/更正”用 update；删除用 delete。update/delete 不得编造 target_id，不知道 ID 时从原文提取 match_text；update 的 payload 只放 patch，query/delete 的 payload 为空。
- contact：kind=contact；operation=create_or_update 或 delete；name 是精确称呼；contact_patch 只放 phone/company/title/email/notes/socials。不要创建 contact asset。后端负责 0/1/多条精确同名决策。
- event：新建只有完整时段才输出 kind=event，并给 start_at/end_at；抽取明确参与者到 attendees。查询/修改/删除分别用 query/update/delete，并用 target_id 或 match_text/title 定位，不能编造 ID。
- qa：用 summary 给 1-3 句短答，records 必须为空。
- 自由文本 fallback 是 notes，不输出 idea/misc/other。
- 模糊时段写 period，明确钟点写 occurred_at；不要把“下午”猜成 15:00。
- 把 dispatcher 提供的 domain 透传到 record.domain；所有相对时间只以当前时间为基准。
""".strip()
    return [
        {"role": "system", "content": instruction},
        {
            "role": "user",
            "content": json.dumps(
                {
                    "intent": intent.model_dump(mode="json"),
                    "full_transcript": transcript,
                },
                ensure_ascii=False,
            ),
        },
    ]


def _validate_intent_result(intent: FlashIntent, result: CaptureAgentResult) -> None:
    if intent.type == "qa":
        if result.records:
            raise CaptureOutputError("qa intent must not create records")
        return
    if not result.records:
        raise CaptureOutputError("record intent returned no records")
    expected_kind = "contact" if intent.type == "contact" else "event" if intent.type == "event" else "asset"
    for record in result.records:
        if record.kind != expected_kind:
            raise CaptureOutputError("skill result kind does not match intent")
        if expected_kind == "asset" and record.skill_machine_name != intent.type:
            raise CaptureOutputError("skill result name does not match intent")


def _response_format(model: str, schema, schema_name: str) -> dict:
    if model.startswith("deepseek/"):
        return {"type": "json_object"}
    return {
        "type": "json_schema",
        "json_schema": {
            "name": schema_name,
            "strict": True,
            "schema": schema.model_json_schema(),
        },
    }


def _message_content(response: Any) -> str:
    try:
        content = response.choices[0].message.content
    except AttributeError:
        try:
            content = response["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise PermanentCaptureAgentError(
                "capture provider returned no message content"
            ) from exc
    if not isinstance(content, str) or not content.strip():
        raise PermanentCaptureAgentError("capture provider returned empty content")
    return content


def _strip_fence(content: str) -> str:
    normalized = content.strip()
    if not normalized.startswith("```"):
        return normalized
    first_line_end = normalized.find("\n")
    if first_line_end < 0 or not normalized.endswith("```"):
        return normalized
    return normalized[first_line_end + 1 : -3].strip()
