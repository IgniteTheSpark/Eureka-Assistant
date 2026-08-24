import re
from app.db.base import utc_now

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.challenges import (
    ChallengeConsumedError,
    ChallengeExpiredError,
    ChallengeInvalidError,
    ChallengeLockedError,
    ChallengeRateLimitError,
    find_active_challenge,
    issue_challenge,
    verify_code,
)
from app.auth.dependencies import get_current_user_id
from app.auth.email_sender import EmailDeliveryError, get_verification_sender
from app.auth.models import (
    CHALLENGE_PASSWORD_RESET,
    CHALLENGE_REGISTER,
    ONBOARDING_PENDING,
    UserAccount,
)
from app.auth.security import create_token, hash_password, verify_password
from app.config import get_settings
from app.db.session import get_session
from app.domains.assets.service import ensure_capture_skills


router = APIRouter(prefix="/api/auth", tags=["auth"])

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_PASSWORD_UPPER_RE = re.compile(r"[A-Z]")
_PASSWORD_LOWER_RE = re.compile(r"[a-z]")
_PASSWORD_DIGIT_RE = re.compile(r"[0-9]")
_PASSWORD_SYMBOL_RE = re.compile(r"[!@#$%^&*._+=?-]")
_PASSWORD_ALLOWED_RE = re.compile(r"^[A-Za-z0-9!@#$%^&*._+=?-]+$")
_MIN_PASSWORD = 8
_MAX_PASSWORD = 128


class AuthRequest(BaseModel):
    email: str
    password: str


class VerificationCodeRequest(BaseModel):
    email: str
    purpose: str


class RegisterRequest(BaseModel):
    email: str
    verification_code: str
    password: str
    terms_version: str
    terms_accepted: bool


class PasswordResetRequest(BaseModel):
    email: str
    verification_code: str
    new_password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def _password_policy(cls, value: str) -> str:
        error = _password_policy_error(value)
        if error is not None:
            raise ValueError(error)
        return value


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _password_policy_error(password: str) -> str | None:
    if len(password) < _MIN_PASSWORD:
        return f"密码长度至少 {_MIN_PASSWORD} 位"
    if len(password) > _MAX_PASSWORD:
        return f"密码长度不能超过 {_MAX_PASSWORD} 位"
    if not _PASSWORD_UPPER_RE.search(password):
        return "密码必须包含大写字母 A-Z"
    if not _PASSWORD_LOWER_RE.search(password):
        return "密码必须包含小写字母 a-z"
    if not _PASSWORD_DIGIT_RE.search(password):
        return "密码必须包含数字 0-9"
    if not _PASSWORD_SYMBOL_RE.search(password):
        return "密码必须包含安全符号 ! @ # $ % ^ & * . _ + = ? -"
    if not _PASSWORD_ALLOWED_RE.fullmatch(password):
        return "密码只能使用 ASCII 字母、数字和安全符号 ! @ # $ % ^ & * . _ + = ? -"
    return None


def _user_response(user: UserAccount) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "email_verified": user.email_verified_at is not None,
        "onboarding_status": user.onboarding_status,
    }


def _client_ip(request: Request) -> str | None:
    fwd = request.headers.get("x-forwarded-for")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else None


@router.post("/verification-codes")
async def request_verification_code(
    request: Request,
    body: VerificationCodeRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    email = _normalize_email(body.email)
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="邮箱格式不正确")
    if body.purpose not in {CHALLENGE_REGISTER, CHALLENGE_PASSWORD_RESET}:
        raise HTTPException(status_code=400, detail="无效的验证码用途")

    # Registration conflict surfaces here only for a well-formed registered
    # address. Password-reset never reveals whether the address exists.
    if body.purpose == CHALLENGE_REGISTER:
        existing = await session.scalar(
            select(UserAccount).where(UserAccount.email == email)
        )
        if existing is not None:
            raise HTTPException(status_code=409, detail="该邮箱已注册")

    try:
        _, code = await issue_challenge(
            session,
            email=email,
            purpose=body.purpose,
            request_ip=_client_ip(request),
        )
    except ChallengeRateLimitError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc

    settings = get_settings()
    try:
        sender = get_verification_sender()
        await sender.send_code(
            email=email,
            code=code,
            purpose=body.purpose,
            expires_in_seconds=settings.email_code_ttl_seconds,
        )
    except EmailDeliveryError:
        raise HTTPException(status_code=503, detail="验证码发送失败，请稍后重试")

    return {
        "ok": True,
        "resend_delay_seconds": settings.email_resend_cooldown_seconds,
        "expires_in_seconds": settings.email_code_ttl_seconds,
    }


@router.post("/register")
async def register(
    body: RegisterRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    email = _normalize_email(body.email)
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="邮箱格式不正确")
    if not body.terms_accepted:
        raise HTTPException(status_code=400, detail="请先阅读并同意服务条款")
    terms_version = (body.terms_version or "").strip()
    if not terms_version:
        raise HTTPException(status_code=400, detail="缺少服务条款版本，请刷新后重试")
    settings = get_settings()
    if terms_version != settings.terms_version_current:
        raise HTTPException(status_code=409, detail="服务条款已更新，请阅读并同意最新版本后重试")
    password_error = _password_policy_error(body.password)
    if password_error is not None:
        raise HTTPException(status_code=422, detail=password_error)

    challenge = await find_active_challenge(
        session, email=email, purpose=CHALLENGE_REGISTER
    )
    if challenge is None:
        raise HTTPException(status_code=400, detail="请先获取验证码")
    try:
        await verify_code(session, challenge=challenge, code=body.verification_code)
    except ChallengeInvalidError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except (ChallengeExpiredError, ChallengeConsumedError) as exc:
        raise HTTPException(status_code=400, detail="验证码已失效，请重新获取") from exc
    except ChallengeLockedError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc

    existing = await session.scalar(
        select(UserAccount).where(UserAccount.email == email)
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="该邮箱已注册")

    now = utc_now()
    user = UserAccount(
        email=email,
        password_hash=hash_password(body.password),
        email_verified_at=now,
        onboarding_status=ONBOARDING_PENDING,
        terms_accepted_at=now,
        terms_version=settings.terms_version_current,
        auth_version=1,
    )
    session.add(user)
    try:
        await session.flush()
        await ensure_capture_skills(session, user.id)
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(status_code=409, detail="该邮箱已注册") from exc

    return {
        "ok": True,
        "token": create_token(user.id, auth_version=user.auth_version),
        "user": _user_response(user),
    }


@router.post("/login")
async def login(
    body: AuthRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    email = _normalize_email(body.email)
    user = await session.scalar(
        select(UserAccount).where(UserAccount.email == email)
    )
    if user is None or user.password_hash is None or not verify_password(
        body.password, user.password_hash
    ):
        raise HTTPException(status_code=401, detail="邮箱或密码错误")
    if user.deleted_at is not None:
        raise HTTPException(status_code=401, detail="邮箱或密码错误")

    return {
        "ok": True,
        "token": create_token(user.id, auth_version=user.auth_version),
        "user": _user_response(user),
    }


@router.get("/me")
async def me(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await session.scalar(
        select(UserAccount).where(UserAccount.id == user_id)
    )
    if user is None:
        raise HTTPException(status_code=404, detail="user not found")
    return {"ok": True, "user": _user_response(user)}


@router.post("/password-reset")
async def password_reset(
    body: PasswordResetRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    email = _normalize_email(body.email)
    password_error = _password_policy_error(body.new_password)
    if password_error is not None:
        raise HTTPException(status_code=422, detail=password_error)
    challenge = await find_active_challenge(
        session, email=email, purpose=CHALLENGE_PASSWORD_RESET
    )
    if challenge is None:
        raise HTTPException(status_code=400, detail="请先获取验证码")
    try:
        await verify_code(session, challenge=challenge, code=body.verification_code)
    except ChallengeInvalidError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except (ChallengeExpiredError, ChallengeConsumedError) as exc:
        raise HTTPException(status_code=400, detail="验证码已失效，请重新获取") from exc
    except ChallengeLockedError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc

    user = await session.scalar(
        select(UserAccount).where(UserAccount.email == email)
    )
    if user is None or user.deleted_at is not None:
        # Uniform response — never reveal whether the address exists.
        return {"ok": True}
    user.password_hash = hash_password(body.new_password)
    user.auth_version += 1
    user.password_updated_at = utc_now()
    await session.flush()
    return {"ok": True}


@router.get("/config")
async def auth_config() -> dict:
    settings = get_settings()
    return {
        "region": settings.env,
        "terms_url": settings.terms_url,
        "privacy_url": settings.privacy_url,
        "terms_version": settings.terms_version_current,
        "email_provider": settings.email_provider,
    }
