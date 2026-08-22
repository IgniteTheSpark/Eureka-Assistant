from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import AsyncIterator, Protocol


class ProviderEventKind(str, Enum):
    PARTIAL = "partial"
    STABLE = "stable"
    FINAL = "final"


@dataclass(frozen=True)
class ProviderTranscriptEvent:
    kind: ProviderEventKind
    sequence: int
    text: str
    duration_ms: int = 0


class StreamingAsrProviderError(RuntimeError):
    """Safe provider error whose private details never cross the gateway."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


class StreamingAsrProvider(Protocol):
    async def start(self) -> None: ...

    async def send_audio(self, frame: bytes) -> None: ...

    async def finish(self) -> None: ...

    async def cancel(self) -> None: ...

    def events(self) -> AsyncIterator[ProviderTranscriptEvent]: ...
