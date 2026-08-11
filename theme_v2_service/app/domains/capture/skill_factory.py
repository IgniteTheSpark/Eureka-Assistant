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
_BUILTIN_OPERATION_TOOLS: dict[str, dict[str, frozenset[str]]] = {
    "todo": {
        "create": frozenset({"tool_create_todo"}),
        "query": frozenset({"tool_query_asset"}),
        "update": frozenset({"tool_query_asset", "tool_update_asset"}),
        "delete": frozenset({"tool_query_asset", "tool_delete_asset"}),
    },
    "event": {
        "create": frozenset(
            {"tool_create_event", "tool_query_contact", "tool_add_event_attendee"}
        ),
        "query": frozenset({"tool_query_event"}),
        "update": frozenset(
            {
                "tool_query_event",
                "tool_update_event",
                "tool_query_contact",
                "tool_add_event_attendee",
                "tool_update_event_attendee",
                "tool_delete_event_attendee",
            }
        ),
        "delete": frozenset({"tool_query_event", "tool_delete_event"}),
    },
    "expense": {
        "create": frozenset({"tool_create_asset"}),
        "query": frozenset({"tool_query_asset"}),
        "update": frozenset({"tool_query_asset", "tool_update_asset"}),
        "delete": frozenset({"tool_query_asset", "tool_delete_asset"}),
    },
    "contact": {
        "create": frozenset({"tool_create_contact"}),
        "query": frozenset({"tool_query_contact"}),
        "update": frozenset({"tool_update_contact"}),
        "delete": frozenset({"tool_delete_contact"}),
    },
    "notes": {
        "create": frozenset({"tool_create_note"}),
        "query": frozenset({"tool_query_asset"}),
        "update": frozenset({"tool_query_asset", "tool_update_asset"}),
        "delete": frozenset({"tool_query_asset", "tool_delete_asset"}),
    },
    "qa": {
        "answer": frozenset({"tool_query_asset"}),
        "query": frozenset({"tool_query_asset"}),
    },
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


def _compact_catalog_text(value: Any, *, limit: int = 240) -> str:
    return " ".join(str(value or "").split())[:limit]


def _catalog_list(value: Any) -> str:
    if not isinstance(value, list):
        return ""
    output: list[str] = []
    seen: set[str] = set()
    for item in value:
        text = _compact_catalog_text(item, limit=120)
        folded = text.casefold()
        if not text or folded in seen:
            continue
        seen.add(folded)
        output.append(text)
        if len(output) >= 8:
            break
    return " / ".join(output)


def _custom_field_summary(schema: dict[str, Any]) -> str:
    fields: list[str] = []
    for name, metadata in _schema_properties(schema).items():
        if not isinstance(metadata, dict):
            continue
        label = _compact_catalog_text(
            metadata.get("title") or metadata.get("label") or name,
            limit=80,
        )
        field_type = _compact_catalog_text(metadata.get("type") or "string", limit=32)
        description = _compact_catalog_text(metadata.get("description"), limit=160)
        detail = f"{label}({name}, {field_type})"
        if description:
            detail += f": {description}"
        fields.append(detail)
        if len(fields) >= 8:
            break
    return "；".join(fields)


def _custom_skill_hint(skills: Iterable[CaptureSkill | dict[str, Any]]) -> str:
    lines: list[str] = []
    for skill in skills:
        machine_name = str(_value(skill, "machine_name", "") or "").strip()
        if not machine_name or machine_name in _BUILTIN_TOOL_ALLOWLIST:
            continue
        if _value(skill, "enabled", True) is False:
            continue
        display_name = _compact_catalog_text(
            _value(skill, "display_name", machine_name) or machine_name,
            limit=160,
        )
        description = _compact_catalog_text(_value(skill, "description", ""), limit=500)
        user_skill_id = _compact_catalog_text(_value(skill, "user_skill_id", ""), limit=100)
        schema = _value(skill, "schema_definition", None)
        if schema is None:
            schema = _value(skill, "schema", {})
        schema = schema if isinstance(schema, dict) else {}
        routing = schema.get("x-routing")
        routing = routing if isinstance(routing, dict) else {}
        intent = _compact_catalog_text(routing.get("intent") or description, limit=500)
        lines.append(f"- id=`{user_skill_id}`; machine=`{machine_name}`; display={display_name}")
        if intent:
            lines.append(f"  用途={intent}")
        for label, key in (
            ("别名", "aliases"),
            ("包含", "include"),
            ("排除", "exclude"),
            ("正例", "positive_examples"),
            ("反例", "negative_examples"),
        ):
            values = _catalog_list(routing.get(key))
            if values:
                lines.append(f"  {label}={values}")
        fields = _custom_field_summary(schema)
        if fields:
            lines.append(f"  字段={fields}")
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
        "外部产品动作归 qa。用户自定义 Skill 优先于 notes；当一段话明确是已经完成的"
        "历史事实时，也优先于模型误判的 todo。提醒、未来计划仍归 todo，用户自定义"
        "Skill 绝不覆盖 event/expense/contact。未来计划不得写入记录型自定义 Skill。"
        "每个 intent 必须明确 operation=create/query/update/delete/answer；"
        "记录事实用 create，读取或汇总已有信息用 query，纠正已有记录用 update，"
        "删除已有记录用 delete，普通知识问答用 answer。ordinal 与 intent_id 由运行时"
        "重写，不要依赖模型生成值。update/delete 可在用户明确给出 ID 时填写 target_id，"
        "或把明确名称写入 target_query；不得编造目标 ID。Contact update 还必须把"
        "用户明确说出的全部变更写入 contact_patch，只允许 name/phone/company/title/"
        "email/notes/socials，未提到的字段不得补充；其他类型的 contact_patch 必须为空。"
        "候选内容若与某个用户自定义 Skill 的 display、description 或 schema 语义一致，"
        "必须输出该 machine_name 和 custom_skill_id，不能只做字面连续匹配；例如动作、"
        "数量和对象之间可以夹有助词或数值。只有无法唯一匹配时才落 notes。\n\n"
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


def make_builtin_skill_agent(
    skill_name: str,
    *,
    operation: str = "create",
) -> FlashAgentDefinition:
    normalized = skill_name.strip().lower()
    operation_tools = _BUILTIN_OPERATION_TOOLS.get(normalized)
    if operation_tools is None:
        raise ValueError(f"unsupported flash skill: {skill_name}")
    allowed_tools = operation_tools.get(operation)
    if allowed_tools is None:
        raise ValueError(
            f"unsupported flash operation: {normalized}/{operation}"
        )
    runtime_contract = (
        f"\n\n---\n\nTheme V2 operation={operation}. "
        f"只允许调用: {', '.join(sorted(allowed_tools)) or '(无工具)'}。"
        "不得用其他 operation 的工具效果代替当前请求。"
        + (
            "输入中的 resolved_target.entity_id 是服务器已验证目标，"
            "必须原样作为 mutation ID；不得改选、猜测或新建。"
            if operation in {"update", "delete"}
            else ""
        )
    )
    return FlashAgentDefinition(
        name=f"{normalized}_skill",
        instruction=_load_instruction(f"flash-{normalized}-skill")
        + runtime_contract,
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


def make_custom_skill_agent(
    skill: CaptureSkill,
    *,
    operation: str = "create",
) -> FlashAgentDefinition:
    machine_name = skill.machine_name.strip()
    if not machine_name or machine_name in _BUILTIN_TOOL_ALLOWLIST:
        raise ValueError(f"not a custom flash skill: {skill.machine_name}")
    schema = dict(skill.schema_definition or {})
    fields = _field_documentation(schema)
    operation_rules = {
        "create": (
            f'调用 tool_create_asset,参数为 user_skill_name="{machine_name}",'
            f'user_skill_id="{skill.user_skill_id or ""}",'
            "payload=只含已出现字段的 JSON,并透传 intent 的 domain 与上述真实时间信息。"
        ),
        "query": (
            f'只调用 tool_query_asset 查询 user_skill_name="{machine_name}"。'
            "不得创建、修改或删除资产；回答必须来自真实查询结果。"
        ),
        "update": (
            "只可先查询并调用 tool_update_asset 更新已经确定的 asset_id。"
            "不得调用创建工具，目标不唯一时不得修改。"
        ),
        "delete": (
            "只可先查询并调用 tool_delete_asset 删除已经确定的 asset_id。"
            "不得调用创建工具，目标不唯一时不得删除。"
        ),
    }
    allowed_tools_by_operation = {
        "create": frozenset({"tool_create_asset"}),
        "query": frozenset({"tool_query_asset"}),
        "update": frozenset({"tool_query_asset", "tool_update_asset"}),
        "delete": frozenset({"tool_query_asset", "tool_delete_asset"}),
    }
    operation_rule = operation_rules.get(operation)
    allowed_tools = allowed_tools_by_operation.get(operation)
    if operation_rule is None or allowed_tools is None:
        raise ValueError(
            f"unsupported custom flash operation: {machine_name}/{operation}"
        )
    instruction = f"""
你是 Eureka 的「{skill.display_name}」记录 Skill。这个 Skill 只记录已经发生的事实,
不得把未来计划当成记录。输入会包含 source_text、完整 user_text、reference_datetime、
domain,以及可信执行上下文之外的普通文字。

当前 operation={operation}。

## 写入字段

所有字段在写入时都视为可选;schema 的 required 只用于最终领域校验,不能驱使你编造值。
{fields}

完整 schema(仅用于类型和含义指导):
{json.dumps(schema, ensure_ascii=False, sort_keys=True)}

## 规则

1. 只从 source_text 抽取用户明确提供的值。未提到的字段不要补、不要猜,也不要使用默认模板值。
   即使能从其他字段计算得到，也必须省略；空字符串、null、空列表或空对象也视为未提到，必须省略。
2. 明确钟点或「刚刚/现在/几分钟前」可传 occurred_at=带时区的 ISO8601;后者使用 reference_datetime。
3. 只有「上午/中午/下午/晚上/凌晨」时只传 period,不得编造 09:00、15:00 等钟点。
4. 只说日期而没有钟点时,可用 effective_at 的该日 00:00 作为日期锚点,但不要传 occurred_at。
5. 完全没说时间时不传 effective_at、occurred_at 或 period,让捕捉时间兜底。
6. {operation_rule} user_id/session_id/source_input_turn_id/tool_call_id
   由可信运行时注入,不得自行生成。
7. 只根据真实工具结果返回 JSON;工具失败时不得声称成功。
""".strip()
    return FlashAgentDefinition(
        name=f"{machine_name}_custom_skill",
        instruction=instruction,
        allowed_tools=allowed_tools,
    )
