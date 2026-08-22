"""Authenticated, provider-neutral streaming ASR session orchestration."""

from __future__ import annotations

import asyncio
import json
import time
from collections import defaultdict, deque
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from itertools import count
from typing import Any

from config import settings, validate_asr_settings
from core.asr.provider import (
    StreamingAsrProvider,
    StreamingAsrProviderError,
)
from core.asr.qwen_streaming import QwenStreamingAsrProvider
from core.asr.session import StreamingAsrSession


_MAX_AUDIO_FRAME_BYTES = 32_000
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


@dataclass(frozen=True)
class AsrSessionLease:
    user_id: str
    token: int


@dataclass(frozen=True)
class _RegistryEntry:
    lease: AsrSessionLease
    session: Any


class AsrSessionRegistry:
    """Atomically replace same-user sessions and release only exact leases."""

    def __init__(self) -> None:
        self._active: dict[str, _RegistryEntry] = {}
        self._tokens = count(1)
        self._lock = asyncio.Lock()

    async def install(
        self,
        user_id: str,
        session: Any,
    ) -> tuple[AsrSessionLease, Any | None]:
        async with self._lock:
            previous = self._active.get(user_id)
            lease = AsrSessionLease(user_id=user_id, token=next(self._tokens))
            self._active[user_id] = _RegistryEntry(lease=lease, session=session)
            return lease, previous.session if previous is not None else None

    async def release(self, lease: AsrSessionLease) -> bool:
        async with self._lock:
            current = self._active.get(lease.user_id)
            if current is None or current.lease != lease:
                return False
            del self._active[lease.user_id]
            return True

    async def is_active(self, user_id: str) -> bool:
        async with self._lock:
            return user_id in self._active


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
        self._last_sweep = float("-inf")

    async def allow(self, user_id: str) -> bool:
        now = self._clock()
        cutoff = now - self._window_seconds
        async with self._lock:
            if now - self._last_sweep >= self._window_seconds:
                for key, historical_starts in list(self._starts.items()):
                    while historical_starts and historical_starts[0] <= cutoff:
                        historical_starts.popleft()
                    if not historical_starts:
                        del self._starts[key]
                self._last_sweep = now
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
        provider_start_timeout_seconds: float | None = None,
        provider_send_timeout_seconds: float | None = None,
        provider_final_timeout_seconds: float | None = None,
        provider_cleanup_timeout_seconds: float | None = None,
        client_send_timeout_seconds: float | None = None,
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
        self._provider_start_timeout_seconds = (
            settings.asr_provider_start_timeout_seconds
            if provider_start_timeout_seconds is None
            else provider_start_timeout_seconds
        )
        self._provider_send_timeout_seconds = (
            settings.asr_provider_send_timeout_seconds
            if provider_send_timeout_seconds is None
            else provider_send_timeout_seconds
        )
        self._provider_final_timeout_seconds = (
            settings.asr_provider_finalize_timeout_seconds
            if provider_final_timeout_seconds is None
            else provider_final_timeout_seconds
        )
        self._provider_cleanup_timeout_seconds = (
            settings.asr_provider_cleanup_timeout_seconds
            if provider_cleanup_timeout_seconds is None
            else provider_cleanup_timeout_seconds
        )
        self._client_send_timeout_seconds = (
            settings.asr_client_send_timeout_seconds
            if client_send_timeout_seconds is None
            else client_send_timeout_seconds
        )

    async def handle(self, socket: Any, *, user_id: str) -> None:
        session: StreamingAsrSession | None = None
        supersede_task: asyncio.Task[None] | None = None
        lease: AsrSessionLease | None = None
        voice_session_id = ""

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
            try:
                self._settings_validator()
                provider = self._provider_factory()
                session = StreamingAsrSession(
                    socket=socket,
                    provider=provider,
                    voice_session_id=voice_session_id,
                    duration_limit_seconds=start.duration_limit_seconds,
                    validate_audio_frame=validate_audio_frame,
                    sleep=self._sleep,
                    provider_start_timeout_seconds=(
                        self._provider_start_timeout_seconds
                    ),
                    provider_send_timeout_seconds=(
                        self._provider_send_timeout_seconds
                    ),
                    provider_final_timeout_seconds=(
                        self._provider_final_timeout_seconds
                    ),
                    provider_cleanup_timeout_seconds=(
                        self._provider_cleanup_timeout_seconds
                    ),
                    client_send_timeout_seconds=self._client_send_timeout_seconds,
                )
            except (RuntimeError, StreamingAsrProviderError):
                await self._send_error(socket, voice_session_id, "service_unavailable")
                return
            except Exception:
                await self._send_error(socket, voice_session_id, "connection_failed")
                return

            lease, previous = await self._registry.install(user_id, session)
            if previous is not None:
                supersede_task = asyncio.create_task(previous.supersede())
            await session.run()
        finally:
            try:
                if session is not None:
                    await session.close()
            finally:
                try:
                    if lease is not None:
                        await self._registry.release(lease)
                finally:
                    if supersede_task is not None:
                        await _drain_supersede(
                            supersede_task,
                            timeout=self._provider_cleanup_timeout_seconds * 4,
                        )

    async def _send_error(
        self, socket: Any, voice_session_id: str, code: str
    ) -> None:
        try:
            await asyncio.wait_for(
                socket.send_json(
                    {
                        "type": "error",
                        "voiceSessionId": voice_session_id,
                        "code": code,
                        "retryable": code in _RETRYABLE_CODES,
                    }
                ),
                timeout=self._client_send_timeout_seconds,
            )
        except Exception:
            pass


async def _drain_supersede(task: asyncio.Task[None], *, timeout: float) -> None:
    try:
        await asyncio.wait_for(task, timeout=timeout)
    except asyncio.TimeoutError:
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):
            pass
    except (asyncio.CancelledError, Exception):
        pass
