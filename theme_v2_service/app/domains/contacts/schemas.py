from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator


class ContactCreate(BaseModel):
    name: str = Field(min_length=1, max_length=320)
    phone: str | None = Field(default=None, max_length=100)
    company: str | None = Field(default=None, max_length=320)
    title: str | None = Field(default=None, max_length=320)
    email: str | None = Field(default=None, max_length=320)
    notes: list[str] = Field(default_factory=list, max_length=100)
    socials: dict[str, str] = Field(default_factory=dict)
    session_id: str | None = None
    source_input_turn_id: str | None = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("name must not be blank")
        return value


class ContactUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=320)
    phone: str | None = Field(default=None, max_length=100)
    company: str | None = Field(default=None, max_length=320)
    title: str | None = Field(default=None, max_length=320)
    email: str | None = Field(default=None, max_length=320)
    notes: list[str] | None = Field(default=None, max_length=100)
    socials: dict[str, str] | None = None

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        if value is None:
            raise ValueError("name must not be null")
        value = value.strip()
        if not value:
            raise ValueError("name must not be blank")
        return value


class ContactRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    phone: str | None
    company: str | None
    title: str | None
    email: str | None
    notes: list[str] = Field(validation_alias="notes_json")
    socials: dict[str, str] = Field(validation_alias="socials_json")
    session_id: str | None
    source_input_turn_id: str | None
    created_at: datetime
    updated_at: datetime

    @field_serializer("created_at", "updated_at")
    def serialize_timestamp(self, value: datetime) -> str:
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
