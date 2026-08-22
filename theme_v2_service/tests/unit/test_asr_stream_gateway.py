from __future__ import annotations

import asyncio
import json
from typing import Any

import pytest

from app.domains.asr.api import serve_asr_websocket
from app.domains.asr.provider import (
    ProviderEventKind,
    ProviderTranscriptEvent,
)
from app.domains.asr.streaming import (
    AsrSessionRegistry,
    SlidingWindowRateLimiter,
    StreamingAsrGateway,
)
from app.config import Settings
from app.main import app


class FakeClientSocket:
    def __init__(
        self,
        incoming: list[dict[str, Any]],
        *,
        headers: dict[str, str] | None = None,
    ) -> None:
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


class HangingSendClientSocket(FakeClientSocket):
    def __init__(self, incoming: list[dict[str, Any]]) -> None:
        super().__init__(incoming)
        self.send_entered = asyncio.Event()

    async def send_json(self, value: dict[str, Any]) -> None:
        self.send_entered.set()
        await asyncio.Event().wait()


class FakeProvider:
    def __init__(self) -> None:
        self.frames: list[bytes] = []
        self.cancel_count = 0
        self._events: asyncio.Queue[ProviderTranscriptEvent | None] = asyncio.Queue()

    async def start(self) -> None:
        return None

    async def send_audio(self, frame: bytes) -> None:
        self.frames.append(frame)

    async def finish(self) -> None:
        await self._events.put(
            ProviderTranscriptEvent(ProviderEventKind.FINAL, 1, "你好 world", 100)
        )
        await self._events.put(None)

    async def cancel(self) -> None:
        self.cancel_count += 1
        await self._events.put(None)

    async def events(self):
        while True:
            event = await self._events.get()
            if event is None:
                return
            yield event


class HangingSendProvider(FakeProvider):
    def __init__(self) -> None:
        super().__init__()
        self.send_entered = asyncio.Event()

    async def send_audio(self, frame: bytes) -> None:
        self.send_entered.set()
        await asyncio.Event().wait()


def text(value: dict[str, Any]) -> dict[str, Any]:
    return {"type": "websocket.receive", "text": json.dumps(value)}


def start(session_id: str = "voice-session") -> dict[str, Any]:
    return text(
        {
            "type": "start",
            "voiceSessionId": session_id,
            "mode": "ordinary",
            "audio": {
                "encoding": "pcm_s16le",
                "sampleRate": 16000,
                "channels": 1,
            },
        }
    )


def test_theme_v2_registers_the_mobile_streaming_route() -> None:
    assert str(app.url_path_for("asr_stream")) == "/api/asr/stream"


def test_qwen_streaming_configuration_is_fail_closed() -> None:
    disabled = Settings(_env_file=None)
    assert disabled.asr_readiness_errors() == []
    with pytest.raises(RuntimeError, match="disabled"):
        disabled.validate_asr()

    missing = Settings(
        _env_file=None,
        streaming_asr_enabled=True,
        dashscope_api_key=None,
        dashscope_asr_ws_url="",
    )
    assert "DASHSCOPE_API_KEY is required" in missing.asr_readiness_errors()

    configured = Settings(
        _env_file=None,
        streaming_asr_enabled=True,
        dashscope_api_key="sk-test-only",
        dashscope_asr_ws_url=(
            "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
        ),
    )
    configured.validate_asr()


@pytest.mark.asyncio
async def test_rate_limiter_sweeps_expired_inactive_users() -> None:
    now = [0.0]
    limiter = SlidingWindowRateLimiter(limit=2, clock=lambda: now[0])

    assert await limiter.allow("inactive-user")
    now[0] = 61.0
    assert await limiter.allow("current-user")

    assert set(limiter._starts) == {"current-user"}


@pytest.mark.asyncio
async def test_authentication_happens_before_accept_or_provider_allocation() -> None:
    created = 0

    def provider_factory() -> FakeProvider:
        nonlocal created
        created += 1
        return FakeProvider()

    socket = FakeClientSocket(
        [start()], headers={"authorization": "Bearer invalid-token"}
    )

    await serve_asr_websocket(
        socket,
        gateway=StreamingAsrGateway(provider_factory=provider_factory),
        token_decoder=lambda _: None,
    )

    assert created == 0
    assert socket.accept_count == 0
    assert socket.closed_codes == [4401]


@pytest.mark.asyncio
async def test_provider_audio_send_timeout_is_terminal_and_releases_user() -> None:
    provider = HangingSendProvider()
    registry = AsrSessionRegistry()
    socket = FakeClientSocket(
        [
            start(),
            {"type": "websocket.receive", "bytes": b"\x00\x00"},
        ]
    )
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        provider_send_timeout_seconds=0.01,
        provider_cleanup_timeout_seconds=0.01,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.2)

    assert provider.send_entered.is_set()
    assert socket.sent[-1] == {
        "type": "error",
        "voiceSessionId": "voice-session",
        "code": "service_unavailable",
        "retryable": True,
    }
    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")


@pytest.mark.asyncio
async def test_client_write_timeout_releases_provider_and_user_lease() -> None:
    provider = FakeProvider()
    registry = AsrSessionRegistry()
    socket = HangingSendClientSocket([start()])
    gateway = StreamingAsrGateway(
        provider_factory=lambda: provider,
        registry=registry,
        client_send_timeout_seconds=0.01,
        provider_cleanup_timeout_seconds=0.01,
    )

    await asyncio.wait_for(gateway.handle(socket, user_id="user-1"), timeout=0.2)

    assert socket.send_entered.is_set()
    assert provider.cancel_count == 1
    assert not await registry.is_active("user-1")
