"""Alibaba Cloud Model Studio Qwen Audio realtime WebSocket adapter.

Provider-specific payloads stay inside this module. Callers receive only the
normalized, content-minimal contracts from :mod:`core.asr.provider`.
"""

from __future__ import annotations

import asyncio
import inspect
import json
import re
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from typing import Any

import websockets

from config import settings
from core.asr.provider import (
    ProviderEventKind,
    ProviderTranscriptEvent,
    StreamingAsrProviderError,
)


Connector = Callable[..., Awaitable[Any]]
TaskIdFactory = Callable[[], str]

_CJK_RE = re.compile(r"[\u3400-\u9fff]$")
_CJK_START_RE = re.compile(r"^[\u3400-\u9fff，。！？；：、）】》]")


class QwenStreamingAsrProvider:
    """One Qwen upstream connection per Eureka voice-input session."""

    def __init__(
        self,
        *,
        api_key: str | None = None,
        ws_url: str | None = None,
        model: str | None = None,
        connector: Connector | None = None,
        task_id_factory: TaskIdFactory | None = None,
    ) -> None:
        self._api_key = api_key if api_key is not None else settings.dashscope_api_key
        self._ws_url = ws_url if ws_url is not None else settings.dashscope_asr_ws_url
        self._model = model if model is not None else settings.ali_asr_model
        self._connector = connector or websockets.connect
        self._task_id_factory = task_id_factory or (lambda: uuid.uuid4().hex)

        self._socket: Any | None = None
        self._task_id = ""
        self._sequence = 0
        self._stable_parts: list[str] = []
        self._partial = ""
        self._duration_ms = 0
        self._started = False
        self._finish_sent = False
        self._cancelled = False
        self._terminal = False
        self._closed = False
        self._close_lock = asyncio.Lock()

    async def start(self) -> None:
        if self._started:
            raise StreamingAsrProviderError(
                "invalid_state", "Qwen streaming ASR already started"
            )
        self._task_id = self._task_id_factory()
        try:
            connection = self._connector(
                self._ws_url,
                additional_headers={"Authorization": f"Bearer {self._api_key}"},
            )
            self._socket = await connection if inspect.isawaitable(connection) else connection
            await self._socket.send(
                json.dumps(
                    {
                        "header": {
                            "action": "run-task",
                            "task_id": self._task_id,
                            "streaming": "duplex",
                        },
                        "payload": {
                            "task_group": "audio",
                            "task": "asr",
                            "function": "recognition",
                            "model": self._model,
                            "parameters": {"format": "pcm", "sample_rate": 16000},
                            "input": {},
                        },
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
            )
            message = self._decode(await self._socket.recv())
            event = self._event_name(message)
            if event == "task-failed":
                raise self._safe_failure()
            if event != "task-started":
                raise StreamingAsrProviderError(
                    "connection_failed", "Qwen streaming ASR did not become ready"
                )
            self._started = True
        except StreamingAsrProviderError:
            await self._close_once()
            raise
        except asyncio.CancelledError:
            await self._close_once()
            raise
        except Exception as exc:
            await self._close_once()
            raise StreamingAsrProviderError(
                "connection_failed", "Qwen streaming ASR connection failed"
            ) from exc

    async def send_audio(self, frame: bytes) -> None:
        if not self._started or self._terminal or self._cancelled or self._socket is None:
            raise StreamingAsrProviderError(
                "invalid_state", "Qwen streaming ASR is not accepting audio"
            )
        try:
            await self._socket.send(frame)
        except Exception as exc:
            raise StreamingAsrProviderError(
                "connection_lost", "Qwen streaming ASR connection was lost"
            ) from exc

    async def finish(self) -> None:
        if self._cancelled or self._terminal or self._finish_sent:
            return
        if not self._started or self._socket is None:
            raise StreamingAsrProviderError(
                "invalid_state", "Qwen streaming ASR is not started"
            )
        self._finish_sent = True
        try:
            await self._socket.send(
                json.dumps(
                    {
                        "header": {
                            "action": "finish-task",
                            "task_id": self._task_id,
                            "streaming": "duplex",
                        },
                        "payload": {"input": {}},
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
            )
        except Exception as exc:
            raise StreamingAsrProviderError(
                "connection_lost", "Qwen streaming ASR connection was lost"
            ) from exc

    async def cancel(self) -> None:
        if self._cancelled:
            return
        self._cancelled = True
        self._terminal = True
        await self._close_once()

    async def events(self) -> AsyncIterator[ProviderTranscriptEvent]:
        if self._cancelled or self._terminal:
            return
        if not self._started or self._socket is None:
            raise StreamingAsrProviderError(
                "invalid_state", "Qwen streaming ASR is not started"
            )

        try:
            while not self._terminal and not self._cancelled:
                message = self._decode(await self._socket.recv())
                event_name = self._event_name(message)
                if event_name == "result-generated":
                    event = self._transcript_event(message)
                    if event is not None:
                        yield event
                    continue
                if event_name == "task-finished":
                    self._terminal = True
                    self._sequence += 1
                    yield ProviderTranscriptEvent(
                        kind=ProviderEventKind.FINAL,
                        sequence=self._sequence,
                        text=self._complete_text(),
                        duration_ms=self._duration_ms,
                    )
                    return
                if event_name == "task-failed":
                    self._terminal = True
                    raise self._safe_failure()
                if event_name == "task-started":
                    continue
                self._terminal = True
                raise StreamingAsrProviderError(
                    "service_unavailable", "Qwen streaming ASR returned an invalid event"
                )
        except StreamingAsrProviderError:
            raise
        except Exception as exc:
            if self._cancelled:
                return
            self._terminal = True
            raise StreamingAsrProviderError(
                "connection_lost", "Qwen streaming ASR connection was lost"
            ) from exc
        finally:
            if self._terminal or self._cancelled:
                await self._close_once()

    def _transcript_event(
        self, message: dict[str, Any]
    ) -> ProviderTranscriptEvent | None:
        payload = message.get("payload")
        output = payload.get("output") if isinstance(payload, dict) else None
        sentence = output.get("sentence") if isinstance(output, dict) else None
        if not isinstance(sentence, dict):
            raise StreamingAsrProviderError(
                "service_unavailable", "Qwen streaming ASR returned an invalid result"
            )

        text = str(sentence.get("text") or "").strip()
        end_time = sentence.get("end_time")
        if isinstance(end_time, (int, float)) and end_time >= 0:
            self._duration_ms = max(self._duration_ms, int(end_time))
        if not text:
            return None

        sentence_end = sentence.get("sentence_end") is True
        self._sequence += 1
        if sentence_end:
            self._stable_parts.append(text)
            self._partial = ""
            kind = ProviderEventKind.STABLE
        else:
            self._partial = text
            kind = ProviderEventKind.PARTIAL
        return ProviderTranscriptEvent(
            kind=kind,
            sequence=self._sequence,
            text=text,
            duration_ms=self._duration_ms,
        )

    def _complete_text(self) -> str:
        parts = [*self._stable_parts]
        if self._partial:
            parts.append(self._partial)
        complete = ""
        for part in parts:
            if not complete:
                complete = part
            elif _needs_space(complete, part):
                complete = f"{complete} {part}"
            else:
                complete += part
        return complete.strip()

    @staticmethod
    def _decode(raw: Any) -> dict[str, Any]:
        if not isinstance(raw, str):
            raise StreamingAsrProviderError(
                "service_unavailable", "Qwen streaming ASR returned a non-JSON event"
            )
        try:
            value = json.loads(raw)
        except (TypeError, ValueError) as exc:
            raise StreamingAsrProviderError(
                "service_unavailable", "Qwen streaming ASR returned invalid JSON"
            ) from exc
        if not isinstance(value, dict):
            raise StreamingAsrProviderError(
                "service_unavailable", "Qwen streaming ASR returned invalid JSON"
            )
        return value

    @staticmethod
    def _event_name(message: dict[str, Any]) -> str:
        header = message.get("header")
        return str(header.get("event") or "") if isinstance(header, dict) else ""

    @staticmethod
    def _safe_failure() -> StreamingAsrProviderError:
        return StreamingAsrProviderError(
            "service_unavailable", "Qwen streaming ASR failed"
        )

    async def _close_once(self) -> None:
        async with self._close_lock:
            if self._closed:
                return
            socket = self._socket
            if socket is None:
                self._closed = True
                return
            try:
                await socket.close()
            except asyncio.CancelledError:
                raise
            except Exception:
                pass
            self._closed = True


def _needs_space(left: str, right: str) -> bool:
    if not left or not right or left[-1].isspace() or right[0].isspace():
        return False
    if _CJK_RE.search(left) or _CJK_START_RE.search(right):
        return False
    return True
