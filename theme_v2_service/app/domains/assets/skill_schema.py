from copy import deepcopy
from datetime import datetime, timezone
from typing import Protocol

from app.domains.assets.schemas import UserSkillUpdate


class _SkillRevision(Protocol):
    global_skill_id: int | None
    schema_json: dict
    updated_at: datetime


class SkillUpdateConflict(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def _utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def _properties(schema: dict) -> dict[str, dict]:
    raw = schema.get("properties")
    if not isinstance(raw, dict):
        return {}
    return {
        str(key): value
        for key, value in raw.items()
        if isinstance(value, dict)
    }


def normalized_custom_skill_schema(schema: dict) -> dict:
    """Return an editable custom-Skill schema with no required fields."""
    normalized = deepcopy(schema)
    normalized["type"] = "object"
    normalized["required"] = []
    normalized.setdefault("additionalProperties", False)
    return normalized


def validate_custom_skill_update(
    skill: _SkillRevision,
    command: UserSkillUpdate,
) -> None:
    protected_fields = {
        "display_name",
        "description",
        "domain",
        "schema_definition",
        "chat_starters",
        "queryable_fields",
    }
    if skill.global_skill_id is not None and protected_fields.intersection(
        command.model_fields_set
    ):
        raise SkillUpdateConflict(
            "system_skill_protected",
            "系统 Skill 不支持修改名称、说明或字段结构",
        )

    if command.expected_updated_at is not None and _utc_naive(
        skill.updated_at
    ) != _utc_naive(command.expected_updated_at):
        raise SkillUpdateConflict(
            "stale_skill_revision",
            "Skill 已在其他位置发生变化，请刷新后重试",
        )

    if command.schema_definition is None:
        return

    current = _properties(skill.schema_json)
    proposed = _properties(command.schema_definition)
    for key, definition in current.items():
        replacement = proposed.get(key)
        if replacement is None:
            raise SkillUpdateConflict(
                "field_removed",
                f"字段 {key} 不能删除，可以将它隐藏",
            )
        if definition.get("type") != replacement.get("type"):
            raise SkillUpdateConflict(
                "field_type_changed",
                f"字段 {key} 的类型不能修改",
            )
        if definition.get("format") != replacement.get("format"):
            raise SkillUpdateConflict(
                "field_format_changed",
                f"字段 {key} 的格式不能修改",
            )

    if not any(not bool(definition.get("x-hidden")) for definition in proposed.values()):
        raise SkillUpdateConflict(
            "no_visible_fields",
            "至少保留一个可见字段",
        )
