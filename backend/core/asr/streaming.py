"""Authenticated, provider-neutral streaming ASR session orchestration."""

from __future__ import annotations

import asyncio
import json
import time
from collections import defaultdict, deque
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Any

from config import settings, validate_asr_settings
from core.asr.provider import (
    ProviderEventKind,
    StreamingAsrProvider,
    StreamingAsrProviderError,
)
from core.asr.qwen_streaming import QwenStreamingAsrProvider


_MAX_AUDIO_FRAME_BYTES = 32_000
_FINAL_TIMEOUT_SECONDS = 10.0
_START_TIMEOUT_SECONDS = 5.0
_RETRYABLE_CODES = {
    "connection_failed",
    "connection_lost",
    "no_speech",
    "rate_limited",
    "service_unavailable",
}


@dataclass(frozen=True)
class ClientStart:
    voice_session_id: str
    mode: str
    duration_limit_seconds: int


class AsrSessionRegistry:
    """Process-local one-active-session guard for the current one-worker deploy."""

    def __init__(self) -> None:
        self._active_users: set[str] = set()
        self._lock = asyncio.Lock()

    async def acquire(self, user_id: str) -> bool:
        async with self._lock:
            if user_id in self._active_users:
                return False
            self._active_users.add(user_id)
            return True

    async def release(self, user_id: str) -> None:
        async with self._lock:
            self._active_users.discard(user_id)


class SlidingWindowRateLimiter:
    def __init__(
        self,
        *,
        limit: int,
        window_seconds: float = 60.0,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._limit = max(1, int(limit))
        self._window_seconds = window_seconds
        self._clock = clock
        self._starts: dict[str, deque[float]] = defaultdict(deque)
        self._lock = asyncio.Lock()

    async def allow(self, user_id: str) -> bool:
        now = self._clock()
        cutoff = now - self._window_seconds
        async with self._lock:
            starts = self._starts[user_id]
            while starts and starts[0] <= cutoff:
                starts.popleft()
            if len(starts) >= self._limit:
                return False
            starts.append(now)
            return True


def duration_limit_for(mode: str) -> int:
    if mode == "ordinary":
        return 300
    if mode == "reka":
        return 60
    raise ValueError("invalid ASR mode")


def validate_audio_frame(frame: bytes) -> None:
    if not frame or len(frame) > _MAX_AUDIO_FRAME_BYTES or len(frame) % 2 != 0:
        raise ValueError("invalid PCM16 audio frame")


def parse_start_message(raw: str) -> ClientStart:
    if len(raw.encode("utf-8")) > 4096:
        raise ValueError("start message too large")
    try:
        value = json.loads(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError("start message is not JSON") from exc
    if not isinstance(value, dict) or value.get("type") != "start":
        raise ValueError("first message must be start")

    voice_session_id = value.get("voiceSessionId")
    if (
        not isinstance(voice_session_id, str)
        or not voice_session_id.strip()
        or len(voice_session_id) > 128
    ):
        raise ValueError("invalid voiceSessionId")
    voice_session_id = voice_session_id.strip()

    mode = value.get("mode")
    if not isinstance(mode, str):
        raise ValueError("invalid mode")
    duration_limit = duration_limit_for(mode)

    audio = value.get("audio")
    if not isinstance(audio, dict) or audio != {
        "encoding": "pcm_s16le",
        "sampleRate": 16000,
        "channels": 1,
    }:
        raise ValueError("unsupported audio contract")
    return ClientStart(voice_session_id, mode, duration_limit)


class StreamingAsrGateway:
    def __init__(
        self,
        *,
        provider_factory: Callable[[], StreamingAsrProvider] | None = None,
        registry: AsrSessionRegistry | None = None,
        rate_limiter: SlidingWindowRateLimiter | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        if provider_factory is None:
            self._provider_factory = QwenStreamingAsrProvider
            self._settings_validator: Callable[[], None] = validate_asr_settings
        else:
            self._provider_factory = provider_factory
            self._settings_validator = lambda: None
        self._registry = registry or AsrSessionRegistry()
        self._rate_limiter = rate_limiter or SlidingWindowRateLimiter(
            limit=settings.asr_rate_limit_per_minute
        )
        self._sleep = sleep

    async def handle(self, socket: Any, *, user_id: str) -> None:
        provider: StreamingAsrProvider | None = None
        provider_task: asyncio.Task[bool] | None = None
        timer_task: asyncio.Task[None] | None = None
        acquired = False
        provider_terminal = False
        voice_session_id = ""
        client_cancelled = asyncio.Event()

        try:
            try:
                first = await asyncio.wait_for(
                    socket.receive(), timeout=_START_TIMEOUT_SECONDS
                )
                if first.get("type") == "websocket.disconnect":
                    return
                first_text = first.get("text")
                if not isinstance(first_text, str):
                    raise ValueError("first message must be text")
                start = parse_start_message(first_text)
                voice_session_id = start.voice_session_id
            except (asyncio.TimeoutError, ValueError, AttributeError):
                await self._send_error(
                    socket, voice_session_id, "unsupported_audio"
                )
                return

            if not await self._rate_limiter.allow(user_id):
                await self._send_error(socket, voice_session_id, "rate_limited")
                return
            acquired = await self._registry.acquire(user_id)
            if not acquired:
                await self._send_error(socket, voice_session_id, "rate_limited")
                return

            try:
                self._settings_validator()
                provider = self._provider_factory()
                await provider.start()
            except (RuntimeError, StreamingAsrProviderError):
                await self._send_error(socket, voice_session_id, "service_unavailable")
                return
            except Exception:
                await self._send_error(socket, voice_session_id, "connection_failed")
                return

            await socket.send_json(
                {"type": "ready", "voiceSessionId": voice_session_id}
            )
            provider_task = asyncio.create_task(
                self._forward_provider_events(
                    socket,
                    provider,
                    voice_session_id,
                    client_cancelled=client_cancelled,
                )
            )
            timer_task = asyncio.create_task(self._sleep(start.duration_limit_seconds))

            while True:
                receive_task = asyncio.create_task(socket.receive())
                done, _ = await asyncio.wait(
                    {receive_task, provider_task, timer_task},
                    return_when=asyncio.FIRST_COMPLETED,
                )

                if provider_task in done:
                    receive_task.cancel()
                    await _drain_cancelled(receive_task)
                    provider_terminal = await provider_task
                    return

                if timer_task in done:
                    receive_task.cancel()
                    await _drain_cancelled(receive_task)
                    await provider.finish()
                    provider_terminal = await self._await_final(
                        socket, provider, provider_task, voice_session_id
                    )
                    return

                message = receive_task.result()
                if message.get("type") == "websocket.disconnect":
                    return
                frame = message.get("bytes")
                if isinstance(frame, bytes):
                    try:
                        validate_audio_frame(frame)
                        await provider.send_audio(frame)
                    except ValueError:
                        await self._send_error(
                            socket, voice_session_id, "unsupported_audio"
                        )
                        return
                    except StreamingAsrProviderError as exc:
                        await self._send_error(
                            socket, voice_session_id, _safe_provider_code(exc.code)
                        )
                        return
                    continue

                raw_control = message.get("text")
                try:
                    control = json.loads(raw_control) if isinstance(raw_control, str) else None
                except ValueError:
                    control = None
                if (
                    not isinstance(control, dict)
                    or control.get("voiceSessionId") != voice_session_id
                ):
                    await self._send_error(
                        socket, voice_session_id, "unsupported_audio"
                    )
                    return

                control_type = control.get("type")
                if control_type == "cancel":
                    # Publish cancellation before asking the provider to stop. Its
                    # event iterator may end immediately, and that is not a
                    # connection failure from the client's perspective.
                    client_cancelled.set()
                    await provider.cancel()
                    provider_terminal = True
                    return
                if control_type == "stop":
                    try:
                        await provider.finish()
                    except StreamingAsrProviderError as exc:
                        await self._send_error(
                            socket, voice_session_id, _safe_provider_code(exc.code)
                        )
                        return
                    provider_terminal = await self._await_final(
                        socket, provider, provider_task, voice_session_id
                    )
                    return
                await self._send_error(socket, voice_session_id, "unsupported_audio")
                return
        finally:
            if timer_task is not None and not timer_task.done():
                timer_task.cancel()
                await _drain_cancelled(timer_task)
            if provider_task is not None and not provider_task.done():
                provider_task.cancel()
                await _drain_cancelled(provider_task)
            if provider is not None and not provider_terminal:
                await provider.cancel()
            if acquired:
                await self._registry.release(user_id)

    async def _await_final(
        self,
        socket: Any,
        provider: StreamingAsrProvider,
        provider_task: asyncio.Task[bool],
        voice_session_id: str,
    ) -> bool:
        try:
            return await asyncio.wait_for(
                asyncio.shield(provider_task), timeout=_FINAL_TIMEOUT_SECONDS
            )
        except asyncio.TimeoutError:
            await provider.cancel()
            await self._send_error(socket, voice_session_id, "service_unavailable")
            return True

    async def _forward_provider_events(
        self,
        socket: Any,
        provider: StreamingAsrProvider,
        voice_session_id: str,
        *,
        client_cancelled: asyncio.Event,
    ) -> bool:
        last_sequence = 0
        saw_terminal = False
        try:
            async for event in provider.events():
                if client_cancelled.is_set():
                    return True
                if event.sequence <= last_sequence:
                    continue
                last_sequence = event.sequence
                if event.kind == ProviderEventKind.FINAL:
                    saw_terminal = True
                    text = event.text.strip()
                    if not text:
                        await self._send_error(socket, voice_session_id, "no_speech")
                    else:
                        await socket.send_json(
                            {
                                "type": "final",
                                "voiceSessionId": voice_session_id,
                                "sequence": event.sequence,
                                "text": text,
                                "audioDurationMs": event.duration_ms,
                            }
                        )
                    return True
                await socket.send_json(
                    {
                        "type": event.kind.value,
                        "voiceSessionId": voice_session_id,
                        "sequence": event.sequence,
                        "text": event.text,
                    }
                )
        except StreamingAsrProviderError as exc:
            await self._send_error(
                socket, voice_session_id, _safe_provider_code(exc.code)
            )
            return True
        except asyncio.CancelledError:
            raise
        except Exception:
            await self._send_error(socket, voice_session_id, "connection_lost")
            return True

        if not saw_terminal and not client_cancelled.is_set():
            await self._send_error(socket, voice_session_id, "connection_lost")
        return True

    @staticmethod
    async def _send_error(
        socket: Any, voice_session_id: str, code: str
    ) -> None:
        try:
            await socket.send_json(
                {
                    "type": "error",
                    "voiceSessionId": voice_session_id,
                    "code": code,
                    "retryable": code in _RETRYABLE_CODES,
                }
            )
        except Exception:
            pass


def _safe_provider_code(code: str) -> str:
    if code in {
        "connection_failed",
        "connection_lost",
        "service_unavailable",
    }:
        return code
    return "service_unavailable"


async def _drain_cancelled(task: asyncio.Task[Any]) -> None:
    try:
        await task
    except (asyncio.CancelledError, Exception):
        pass
