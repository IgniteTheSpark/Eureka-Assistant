"""DirectMail sender lifecycle, 503 boundary, and log redaction tests (§5.3).

Focused unit coverage for the hardening contract: initialization failures are
normalized to EmailDeliveryError, the blocking HTTP call (urlopen/drain/close)
runs together off the event loop, provider failures are bounded, and logs never
contain recipient addresses, codes, or credentials. Uses only fakes/mocks —
never a live DirectMail call.
"""
import asyncio
import logging
import threading
import time
import types

import pytest

from app.auth import email_sender as es
from app.auth.email_sender import (
    AliyunDirectMailVerificationSender,
    DisabledVerificationSender,
    EmailDeliveryError,
    FakeVerificationSender,
    _directmail_post,
    _resolve_provider,
)

_SENDER_KWARGS = {
    "account_name": "sender@example.com",
    "access_key_id": "AKID-test",
    "access_key_secret": "SK-test-secret",
    "from_name": "UReka",
}


def _settings(**overrides):
    base = {
        "env": "dev",
        "email_provider": "aliyun_directmail",
        "directmail_account_name": "sender@example.com",
        "directmail_access_key_id": "AKID-test",
        "directmail_access_key_secret": "SK-test-secret",
        "email_from_name": "UReka",
    }
    base.update(overrides)
    return types.SimpleNamespace(**base)


# --- initialization failures normalize to EmailDeliveryError ---------------


def test_init_missing_credentials_raises_email_delivery_error(monkeypatch):
    monkeypatch.setattr(
        es,
        "get_settings",
        lambda: _settings(directmail_access_key_id="", directmail_access_key_secret=""),
    )
    with pytest.raises(EmailDeliveryError):
        AliyunDirectMailVerificationSender()


def test_init_normalizes_settings_failure_to_email_delivery_error(monkeypatch):
    def boom():
        raise ValueError("invalid configuration")

    monkeypatch.setattr(es, "get_settings", boom)
    with pytest.raises(EmailDeliveryError):
        AliyunDirectMailVerificationSender()


def test_resolve_unknown_provider_is_email_delivery_error(monkeypatch):
    monkeypatch.setattr(
        es, "get_settings", lambda: _settings(email_provider="carrier_pigeon")
    )
    with pytest.raises(EmailDeliveryError):
        _resolve_provider()


def test_resolve_prod_forbids_mock_provider(monkeypatch):
    monkeypatch.setattr(
        es,
        "get_settings",
        lambda: _settings(env="prod", email_provider="mock"),
    )
    with pytest.raises(EmailDeliveryError):
        _resolve_provider()


# --- provider failures become bounded, retryable errors --------------------


async def test_send_provider_exception_is_bounded_and_redacted(caplog, monkeypatch):
    def raise_io(request, *, timeout):
        raise OSError("connection refused")

    monkeypatch.setattr(es, "_directmail_post", raise_io)
    sender = AliyunDirectMailVerificationSender(**_SENDER_KWARGS)

    with caplog.at_level(logging.WARNING, logger="app.auth.email_sender"):
        with pytest.raises(EmailDeliveryError) as exc_info:
            await sender.send_code(
                email="target@example.com",
                code="482913",
                purpose="register",
                expires_in_seconds=600,
            )

    assert str(exc_info.value) == "验证码发送失败，请稍后重试"
    text = caplog.text
    assert "target@example.com" not in text
    assert "482913" not in text
    assert "AKID-test" not in text
    assert "SK-test-secret" not in text
    assert "register" in text


async def test_send_non_200_is_bounded_and_redacted(caplog, monkeypatch):
    monkeypatch.setattr(es, "_directmail_post", lambda request, *, timeout: 500)
    sender = AliyunDirectMailVerificationSender(**_SENDER_KWARGS)

    with caplog.at_level(logging.WARNING, logger="app.auth.email_sender"):
        with pytest.raises(EmailDeliveryError) as exc_info:
            await sender.send_code(
                email="target@example.com",
                code="482913",
                purpose="register",
                expires_in_seconds=600,
            )

    assert str(exc_info.value) == "验证码发送失败，请稍后重试"
    text = caplog.text
    assert "target@example.com" not in text
    assert "482913" not in text
    assert "500" in text


async def test_send_success_discards_payload(monkeypatch):
    monkeypatch.setattr(es, "_directmail_post", lambda request, *, timeout: 200)
    sender = AliyunDirectMailVerificationSender(**_SENDER_KWARGS)
    result = await sender.send_code(
        email="target@example.com",
        code="482913",
        purpose="register",
        expires_in_seconds=600,
    )
    assert result is None


# --- urlopen/drain/close execute together and close is guaranteed ----------


class _FakeResponse:
    def __init__(self, status, payload=b"{}"):
        self.status = status
        self._payload = payload
        self.read_calls = 0
        self.closed = False

    def read(self, *args, **kwargs):
        self.read_calls += 1
        return self._payload

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.closed = True
        return False


def test_directmail_post_drains_and_closes(monkeypatch):
    fake = _FakeResponse(200)
    captured = {}

    def fake_urlopen(request, timeout):
        captured["request"] = request
        captured["timeout"] = timeout
        return fake

    monkeypatch.setattr(es.urllib.request, "urlopen", fake_urlopen)

    status = _directmail_post("REQUEST", timeout=10)

    assert status == 200
    assert captured["timeout"] == 10
    assert captured["request"] == "REQUEST"
    assert fake.read_calls >= 1
    assert fake.closed is True


def test_directmail_post_closes_when_read_fails(monkeypatch):
    class _BoomResponse(_FakeResponse):
        def read(self, *args, **kwargs):
            raise RuntimeError("malformed provider payload")

    fake = _BoomResponse(200)
    monkeypatch.setattr(
        es.urllib.request, "urlopen", lambda request, timeout: fake
    )

    with pytest.raises(RuntimeError):
        _directmail_post("REQUEST", timeout=10)
    assert fake.closed is True


# --- the blocking call runs off the event loop ------------------------------


async def test_send_posts_on_worker_thread(monkeypatch):
    observed = {}

    def record_post(request, *, timeout):
        observed["thread"] = threading.current_thread().name
        return 200

    monkeypatch.setattr(es, "_directmail_post", record_post)
    sender = AliyunDirectMailVerificationSender(**_SENDER_KWARGS)

    await sender.send_code(
        email="target@example.com",
        code="482913",
        purpose="register",
        expires_in_seconds=600,
    )

    assert observed["thread"] != threading.main_thread().name


async def test_send_does_not_block_event_loop(monkeypatch):
    def slow_post(request, *, timeout):
        time.sleep(0.3)
        return 200

    monkeypatch.setattr(es, "_directmail_post", slow_post)
    sender = AliyunDirectMailVerificationSender(**_SENDER_KWARGS)
    loop = asyncio.get_running_loop()

    started = loop.time()
    task = asyncio.create_task(
        sender.send_code(
            email="target@example.com",
            code="482913",
            purpose="register",
            expires_in_seconds=600,
        )
    )
    await asyncio.sleep(0.05)
    heartbeat_elapsed = loop.time() - started
    await task

    assert heartbeat_elapsed < 0.1


# --- fake provider workflow stays intact and logs nothing sensitive ---------


async def test_fake_sender_records_and_logs_no_secrets(caplog):
    sender = FakeVerificationSender()
    with caplog.at_level(logging.INFO, logger="app.auth.email_sender"):
        await sender.send_code(
            email="target@example.com",
            code="482913",
            purpose="register",
            expires_in_seconds=600,
        )

    assert sender.sent[-1]["email"] == "target@example.com"
    assert sender.sent[-1]["code"] == "482913"
    text = caplog.text
    assert "target@example.com" not in text
    assert "482913" not in text
    assert "register" in text


async def test_disabled_sender_raises_bounded_error():
    with pytest.raises(EmailDeliveryError):
        await DisabledVerificationSender().send_code(
            email="target@example.com",
            code="482913",
            purpose="register",
            expires_in_seconds=600,
        )
