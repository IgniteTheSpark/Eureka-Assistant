from datetime import datetime, timezone
from typing import Literal

from pydantic import (
    AliasChoices,
    BaseModel,
    ConfigDict,
    Field,
    field_serializer,
    field_validator,
)

from app.domains.reminders.preferences import normalize_reminder_offsets


def _as_utc_z(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class UserSkillCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    machine_name: str = Field(min_length=1, max_length=100)
    display_name: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=1000)
    domain: str | None = Field(default=None, max_length=100)
    schema_definition: dict = Field(default_factory=dict, alias="schema")
    render_spec: dict = Field(default_factory=dict)
    chat_starters: list[str] = Field(default_factory=list, max_length=12)
    queryable_fields: list[str] = Field(default_factory=list, max_length=100)
    position: int = Field(default=0, ge=0)
    enabled: bool = True


class UserSkillUpdate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    display_name: str | None = Field(default=None, min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=1000)
    domain: str | None = Field(default=None, max_length=100)
    schema_definition: dict | None = Field(default=None, alias="schema")
    render_spec: dict | None = None
    chat_starters: list[str] | None = Field(default=None, max_length=12)
    queryable_fields: list[str] | None = Field(default=None, max_length=100)
    position: int | None = Field(default=None, ge=0)
    enabled: bool | None = None
    expected_updated_at: datetime | None = None


class SkillDraftAnswer(BaseModel):
    key: str = Field(min_length=1, max_length=100)
    value: str = Field(default="", max_length=1000)


class SkillDraftRequest(BaseModel):
    description: str = Field(min_length=1, max_length=4000)
    answers: list[SkillDraftAnswer] = Field(default_factory=list, max_length=3)


class AssetCreate(BaseModel):
    user_skill_id: str
    payload: dict
    session_id: str | None = None
    effective_at: datetime | None = None
    period: Literal["凌晨", "上午", "中午", "下午", "晚上"] | None = None
    occurred_at: datetime | None = None
    domain: str | None = Field(default=None, max_length=100)
    source_input_turn_id: str | None = None


class AssetUpdate(BaseModel):
    payload: dict | None = None
    effective_at: datetime | None = None
    period: Literal["凌晨", "上午", "中午", "下午", "晚上"] | None = None
    occurred_at: datetime | None = None
    domain: str | None = Field(default=None, max_length=100)


class EventAttendeeCreate(BaseModel):
    name: str = Field(min_length=1, max_length=320)
    contact_id: str | None = None
    role: str = Field(default="attendee", min_length=1, max_length=32)


class EventAttendeeRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str | None = None
    contact_id: str | None = None
    name_raw: str
    display_name: str
    is_resolved: bool
    contact_summary: str = ""
    role: str = "attendee"


class EventCreate(BaseModel):
    title: str = Field(min_length=1, max_length=500)
    description: str | None = None
    location: str | None = Field(default=None, max_length=500)
    start_at: datetime
    end_at: datetime
    all_day: bool = False
    reminder_offsets_minutes: list[int] = Field(default_factory=lambda: [15])
    status: Literal["scheduled", "cancelled", "done"] = "scheduled"
    attendees: list[EventAttendeeCreate] = Field(default_factory=list)
    recurrence_rule: str | None = Field(default=None, max_length=500)
    source_input_turn_id: str | None = None

    @field_validator("reminder_offsets_minutes", mode="before")
    @classmethod
    def normalize_reminders(cls, value):
        return normalize_reminder_offsets(value, missing_uses_default=True)


class EventUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = None
    location: str | None = Field(default=None, max_length=500)
    start_at: datetime | None = None
    end_at: datetime | None = None
    all_day: bool | None = None
    reminder_offsets_minutes: list[int] | None = None
    status: Literal["scheduled", "cancelled", "done"] | None = None
    attendees: list[EventAttendeeCreate] | None = None
    recurrence_rule: str | None = Field(default=None, max_length=500)

    @field_validator("reminder_offsets_minutes", mode="before")
    @classmethod
    def normalize_reminders(cls, value):
        return normalize_reminder_offsets(value, missing_uses_default=True)


class UserSkillRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    machine_name: str
    display_name: str
    description: str | None
    domain: str | None
    schema_definition: dict = Field(
        validation_alias="schema_json",
        serialization_alias="schema",
    )
    render_spec: dict = Field(validation_alias="render_spec_json")
    chat_starters: list[str] = Field(validation_alias="chat_starters_json")
    queryable_fields: list[str] = Field(
        default_factory=list,
        validation_alias="queryable_fields_json",
    )
    position: int = 0
    enabled: bool = True
    created_at: datetime
    updated_at: datetime

    @field_serializer("created_at", "updated_at")
    def serialize_timestamp(self, value: datetime) -> str:
        return _as_utc_z(value)


class SkillDeletionImpact(BaseModel):
    skill_id: str
    asset_count: int = Field(ge=0)


class SkillDeletionResult(BaseModel):
    skill_id: str
    deleted_asset_count: int = Field(ge=0)


class AssetRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_skill_id: str
    payload_data: dict = Field(
        validation_alias="payload_json",
        serialization_alias="payload",
    )
    effective_at: datetime | None
    period: str | None
    occurred_at: datetime | None
    created_at: datetime
    updated_at: datetime
    source_recording_id: str | None = None
    session_id: str | None = None
    source_input_turn_id: str | None = None
    source_report_id: str | None = None
    source_report_action_id: str | None = None
    source_report_title: str | None = None
    domain: str | None = None

    @field_serializer("effective_at", "occurred_at", "created_at", "updated_at")
    def serialize_timestamp(self, value: datetime | None) -> str | None:
        return _as_utc_z(value)


class EventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    title: str
    description: str | None = Field(
        validation_alias=AliasChoices("display_description", "description")
    )
    location: str | None
    start_at: datetime
    end_at: datetime
    all_day: bool
    reminder_offsets_minutes: list[int] = Field(
        default_factory=lambda: [15],
        validation_alias="reminder_offsets_json",
    )
    status: str
    created_at: datetime
    updated_at: datetime
    attendees: list[EventAttendeeRead] = Field(
        default_factory=list,
        validation_alias=AliasChoices("attendee_payload", "attendees"),
    )
    source_recording_id: str | None = None
    source_input_turn_id: str | None = None
    recurrence_rule: str | None = None

    @field_validator("reminder_offsets_minutes", mode="before")
    @classmethod
    def normalize_reminders(cls, value):
        return normalize_reminder_offsets(value, missing_uses_default=True)

    @field_serializer("start_at", "end_at", "created_at", "updated_at")
    def serialize_timestamp(self, value: datetime) -> str:
        return _as_utc_z(value)
