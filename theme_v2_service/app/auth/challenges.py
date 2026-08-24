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

from sqlalchemy import delete, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.models import EmailRateLimitBucket, EmailVerificationChallenge
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


def _bucket_key(scope: str, value: str) -> tuple[str, str]:
    return scope, _hash_ip(value)


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

    async with session.begin_nested():
        await _enforce_rate_limits(
            session,
            email=email,
            ip_hash=_hash_ip(request_ip) if request_ip is not None else None,
        )

    # Only the newest successfully issued challenge may remain usable. This
    # update stays in the caller's transaction so a later delivery failure
    # rolls it back and leaves the previous code valid.
    await session.execute(
        update(EmailVerificationChallenge)
        .where(
            EmailVerificationChallenge.email == email,
            EmailVerificationChallenge.purpose == purpose,
            EmailVerificationChallenge.consumed_at.is_(None),
        )
        .values(consumed_at=now)
    )

    code = (
        settings.email_fixed_code
        if settings.email_provider == "mock" and settings.email_fixed_code is not None
        else generate_code()
    )
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
    ip_hash: str | None,
) -> None:
    settings = get_settings()
    now = _now()

    if not await _reserve_cooldown(
        session,
        key=_bucket_key("email-cooldown", email),
        cooldown_seconds=settings.email_resend_cooldown_seconds,
        now=now,
    ):
        raise ChallengeRateLimitError("发送太频繁，请稍后再试")

    if not await _reserve_bucket(
        session,
        key=_bucket_key("email-hour", email),
        window_seconds=3600,
        limit=settings.email_send_per_hour_per_email,
        now=now,
    ):
        raise ChallengeRateLimitError("发送太频繁，请稍后再试")
    if not await _reserve_bucket(
        session,
        key=_bucket_key("email-day", email),
        window_seconds=86400,
        limit=settings.email_send_per_day_per_email,
        now=now,
    ):
        raise ChallengeRateLimitError("今日发送次数已达上限")

    if ip_hash is not None:
        if not await _reserve_bucket(
            session,
            key=_bucket_key("ip-hour", ip_hash),
            window_seconds=3600,
            limit=settings.email_send_per_hour_per_ip,
            now=now,
        ):
            raise ChallengeRateLimitError("发送太频繁，请稍后再试")
        if not await _reserve_bucket(
            session,
            key=_bucket_key("ip-day", ip_hash),
            window_seconds=86400,
            limit=settings.email_send_per_day_per_ip,
            now=now,
        ):
            raise ChallengeRateLimitError("今日发送次数已达上限")


async def _reserve_bucket(
    session: AsyncSession,
    *,
    key: tuple[str, str],
    window_seconds: int,
    limit: int,
    now: datetime,
) -> bool:
    epoch = datetime(1970, 1, 1)
    elapsed = int((now - epoch).total_seconds())
    bucket_start = epoch + timedelta(
        seconds=elapsed - (elapsed % window_seconds)
    )
    scope_type, scope_hash = key
    await session.execute(
        text(
            """
            INSERT INTO email_rate_limit_buckets
                (scope_type, scope_hash, bucket_start, last_request_at, request_count)
            VALUES (:scope_type, :scope_hash, :bucket_start, NULL, 1)
            ON DUPLICATE KEY UPDATE
                request_count = IF(
                    bucket_start < VALUES(bucket_start),
                    1,
                    request_count + 1
                ),
                bucket_start = GREATEST(bucket_start, VALUES(bucket_start)),
                last_request_at = NULL
            """
        ),
        {
            "scope_type": scope_type,
            "scope_hash": scope_hash,
            "bucket_start": bucket_start,
        },
    )
    bucket = (
        await session.execute(
            text(
                """
                SELECT request_count
                FROM email_rate_limit_buckets
                WHERE scope_type = :scope_type
                  AND scope_hash = :scope_hash
                  AND bucket_start = :bucket_start
                FOR UPDATE
                """
            ),
            {
                "scope_type": scope_type,
                "scope_hash": scope_hash,
                "bucket_start": bucket_start,
            },
        )
    ).one_or_none()
    return bucket is not None and bucket.request_count <= limit


async def _reserve_cooldown(
    session: AsyncSession,
    *,
    key: str,
    cooldown_seconds: int,
    now: datetime,
) -> bool:
    await session.execute(
        text(
            """
            INSERT INTO email_rate_limit_buckets
                (scope_type, scope_hash, bucket_start, last_request_at, request_count)
            VALUES (:scope_type, :scope_hash, :bucket_start, :initial_request_at, 1)
            ON DUPLICATE KEY UPDATE scope_type = scope_type
            """
        ),
        {
            "scope_type": key[0],
            "scope_hash": key[1],
            "bucket_start": datetime(1970, 1, 1),
            "initial_request_at": now
            - timedelta(seconds=cooldown_seconds)
            - timedelta(microseconds=1),
        },
    )
    bucket = (
        await session.execute(
            text(
                """
                SELECT last_request_at
                FROM email_rate_limit_buckets
                WHERE scope_type = :scope_type
                  AND scope_hash = :scope_hash
                  AND bucket_start = :bucket_start
                FOR UPDATE
                """
            ),
            {
                "scope_type": key[0],
                "scope_hash": key[1],
                "bucket_start": datetime(1970, 1, 1),
            },
        )
    ).one_or_none()
    if bucket is None:
        return False
    if bucket.last_request_at is not None and now - bucket.last_request_at < timedelta(
        seconds=cooldown_seconds
    ):
        return False
    await session.execute(
        text(
            """
            UPDATE email_rate_limit_buckets
            SET last_request_at = :now, request_count = 1
            WHERE scope_type = :scope_type
              AND scope_hash = :scope_hash
              AND bucket_start = :bucket_start
            """
        ),
        {
            "scope_type": key[0],
            "scope_hash": key[1],
            "bucket_start": datetime(1970, 1, 1),
            "now": now,
        },
    )
    return True


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
        .with_for_update()
    )
    return await session.scalar(stmt)


async def verify_code(
    session: AsyncSession,
    *,
    challenge: EmailVerificationChallenge,
    code: str,
) -> bool:
    """Consume-verify one challenge.

    A successful match is only flushed, so challenge consumption commits with
    the protected account mutation. An invalid match commits its locked counter
    before raising; callers must therefore verify before making business
    writes.
    """
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

    # Persist the failure immediately with its own commit so a later rollback
    # of the caller's transaction cannot erase the counter and bypass the
    # lockout (§5.2: five invalid submissions lock verification for 15 minutes).
    challenge.failed_attempts += 1
    if challenge.failed_attempts >= settings.email_max_failed_attempts:
        challenge.locked_until = now + timedelta(seconds=settings.email_lockout_seconds)
    await session.commit()
    raise ChallengeInvalidError("验证码不正确")


async def cleanup_expired(session: AsyncSession) -> int:
    """Delete consumed/expired challenges older than the 30-day window."""
    cutoff = _now() - timedelta(days=30)
    challenge_stmt = delete(EmailVerificationChallenge).where(
        EmailVerificationChallenge.created_at < cutoff
    )
    result = await session.execute(challenge_stmt)
    bucket_stmt = delete(EmailRateLimitBucket).where(
        (
            EmailRateLimitBucket.last_request_at.is_not(None)
            & (EmailRateLimitBucket.last_request_at < _now() - timedelta(days=2))
        )
        | (
            EmailRateLimitBucket.last_request_at.is_(None)
            & (EmailRateLimitBucket.bucket_start < _now() - timedelta(days=2))
        )
    )
    await session.execute(bucket_stmt)
    await session.flush()
    return result.rowcount or 0
