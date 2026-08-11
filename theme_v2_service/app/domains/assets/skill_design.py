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

_ROUTING_LIST_LIMITS = {
    "aliases": 8,
    "include": 8,
    "exclude": 8,
    "positive_examples": 6,
    "negative_examples": 6,
}

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


def _bounded_unique_strings(value, *, limit: int, max_length: int = 160) -> list[str]:
    if not isinstance(value, list):
        return []
    output: list[str] = []
    seen: set[str] = set()
    for item in value:
        text = str(item or "").strip()[:max_length]
        folded = text.casefold()
        if not text or folded in seen:
            continue
        seen.add(folded)
        output.append(text)
        if len(output) >= limit:
            break
    return output


def _normalize_routing_profile(raw, description: str) -> dict:
    source = raw if isinstance(raw, dict) else {}
    intent = str(source.get("intent") or description).strip()[:500]
    if not intent:
        intent = description.strip()[:500]
    return {
        "intent": intent,
        **{
            key: _bounded_unique_strings(source.get(key), limit=limit)
            for key, limit in _ROUTING_LIST_LIMITS.items()
        },
    }


def _answer_parts(answer) -> tuple[str, str]:
    if isinstance(answer, dict):
        return str(answer.get("key") or ""), str(answer.get("value") or "")
    return str(getattr(answer, "key", "") or ""), str(
        getattr(answer, "value", "") or ""
    )


def _normalize_question(raw) -> dict:
    if not isinstance(raw, dict):
        raise InvalidSkillDraft("skill designer returned an invalid question")
    raw_type = str(raw.get("type") or "choice").strip().lower()
    default_key = "recording_content" if raw_type == "text" else "recording_scope"
    key = str(raw.get("key") or default_key).strip().lower()
    key = re.sub(r"[^a-z0-9_]+", "_", key).strip("_")
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", key):
        key = "recording_scope"
    prompt = str(raw.get("prompt") or raw.get("question") or "").strip()[:240]
    is_content = any(token in key for token in ("content", "field", "information")) or any(
        token in prompt for token in ("哪些内容", "哪些信息", "记录什么", "保留什么")
    )
    options = _bounded_unique_strings(
        raw.get("options"),
        limit=5 if is_content else 3,
        max_length=80,
    )
    options = [option for option in options if option != "其他"]
    if is_content and len(options) < 2:
        options = ["类型", "时长", "地点", "感受"]
    if not prompt or len(options) < 2:
        raise InvalidSkillDraft("skill designer returned an invalid question")
    placeholder = str(raw.get("placeholder") or "").strip()[:160]
    if is_content or not placeholder:
        placeholder = "请输入其他想记录的内容" if is_content else "请选择记录范围"
    return {
        "key": key,
        "prompt": prompt,
        "type": "choice",
        "multiple": is_content,
        "options": options,
        "placeholder": placeholder,
    }


def _recording_content_question() -> dict:
    return {
        "key": "recording_content",
        "prompt": "每次记录时，你最想保留哪些内容？",
        "type": "choice",
        "multiple": True,
        "options": ["类型", "时长", "地点", "感受"],
        "placeholder": "请输入其他想记录的内容",
    }


def _asks_for_recording_content(question: dict) -> bool:
    key = str(question.get("key") or "").lower()
    prompt = str(question.get("prompt") or "")
    return (
        any(token in key for token in ("content", "field", "information"))
        or any(token in prompt for token in ("哪些内容", "哪些信息", "记录什么", "保留什么"))
    )


def _normalize_design_step(raw: dict, description: str, *, answers=None) -> dict:
    if not isinstance(raw, dict):
        raise InvalidSkillDraft("skill designer returned invalid JSON")
    answered = any(value.strip() for _, value in map(_answer_parts, answers or []))
    raw_questions = raw.get("questions")
    if isinstance(raw_questions, list) and raw_questions:
        if answered:
            raise InvalidSkillDraft("skill designer returned question after scope confirmation")
        questions = [_normalize_question(item) for item in raw_questions[:2]]
        if not any(_asks_for_recording_content(question) for question in questions):
            if len(questions) == 2:
                questions[-1] = _recording_content_question()
            else:
                questions.append(_recording_content_question())
        return {"questions": questions}
    draft_source = raw.get("draft")
    if not isinstance(draft_source, dict):
        draft_source = raw
    return {"draft": _normalize_draft(draft_source, description)}


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
    routing_profile = _normalize_routing_profile(
        raw.get("routing_profile"),
        str(raw.get("description") or description),
    )
    skill_description = str(
        raw.get("description") or routing_profile["intent"] or description
    ).strip()[:1000]
    return {
        "name": name,
        "display_name": display_name,
        "description": skill_description,
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
        "routing_profile": routing_profile,
    }


async def design_skill_step(description: str, answers=None) -> dict:
    settings = get_settings()
    if not settings.capture_agent_enabled or not settings.capture_agent_model:
        raise SkillDesignUnavailable("skill designer is not configured")
    answer_lines = [
        f"- {key}: {value}"
        for key, value in map(_answer_parts, answers or [])
        if value.strip()
    ]
    user_description = description.strip()
    if answer_lines:
        user_description += "\n用户补充：\n" + "\n".join(answer_lines)
    messages = [
        {
            "role": "system",
            "content": (
                "你是 Eureka Skill Builder。根据用户想记录的内容设计一个可编辑技能。"
                "只返回 JSON 对象。先判断用户是否已经明确了实际要记录的对象和范围。"
                "如果一个简短描述存在会改变路由或字段的实质歧义，只返回 questions，"
                "一次返回两个简短问题：第一个是单选 choice 范围问题，带 2 到 3 个自然语言"
                "选项；第二个是多选 choice 内容问题，带 2 到 5 个与记录目标有关的简短"
                "字段标签，询问用户每次最想保留哪些信息。不要在 options 中返回‘其他’，"
                "客户端会统一添加。"
                "例如‘喝水记录’"
                "应确认仅白水还是全部无酒精饮品，‘跳舞记录’应确认用户主要想记录每次"
                "实际训练、课程还是比赛；同时都要询问想记录的内容，例如舞种、时长、"
                "地点或感受。不要询问频率、颜色、图标或技术字段。"
                "问题必须严格使用这个结构："
                '{"questions":[{"key":"recording_scope","prompt":"...",'
                '"type":"choice","multiple":false,"options":["...","..."]},'
                '{"key":"recording_content","prompt":"每次记录时，你最想保留哪些内容？",'
                '"type":"choice","multiple":true,"options":["...","..."],'
                '"placeholder":"请输入其他想记录的内容"}]}。'
                "如果用户补充区已经包含回答，不得再次返回问题，必须返回 draft。"
                "draft 包含 name、display_name、description、payload_schema、"
                "render_spec、sample_payload、routing_profile。name 和字段 key 使用"
                "小写英文 snake_case。description 用一句话准确说明记录目标。"
                "payload_schema 是字段映射，每个字段必须含 type、label、description、"
                "required、long；required 必须为 false，所有字段默认可选；"
                "type 仅可为 string/number/integer/date/datetime/boolean。"
                "字段控制在 2 到 6 个。render_spec 至少含 icon、primary_field，"
                "icon 必须是一个语义匹配的 emoji，不能返回 fire、water、running 等英文图标名；"
                "primary_field 必须是 payload_schema 中的字段。routing_profile 必须包含"
                "intent、aliases、include、exclude、positive_examples、negative_examples；"
                "它描述何时应该路由到该 Skill，未来计划、购买行为和提醒行为应放入反例，"
                "不要把字段必填规则写入 routing_profile。不要输出 Markdown。"
            ),
        },
        {"role": "user", "content": user_description},
    ]
    kwargs = {
        "model": settings.capture_agent_model,
        "messages": messages,
        "response_format": {"type": "json_object"},
        "timeout": settings.capture_agent_timeout_seconds,
        "temperature": 0,
    }
    if settings.capture_agent_api_key:
        kwargs["api_key"] = settings.capture_agent_api_key
    try:
        response = await litellm.acompletion(**kwargs)
    except Exception as exc:
        raise SkillDesignUnavailable("skill designer unavailable") from exc
    return _normalize_design_step(
        _parse_json_object(_message_content(response)),
        description,
        answers=answers,
    )


async def design_skill_draft(description: str, answers=None) -> dict:
    """Compatibility helper for callers that require a completed draft."""

    result = await design_skill_step(description, answers)
    draft = result.get("draft")
    if not isinstance(draft, dict):
        raise InvalidSkillDraft("skill designer requires scope confirmation")
    return draft
