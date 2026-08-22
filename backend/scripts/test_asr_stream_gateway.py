"""Deterministic gateway tests for mobile streaming ASR.

Run from backend/:
    python -m scripts.test_asr_stream_gateway
"""

from __future__ import annotations

import asyncio
import json
from collections import deque
from typing import Any

from api.asr_stream import authenticate_websocket, serve_asr_websocket
from core.asr.provider import (
    ProviderEventKind,
    ProviderTranscriptEvent,
    StreamingAsrProviderError,
)
from core.asr.streaming import (
    AsrSessionRegistry,
    SlidingWindowRateLimiter,
    StreamingAsrGateway,
    duration_limit_for,
    validate_audio_frame,
)


class _FakeClientSocket:
    def __init__(self, incoming: list[dict[str, Any]], *, headers: dict[str, str] | None = None):
        self.headers = headers or {}
        self._incoming: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        for item in incoming:
            self._incoming.put_nowait(item)
        self.sent: list[dict[str, Any]] = []
        self.accept_count = 0
        self.closed_codes: list[int] = []

    async def accept(self) -> None:
        self.accept_count += 1

    async def close(self, code: int = 1000) -> None:
        self.closed_codes.append(code)

    async def receive(self) -> dict[str, Any]:
        return await self._incoming.get()

    async def send_json(self, value: dict[str, Any]) -> None:
        self.sent.append(value)

    def queue(self, value: dict[str, Any]) -> None:
        self._incoming.put_nowait(value)


class _FakeProvider:
    def __init__(self, *, final_text: str = "你好 world", fail: bool = False):
        self.final_text = final_text
        self.fail = fail
        self.started = 0
        self.frames: list[bytes] = []
        self.finish_count = 0
        self.cancel_count = 0
        self._events: asyncio.Queue[ProviderTranscriptEvent | Exception | None] = (
            asyncio.Queue()
        )

    async def start(self) -> None:
        self.started += 1
        await self._events.put(
            ProviderTranscriptEvent(ProviderEventKind.PARTIAL, 1, "你好", 400)
        )
        # Duplicate/stale event must not regress or be forwarded twice.
        await self._events.put(
            ProviderTranscriptEvent(ProviderEventKind.PARTIAL, 1, "旧", 300)
        )

    async def send_audio(self, frame: bytes) -> None:
        self.frames.append(frame)

    async def finish(self) -> None:
        self.finish_count += 1
        if self.fail:
            await self._events.put(
                StreamingAsrProviderError(
                    "service_unavailable", "provider secret must not cross gateway"
                )
            )
        else:
            await self._events.put(
                ProviderTranscriptEvent(
                    ProviderEventKind.STABLE, 2, self.final_text, 900
                )
            )
            await self._events.put(
                ProviderTranscriptEvent(
                    ProviderEventKind.FINAL, 3, self.final_text, 1000
                )
            )
        await self._events.put(None)

    async def cancel(self) -> None:
        self.cancel_count += 1
        await self._events.put(None)

    async def events(self):
        while True:
            item = await self._events.get()
            if item is None:
                return
            if isinstance(item, Exception):
                raise item
            yield item


class _HangingStartProvider(_FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.start_cancelled = 0
        self.start_entered = asyncio.Event()
        self._never_ready = asyncio.Event()

    async def start(self) -> None:
        self.started += 1
        self.start_entered.set()
        try:
            await self._never_ready.wait()
        except asyncio.CancelledError:
            self.start_cancelled += 1
            raise


class _CleanupFailProvider(_HangingStartProvider):
    async def cancel(self) -> None:
        self.cancel_count += 1
        raise RuntimeError("cleanup failed")


class _DuplicateFinalProvider(_FakeProvider):
    async def finish(self) -> None:
        self.finish_count += 1
        for sequence, text in ((2, "first"), (3, "second")):
            await self._events.put(
                ProviderTranscriptEvent(
                    ProviderEventKind.FINAL,
                    sequence,
                    text,
                    1000,
                )
            )
        await self._events.put(None)


class _HangingFinishProvider(_FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.finish_entered = asyncio.Event()
        self._never_finishes = asyncio.Event()

    async def finish(self) -> None:
        self.finish_count += 1
        self.finish_entered.set()
        await self._never_finishes.wait()


class _HangingSendProvider(_FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.send_entered = asyncio.Event()

    async def send_audio(self, frame: bytes) -> None:
        self.send_entered.set()
        await asyncio.Event().wait()


class _HangingCleanupProvider(_HangingStartProvider):
    def __init__(self) -> None:
        super().__init__()
        self.cleanup_entered = asyncio.Event()

    async def cancel(self) -> None:
        self.cancel_count += 1
        self.cleanup_entered.set()
        await asyncio.Event().wait()


class _ReadyStartProvider(_FakeProvider):
    def __init__(self, *, final_text: str) -> None:
        super().__init__(final_text=final_text)
        self.start_entered = asyncio.Event()

    async def start(self) -> None:
        self.start_entered.set()
        await super().start()


class _FailingSendSocket(_FakeClientSocket):
    def __init__(self, incoming: list[dict[str, Any]], *, fail_after: int):
        super().__init__(incoming)
        self._send_count = 0
        self._fail_after = fail_after

    async def send_json(self, value: dict[str, Any]) -> None:
        self._send_count += 1
        if self._send_count > self._fail_after:
            raise RuntimeError("client disconnected while sending")
        await super().send_json(value)


class _SupersedableSession:
    def __init__(self) -> None:
        self.supersede_count = 0

    async def supersede(self) -> None:
        self.supersede_count += 1


def _text(value: dict[str, Any]) -> dict[str, Any]:
    return {"type": "websocket.receive", "text": json.dumps(value)}


def _bytes(value: bytes) -> dict[str, Any]:
    return {"type": "websocket.receive", "bytes": value}


def _start(session_id: str = "voice-session", mode: str = "ordinary") -> dict[str, Any]:
    return _text(
        {
            "type": "start",
            "voiceSessionId": session_id,
            "mode": mode,
            "audio": {
                "encoding": "pcm_s16le",
                "sampleRate": 16000,
                "channels": 1,
            },
        }
    )


async def test_authentication_happens_before_accept_or_provider_allocation() -> None:
    created = 0

    def provider_factory() -> _FakeProvider:
        nonlocal created
        created += 1
        return _FakeProvider()

    socket = _FakeClientSocket(
        [_start()], headers={"authorization": "Bearer invalid-token"}
    )
    gateway = StreamingAsrGateway(provider_factory=provider_factory)

    await serve_asr_websocket(
        socket,
        gateway=gateway,
        token_decoder=lambda _: None,
    )

    assert created == 0
    assert socket.accept_count == 0
    assert socket.closed_codes == [4401]


async def test_valid_stream_forwards_audio_and_normalizes_events() -> None:
    provider = _FakeProvider()
    socket = _FakeClientSocket(
        [
            _start(),
            _bytes(b"\x01\x00\x02\x00"),
            _text({"type": "stop", "voiceSessionId": "voice-session"}),
        ],
        headers={"authorization": "Bearer valid-token"},
    )
    gateway = StreamingAsrGateway(provider_factory=lambda: provider)

    await serve_asr_websocket(
        socket,
        gateway=gateway,
        token_decoder=lambda _: {"sub": "user-1"},
    )

    assert socket.accept_count == 1
    assert provider.started == 1
    assert provider.frames == [b"\x01\x00\x02\x00"]
    assert provider.finish_count == 1
    assert [event["type"] for event in socket.sent] == [
        "ready",
        "partial",
        "stable",
        "final",
    ]
    assert socket.sent[1]["sequence"] == 1
    assert socket.sent[2]["sequence"] == 2
    assert socket.sent[3] == {
        "type": "final",
        "voiceSessionId": "voice-session",
        "sequence": 3,
        "text": "你好 world",
        "audioDurationMs": 1000,
    }


async def test_cancel_discards_provider_and_sends_no_terminal_text() -> None:
    provider = _FakeProvider()
    socket = _FakeClientSocket(
        [
            _start(mode="reka"),
            _text({"type": "cancel", "voiceSessionId": "voice-session"}),
        ]
    )
    gateway = StreamingAsrGateway(provider_factory=lambda: provider)

    await gateway.handle(socket, user_id="user-1")

    assert provider.cancel_count == 1
    assert provider.finish_count == 0
    assert all(event["type"] not in {"stable", "final", "error"} for event in socket.sent)


async def test_provider_error_is_redacted() -> None:
    provider = _FakeProvider(fail=True)
    socket = _FakeClientSocket(
        [
            _start(),
            _text({"type": "stop", "voiceSessionId": "voice-session"}),
        ]
    )
    gateway = StreamingAsrGateway(provider_factory=lambda: provider)

    await gateway.handle(socket, user_id="user-1")

    errors = [event for event in socket.sent if event["type"] == "error"]
    assert errors == [
        {
            "type": "error",
            "voiceSessionId": "voice-session",
            "code": "service_unavailable",
            "retryable": True,
        }
    ]
    assert "secret" not in json.dumps(socket.sent)


async def test_empty_final_becomes_no_speech() -> None:
    provider = _FakeProvider(final_text="")
    socket = _FakeClientSocket(
        [
            _start(),
            _text({"type": "stop", "voiceSessionId": "voice-session"}),
        ]
    )
    gateway = StreamingAsrGateway(provider_factory=lambda: provider)

    await gateway.handle(socket, user_id="user-1")

    assert socket.sent[-1] == {
        "type": "error",
        "voiceSessionId": "voice-session",
        "code": "no_speech",
        "retryable": True,
    }


async def test_registry_and_rate_limiter_fail_closed() -> None:
    registry = AsrSessionRegistry()
    first = _SupersedableSession()
    second = _SupersedableSession()
    first_lease, replaced = await registry.install("user-1", first)
    assert replaced is None
    second_lease, replaced = await registry.install("user-1", second)
    assert replaced is first
    assert await registry.release(first_lease) is False
    assert await registry.release(second_lease) is True

    now = [100.0]
    limiter = SlidingWindowRateLimiter(limit=2, clock=lambda: now[0])
    assert await limiter.allow("user-1") is True
    assert await limiter.allow("user-1") is True
    assert await limiter.allow("user-1") is False
    now[0] += 61
    assert await limiter.allow("user-1") is True
    now[0] += 61
    assert await limiter.allow("current-user") is True
    assert set(limiter._starts) == {"current-user"}


async def test_provider_start_timeout_cleans_up_and_releases_user() -> None:
    provider = _HangingStartProvider()
    registry = AsrSessionRegistry()
    socket = _FakeClientSocket([_start()])
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_start_timeout_seconds=0.01,
    )

    await gateway.handle(socket, user_id="user-1")

    assert socket.sent == [
        {
            "type": "error",
            "voiceSessionId": "voice-session",
            "code": "service_unavailable",
            "retryable": True,
        }
    ]
    assert provider.started == 1
    assert provider.start_cancelled == 1
    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")
    probe_lease, _ = await registry.install("user-1", _SupersedableSession())
    assert await registry.release(probe_lease) is True


async def test_disconnect_during_provider_start_cancels_immediately() -> None:
    provider = _HangingStartProvider()
    registry = AsrSessionRegistry()
    socket = _FakeClientSocket(
        [_start(), {"type": "websocket.disconnect"}],
    )
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_start_timeout_seconds=1.0,
    )

    await asyncio.wait_for(
        gateway.handle(socket, user_id="user-1"),
        timeout=0.1,
    )

    assert socket.sent == []
    assert provider.started == 1
    assert provider.start_cancelled == 1
    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")
    probe_lease, _ = await registry.install("user-1", _SupersedableSession())
    assert await registry.release(probe_lease) is True


async def test_cleanup_failure_still_releases_user() -> None:
    provider = _CleanupFailProvider()
    registry = AsrSessionRegistry()
    socket = _FakeClientSocket([_start()])
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_start_timeout_seconds=0.01,
    )

    await gateway.handle(socket, user_id="user-1")

    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")
    probe_lease, _ = await registry.install("user-1", _SupersedableSession())
    assert await registry.release(probe_lease) is True


async def test_terminal_event_is_emitted_at_most_once() -> None:
    provider = _DuplicateFinalProvider()
    socket = _FakeClientSocket(
        [
            _start(),
            _text({"type": "stop", "voiceSessionId": "voice-session"}),
        ]
    )
    gateway = StreamingAsrGateway(provider_factory=lambda: provider)

    await gateway.handle(socket, user_id="user-1")

    terminal = [event for event in socket.sent if event["type"] in {"final", "error"}]
    assert len(terminal) == 1
    assert terminal[0]["text"] == "first"


async def test_registry_releases_only_the_exact_installed_lease() -> None:
    registry = AsrSessionRegistry()
    first = _SupersedableSession()
    second = _SupersedableSession()

    first_lease, replaced = await registry.install("user-1", first)
    assert replaced is None
    second_lease, replaced = await registry.install("user-1", second)
    assert replaced is first

    assert await registry.release(first_lease) is False
    assert await registry.is_active("user-1")
    assert await registry.release(second_lease) is True
    assert not await registry.is_active("user-1")


async def test_new_same_user_session_supersedes_stalled_session() -> None:
    stalled = _HangingStartProvider()
    replacement = _FakeProvider(final_text="replacement")
    providers = deque([stalled, replacement])
    registry = AsrSessionRegistry()
    gateway = StreamingAsrGateway(
        provider_factory=providers.popleft,
        registry=registry,
        provider_start_timeout_seconds=5.0,
    )
    first_socket = _FakeClientSocket([_start("old")])
    second_socket = _FakeClientSocket(
        [
            _start("new"),
            _text({"type": "stop", "voiceSessionId": "new"}),
        ]
    )
    first_task = asyncio.create_task(gateway.handle(first_socket, user_id="user-1"))
    await asyncio.wait_for(stalled.start_entered.wait(), timeout=0.1)

    try:
        await asyncio.wait_for(
            gateway.handle(second_socket, user_id="user-1"),
            timeout=0.2,
        )
        await asyncio.wait_for(first_task, timeout=0.2)
    finally:
        if not first_task.done():
            first_task.cancel()
            try:
                await first_task
            except asyncio.CancelledError:
                pass

    assert stalled.start_cancelled == 1
    assert stalled.cancel_count == 1
    assert [event["type"] for event in second_socket.sent] == [
        "ready",
        "partial",
        "stable",
        "final",
    ]
    assert all(event.get("code") != "rate_limited" for event in second_socket.sent)
    assert not await registry.is_active("user-1")


async def test_stalled_user_does_not_delay_another_user() -> None:
    stalled = _HangingStartProvider()
    other = _FakeProvider(final_text="other user")
    providers = deque([stalled, other])
    registry = AsrSessionRegistry()
    gateway = StreamingAsrGateway(
        provider_factory=providers.popleft,
        registry=registry,
        provider_start_timeout_seconds=5.0,
    )
    first_task = asyncio.create_task(
        gateway.handle(_FakeClientSocket([_start("a")]), user_id="user-a")
    )
    await asyncio.wait_for(stalled.start_entered.wait(), timeout=0.1)
    other_socket = _FakeClientSocket(
        [
            _start("b"),
            _text({"type": "stop", "voiceSessionId": "b"}),
        ]
    )

    await asyncio.wait_for(
        gateway.handle(other_socket, user_id="user-b"),
        timeout=0.2,
    )
    first_task.cancel()
    try:
        await first_task
    except asyncio.CancelledError:
        pass

    assert other.finish_count == 1
    assert other_socket.sent[-1]["type"] == "final"


async def test_replacement_start_does_not_wait_for_old_cleanup() -> None:
    stalled = _HangingCleanupProvider()
    replacement = _ReadyStartProvider(final_text="replacement")
    providers = deque([stalled, replacement])
    gateway = StreamingAsrGateway(
        provider_factory=providers.popleft,
        registry=AsrSessionRegistry(),
        provider_start_timeout_seconds=5.0,
        provider_cleanup_timeout_seconds=0.05,
    )
    first_task = asyncio.create_task(
        gateway.handle(_FakeClientSocket([_start("old")]), user_id="user-1")
    )
    await asyncio.wait_for(stalled.start_entered.wait(), timeout=0.1)
    second_socket = _FakeClientSocket(
        [
            _start("new"),
            _text({"type": "stop", "voiceSessionId": "new"}),
        ]
    )
    second_task = asyncio.create_task(
        gateway.handle(second_socket, user_id="user-1")
    )

    try:
        await asyncio.wait_for(replacement.start_entered.wait(), timeout=0.02)
    finally:
        await asyncio.wait_for(
            asyncio.gather(first_task, second_task, return_exceptions=True),
            timeout=0.3,
        )

    assert second_socket.sent[-1]["type"] == "final"


async def test_finalization_timeout_is_bounded_and_releases_user() -> None:
    provider = _HangingFinishProvider()
    registry = AsrSessionRegistry()
    socket = _FakeClientSocket(
        [
            _start(),
            _text({"type": "stop", "voiceSessionId": "voice-session"}),
        ]
    )
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_final_timeout_seconds=0.01,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.1)

    assert provider.finish_count == 1
    assert provider.cancel_count == 1
    assert socket.sent[-1]["code"] == "service_unavailable"
    assert not await registry.is_active("user-1")


async def test_provider_audio_send_timeout_is_bounded_and_releases_user() -> None:
    provider = _HangingSendProvider()
    registry = AsrSessionRegistry()
    socket = _FakeClientSocket([_start(), _bytes(b"\x00\x00")])
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_send_timeout_seconds=0.01,
        provider_cleanup_timeout_seconds=0.01,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.2)

    assert provider.send_entered.is_set()
    assert socket.sent[-1]["code"] == "service_unavailable"
    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")


async def test_cleanup_timeout_is_bounded_and_releases_user() -> None:
    provider = _HangingCleanupProvider()
    registry = AsrSessionRegistry()
    socket = _FakeClientSocket([_start()])
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_start_timeout_seconds=0.01,
        provider_cleanup_timeout_seconds=0.01,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.1)

    assert provider.cleanup_entered.is_set()
    assert not await registry.is_active("user-1")


async def test_client_send_failure_cleans_provider_and_releases_user() -> None:
    provider = _FakeProvider()
    registry = AsrSessionRegistry()
    socket = _FailingSendSocket(
        [
            _start(),
            _text({"type": "stop", "voiceSessionId": "voice-session"}),
        ],
        fail_after=1,
    )
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.1)

    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")


async def test_cumulative_pcm_bytes_cannot_exceed_mode_limit() -> None:
    provider = _FakeProvider()
    registry = AsrSessionRegistry()
    one_second = b"\x00\x00" * 16_000
    socket = _FakeClientSocket(
        [_start(mode="reka"), *[_bytes(one_second) for _ in range(61)]]
    )
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.2)

    assert len(provider.frames) == 60
    assert socket.sent[-1] == {
        "type": "error",
        "voiceSessionId": "voice-session",
        "code": "unsupported_audio",
        "retryable": False,
    }
    assert not await registry.is_active("user-1")


def test_contract_validation_and_authoritative_limits() -> None:
    assert duration_limit_for("ordinary") == 300
    assert duration_limit_for("reka") == 60
    for invalid_mode in ("", "flash", "600"):
        try:
            duration_limit_for(invalid_mode)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid mode accepted: {invalid_mode}")

    validate_audio_frame(b"\x00\x00")
    for invalid in (b"", b"\x00", b"\x00" * 32002):
        try:
            validate_audio_frame(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"invalid audio frame accepted: {len(invalid)} bytes")


def test_bearer_parser_is_strict() -> None:
    decoder_calls: list[str] = []

    def decode(value: str) -> dict[str, str] | None:
        decoder_calls.append(value)
        return {"sub": "user-1"} if value == "valid" else None

    assert authenticate_websocket({}, token_decoder=decode) is None
    assert authenticate_websocket({"authorization": "Basic valid"}, token_decoder=decode) is None
    assert authenticate_websocket({"authorization": "Bearer valid"}, token_decoder=decode) == "user-1"
    assert decoder_calls == ["valid"]


async def _run() -> None:
    await test_authentication_happens_before_accept_or_provider_allocation()
    await test_valid_stream_forwards_audio_and_normalizes_events()
    await test_cancel_discards_provider_and_sends_no_terminal_text()
    await test_provider_error_is_redacted()
    await test_empty_final_becomes_no_speech()
    await test_registry_and_rate_limiter_fail_closed()
    await test_provider_start_timeout_cleans_up_and_releases_user()
    await test_disconnect_during_provider_start_cancels_immediately()
    await test_cleanup_failure_still_releases_user()
    await test_terminal_event_is_emitted_at_most_once()
    await test_registry_releases_only_the_exact_installed_lease()
    await test_new_same_user_session_supersedes_stalled_session()
    await test_stalled_user_does_not_delay_another_user()
    await test_replacement_start_does_not_wait_for_old_cleanup()
    await test_finalization_timeout_is_bounded_and_releases_user()
    await test_provider_audio_send_timeout_is_bounded_and_releases_user()
    await test_cleanup_timeout_is_bounded_and_releases_user()
    await test_client_send_failure_cleans_provider_and_releases_user()
    await test_cumulative_pcm_bytes_cannot_exceed_mode_limit()
    test_contract_validation_and_authoritative_limits()
    test_bearer_parser_is_strict()


def main() -> None:
    asyncio.run(_run())
    print("PASS - authenticated ASR gateway protocol and lifecycle")


if __name__ == "__main__":
    main()
