"""Provider-neutral contracts for realtime streaming ASR."""

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
    """Safe provider error; details are intentionally unavailable to clients."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


class StreamingAsrProvider(Protocol):
    async def start(self) -> None:
        raise NotImplementedError

    async def send_audio(self, frame: bytes) -> None:
        raise NotImplementedError

    async def finish(self) -> None:
        raise NotImplementedError

    async def cancel(self) -> None:
        raise NotImplementedError

    def events(self) -> AsyncIterator[ProviderTranscriptEvent]:
        raise NotImplementedError
