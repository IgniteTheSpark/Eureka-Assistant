"""ASR provider contracts for flash audio."""
from typing import Optional, Protocol

from pydantic import BaseModel, Field


class AsrResult(BaseModel):
    text: str
    language: Optional[str] = None
    duration_sec: Optional[float] = None
    segments: list[dict] = Field(default_factory=list)
    provider_request_id: Optional[str] = None
    raw: dict = Field(default_factory=dict)


class AsrProvider(Protocol):
    async def transcribe_url(self, oss_url: str) -> AsrResult:
        ...


class AsrError(RuntimeError):
    pass


class AsrProviderNotConfigured(AsrError):
    pass
