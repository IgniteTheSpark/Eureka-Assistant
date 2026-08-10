from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Protocol

from pydantic import BaseModel, Field, model_validator

from app.db.models import UserSkill
from app.domains.assets.validation import (
    AssetPayloadInvalid,
    AssetWriteProfile,
    validate_asset_payload,
)


BASELINE_CAPTURE_SKILL_NAMES = {
    "todo",
    "expense",
    "contact",
    "notes",
}


class CaptureOutputError(Exception):
    pass


class RetryableCaptureAgentError(Exception):
    pass


class PermanentCaptureAgentError(Exception):
    pass


class CaptureSkill(BaseModel):
    user_skill_id: str | None = None
    machine_name: str
    display_name: str
    description: str | None = None
    schema_definition: dict = Field(default_factory=dict)
    enabled: bool = True


class CaptureAgentRequest(BaseModel):
    transcript: str = Field(min_length=1)
    reference_datetime: datetime
    skills: list[CaptureSkill]


class CaptureRecordCommand(BaseModel):
    kind: Literal["asset", "event", "contact"]
    skill_machine_name: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    effective_at: datetime | None = None
    source_text: str = Field(default="", max_length=4000)
    period: Literal["凌晨", "上午", "中午", "下午", "晚上"] | None = None
    occurred_at: datetime | None = None
    title: str | None = None
    description: str | None = None
    location: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    all_day: bool = False
    attendees: list[str] = Field(default_factory=list, max_length=50)
    operation: Literal[
        "create",
        "create_or_update",
        "query",
        "update",
        "delete",
    ] | None = None
    target_id: str | None = Field(default=None, max_length=64)
    match_text: str | None = Field(default=None, max_length=500)
    domain: str | None = Field(default=None, max_length=64)
    name: str | None = Field(default=None, max_length=320)
    contact_patch: dict[str, Any] = Field(default_factory=dict)

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
            if self.operation == "create_or_update":
                raise ValueError("asset command does not support create_or_update")
            if self.name is not None or self.contact_patch:
                raise ValueError("asset command contains contact fields")
            operation = self.operation or "create"
            if operation in {"update", "delete"} and not (
                (self.target_id or "").strip() or (self.match_text or "").strip()
            ):
                raise ValueError(
                    "asset update/delete requires target_id or match_text"
                )
            if operation == "update" and not self.payload:
                raise ValueError("asset update requires payload patch")
            if operation in {"query", "delete"} and self.payload:
                raise ValueError("asset query/delete payload must be empty")
            for name, value in (
                ("effective_at", self.effective_at),
                ("occurred_at", self.occurred_at),
            ):
                if value is not None and value.tzinfo is None:
                    raise ValueError(f"{name} must include a timezone")
            return self

        if self.kind == "contact":
            if self.skill_machine_name is not None or self.payload:
                raise ValueError("contact command must not contain asset fields")
            if any(
                value is not None
                for value in (
                    self.effective_at,
                    self.occurred_at,
                    self.title,
                    self.description,
                    self.location,
                    self.start_at,
                    self.end_at,
                )
            ) or self.period is not None or self.all_day or self.attendees:
                raise ValueError("contact command contains non-contact fields")
            if self.operation not in {"create_or_update", "delete"}:
                raise ValueError("contact operation is required")
            if self.target_id is not None or self.match_text is not None:
                raise ValueError("contact command contains generic target fields")
            self.name = (self.name or "").strip()
            if not self.name:
                raise ValueError("contact name is required")
            allowed = {"phone", "company", "title", "email", "notes", "socials"}
            unknown = set(self.contact_patch) - allowed
            if unknown:
                raise ValueError(
                    f"contact patch contains unknown fields: {sorted(unknown)}"
                )
            if self.operation == "delete" and self.contact_patch:
                raise ValueError("delete contact command must not contain a patch")
            return self

        if self.skill_machine_name is not None:
            raise ValueError("event command must not name an asset skill")
        if self.payload:
            raise ValueError("event command payload must be empty")
        operation = self.operation or "create"
        if operation == "create_or_update":
            raise ValueError("event command does not support create_or_update")
        if operation == "create":
            if not (self.title or "").strip():
                raise ValueError("event title is required")
            if self.start_at is None or self.end_at is None:
                raise ValueError("event start_at and end_at are required")
        if operation in {"update", "delete"} and not (
            (self.target_id or "").strip()
            or (self.match_text or "").strip()
            or (self.title or "").strip()
        ):
            raise ValueError("event update/delete requires a target")
        if operation == "update" and not any(
            value is not None
            for value in (
                self.title,
                self.description,
                self.location,
                self.start_at,
                self.end_at,
            )
        ):
            raise ValueError("event update requires a patch")
        for name, value in (("start_at", self.start_at), ("end_at", self.end_at)):
            if value is not None and value.tzinfo is None:
                raise ValueError(f"event {name} must include a timezone")
        if self.start_at is not None and self.end_at is not None:
            if self.end_at <= self.start_at:
                raise ValueError("end_at must be after start_at")
        if self.effective_at is not None:
            raise ValueError("event command must not set effective_at")
        if self.occurred_at is not None or self.period is not None:
            raise ValueError("event command must not set asset temporal fields")
        if self.name is not None or self.contact_patch:
            raise ValueError("event command contains contact fields")
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
        reference_datetime: datetime,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult: ...


class UnavailableCaptureAgentProvider:
    async def organize(
        self,
        *,
        transcript: str,
        reference_datetime: datetime,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult:
        raise PermanentCaptureAgentError("capture agent is not configured")


def capture_skill_from_model(skill: UserSkill) -> CaptureSkill:
    schema = skill.schema_json or {}
    enabled = skill.machine_name in BASELINE_CAPTURE_SKILL_NAMES or (
        schema.get("x-capture-enabled") is True
    )
    return CaptureSkill(
        user_skill_id=skill.id,
        machine_name=skill.machine_name,
        display_name=skill.display_name,
        description=skill.description,
        schema_definition=schema,
        enabled=enabled,
    )


def _validate_payload(
    payload: dict[str, Any],
    schema: dict,
    *,
    profile: AssetWriteProfile,
) -> None:
    try:
        validate_asset_payload(payload, schema, profile=profile)
    except AssetPayloadInvalid as exc:
        raise CaptureOutputError(str(exc)) from exc


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
        if command.operation in {"query", "delete"}:
            continue
        profile = (
            AssetWriteProfile.manual
            if skill.machine_name in BASELINE_CAPTURE_SKILL_NAMES
            and command.operation != "update"
            else AssetWriteProfile.agent
        )
        _validate_payload(
            command.payload,
            skill.schema_definition,
            profile=profile,
        )
    return result
