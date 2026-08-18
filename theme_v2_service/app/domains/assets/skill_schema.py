import re
from copy import deepcopy
from datetime import datetime, timezone
from typing import Protocol

from app.domains.assets.schemas import UserSkillUpdate


class _SkillRevision(Protocol):
    global_skill_id: int | None
    machine_name: str
    schema_json: dict
    updated_at: datetime


class SkillUpdateConflict(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


PROTECTED_SYSTEM_SKILL_NAMES = frozenset(
    {"todo", "expense", "contact", "notes", "event", "qa"}
)
_FIELD_KEY = re.compile(r"^[a-z][a-z0-9_]*$")
_SUPPORTED_TYPES = frozenset({"string", "number", "integer", "boolean", "array"})
_SUPPORTED_FORMATS = {
    "string": frozenset({"date", "date-time", "uuid", "email", "uri", "time"}),
    # Kept for backward compatibility with existing duration render specs.
    "number": frozenset({"duration"}),
    "integer": frozenset({"duration"}),
}


def _utc_naive(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def is_system_skill(skill: _SkillRevision) -> bool:
    return skill.global_skill_id is not None or (
        skill.machine_name.strip().lower() in PROTECTED_SYSTEM_SKILL_NAMES
    )


def _invalid(message: str) -> None:
    raise SkillUpdateConflict("invalid_skill_schema", message)


def _validate_field_definition(key: str, definition: object) -> None:
    if not _FIELD_KEY.fullmatch(key):
        _invalid(f"字段 ID {key} 必须使用 snake_case")
    if not isinstance(definition, dict):
        _invalid(f"字段 {key} 的定义必须是对象")
    field_type = definition.get("type")
    if field_type not in _SUPPORTED_TYPES:
        _invalid(f"字段 {key} 使用了不支持的类型")
    field_format = definition.get("format")
    if field_format is not None and field_format not in _SUPPORTED_FORMATS.get(
        field_type, frozenset()
    ):
        _invalid(f"字段 {key} 使用了不支持的格式")
    items = definition.get("items")
    if field_type == "array":
        if not isinstance(items, dict):
            _invalid(f"数组字段 {key} 必须声明 items 对象")
        item_type = items.get("type")
        if item_type not in _SUPPORTED_TYPES - {"array"}:
            _invalid(f"数组字段 {key} 使用了不支持的 items 类型")
        item_format = items.get("format")
        if item_format is not None and item_format not in _SUPPORTED_FORMATS.get(
            item_type, frozenset()
        ):
            _invalid(f"数组字段 {key} 使用了不支持的 items 格式")
    elif items is not None:
        _invalid(f"非数组字段 {key} 不能声明 items")


def _canonical_schema(schema: dict) -> dict:
    """Validate a complete JSON-schema shape or the legacy properties shorthand."""
    if not isinstance(schema, dict):
        _invalid("Skill schema 必须是对象")
    complete_keys = {"type", "properties", "required", "additionalProperties"}
    # Legacy clients send a properties map directly and may legitimately use
    # JSON Schema keywords as field IDs. A root keyword denotes the complete
    # shape only when its value is not itself a valid field definition.
    is_complete = any(
        key in schema
        and not (
            isinstance(schema[key], dict)
            and schema[key].get("type") in _SUPPORTED_TYPES
        )
        for key in complete_keys
    )
    if is_complete:
        if schema.get("type") != "object":
            _invalid("Skill schema 根节点 type 必须是 object")
        properties = schema.get("properties")
        if not isinstance(properties, dict):
            _invalid("Skill schema properties 必须是对象")
        required = schema.get("required", [])
        if not isinstance(required, list) or any(
            not isinstance(key, str) for key in required
        ):
            _invalid("Skill schema required 必须是字段 ID 数组")
        if len(set(required)) != len(required) or not set(required).issubset(
            properties
        ):
            _invalid("Skill schema required 只能引用已声明字段")
        additional = schema.get("additionalProperties", False)
        if not isinstance(additional, bool):
            _invalid("Skill schema additionalProperties 必须是布尔值")
        canonical = deepcopy(schema)
        canonical.setdefault("required", [])
        canonical.setdefault("additionalProperties", False)
    else:
        # Old clients send just the properties mapping. Continue accepting it.
        properties = schema
        canonical = {
            "type": "object",
            "properties": deepcopy(properties),
            "required": [],
            "additionalProperties": False,
        }
    for key, definition in properties.items():
        if not isinstance(key, str):
            _invalid("字段 ID 必须是字符串")
        _validate_field_definition(key, definition)
    return canonical


def validate_custom_skill_create_schema(schema: dict) -> None:
    _canonical_schema(schema)


def _properties(schema: dict) -> dict[str, dict]:
    return _canonical_schema(schema)["properties"]


def normalized_custom_skill_schema(schema: dict) -> dict:
    """Return an editable custom-Skill schema with no required fields."""
    normalized = _canonical_schema(schema)
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
    if is_system_skill(skill) and protected_fields.intersection(
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
    proposed_schema = _canonical_schema(command.schema_definition)
    proposed = proposed_schema["properties"]
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

    current_keys = set(current)
    new_required = set(proposed_schema.get("required") or []) - current_keys
    if new_required:
        raise SkillUpdateConflict(
            "new_field_required",
            "新增字段必须保持可选",
        )

    if not any(not bool(definition.get("x-hidden")) for definition in proposed.values()):
        raise SkillUpdateConflict(
            "no_visible_fields",
            "至少保留一个可见字段",
        )
