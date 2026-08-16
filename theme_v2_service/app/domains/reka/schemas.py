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
    type: Literal["asset", "skill", "trigger_execution", "report_run", "report"]
    id: str


class RekaSignalPayload(_UtcModel):
    id: str
    natural_key: str
    kind: Literal["overdue", "rhythm_gap", "report"]
    title: str
    body: str
    target: RekaSignalTarget
    actions: list[str]
    delivered_at: datetime
    expires_at: datetime | None = None
    phase: Literal["opportunity", "plan_ready", "report_ready"] | None = None
    chain_id: str | None = None
    evidence: dict | None = None
    report_run_id: str | None = None
    report_id: str | None = None


class RekaSignalsResponse(_UtcModel):
    ok: bool = True
    signals: list[RekaSignalPayload]
    partial_failures: list[str]
    generated_at: datetime


class RekaDismissResponse(BaseModel):
    ok: bool = True
    status: str


class RekaSnoozeRequest(BaseModel):
    remind_again_at: datetime


class RekaSnoozeResponse(_UtcModel):
    ok: bool = True
    status: str
    remind_again_at: datetime
