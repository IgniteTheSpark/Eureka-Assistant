from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.agent_runner import FlashAgentDefinition


SKILLS_DIR = Path(__file__).resolve().parents[3] / "skills"

_BUILTIN_TOOL_ALLOWLIST: dict[str, frozenset[str]] = {
    "todo": frozenset(
        {
            "tool_create_todo",
            "tool_query_asset",
            "tool_update_asset",
            "tool_delete_asset",
        }
    ),
    "event": frozenset(
        {
            "tool_create_event",
            "tool_query_event",
            "tool_update_event",
            "tool_delete_event",
            "tool_query_contact",
            "tool_add_event_attendee",
            "tool_update_event_attendee",
            "tool_delete_event_attendee",
        }
    ),
    "expense": frozenset(
        {
            "tool_create_asset",
            "tool_query_asset",
            "tool_update_asset",
            "tool_delete_asset",
        }
    ),
    "contact": frozenset(
        {
            "tool_create_contact",
            "tool_query_contact",
            "tool_update_contact",
            "tool_delete_contact",
        }
    ),
    "notes": frozenset({"tool_create_note"}),
    "qa": frozenset({"tool_query_asset"}),
}


def _load_instruction(folder: str) -> str:
    path = SKILLS_DIR / folder / "SKILL.md"
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError as exc:
        raise RuntimeError(f"missing Theme V2 Flash instruction: {folder}") from exc


def _value(skill: CaptureSkill | dict[str, Any], name: str, default: Any = None) -> Any:
    if isinstance(skill, dict):
        return skill.get(name, default)
    return getattr(skill, name, default)


def _custom_skill_hint(skills: Iterable[CaptureSkill | dict[str, Any]]) -> str:
    lines: list[str] = []
    for skill in skills:
        machine_name = str(_value(skill, "machine_name", "") or "").strip()
        if not machine_name or machine_name in _BUILTIN_TOOL_ALLOWLIST:
            continue
        if _value(skill, "enabled", True) is False:
            continue
        display_name = str(_value(skill, "display_name", machine_name) or machine_name)
        description = str(_value(skill, "description", "") or "")
        schema = _value(skill, "schema_definition", None)
        if schema is None:
            schema = _value(skill, "schema", {})
        lines.append(
            f"- `{machine_name}` / {display_name}: {description}; "
            f"schema={json.dumps(schema or {}, ensure_ascii=False, sort_keys=True)}"
        )
    if not lines:
        return "(无)"
    return "\n".join(lines)


def make_dispatcher_agent(
    custom_skills: Iterable[CaptureSkill | dict[str, Any]] = (),
) -> FlashAgentDefinition:
    from app.domains.capture.dispatcher import FlashDispatchResult

    instruction = "FLASH_DISPATCHER\n\n" + _load_instruction("flash-dispatcher")
    instruction += (
        "\n\n---\n\n"
        "## Theme V2 runtime contract (优先级最高)\n\n"
        "只允许 todo / event / expense / contact / notes / qa 和下列用户自定义 "
        "machine_name。不得输出 idea、misc、other 或 task;未知类型归 notes,"
        "外部产品动作归 qa。用户自定义 Skill 只压过 notes,绝不覆盖 "
        "todo/event/expense/contact。未来计划不得写入记录型自定义 Skill。\n\n"
        "### 用户自定义 Skill\n"
        f"{_custom_skill_hint(custom_skills)}\n\n"
        "### FlashDispatchResult JSON Schema (仅作输出指导)\n"
        f"{json.dumps(FlashDispatchResult.model_json_schema(), ensure_ascii=False, sort_keys=True)}\n\n"
        "只输出一个 JSON 对象。即使 provider 添加了前缀或代码围栏,运行时也会使用"
        "有界容错解析;不要依赖 markdown。"
    )
    return FlashAgentDefinition(
        name="flash_dispatcher",
        instruction=instruction,
        allowed_tools=frozenset(),
    )


def make_builtin_skill_agent(skill_name: str) -> FlashAgentDefinition:
    normalized = skill_name.strip().lower()
    allowed_tools = _BUILTIN_TOOL_ALLOWLIST.get(normalized)
    if allowed_tools is None:
        raise ValueError(f"unsupported flash skill: {skill_name}")
    return FlashAgentDefinition(
        name=f"{normalized}_skill",
        instruction=_load_instruction(f"flash-{normalized}-skill"),
        allowed_tools=allowed_tools,
    )


def _schema_properties(schema: dict[str, Any]) -> dict[str, Any]:
    properties = schema.get("properties")
    if isinstance(properties, dict):
        return properties
    return {
        name: value
        for name, value in schema.items()
        if isinstance(value, dict)
        and name not in {"required", "$defs", "definitions", "render_spec"}
    }


def _field_documentation(schema: dict[str, Any]) -> str:
    lines: list[str] = []
    for name, metadata in _schema_properties(schema).items():
        if not isinstance(metadata, dict):
            continue
        field_type = str(metadata.get("type") or "string")
        description = str(metadata.get("description") or "").strip()
        suffix = f": {description}" if description else ""
        lines.append(f"- `{name}` ({field_type}, 可选){suffix}")
    return "\n".join(lines) if lines else "(无可抽取字段)"


def make_custom_skill_agent(skill: CaptureSkill) -> FlashAgentDefinition:
    machine_name = skill.machine_name.strip()
    if not machine_name or machine_name in _BUILTIN_TOOL_ALLOWLIST:
        raise ValueError(f"not a custom flash skill: {skill.machine_name}")
    schema = dict(skill.schema_definition or {})
    fields = _field_documentation(schema)
    instruction = f"""
你是 Eureka 的「{skill.display_name}」记录 Skill。这个 Skill 只记录已经发生的事实,
不得把未来计划当成记录。输入会包含 source_text、完整 user_text、reference_datetime、
domain,以及可信执行上下文之外的普通文字。

## 写入字段

所有字段在写入时都视为可选;schema 的 required 只用于最终领域校验,不能驱使你编造值。
{fields}

完整 schema(仅用于类型和含义指导):
{json.dumps(schema, ensure_ascii=False, sort_keys=True)}

## 规则

1. 只从 source_text 抽取用户明确提供的值。未提到的字段不要补、不要猜,也不要使用默认模板值。
2. 明确钟点或「刚刚/现在/几分钟前」可传 occurred_at=带时区的 ISO8601;后者使用 reference_datetime。
3. 只有「上午/中午/下午/晚上/凌晨」时只传 period,不得编造 09:00、15:00 等钟点。
4. 只说日期而没有钟点时,可用 effective_at 的该日 00:00 作为日期锚点,但不要传 occurred_at。
5. 完全没说时间时不传 effective_at、occurred_at 或 period,让捕捉时间兜底。
6. 调用 tool_create_asset,参数为 user_skill_name="{machine_name}",payload=只含已出现字段的 JSON,
   并透传 intent 的 domain 与上述真实时间信息。user_id/session_id/source_input_turn_id/tool_call_id
   由可信运行时注入,不得自行生成。
7. 只根据真实工具结果返回 JSON;工具失败时不得声称成功。
""".strip()
    return FlashAgentDefinition(
        name=f"{machine_name}_custom_skill",
        instruction=instruction,
        allowed_tools=frozenset({"tool_create_asset"}),
    )
