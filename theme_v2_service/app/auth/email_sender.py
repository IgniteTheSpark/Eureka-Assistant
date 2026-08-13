"""Email verification sender boundary (§5.3).

Application-owned interface with three implementations:
  - FakeVerificationSender      : automated tests / local dev (code captured)
  - AliyunDirectMailVerificationSender : production mainland-China provider
  - DisabledVerificationSender  : explicit local disable; fails readiness in prod

Provider timeouts/failures become a bounded public error so the client can retry.
DirectMail response payloads are never exposed to the client.
"""
from __future__ import annotations

import logging

from functools import lru_cache

from app.config import get_settings

logger = logging.getLogger(__name__)


class EmailDeliveryError(Exception):
    """Raised when the provider fails to deliver; safe to surface as a retryable error."""


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
    """Test provider. Records the last sent code for in-process retrieval."""

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
        self.sent.append(
            {"email": email, "code": code, "purpose": purpose}
        )
        logger.info("fake email to %s purpose=%s code=%s", email, purpose, code)


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
    """Aliyun DirectMail via HTTP API (transactional single-send mail).

    Real signing/endpoint is filled when credentials land; the wiring here
    keeps the provider boundary stable.
    """

    async def send_code(
        self,
        *,
        email: str,
        code: str,
        purpose: str,
        expires_in_seconds: int,
    ) -> None:
        settings = get_settings()
        if not (
            settings.directmail_access_key_id
            and settings.directmail_access_key_secret
            and settings.directmail_account_name
        ):
            raise EmailDeliveryError("DirectMail credentials are not configured")
        # TODO(directmail): HMAC-SHA1 sign + POST SingleSendMail.
        raise EmailDeliveryError("DirectMail transport not implemented yet")


@lru_cache(maxsize=None)
def get_verification_sender() -> VerificationSender:
    provider = get_settings().email_provider
    if provider == "aliyun_directmail":
        return AliyunDirectMailVerificationSender()
    if provider == "disabled":
        return DisabledVerificationSender()
    return FakeVerificationSender()
