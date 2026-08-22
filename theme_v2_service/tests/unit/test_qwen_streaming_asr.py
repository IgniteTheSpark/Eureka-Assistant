from __future__ import annotations

import json
from collections import deque
from typing import Any

import pytest

from app.domains.asr.provider import ProviderEventKind, StreamingAsrProviderError
from app.domains.asr.qwen_streaming import QwenStreamingAsrProvider


class FakeQwenSocket:
    def __init__(self, inbound: list[dict[str, Any]]) -> None:
        self._inbound = deque(json.dumps(item) for item in inbound)
        self.sent: list[str | bytes] = []
        self.close_count = 0

    async def send(self, value: str | bytes) -> None:
        self.sent.append(value)

    async def recv(self) -> str:
        return self._inbound.popleft()

    async def close(self) -> None:
        self.close_count += 1


def started() -> dict[str, Any]:
    return {"header": {"event": "task-started", "task_id": "provider-task"}}


def result(text: str, *, sentence_end: bool, end_time: int) -> dict[str, Any]:
    return {
        "header": {"event": "result-generated", "task_id": "provider-task"},
        "payload": {
            "output": {
                "sentence": {
                    "text": text,
                    "sentence_end": sentence_end,
                    "end_time": end_time,
                }
            }
        },
    }


def provider_for(
    inbound: list[dict[str, Any]],
) -> tuple[QwenStreamingAsrProvider, FakeQwenSocket, list[dict[str, Any]]]:
    socket = FakeQwenSocket(inbound)
    calls: list[dict[str, Any]] = []

    async def connect(url: str, **kwargs: Any) -> FakeQwenSocket:
        calls.append({"url": url, **kwargs})
        return socket

    provider = QwenStreamingAsrProvider(
        api_key="sk-test-only",
        ws_url=(
            "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
        ),
        model="qwen-audio-3.0-asr-flash-streaming",
        connector=connect,
        task_id_factory=lambda: "client-task",
    )
    return provider, socket, calls


@pytest.mark.asyncio
async def test_qwen_start_uses_workspace_protocol_and_bearer_key() -> None:
    provider, socket, calls = provider_for([started()])

    await provider.start()

    assert calls[0]["additional_headers"] == {
        "Authorization": "Bearer sk-test-only"
    }
    request = json.loads(socket.sent[0])
    assert request["header"] == {
        "action": "run-task",
        "task_id": "client-task",
        "streaming": "duplex",
    }
    assert request["payload"]["model"] == "qwen-audio-3.0-asr-flash-streaming"
    assert request["payload"]["parameters"] == {
        "format": "pcm",
        "sample_rate": 16000,
    }


@pytest.mark.asyncio
async def test_qwen_orders_partial_stable_and_final_transcripts() -> None:
    provider, socket, _ = provider_for(
        [
            started(),
            result("你好", sentence_end=False, end_time=300),
            result("你好世界。", sentence_end=True, end_time=800),
            {"header": {"event": "task-finished", "task_id": "provider-task"}},
        ]
    )
    await provider.start()

    await provider.send_audio(b"\x01\x00")
    events = [event async for event in provider.events()]

    assert socket.sent[1] == b"\x01\x00"
    assert [(event.kind, event.sequence, event.text) for event in events] == [
        (ProviderEventKind.PARTIAL, 1, "你好"),
        (ProviderEventKind.STABLE, 2, "你好世界。"),
        (ProviderEventKind.FINAL, 3, "你好世界。"),
    ]
    assert events[-1].duration_ms == 800
    assert socket.close_count == 1


@pytest.mark.asyncio
async def test_qwen_redacts_provider_failure_details() -> None:
    provider, _, _ = provider_for(
        [
            started(),
            {
                "header": {
                    "event": "task-failed",
                    "error_code": "InvalidApiKey",
                    "error_message": "secret provider body",
                }
            },
        ]
    )
    await provider.start()

    with pytest.raises(StreamingAsrProviderError) as caught:
        _ = [event async for event in provider.events()]

    assert caught.value.code == "service_unavailable"
    assert str(caught.value) == "Qwen ASR failed"
    assert "secret" not in str(caught.value)
