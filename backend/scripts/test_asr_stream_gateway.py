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
    assert await registry.acquire("user-1") is True
    assert await registry.acquire("user-1") is False
    await registry.release("user-1")
    assert await registry.acquire("user-1") is True

    now = [100.0]
    limiter = SlidingWindowRateLimiter(limit=2, clock=lambda: now[0])
    assert await limiter.allow("user-1") is True
    assert await limiter.allow("user-1") is True
    assert await limiter.allow("user-1") is False
    now[0] += 61
    assert await limiter.allow("user-1") is True


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
    test_contract_validation_and_authoritative_limits()
    test_bearer_parser_is_strict()


def main() -> None:
    asyncio.run(_run())
    print("PASS - authenticated ASR gateway protocol and lifecycle")


if __name__ == "__main__":
    main()
