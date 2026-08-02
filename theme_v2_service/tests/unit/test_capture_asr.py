import json

import httpx
import pytest

from app.domains.capture.asr import (
    AsrPollResult,
    PermanentAsrError,
    RetryableAsrError,
    TencentS3AsrProvider,
    redact_signed_url,
)


def _client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_provider_creates_task_with_expected_shape():
    requests = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={"code": 0, "data": {"task_id": "tencent-7"}},
        )

    client = _client(handler)
    provider = TencentS3AsrProvider(
        base_url="https://speech.example/",
        client=client,
        timeout_seconds=3,
    )
    task = await provider.create_task(
        audio_url="https://audio.example/F001.mp3?signature=secret",
        engine_type="16k_zh",
        speaker_diarization=True,
        hotword_list="Eureka",
    )

    assert task.task_id == "tencent-7"
    assert requests[0].url.path == "/api/platform/speech/tencent_asr/s3_task"
    assert json.loads(requests[0].content) == {
        "audio_url": "https://audio.example/F001.mp3?signature=secret",
        "engine_type": "16k_zh",
        "speaker_diarization": True,
        "hotword_list": "Eureka",
    }
    await client.aclose()


@pytest.mark.parametrize(
    ("provider_status", "expected_status"),
    [
        ("pending", "pending"),
        ("queued", "pending"),
        ("running", "running"),
        ("processing", "running"),
        ("finished", "finished"),
        ("completed", "finished"),
        ("failed", "failed"),
    ],
)
async def test_provider_normalizes_poll_states(provider_status, expected_status):
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "code": 0,
                "data": {
                    "task_id": "tencent-7",
                    "status": provider_status,
                    "text": "记下咖啡二十八元" if expected_status == "finished" else "",
                    "segments": [{"text": "咖啡", "start_ms": 0, "end_ms": 500}],
                    "error_message": "识别失败" if expected_status == "failed" else "",
                },
            },
        )

    client = _client(handler)
    provider = TencentS3AsrProvider(
        base_url="https://speech.example",
        client=client,
    )
    result = await provider.get_result("tencent-7")

    assert isinstance(result, AsrPollResult)
    assert result.status == expected_status
    if expected_status == "finished":
        assert result.text == "记下咖啡二十八元"
        assert result.segments[0]["text"] == "咖啡"
    if expected_status == "failed":
        assert result.error_message == "识别失败"
    await client.aclose()


async def test_transport_error_is_retryable():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("temporary private endpoint failure", request=request)

    client = _client(handler)
    provider = TencentS3AsrProvider(
        base_url="https://speech.example",
        client=client,
    )

    with pytest.raises(RetryableAsrError):
        await provider.get_result("tencent-7")
    await client.aclose()


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, json={"code": 0, "data": {"status": "mystery"}}),
        httpx.Response(200, json={"code": 0, "data": []}),
        httpx.Response(400, json={"code": 400, "message": "bad task"}),
    ],
)
async def test_invalid_provider_response_is_permanent(response):
    client = _client(lambda request: response)
    provider = TencentS3AsrProvider(
        base_url="https://speech.example",
        client=client,
    )

    with pytest.raises(PermanentAsrError):
        await provider.get_result("tencent-7")
    await client.aclose()


def test_signed_url_redaction_removes_query_fragment_and_credentials():
    safe = redact_signed_url(
        "https://user:password@audio.example:8443/F001.mp3?signature=secret#token"
    )

    assert safe == "https://audio.example:8443/F001.mp3"
    assert "secret" not in safe
    assert "password" not in safe
