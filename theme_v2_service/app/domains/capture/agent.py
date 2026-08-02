from __future__ import annotations

from datetime import date, datetime
from typing import Any, Literal, Protocol

from pydantic import BaseModel, Field, model_validator

from app.db.models import UserSkill


BASELINE_CAPTURE_SKILL_NAMES = {
    "todo",
    "expense",
    "contact",
    "idea",
    "notes",
    "misc",
}


class CaptureOutputError(Exception):
    pass


class RetryableCaptureAgentError(Exception):
    pass


class PermanentCaptureAgentError(Exception):
    pass


class CaptureSkill(BaseModel):
    machine_name: str
    display_name: str
    description: str | None = None
    schema_definition: dict = Field(default_factory=dict)
    enabled: bool = True


class CaptureAgentRequest(BaseModel):
    transcript: str = Field(min_length=1)
    local_date: date
    skills: list[CaptureSkill]


class CaptureRecordCommand(BaseModel):
    kind: Literal["asset", "event"]
    skill_machine_name: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    effective_at: datetime | None = None
    title: str | None = None
    description: str | None = None
    location: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    all_day: bool = False
    attendees: list[str] = Field(default_factory=list, max_length=50)

    @model_validator(mode="after")
    def validate_kind_shape(self) -> "CaptureRecordCommand":
        if self.kind == "asset":
            if not (self.skill_machine_name or "").strip():
                raise ValueError("asset skill_machine_name is required")
            if any(
                value is not None
                for value in (
                    self.title,
                    self.description,
                    self.location,
                    self.start_at,
                    self.end_at,
                )
            ) or self.all_day or self.attendees:
                raise ValueError("asset command contains event fields")
            if self.effective_at is not None and self.effective_at.tzinfo is None:
                raise ValueError("effective_at must include a timezone")
            return self

        if self.skill_machine_name is not None:
            raise ValueError("event command must not name an asset skill")
        if self.payload:
            raise ValueError("event command payload must be empty")
        if not (self.title or "").strip():
            raise ValueError("event title is required")
        if self.start_at is None or self.end_at is None:
            raise ValueError("event start_at and end_at are required")
        if self.start_at.tzinfo is None or self.end_at.tzinfo is None:
            raise ValueError("event timestamps must include a timezone")
        if self.end_at <= self.start_at:
            raise ValueError("end_at must be after start_at")
        if self.effective_at is not None:
            raise ValueError("event command must not set effective_at")
        self.attendees = list(
            dict.fromkeys(name.strip() for name in self.attendees if name.strip())
        )
        return self


class CaptureAgentResult(BaseModel):
    summary: str = Field(min_length=1, max_length=2000)
    records: list[CaptureRecordCommand] = Field(default_factory=list, max_length=20)


class CaptureAgentProvider(Protocol):
    async def organize(
        self,
        *,
        transcript: str,
        local_date: date,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult: ...


class UnavailableCaptureAgentProvider:
    async def organize(
        self,
        *,
        transcript: str,
        local_date: date,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult:
        raise PermanentCaptureAgentError("capture agent is not configured")


def capture_skill_from_model(skill: UserSkill) -> CaptureSkill:
    schema = skill.schema_json or {}
    enabled = skill.machine_name in BASELINE_CAPTURE_SKILL_NAMES or (
        schema.get("x-capture-enabled") is True
    )
    return CaptureSkill(
        machine_name=skill.machine_name,
        display_name=skill.display_name,
        description=skill.description,
        schema_definition=schema,
        enabled=enabled,
    )


def _matches_type(value: Any, expected: str) -> bool:
    if expected == "string":
        return isinstance(value, str)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "null":
        return value is None
    return False


def _validate_value(value: Any, schema: dict, path: str) -> None:
    expected = schema.get("type")
    if isinstance(expected, list):
        if not any(_matches_type(value, item) for item in expected):
            raise CaptureOutputError(f"{path} has invalid type")
    elif isinstance(expected, str) and not _matches_type(value, expected):
        raise CaptureOutputError(f"{path} has invalid type")
    if "enum" in schema and value not in schema["enum"]:
        raise CaptureOutputError(f"{path} is not an allowed value")
    if isinstance(value, list) and isinstance(schema.get("items"), dict):
        for index, item in enumerate(value):
            _validate_value(item, schema["items"], f"{path}[{index}]")


def _validate_payload(payload: dict[str, Any], schema: dict) -> None:
    if schema.get("type", "object") != "object":
        raise CaptureOutputError("skill schema root must be an object")
    properties = schema.get("properties")
    shorthand = not isinstance(properties, dict)
    if shorthand:
        properties = {
            name: definition
            for name, definition in schema.items()
            if not name.startswith("x-") and isinstance(definition, dict)
        }
    if not isinstance(properties, dict) or not properties:
        raise CaptureOutputError("skill schema properties are required")
    required = schema.get("required") or []
    if not isinstance(required, list):
        raise CaptureOutputError("skill schema required must be a list")
    missing = [name for name in required if name not in payload]
    if missing:
        raise CaptureOutputError(f"asset payload missing required field: {missing[0]}")
    allows_additional = schema.get("additionalProperties", not shorthand)
    if allows_additional is False:
        unknown = [name for name in payload if name not in properties]
        if unknown:
            raise CaptureOutputError(f"asset payload has unknown field: {unknown[0]}")
    for name, value in payload.items():
        field_schema = properties.get(name)
        if isinstance(field_schema, dict):
            _validate_value(value, field_schema, f"payload.{name}")


def validate_capture_result(
    result: CaptureAgentResult,
    skills: list[CaptureSkill],
) -> CaptureAgentResult:
    enabled = {
        skill.machine_name: skill
        for skill in skills
        if skill.enabled
    }
    for command in result.records:
        if command.kind != "asset":
            continue
        skill = enabled.get(command.skill_machine_name or "")
        if skill is None:
            raise CaptureOutputError(
                f"unknown or disabled skill: {command.skill_machine_name}"
            )
        _validate_payload(command.payload, skill.schema_definition)
    return result
