from datetime import datetime

from sqlalchemy import CHAR, Integer, String
from sqlalchemy.dialects import mysql
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, new_uuid, utc_now

ONBOARDING_PENDING = "pending"
ONBOARDING_SKIPPED = "skipped"
ONBOARDING_COMPLETED = "completed"

CHALLENGE_REGISTER = "register"
CHALLENGE_PASSWORD_RESET = "password_reset"


class UserAccount(Base):
    __tablename__ = "user_accounts"

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    # email / password_hash are nullable: a future OAuth/phone user may have
    # neither; email-verified accounts always set both.
    email: Mapped[str | None] = mapped_column(String(320), unique=True, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    email_verified_at: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    onboarding_status: Mapped[str] = mapped_column(
        String(24), default=ONBOARDING_PENDING, nullable=False
    )
    terms_accepted_at: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    terms_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # Session revocation epoch: increment on password change/reset/delete to
    # invalidate every previously issued token.
    auth_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    password_updated_at: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6),
        default=utc_now,
        nullable=False,
    )


class EmailVerificationChallenge(Base):
    __tablename__ = "email_verification_challenges"

    id: Mapped[str] = mapped_column(CHAR(36), primary_key=True, default=new_uuid)
    purpose: Mapped[str] = mapped_column(String(24), nullable=False)
    email: Mapped[str] = mapped_column(String(320), nullable=False)
    # HMAC-SHA256 digest of the code — plaintext is never stored.
    code_digest: Mapped[str] = mapped_column(String(128), nullable=False)
    request_ip_hash: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), default=utc_now, nullable=False
    )
    sent_at: Mapped[datetime | None] = mapped_column(mysql.DATETIME(fsp=6), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(mysql.DATETIME(fsp=6), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    failed_attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    locked_until: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    delivery_status: Mapped[str] = mapped_column(
        String(24), default="pending", nullable=False
    )


class EmailRateLimitBucket(Base):
    __tablename__ = "email_rate_limit_buckets"

    scope_type: Mapped[str] = mapped_column(String(32), primary_key=True)
    scope_hash: Mapped[str] = mapped_column(String(128), primary_key=True)
    bucket_start: Mapped[datetime] = mapped_column(
        mysql.DATETIME(fsp=6), primary_key=True
    )
    last_request_at: Mapped[datetime | None] = mapped_column(
        mysql.DATETIME(fsp=6), nullable=True
    )
    request_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
