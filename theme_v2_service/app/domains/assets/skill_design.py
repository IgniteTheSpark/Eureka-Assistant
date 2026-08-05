import hashlib
import json
import re

import litellm

from app.config import get_settings


class SkillDesignUnavailable(RuntimeError):
    pass


class InvalidSkillDraft(RuntimeError):
    pass


_FIELD_TYPES = {"string", "number", "integer", "date", "datetime", "boolean"}

_ICON_ALIASES = {
    "fire": "🔥",
    "flame": "🔥",
    "water": "💧",
    "drop": "💧",
    "water_drop": "💧",
    "run": "🏃",
    "running": "🏃",
    "directions_run": "🏃",
    "expense": "💳",
    "payment": "💳",
    "credit_card": "💳",
    "calendar": "📅",
    "event": "📅",
    "todo": "📋",
    "task": "📋",
    "checklist": "📋",
    "note": "✍️",
    "notes": "✍️",
    "contact": "👤",
    "person": "👤",
    "food": "🍽️",
    "meal": "🍽️",
    "restaurant": "🍽️",
}


def _normalize_icon(value) -> str:
    icon = str(value or "").strip()
    if not icon:
        return "•"
    alias = re.sub(r"[\s-]+", "_", icon.lower())
    return _ICON_ALIASES.get(alias, icon[:8])


def _parse_json_object(content: str) -> dict:
    text = (content or "").strip()
    candidates = [text]
    if "{" in text and "}" in text:
        candidates.append(text[text.find("{") : text.rfind("}") + 1])
    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
        except (TypeError, ValueError):
            continue
        if isinstance(parsed, dict):
            return parsed
    raise InvalidSkillDraft("skill designer returned invalid JSON")


def _message_content(response) -> str:
    try:
        content = response.choices[0].message.content
    except AttributeError:
        try:
            content = response["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as exc:
            raise InvalidSkillDraft("skill designer returned no content") from exc
    if not isinstance(content, str) or not content.strip():
        raise InvalidSkillDraft("skill designer returned no content")
    return content


def _normalize_draft(raw: dict, description: str) -> dict:
    schema = raw.get("payload_schema")
    if not isinstance(schema, dict) or not schema:
        raise InvalidSkillDraft("skill draft has no fields")
    normalized_schema = {}
    for key, value in schema.items():
        if not isinstance(key, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", key):
            raise InvalidSkillDraft("skill draft has an invalid field key")
        metadata = value if isinstance(value, dict) else {}
        field_type = str(metadata.get("type") or "string")
        if field_type not in _FIELD_TYPES:
            field_type = "string"
        normalized_schema[key] = {
            **metadata,
            "type": field_type,
            "label": str(metadata.get("label") or key)[:80],
            "description": str(metadata.get("description") or "")[:500],
            # A custom Skill describes what may be captured; it does not make
            # every spoken Flash satisfy a form contract. Importance belongs
            # in presentation metadata, never a hard Agent-write prerequisite.
            "required": False,
            "long": metadata.get("long") is True,
        }
    name = str(raw.get("name") or "").strip().lower()
    if not re.fullmatch(r"[a-z][a-z0-9_]{1,99}", name):
        digest = hashlib.sha256(description.encode("utf-8")).hexdigest()[:12]
        name = f"custom_{digest}"
    display_name = str(raw.get("display_name") or description).strip()[:160]
    if not display_name:
        display_name = "自定义记录"
    render_spec = raw.get("render_spec")
    if not isinstance(render_spec, dict):
        render_spec = {}
    primary = str(render_spec.get("primary_field") or "")
    if primary not in normalized_schema:
        primary = next(iter(normalized_schema))
    return {
        "name": name,
        "display_name": display_name,
        "payload_schema": normalized_schema,
        "render_spec": {
            "card_layout": "horizontal",
            "accent_color": str(render_spec.get("accent_color") or "gray"),
            **render_spec,
            "icon": _normalize_icon(render_spec.get("icon")),
            "primary_field": primary,
        },
        "sample_payload": raw.get("sample_payload")
        if isinstance(raw.get("sample_payload"), dict)
        else {},
        "chat_starters": raw.get("chat_starters")
        if isinstance(raw.get("chat_starters"), list)
        else [],
    }


async def design_skill_draft(description: str, answers=None) -> dict:
    settings = get_settings()
    if not settings.capture_agent_enabled or not settings.capture_agent_model:
        raise SkillDesignUnavailable("skill designer is not configured")
    answer_lines = [
        f"- {answer.key}: {answer.value}"
        for answer in (answers or [])
        if answer.value.strip()
    ]
    user_description = description.strip()
    if answer_lines:
        user_description += "\n用户补充：\n" + "\n".join(answer_lines)
    messages = [
        {
            "role": "system",
            "content": (
                "你是 Eureka Skill Builder。根据用户想记录的内容设计一个可编辑技能。"
                "只返回 JSON 对象，包含 name、display_name、payload_schema、"
                "render_spec、sample_payload。name 和字段 key 使用小写英文 snake_case。"
                "payload_schema 是字段映射，每个字段必须含 type、label、description、"
                "required、long；required 必须为 false，所有字段默认可选；"
                "type 仅可为 string/number/integer/date/datetime/boolean。"
                "字段控制在 2 到 6 个。render_spec 至少含 icon、primary_field，"
                "icon 必须是一个语义匹配的 emoji，不能返回 fire、water、running 等英文图标名；"
                "primary_field 必须是 payload_schema 中的字段。不要输出 Markdown。"
            ),
        },
        {"role": "user", "content": user_description},
    ]
    kwargs = {
        "model": settings.capture_agent_model,
        "messages": messages,
        "response_format": {"type": "json_object"},
        "timeout": settings.capture_agent_timeout_seconds,
    }
    if settings.capture_agent_api_key:
        kwargs["api_key"] = settings.capture_agent_api_key
    try:
        response = await litellm.acompletion(**kwargs)
    except Exception as exc:
        raise SkillDesignUnavailable("skill designer unavailable") from exc
    return _normalize_draft(_parse_json_object(_message_content(response)), description)
