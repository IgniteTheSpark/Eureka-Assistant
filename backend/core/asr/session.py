"""Bounded lifecycle for one provider-neutral streaming ASR connection."""

from __future__ import annotations

import asyncio
import json
from collections.abc import Awaitable, Callable
from enum import Enum
from typing import Any

from core.asr.provider import (
    ProviderEventKind,
    StreamingAsrProvider,
    StreamingAsrProviderError,
)


_RETRYABLE_CODES = {
    "connection_failed",
    "connection_lost",
    "no_speech",
    "rate_limited",
    "service_unavailable",
}


class SessionPhase(str, Enum):
    ACCEPTED = "accepted"
    VALIDATING = "validating"
    PROVIDER_STARTING = "provider_starting"
    READY = "ready"
    STREAMING = "streaming"
    FINALIZING = "finalizing"
    TERMINAL = "terminal"
    CLOSED = "closed"


class StreamingAsrSession:
    """Own every task and resource created for one client connection."""

    def __init__(
        self,
        *,
        socket: Any,
        provider: StreamingAsrProvider,
        voice_session_id: str,
        duration_limit_seconds: int,
        validate_audio_frame: Callable[[bytes], None],
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        provider_start_timeout_seconds: float,
        provider_final_timeout_seconds: float,
        provider_cleanup_timeout_seconds: float,
    ) -> None:
        self._socket = socket
        self._provider = provider
        self._voice_session_id = voice_session_id
        self._duration_limit_seconds = duration_limit_seconds
        self._validate_audio_frame = validate_audio_frame
        self._sleep = sleep
        self._provider_start_timeout_seconds = provider_start_timeout_seconds
        self._provider_final_timeout_seconds = provider_final_timeout_seconds
        self._provider_cleanup_timeout_seconds = provider_cleanup_timeout_seconds

        self._phase = SessionPhase.ACCEPTED
        self._provider_start_task: asyncio.Task[None] | None = None
        self._provider_events_task: asyncio.Task[bool] | None = None
        self._client_receive_task: asyncio.Task[dict[str, Any]] | None = None
        self._timer_task: asyncio.Task[None] | None = None
        self._client_cancelled = asyncio.Event()
        self._close_lock = asyncio.Lock()
        self._terminal_event_sent = False
        self._provider_terminal = False
        self._client_gone = False
        self._superseded = False
        self._closed = False
        self._received_pcm_bytes = 0
        self._maximum_pcm_bytes = duration_limit_seconds * 16_000 * 2

    @property
    def phase(self) -> SessionPhase:
        return self._phase

    async def run(self) -> None:
        """Run until the client, provider, or deadline reaches a terminal state."""

        self._phase = SessionPhase.VALIDATING
        pending_message = await self._start_provider()
        if self._closed or self._phase in {
            SessionPhase.TERMINAL,
            SessionPhase.CLOSED,
        }:
            return

        self._phase = SessionPhase.READY
        if not await self._send_json(
            {"type": "ready", "voiceSessionId": self._voice_session_id}
        ):
            self._phase = SessionPhase.TERMINAL
            return

        self._phase = SessionPhase.STREAMING
        self._provider_events_task = asyncio.create_task(
            self._forward_provider_events()
        )
        self._timer_task = asyncio.create_task(
            self._sleep(self._duration_limit_seconds)
        )
        await self._stream(pending_message)
        self._phase = SessionPhase.TERMINAL

    async def supersede(self) -> None:
        """Cancel this session because a newer same-user session won ownership."""

        self._superseded = True
        self._client_cancelled.set()
        self._phase = SessionPhase.TERMINAL
        await self.close()

    async def close(self) -> None:
        """Idempotently drain tasks and close provider/client within one deadline."""

        async with self._close_lock:
            if self._closed:
                return
            self._closed = True
            self._phase = SessionPhase.TERMINAL

            current = asyncio.current_task()
            tasks = (
                self._provider_start_task,
                self._provider_events_task,
                self._client_receive_task,
                self._timer_task,
            )
            for task in tasks:
                if task is not None and task is not current and not task.done():
                    task.cancel()
            drainable = [
                task for task in tasks if task is not None and task is not current
            ]
            if drainable:
                await _bounded_cleanup(
                    asyncio.gather(*drainable, return_exceptions=True),
                    timeout=self._provider_cleanup_timeout_seconds,
                )

            if not self._provider_terminal:
                await _bounded_cleanup(
                    self._provider.cancel(),
                    timeout=self._provider_cleanup_timeout_seconds,
                )
            if not self._client_gone:
                await _bounded_cleanup(
                    self._socket.close(code=1000),
                    timeout=self._provider_cleanup_timeout_seconds,
                )
            self._phase = SessionPhase.CLOSED

    async def _start_provider(self) -> dict[str, Any] | None:
        self._phase = SessionPhase.PROVIDER_STARTING
        self._provider_start_task = asyncio.create_task(self._provider.start())
        self._client_receive_task = asyncio.create_task(self._socket.receive())

        done, _ = await asyncio.wait(
            {self._provider_start_task, self._client_receive_task},
            timeout=self._provider_start_timeout_seconds,
            return_when=asyncio.FIRST_COMPLETED,
        )
        if not done:
            await self._send_error("service_unavailable")
            self._phase = SessionPhase.TERMINAL
            return None

        pending_message: dict[str, Any] | None = None
        if self._client_receive_task in done:
            try:
                pending_message = self._client_receive_task.result()
            except asyncio.CancelledError:
                if self._superseded or self._closed:
                    self._phase = SessionPhase.TERMINAL
                    return None
                raise
            except Exception:
                self._client_gone = True
                self._phase = SessionPhase.TERMINAL
                return None
            if self._is_disconnect(pending_message):
                self._client_gone = True
                self._client_cancelled.set()
                self._phase = SessionPhase.TERMINAL
                return None
            if self._is_cancel(pending_message):
                self._client_cancelled.set()
                self._phase = SessionPhase.TERMINAL
                return None
            if self._provider_start_task not in done:
                await self._send_error("unsupported_audio")
                self._phase = SessionPhase.TERMINAL
                return None
        else:
            self._client_receive_task.cancel()
            await _drain_task(self._client_receive_task)
            self._client_receive_task = None

        try:
            await self._provider_start_task
        except StreamingAsrProviderError as exc:
            await self._send_error(_safe_provider_code(exc.code))
            self._phase = SessionPhase.TERMINAL
            return None
        except asyncio.CancelledError:
            if self._superseded or self._closed:
                self._phase = SessionPhase.TERMINAL
                return None
            raise
        except Exception:
            await self._send_error("connection_failed")
            self._phase = SessionPhase.TERMINAL
            return None
        return pending_message

    async def _stream(self, pending_message: dict[str, Any] | None) -> None:
        assert self._provider_events_task is not None
        assert self._timer_task is not None

        while True:
            if pending_message is None:
                self._client_receive_task = asyncio.create_task(self._socket.receive())
                done, _ = await asyncio.wait(
                    {
                        self._client_receive_task,
                        self._provider_events_task,
                        self._timer_task,
                    },
                    return_when=asyncio.FIRST_COMPLETED,
                )
                if self._provider_events_task in done:
                    await self._cancel_receive()
                    self._provider_terminal = await self._provider_events_task
                    return
                if self._timer_task in done:
                    await self._cancel_receive()
                    await self._finalize()
                    return
                try:
                    pending_message = self._client_receive_task.result()
                except Exception:
                    self._client_gone = True
                    return

            message = pending_message
            pending_message = None
            self._client_receive_task = None
            if self._is_disconnect(message):
                self._client_gone = True
                return

            frame = message.get("bytes")
            if isinstance(frame, bytes):
                try:
                    self._validate_audio_frame(frame)
                    if self._received_pcm_bytes + len(frame) > self._maximum_pcm_bytes:
                        raise ValueError("audio duration exceeds mode limit")
                    self._received_pcm_bytes += len(frame)
                    await self._provider.send_audio(frame)
                except ValueError:
                    await self._send_error("unsupported_audio")
                    return
                except StreamingAsrProviderError as exc:
                    await self._send_error(_safe_provider_code(exc.code))
                    return
                continue

            control = self._parse_control(message)
            if control is None:
                await self._send_error("unsupported_audio")
                return
            control_type = control.get("type")
            if control_type == "cancel":
                self._client_cancelled.set()
                return
            if control_type == "stop":
                await self._finalize()
                return
            await self._send_error("unsupported_audio")
            return

    async def _finalize(self) -> None:
        assert self._provider_events_task is not None
        self._phase = SessionPhase.FINALIZING

        async def finish_and_wait() -> bool:
            await self._provider.finish()
            return await asyncio.shield(self._provider_events_task)

        try:
            self._provider_terminal = await asyncio.wait_for(
                finish_and_wait(),
                timeout=self._provider_final_timeout_seconds,
            )
        except asyncio.TimeoutError:
            await self._send_error("service_unavailable")
        except StreamingAsrProviderError as exc:
            await self._send_error(_safe_provider_code(exc.code))
        except asyncio.CancelledError:
            if self._superseded or self._closed:
                return
            raise
        except Exception:
            await self._send_error("connection_lost")

    async def _forward_provider_events(self) -> bool:
        last_sequence = 0
        try:
            async for event in self._provider.events():
                if self._client_cancelled.is_set():
                    return True
                if event.sequence <= last_sequence:
                    continue
                last_sequence = event.sequence
                if event.kind == ProviderEventKind.FINAL:
                    text = event.text.strip()
                    if not text:
                        await self._send_error("no_speech")
                    else:
                        await self._send_terminal(
                            {
                                "type": "final",
                                "voiceSessionId": self._voice_session_id,
                                "sequence": event.sequence,
                                "text": text,
                                "audioDurationMs": event.duration_ms,
                            }
                        )
                    return True
                if not await self._send_json(
                    {
                        "type": event.kind.value,
                        "voiceSessionId": self._voice_session_id,
                        "sequence": event.sequence,
                        "text": event.text,
                    }
                ):
                    return False
        except StreamingAsrProviderError as exc:
            await self._send_error(_safe_provider_code(exc.code))
            return True
        except asyncio.CancelledError:
            raise
        except Exception:
            if not self._client_cancelled.is_set():
                await self._send_error("connection_lost")
            return True

        if not self._client_cancelled.is_set():
            await self._send_error("connection_lost")
        return True

    async def _send_error(self, code: str) -> None:
        await self._send_terminal(
            {
                "type": "error",
                "voiceSessionId": self._voice_session_id,
                "code": code,
                "retryable": code in _RETRYABLE_CODES,
            }
        )

    async def _send_terminal(self, value: dict[str, Any]) -> None:
        if self._terminal_event_sent or self._client_gone:
            return
        self._terminal_event_sent = True
        await self._send_json(value)

    async def _send_json(self, value: dict[str, Any]) -> bool:
        if self._client_gone:
            return False
        try:
            await self._socket.send_json(value)
            return True
        except Exception:
            self._client_gone = True
            return False

    async def _cancel_receive(self) -> None:
        task = self._client_receive_task
        if task is not None and not task.done():
            task.cancel()
        if task is not None:
            await _drain_task(task)
        self._client_receive_task = None

    @staticmethod
    def _is_disconnect(message: dict[str, Any]) -> bool:
        return message.get("type") == "websocket.disconnect"

    def _is_cancel(self, message: dict[str, Any]) -> bool:
        control = self._parse_control(message)
        return control is not None and control.get("type") == "cancel"

    def _parse_control(self, message: dict[str, Any]) -> dict[str, Any] | None:
        raw = message.get("text")
        try:
            value = json.loads(raw) if isinstance(raw, str) else None
        except ValueError:
            return None
        if (
            not isinstance(value, dict)
            or value.get("voiceSessionId") != self._voice_session_id
        ):
            return None
        return value


def _safe_provider_code(code: str) -> str:
    if code in {"connection_failed", "connection_lost", "service_unavailable"}:
        return code
    return "service_unavailable"


async def _drain_task(task: asyncio.Task[Any]) -> None:
    try:
        await task
    except (asyncio.CancelledError, Exception):
        pass


async def _bounded_cleanup(awaitable: Awaitable[Any], *, timeout: float) -> None:
    try:
        await asyncio.wait_for(awaitable, timeout=timeout)
    except (asyncio.TimeoutError, asyncio.CancelledError, Exception):
        pass
