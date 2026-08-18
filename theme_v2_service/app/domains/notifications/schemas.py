from datetime import datetime, timezone
from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_serializer,
    field_validator,
)


class NotificationCreate(BaseModel):
    user_id: str
    type: str = Field(min_length=1, max_length=32)
    title: str = Field(min_length=1)
    body: str = ""
    link: str | None = Field(default=None, max_length=255)
    confirmed_mutation: bool = Field(default=False, exclude=True)


class NotificationPayload(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    type: str
    title: str
    body: str
    link: str | None
    read: bool
    created_at: datetime
    confirmed_mutation: Literal[True] | None = Field(
        default=None,
        exclude_if=lambda value: value is None,
    )

    @field_validator("body", mode="before")
    @classmethod
    def normalize_empty_body(cls, value: str | None) -> str:
        return value or ""

    @field_serializer("created_at")
    def serialize_created_at(self, value: datetime) -> str:
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class NotificationListResponse(BaseModel):
    notifications: list[NotificationPayload]
    unread: int
