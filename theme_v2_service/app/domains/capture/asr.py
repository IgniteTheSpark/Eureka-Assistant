from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any, Literal, Protocol
from urllib.parse import urlsplit, urlunsplit

import httpx


logger = logging.getLogger("capture_asr")


class AsrProviderError(Exception):
    pass


class RetryableAsrError(AsrProviderError):
    pass


class PermanentAsrError(AsrProviderError):
    pass


@dataclass(frozen=True)
class AsrTask:
    task_id: str
    raw_response: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class AsrPollResult:
    status: Literal["pending", "running", "finished", "failed"]
    text: str = ""
    segments: list[dict[str, Any]] = field(default_factory=list)
    error_message: str = ""
    raw_response: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def pending(
        cls,
        *,
        raw_response: dict[str, Any] | None = None,
    ) -> "AsrPollResult":
        return cls(status="pending", raw_response=raw_response or {})

    @classmethod
    def running(
        cls,
        *,
        raw_response: dict[str, Any] | None = None,
    ) -> "AsrPollResult":
        return cls(status="running", raw_response=raw_response or {})

    @classmethod
    def finished(
        cls,
        text: str,
        *,
        segments: list[dict[str, Any]] | None = None,
        raw_response: dict[str, Any] | None = None,
    ) -> "AsrPollResult":
        return cls(
            status="finished",
            text=text,
            segments=segments or [],
            raw_response=raw_response or {},
        )

    @classmethod
    def failed(
        cls,
        error_message: str,
        *,
        raw_response: dict[str, Any] | None = None,
    ) -> "AsrPollResult":
        return cls(
            status="failed",
            error_message=error_message,
            raw_response=raw_response or {},
        )


class AsrProvider(Protocol):
    async def create_task(
        self,
        *,
        audio_url: str,
        engine_type: str,
        speaker_diarization: bool,
        hotword_list: str,
    ) -> AsrTask: ...

    async def get_result(self, task_id: str) -> AsrPollResult: ...


def redact_signed_url(url: str) -> str:
    try:
        parsed = urlsplit(url)
        hostname = parsed.hostname or ""
        if ":" in hostname and not hostname.startswith("["):
            hostname = f"[{hostname}]"
        netloc = hostname
        if parsed.port is not None:
            netloc = f"{netloc}:{parsed.port}"
        return urlunsplit((parsed.scheme, netloc, parsed.path, "", ""))
    except (TypeError, ValueError):
        return "<invalid-url>"


class TencentS3AsrProvider:
    def __init__(
        self,
        *,
        base_url: str,
        client: httpx.AsyncClient | None = None,
        timeout_seconds: float = 20,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._client = client
        self.timeout_seconds = timeout_seconds

    async def _post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        url = f"{self.base_url}{path}"
        try:
            if self._client is not None:
                response = await self._client.post(
                    url,
                    json=payload,
                    timeout=self.timeout_seconds,
                )
            else:
                async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                    response = await client.post(url, json=payload)
        except httpx.RequestError as exc:
            raise RetryableAsrError("Tencent ASR transport unavailable") from exc

        if response.status_code == 429 or response.status_code >= 500:
            raise RetryableAsrError(
                f"Tencent ASR temporarily unavailable: http {response.status_code}"
            )
        if response.status_code >= 400:
            raise PermanentAsrError(
                f"Tencent ASR rejected request: http {response.status_code}"
            )
        try:
            body = response.json()
        except ValueError as exc:
            raise PermanentAsrError("Tencent ASR response is not JSON") from exc
        if not isinstance(body, dict):
            raise PermanentAsrError("Tencent ASR response must be an object")
        if body.get("code") != 0:
            message = str(body.get("message") or "Tencent ASR request failed")
            raise PermanentAsrError(message[:200])
        data = body.get("data")
        if not isinstance(data, dict):
            raise PermanentAsrError("Tencent ASR response missing data")
        return {"data": data, "raw": body}

    async def create_task(
        self,
        *,
        audio_url: str,
        engine_type: str,
        speaker_diarization: bool,
        hotword_list: str,
    ) -> AsrTask:
        logger.info(
            "Tencent ASR create task audio_url=%s engine=%s diarization=%s",
            redact_signed_url(audio_url),
            engine_type,
            speaker_diarization,
        )
        response = await self._post(
            "/api/platform/speech/tencent_asr/s3_task",
            {
                "audio_url": audio_url,
                "engine_type": engine_type,
                "speaker_diarization": speaker_diarization,
                "hotword_list": hotword_list,
            },
        )
        task_id = str(response["data"].get("task_id") or "").strip()
        if not task_id:
            raise PermanentAsrError("Tencent ASR response missing task_id")
        return AsrTask(task_id=task_id, raw_response=response["raw"])

    async def get_result(self, task_id: str) -> AsrPollResult:
        normalized_task_id = str(task_id).strip()
        if not normalized_task_id:
            raise PermanentAsrError("Tencent ASR task_id is required")
        payload_task_id: str | int = (
            int(normalized_task_id)
            if normalized_task_id.isdigit()
            else normalized_task_id
        )
        response = await self._post(
            "/api/platform/speech/tencent_asr/task_result",
            {"task_id": payload_task_id},
        )
        data = response["data"]
        status = str(data.get("status") or "").strip().lower()
        if status in {"pending", "queued", "created"}:
            return AsrPollResult.pending(raw_response=response["raw"])
        if status in {"running", "processing"}:
            return AsrPollResult.running(raw_response=response["raw"])
        if status in {"finished", "completed", "success", "succeeded"}:
            segments = data.get("segments")
            normalized_segments = (
                [item for item in segments if isinstance(item, dict)]
                if isinstance(segments, list)
                else []
            )
            return AsrPollResult.finished(
                str(data.get("text") or "").strip(),
                segments=normalized_segments,
                raw_response=response["raw"],
            )
        if status in {"failed", "error"}:
            message = str(
                data.get("error_message")
                or data.get("message")
                or "Tencent ASR failed"
            )
            return AsrPollResult.failed(
                message[:500],
                raw_response=response["raw"],
            )
        raise PermanentAsrError(f"unsupported Tencent ASR status: {status or 'missing'}")
