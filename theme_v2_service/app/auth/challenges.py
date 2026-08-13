"""Email verification challenge lifecycle (§5.2).

Security properties enforced here:
  - code is 6 digits from `secrets.SystemRandom` (never Python `random`)
  - only an HMAC-SHA256 digest of the code is stored; plaintext never persists
  - constant-time digest comparison on verify
  - single-use consumption; only the newest unconsumed challenge per (email, purpose)
  - resend cooldown, per-email and per-IP rate limits, lockout after failures
  - consumed/expired rows are removed after a 30-day audit window
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import and_, delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import EmailVerificationChallenge
from app.config import get_settings


def _now() -> datetime:
    # Naive UTC, matching the codebase's utc_now convention (MySQL DATETIME).
    return datetime.now(timezone.utc).replace(tzinfo=None)


def _digest(code: str) -> str:
    settings = get_settings()
    return hmac.new(
        settings.jwt_secret.encode(),
        code.encode(),
        hashlib.sha256,
    ).hexdigest()


def _hash_ip(ip: str) -> str:
    settings = get_settings()
    return hmac.new(
        settings.jwt_secret.encode(),
        ip.encode(),
        hashlib.sha256,
    ).hexdigest()


def generate_code() -> str:
    rng = secrets.SystemRandom()
    return f"{rng.randrange(0, 1_000_000):06d}"


class ChallengeRateLimitError(Exception):
    pass


class ChallengeLockedError(Exception):
    pass


class ChallengeInvalidError(Exception):
    pass


class ChallengeExpiredError(Exception):
    pass


class ChallengeConsumedError(Exception):
    pass


async def issue_challenge(
    session: AsyncSession,
    *,
    email: str,
    purpose: str,
    request_ip: str | None,
) -> tuple[EmailVerificationChallenge, str]:
    """Create a challenge, return (row, plaintext_code). Plaintext is returned
    only to the caller for immediate delivery; it is never stored."""
    settings = get_settings()
    now = _now()

    if request_ip is not None:
        await _enforce_rate_limits(session, email=email, ip_hash=_hash_ip(request_ip))

    code = generate_code()
    challenge = EmailVerificationChallenge(
        id=str(uuid4()),
        purpose=purpose,
        email=email,
        code_digest=_digest(code),
        request_ip_hash=_hash_ip(request_ip) if request_ip else None,
        created_at=now,
        sent_at=now,
        expires_at=now + timedelta(seconds=settings.email_code_ttl_seconds),
        failed_attempts=0,
        delivery_status="pending",
    )
    session.add(challenge)
    await session.flush()
    return challenge, code


async def _enforce_rate_limits(
    session: AsyncSession,
    *,
    email: str,
    ip_hash: str,
) -> None:
    settings = get_settings()
    now = _now()

    cooldown = now - timedelta(seconds=settings.email_resend_cooldown_seconds)
    last = await _count_sent(session, email=email, since=cooldown)
    if last >= 1:
        raise ChallengeRateLimitError("发送太频繁，请稍后再试")

    email_hour = now - timedelta(hours=1)
    email_day = now - timedelta(days=1)
    hour_count = await _count_sent(session, email=email, since=email_hour)
    day_count = await _count_sent(session, email=email, since=email_day)
    if hour_count >= settings.email_send_per_hour_per_email:
        raise ChallengeRateLimitError("发送太频繁，请稍后再试")
    if day_count >= settings.email_send_per_day_per_email:
        raise ChallengeRateLimitError("今日发送次数已达上限")

    ip_hour = await _count_sent(session, ip_hash=ip_hash, since=email_hour)
    ip_day = await _count_sent(session, ip_hash=ip_hash, since=email_day)
    if ip_hour >= settings.email_send_per_hour_per_ip:
        raise ChallengeRateLimitError("发送太频繁，请稍后再试")
    if ip_day >= settings.email_send_per_day_per_ip:
        raise ChallengeRateLimitError("今日发送次数已达上限")


async def _count_sent(
    session: AsyncSession,
    *,
    email: str | None = None,
    ip_hash: str | None = None,
    since: datetime,
) -> int:
    stmt = select(EmailVerificationChallenge).where(
        EmailVerificationChallenge.sent_at >= since
    )
    if email is not None:
        stmt = stmt.where(EmailVerificationChallenge.email == email)
    if ip_hash is not None:
        stmt = stmt.where(EmailVerificationChallenge.request_ip_hash == ip_hash)
    rows = (await session.scalars(stmt)).all()
    return len(rows)


async def find_active_challenge(
    session: AsyncSession,
    *,
    email: str,
    purpose: str,
) -> EmailVerificationChallenge | None:
    stmt = (
        select(EmailVerificationChallenge)
        .where(
            EmailVerificationChallenge.email == email,
            EmailVerificationChallenge.purpose == purpose,
            EmailVerificationChallenge.consumed_at.is_(None),
        )
        .order_by(EmailVerificationChallenge.created_at.desc())
        .limit(1)
    )
    return await session.scalar(stmt)


async def verify_code(
    session: AsyncSession,
    *,
    challenge: EmailVerificationChallenge,
    code: str,
) -> bool:
    """Consume-verify one challenge. Returns True only on a fresh successful
    match; raises on lockout/expiry/consumed, records failures otherwise."""
    settings = get_settings()
    now = _now()

    if challenge.locked_until is not None and challenge.locked_until > now:
        raise ChallengeLockedError("验证码错误次数过多，请稍后再试")

    if challenge.consumed_at is not None:
        raise ChallengeConsumedError("验证码已使用")

    if challenge.expires_at < now:
        raise ChallengeExpiredError("验证码已过期，请重新获取")

    if hmac.compare_digest(challenge.code_digest, _digest(code)):
        challenge.consumed_at = now
        await session.flush()
        return True

    challenge.failed_attempts += 1
    if challenge.failed_attempts >= settings.email_max_failed_attempts:
        challenge.locked_until = now + timedelta(seconds=settings.email_lockout_seconds)
    await session.flush()
    raise ChallengeInvalidError("验证码不正确")


async def cleanup_expired(session: AsyncSession) -> int:
    """Delete consumed/expired challenges older than the 30-day window."""
    cutoff = _now() - timedelta(days=30)
    stmt = delete(EmailVerificationChallenge).where(
        EmailVerificationChallenge.created_at < cutoff
    )
    result = await session.execute(stmt)
    await session.flush()
    return result.rowcount or 0
