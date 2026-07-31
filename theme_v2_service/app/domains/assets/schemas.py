from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer


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


class AssetCreate(BaseModel):
    user_skill_id: str
    payload: dict
    effective_at: datetime | None = None


class AssetUpdate(BaseModel):
    payload: dict | None = None
    effective_at: datetime | None = None


class EventCreate(BaseModel):
    title: str = Field(min_length=1, max_length=500)
    description: str | None = None
    location: str | None = Field(default=None, max_length=500)
    start_at: datetime
    end_at: datetime
    all_day: bool = False
    status: Literal["scheduled", "cancelled"] = "scheduled"


class EventUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=500)
    description: str | None = None
    location: str | None = Field(default=None, max_length=500)
    start_at: datetime | None = None
    end_at: datetime | None = None
    all_day: bool | None = None
    status: Literal["scheduled", "cancelled"] | None = None


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
    created_at: datetime
    updated_at: datetime

    @field_serializer("created_at", "updated_at")
    def serialize_timestamp(self, value: datetime) -> str:
        return _as_utc_z(value)


class AssetRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    user_skill_id: str
    payload_data: dict = Field(
        validation_alias="payload_json",
        serialization_alias="payload",
    )
    effective_at: datetime | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("effective_at", "created_at", "updated_at")
    def serialize_timestamp(self, value: datetime | None) -> str | None:
        return _as_utc_z(value)


class EventRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    title: str
    description: str | None
    location: str | None
    start_at: datetime
    end_at: datetime
    all_day: bool
    status: str
    created_at: datetime
    updated_at: datetime

    @field_serializer("start_at", "end_at", "created_at", "updated_at")
    def serialize_timestamp(self, value: datetime) -> str:
        return _as_utc_z(value)
