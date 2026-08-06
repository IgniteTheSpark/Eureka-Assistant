from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Literal

from app.domains.capture.agent import CaptureSkill
from app.domains.capture.dispatcher import FlashIntent


class RetryableFlashExecutionError(Exception):
    """A provider or infrastructure failure that a durable job may retry."""


class PermanentFlashExecutionError(Exception):
    """A trusted input or configuration failure that retry cannot repair."""


@dataclass(frozen=True)
class FlashExecutionContext:
    recording_id: str
    user_id: str
    session_id: str
    input_turn_id: str
    transcript: str
    reference_datetime: datetime
    skills: tuple[CaptureSkill, ...]


@dataclass(frozen=True)
class FlashExecutionItem:
    intent: FlashIntent
    status: Literal["success", "pending_confirmation", "error", "reply"]
    result: dict[str, Any] = field(default_factory=dict)
    tool_events: tuple[dict[str, Any], ...] = ()
    error_code: str | None = None


@dataclass(frozen=True)
class FlashExecutionResult:
    summary: str
    items: tuple[FlashExecutionItem, ...]
    warnings: tuple[str, ...] = ()
    usage_tokens: int = 0
