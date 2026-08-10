from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, field_serializer


class _UtcModel(BaseModel):
    @field_serializer("*", when_used="json", check_fields=False)
    def serialize_datetimes(self, value):
        if not isinstance(value, datetime):
            return value
        aware = value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
        return aware.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class RekaSignalTarget(BaseModel):
    type: Literal["asset", "skill"]
    id: str


class RekaSignalPayload(_UtcModel):
    id: str
    natural_key: str
    kind: Literal["overdue", "rhythm_gap"]
    title: str
    body: str
    target: RekaSignalTarget
    actions: list[str]
    delivered_at: datetime
    expires_at: datetime | None = None


class RekaSignalsResponse(_UtcModel):
    ok: bool = True
    signals: list[RekaSignalPayload]
    partial_failures: list[str]
    generated_at: datetime


class RekaDismissResponse(BaseModel):
    ok: bool = True
    status: str
