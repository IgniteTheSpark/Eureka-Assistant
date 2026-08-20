"""Deterministic tests for the Alibaba Qwen streaming ASR adapter.

No network or real provider credentials are used.

Run from backend/:
    python -m scripts.test_qwen_streaming_asr
"""

from __future__ import annotations

import asyncio
import json
from collections import deque
from typing import Any

from core.asr.provider import ProviderEventKind, StreamingAsrProviderError
from core.asr.qwen_streaming import QwenStreamingAsrProvider


class _FakeSocket:
    def __init__(self, inbound: list[dict[str, Any]]):
        self._inbound = deque(json.dumps(item) for item in inbound)
        self.sent: list[str | bytes] = []
        self.close_count = 0

    async def send(self, value: str | bytes) -> None:
        self.sent.append(value)

    async def recv(self) -> str:
        if not self._inbound:
            raise AssertionError("fake upstream has no queued event")
        return self._inbound.popleft()

    async def close(self) -> None:
        self.close_count += 1


class _BlockingStartSocket(_FakeSocket):
    def __init__(self) -> None:
        super().__init__([])
        self.send_entered = asyncio.Event()

    async def send(self, value: str | bytes) -> None:
        self.sent.append(value)
        self.send_entered.set()
        await asyncio.Event().wait()


async def _provider(
    inbound: list[dict[str, Any]],
) -> tuple[QwenStreamingAsrProvider, _FakeSocket, list[dict[str, Any]]]:
    socket = _FakeSocket(inbound)
    connection_calls: list[dict[str, Any]] = []

    async def connect(url: str, **kwargs: Any) -> _FakeSocket:
        connection_calls.append({"url": url, **kwargs})
        return socket

    provider = QwenStreamingAsrProvider(
        api_key="sk-test-only",
        ws_url="wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
        model="qwen-audio-3.0-asr-flash-streaming",
        connector=connect,
        task_id_factory=lambda: "client-task-id",
    )
    return provider, socket, connection_calls


def _started() -> dict[str, Any]:
    return {"header": {"event": "task-started", "task_id": "provider-task-id"}}


def _result(text: str, *, sentence_end: bool, end_time: int) -> dict[str, Any]:
    return {
        "header": {"event": "result-generated", "task_id": "provider-task-id"},
        "payload": {
            "output": {
                "sentence": {
                    "text": text,
                    "sentence_end": sentence_end,
                    "begin_time": 0,
                    "end_time": end_time,
                }
            }
        },
    }


async def test_start_sends_run_task_and_waits_for_started() -> None:
    provider, socket, calls = await _provider([_started()])

    await provider.start()

    assert calls == [
        {
            "url": "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
            "additional_headers": {"Authorization": "Bearer sk-test-only"},
        }
    ]
    assert len(socket.sent) == 1
    run_task = json.loads(socket.sent[0])
    assert run_task["header"] == {
        "action": "run-task",
        "task_id": "client-task-id",
        "streaming": "duplex",
    }
    assert run_task["payload"]["task_group"] == "audio"
    assert run_task["payload"]["task"] == "asr"
    assert run_task["payload"]["function"] == "recognition"
    assert run_task["payload"]["model"] == "qwen-audio-3.0-asr-flash-streaming"
    assert run_task["payload"]["parameters"] == {
        "format": "pcm",
        "sample_rate": 16000,
    }
    assert run_task["payload"]["input"] == {}


async def test_audio_partial_and_stable_events_are_ordered() -> None:
    provider, socket, _ = await _provider(
        [
            _started(),
            _result("你好", sentence_end=False, end_time=400),
            _result("你好世界。", sentence_end=True, end_time=900),
            {"header": {"event": "task-finished", "task_id": "provider-task-id"}},
        ]
    )
    await provider.start()

    await provider.send_audio(b"\x01\x00\x02\x00")
    events = [event async for event in provider.events()]

    assert socket.sent[1] == b"\x01\x00\x02\x00"
    assert [(event.kind, event.sequence, event.text) for event in events] == [
        (ProviderEventKind.PARTIAL, 1, "你好"),
        (ProviderEventKind.STABLE, 2, "你好世界。"),
        (ProviderEventKind.FINAL, 3, "你好世界。"),
    ]
    assert events[-1].duration_ms == 900


async def test_finish_sends_finish_task_and_keeps_last_partial() -> None:
    provider, socket, _ = await _provider(
        [
            _started(),
            _result("Hello", sentence_end=True, end_time=500),
            _result("world", sentence_end=False, end_time=850),
            {"header": {"event": "task-finished", "task_id": "provider-task-id"}},
        ]
    )
    await provider.start()
    await provider.finish()

    events = [event async for event in provider.events()]

    finish_task = json.loads(socket.sent[-1])
    assert finish_task["header"] == {
        "action": "finish-task",
        "task_id": "client-task-id",
        "streaming": "duplex",
    }
    assert events[-1].kind == ProviderEventKind.FINAL
    assert events[-1].text == "Hello world"
    assert socket.close_count == 1


async def test_task_failed_uses_stable_error_without_provider_body() -> None:
    provider, _, _ = await _provider(
        [
            _started(),
            {
                "header": {
                    "event": "task-failed",
                    "task_id": "provider-task-id",
                    "error_code": "InvalidApiKey",
                    "error_message": "secret sk-provider-must-not-leak",
                }
            },
        ]
    )
    await provider.start()

    try:
        _ = [event async for event in provider.events()]
    except StreamingAsrProviderError as exc:
        assert exc.code == "service_unavailable"
        assert str(exc) == "Qwen streaming ASR failed"
        assert "secret" not in str(exc)
        assert "InvalidApiKey" not in str(exc)
    else:
        raise AssertionError("task-failed did not raise a safe provider error")


async def test_cancel_is_idempotent_and_emits_nothing() -> None:
    provider, socket, _ = await _provider([_started()])
    await provider.start()

    await provider.cancel()
    await provider.cancel()
    events = [event async for event in provider.events()]

    assert socket.close_count == 1
    assert events == []
    assert all(
        not isinstance(value, str)
        or json.loads(value)["header"]["action"] != "finish-task"
        for value in socket.sent
    )


async def test_cancelled_partial_start_closes_allocated_socket() -> None:
    socket = _BlockingStartSocket()

    async def connect(url: str, **kwargs: Any) -> _BlockingStartSocket:
        return socket

    provider = QwenStreamingAsrProvider(
        api_key="sk-test-only",
        ws_url="wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
        model="qwen-audio-3.0-asr-flash-streaming",
        connector=connect,
        task_id_factory=lambda: "client-task-id",
    )
    start_task = asyncio.create_task(provider.start())
    await asyncio.wait_for(socket.send_entered.wait(), timeout=0.1)

    start_task.cancel()
    try:
        await start_task
    except asyncio.CancelledError:
        pass
    else:
        raise AssertionError("cancelled provider start did not propagate cancellation")

    assert socket.close_count == 1


async def _run() -> None:
    await test_start_sends_run_task_and_waits_for_started()
    await test_audio_partial_and_stable_events_are_ordered()
    await test_finish_sends_finish_task_and_keeps_last_partial()
    await test_task_failed_uses_stable_error_without_provider_body()
    await test_cancel_is_idempotent_and_emits_nothing()
    await test_cancelled_partial_start_closes_allocated_socket()


def main() -> None:
    asyncio.run(_run())
    print("PASS - Qwen streaming ASR adapter lifecycle and redaction")


if __name__ == "__main__":
    main()
