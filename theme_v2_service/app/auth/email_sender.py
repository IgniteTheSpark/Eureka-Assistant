"""Email verification sender boundary (§5.3).

Application-owned interface with three implementations:
  - FakeVerificationSender      : automated tests / local dev (code captured)
  - AliyunDirectMailVerificationSender : production mainland-China provider
  - DisabledVerificationSender  : explicit local disable; fails readiness in prod

Provider timeouts/failures and configuration/initialization failures all become
a bounded public error (`EmailDeliveryError`) so the client can retry. The
blocking HTTP call (`urlopen`, response drain, and close) runs entirely inside
one worker thread so the event loop stays free. DirectMail response payloads,
recipient addresses, codes, and access keys are never logged or exposed to the
client.
"""
from __future__ import annotations

import asyncio
import hashlib
import hmac
import logging
import urllib.parse
import urllib.request
from base64 import b64encode
from datetime import datetime, timezone
from functools import lru_cache
from uuid import uuid4

from app.config import get_settings

logger = logging.getLogger(__name__)

_DIRECTMAIL_ENDPOINT = "https://dm.aliyuncs.com/"
_DIRECTMAIL_VERSION = "2015-11-23"
_DIRECTMAIL_ACTION = "SingleSendMail"
_DIRECTMAIL_SIGN_METHOD = "HMAC-SHA1"


class EmailDeliveryError(Exception):
    """Raised when the provider (or its configuration) cannot deliver.

    Safe to surface as a bounded, retryable error; never contains secrets.
    """


_SEND_FAILED_MESSAGE = "验证码发送失败，请稍后重试"


class VerificationSender:
    """Application-owned contract for sending a verification code."""

    async def send_code(
        self,
        *,
        email: str,
        code: str,
        purpose: str,
        expires_in_seconds: int,
    ) -> None:
        raise NotImplementedError


class FakeVerificationSender(VerificationSender):
    """Test provider. Records the last sent code for in-process retrieval.

    Never used in production: the provider factory refuses Mock in prod.
    Recipient addresses and codes are intentionally absent from the log line
    (the recorded `sent` list is the retrieval mechanism for tests).
    """

    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send_code(
        self,
        *,
        email: str,
        code: str,
        purpose: str,
        expires_in_seconds: int,
    ) -> None:
        self.sent.append({"email": email, "code": code, "purpose": purpose})
        logger.info("fake verification code sent purpose=%s", purpose)


class DisabledVerificationSender(VerificationSender):
    async def send_code(
        self,
        *,
        email: str,
        code: str,
        purpose: str,
        expires_in_seconds: int,
    ) -> None:
        raise EmailDeliveryError("email provider is disabled")


class AliyunDirectMailVerificationSender(VerificationSender):
    """Aliyun DirectMail SingleSendMail via POP RPC API (HMAC-SHA1 signed).

    Credentials come from settings (DIRECTMAIL_*), never logged. The response
    payload is discarded; only a success/failure outcome is surfaced as a
    bounded, retryable error.
    """

    def __init__(
        self,
        *,
        account_name: str | None = None,
        access_key_id: str | None = None,
        access_key_secret: str | None = None,
        from_name: str | None = None,
    ) -> None:
        try:
            settings = get_settings()
            self.account_name = (
                "verify@mail.ureka.chat"
                if settings.env in {"prod", "production"}
                else account_name or settings.directmail_account_name
            )
            self.access_key_id = access_key_id or settings.directmail_access_key_id
            self.access_key_secret = (
                access_key_secret or settings.directmail_access_key_secret
            )
            self.from_name = from_name or settings.email_from_name
            if not (self.account_name and self.access_key_id and self.access_key_secret):
                raise EmailDeliveryError("DirectMail credentials are not configured")
        except EmailDeliveryError:
            raise
        except Exception as exc:
            # Config failures are normalized into the bounded, retryable boundary.
            logger.warning("directmail sender initialization failed")
            raise EmailDeliveryError("DirectMail provider is not configured") from exc

    def _sign(self, params: dict[str, str]) -> str:
        canonical = "&".join(
            f"{urllib.parse.quote(k, safe='')}={urllib.parse.quote(v, safe='')}"
            for k, v in sorted(params.items())
        )
        string_to_sign = f"POST&%2F&{urllib.parse.quote(canonical, safe='')}"
        digest = hmac.new(
            f"{self.access_key_secret}&".encode(),
            string_to_sign.encode(),
            hashlib.sha1,
        ).digest()
        return b64encode(digest).decode()

    async def send_code(
        self,
        *,
        email: str,
        code: str,
        purpose: str,
        expires_in_seconds: int,
    ) -> None:
        now = datetime.now(timezone.utc)
        params = {
            "Action": _DIRECTMAIL_ACTION,
            "Version": _DIRECTMAIL_VERSION,
            "Format": "JSON",
            "AccessKeyId": self.access_key_id,
            "SignatureMethod": _DIRECTMAIL_SIGN_METHOD,
            "Timestamp": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "SignatureVersion": "1.0",
            "SignatureNonce": str(uuid4()),
            "AccountName": self.account_name,
            "AddressType": "1",
            "FromAlias": self.from_name or "",
            "ReplyToAddress": "false",
            "ToAddress": email,
            "Subject": self._subject(purpose),
            "HtmlBody": self._html_body(code, expires_in_seconds),
        }
        params["Signature"] = self._sign(params)

        body = urllib.parse.urlencode(params).encode()
        request = urllib.request.Request(
            _DIRECTMAIL_ENDPOINT,
            data=body,
            method="POST",
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        try:
            # urlopen, drain, and close all run together inside the worker
            # thread (to_thread), so blocking I/O never touches the event loop.
            status = await asyncio.to_thread(_directmail_post, request, timeout=10)
        except Exception as exc:
            logger.warning("directmail send failed purpose=%s", purpose)
            raise EmailDeliveryError(_SEND_FAILED_MESSAGE) from exc

        if status != 200:
            logger.warning("directmail returned status=%s purpose=%s", status, purpose)
            raise EmailDeliveryError(_SEND_FAILED_MESSAGE)

    def _subject(self, purpose: str) -> str:
        return "UReka 注册验证码" if purpose == "register" else "UReka 重置密码验证码"

    def _html_body(self, code: str, expires_in_seconds: int) -> str:
        minutes = max(1, expires_in_seconds // 60)
        return (
            "<div style='font-family:sans-serif;padding:24px;color:#101319'>"
            f"<p>你的验证码是:</p>"
            f"<p style='font-size:32px;font-weight:700;letter-spacing:4px;'>{code}</p>"
            f"<p style='color:#6D7480'>验证码 {minutes} 分钟内有效。</p>"
            "</div>"
        )


def _directmail_post(request: urllib.request.Request, *, timeout: int) -> int:
    """POST and fully consume the response inside this worker thread.

    The response is closed by the context manager, the body is drained and
    discarded (never parsed, never logged), and only the HTTP status is
    returned.
    """
    with urllib.request.urlopen(request, timeout=timeout) as response:
        status = response.status
        response.read()
    return status


def _resolve_provider() -> VerificationSender:
    """Strict provider resolution; failures surface as EmailDeliveryError."""
    settings = get_settings()
    provider = settings.email_provider
    if settings.env in {"prod", "production"}:
        if provider != "aliyun_directmail":
            raise EmailDeliveryError(
                "EMAIL_PROVIDER must be 'aliyun_directmail' in production; "
                "mock/disabled providers are forbidden."
            )
        return AliyunDirectMailVerificationSender()
    if provider == "aliyun_directmail":
        return AliyunDirectMailVerificationSender()
    if provider == "disabled":
        return DisabledVerificationSender()
    if provider == "mock":
        return FakeVerificationSender()
    raise EmailDeliveryError(f"unknown EMAIL_PROVIDER: {provider!r}")


@lru_cache(maxsize=None)
def get_verification_sender() -> VerificationSender:
    return _resolve_provider()
