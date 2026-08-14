"""Email verification challenge lifecycle tests (§5.2)."""
from datetime import datetime, timedelta, timezone

import pytest

from app.auth.challenges import (
    ChallengeExpiredError,
    ChallengeInvalidError,
    ChallengeLockedError,
    ChallengeRateLimitError,
    cleanup_expired,
    find_active_challenge,
    generate_code,
    issue_challenge,
    verify_code,
)
from app.auth.models import CHALLENGE_REGISTER
from app.config import get_settings


def test_generate_code_is_six_digits():
    for _ in range(200):
        code = generate_code()
        assert len(code) == 6
        assert code.isdigit()


async def test_challenge_stores_digest_not_plaintext(session):
    challenge, code = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    assert challenge.code_digest != code
    assert code not in challenge.code_digest
    assert challenge.consumed_at is None


async def test_verify_correct_code_consumes(session):
    challenge, code = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    assert await verify_code(session, challenge=challenge, code=code) is True
    assert challenge.consumed_at is not None


async def test_verify_wrong_code_raises_and_counts(session):
    challenge, code = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    with pytest.raises(ChallengeInvalidError):
        await verify_code(session, challenge=challenge, code="000000")
    assert challenge.failed_attempts == 1
    assert await verify_code(session, challenge=challenge, code=code) is True


async def test_verify_expired_challenge(session):
    challenge, _ = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    challenge.expires_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=1)
    with pytest.raises(ChallengeExpiredError):
        await verify_code(session, challenge=challenge, code="123456")


async def test_verify_consumed_challenge_rejected(session):
    challenge, code = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    await verify_code(session, challenge=challenge, code=code)
    with pytest.raises(Exception):
        await verify_code(session, challenge=challenge, code=code)


async def test_find_active_challenge_picks_newest(session):
    first, _ = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    # Backdate the first send so the 60s cooldown does not block the second.
    first.sent_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=120)
    await session.flush()
    c2, _ = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    found = await find_active_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER
    )
    assert found.id == c2.id


async def test_cleanup_removes_old_rows(session):
    challenge, _ = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    challenge.created_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=31)
    await session.flush()
    removed = await cleanup_expired(session)
    assert removed >= 1


async def test_resend_cooldown_blocks_immediate_resend(session):
    await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    with pytest.raises(ChallengeRateLimitError):
        await issue_challenge(
            session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
        )


async def test_rate_limit_after_max_sends(session):
    settings = get_settings()
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    # Backdate sent_at so cooldown (60s) never triggers while filling the
    # per-hour budget — each send is spaced ~70s apart and the newest is
    # already 120s old (outside the cooldown window).
    for index in range(settings.email_send_per_hour_per_email):
        challenge, _ = await issue_challenge(
            session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
        )
        challenge.sent_at = now - timedelta(seconds=120 + index * 70)
    await session.flush()
    with pytest.raises(ChallengeRateLimitError):
        await issue_challenge(
            session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
        )


async def test_lockout_persists_across_transactions(session):
    """§5.2: five invalid submissions lock verification for 15 minutes, and the
    counter survives a rollback (review blocker #2)."""
    settings = get_settings()
    challenge, code = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    await session.commit()

    # Simulate the caller rolling back after each failure: the counter must
    # persist because verify_code commits its own failure record.
    for _ in range(settings.email_max_failed_attempts - 1):
        async with AsyncSessionFactory() as fresh:
            c = await fresh.get(type(challenge), challenge.id)
            with pytest.raises(ChallengeInvalidError):
                await verify_code(fresh, challenge=c, code="000000")
            await fresh.rollback()

    async with AsyncSessionFactory() as fresh:
        c = await fresh.get(type(challenge), challenge.id)
        assert c.failed_attempts == settings.email_max_failed_attempts - 1
        with pytest.raises(ChallengeInvalidError):
            await verify_code(fresh, challenge=c, code="000000")
        await fresh.rollback()

    # Locked: even the correct code is rejected now.
    async with AsyncSessionFactory() as fresh:
        c = await fresh.get(type(challenge), challenge.id)
        assert c.locked_until is not None
        with pytest.raises(ChallengeLockedError):
            await verify_code(fresh, challenge=c, code=code)


async def test_lockout_persists_across_transactions(session):
    """§5.2: five invalid submissions lock verification for 15 minutes, and the
    counter survives a rollback (review blocker #2)."""
    from app.db.session import AsyncSessionFactory

    settings = get_settings()
    challenge, code = await issue_challenge(
        session, email="a@x.com", purpose=CHALLENGE_REGISTER, request_ip="1.2.3.4"
    )
    await session.commit()

    for _ in range(settings.email_max_failed_attempts - 1):
        async with AsyncSessionFactory() as fresh:
            c = await fresh.get(type(challenge), challenge.id)
            with pytest.raises(ChallengeInvalidError):
                await verify_code(fresh, challenge=c, code="000000")
            await fresh.rollback()

    async with AsyncSessionFactory() as fresh:
        c = await fresh.get(type(challenge), challenge.id)
        assert c.failed_attempts == settings.email_max_failed_attempts - 1
        with pytest.raises(ChallengeInvalidError):
            await verify_code(fresh, challenge=c, code="000000")
        await fresh.rollback()

    async with AsyncSessionFactory() as fresh:
        c = await fresh.get(type(challenge), challenge.id)
        assert c.locked_until is not None
        with pytest.raises(ChallengeLockedError):
            await verify_code(fresh, challenge=c, code=code)
