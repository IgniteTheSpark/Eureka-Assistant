import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.auth.models import UserAccount
from app.auth.security import create_token, hash_password, verify_password
from app.db.session import get_session


router = APIRouter(prefix="/api/auth", tags=["auth"])

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_MIN_PASSWORD = 6


class AuthRequest(BaseModel):
    email: str
    password: str


def _normalize_email(email: str) -> str:
    return email.strip().lower()


def _user_response(user: UserAccount) -> dict[str, str]:
    return {"id": user.id, "email": user.email}


@router.post("/register")
async def register(
    request: AuthRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    email = _normalize_email(request.email)
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="邮箱格式不正确")
    if len(request.password) < _MIN_PASSWORD:
        raise HTTPException(status_code=400, detail=f"密码至少 {_MIN_PASSWORD} 位")

    existing = await session.scalar(
        select(UserAccount).where(UserAccount.email == email)
    )
    if existing is not None:
        raise HTTPException(status_code=409, detail="该邮箱已注册")

    user = UserAccount(email=email, password_hash=hash_password(request.password))
    session.add(user)
    try:
        await session.flush()
    except IntegrityError as exc:
        await session.rollback()
        raise HTTPException(status_code=409, detail="该邮箱已注册") from exc

    return {
        "ok": True,
        "token": create_token(user.id),
        "user": _user_response(user),
    }


@router.post("/login")
async def login(
    request: AuthRequest,
    session: AsyncSession = Depends(get_session),
) -> dict:
    email = _normalize_email(request.email)
    user = await session.scalar(
        select(UserAccount).where(UserAccount.email == email)
    )
    if user is None or not verify_password(request.password, user.password_hash):
        raise HTTPException(status_code=401, detail="邮箱或密码错误")

    return {
        "ok": True,
        "token": create_token(user.id),
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
