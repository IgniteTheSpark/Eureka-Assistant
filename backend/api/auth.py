"""
Auth — email + password → HS256 token.

POST /api/auth/register {email, password} → {token, user}
POST /api/auth/login    {email, password} → {token, user}
GET  /api/auth/me                          → {user}   (requires Bearer token)

Every other route resolves the user via `get_current_user_id` (now token-based),
so a registered user's data is isolated automatically — all tables are already
`user_id`-scoped.
"""
import re

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select

from core.auth import get_current_user_id
from core.provisioning import provision_user_skills
from core.security import create_token, hash_password, verify_password
from db.database import AsyncSessionLocal
from db.models import User

router = APIRouter()

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
_MIN_PASSWORD = 6


class AuthRequest(BaseModel):
    email: str
    password: str


def _norm_email(email: str) -> str:
    return email.strip().lower()


@router.post("/auth/register")
async def register(req: AuthRequest):
    email = _norm_email(req.email)
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="邮箱格式不正确")
    if len(req.password) < _MIN_PASSWORD:
        raise HTTPException(status_code=400, detail=f"密码至少 {_MIN_PASSWORD} 位")
    async with AsyncSessionLocal() as db:
        exists = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
        if exists:
            raise HTTPException(status_code=409, detail="该邮箱已注册")
        user = User(email=email, password_hash=hash_password(req.password))
        db.add(user)
        await db.flush()  # assign user.id before provisioning
        await provision_user_skills(db, user.id)
        await db.commit()
        await db.refresh(user)
        uid = user.id
    return {"ok": True, "token": create_token(uid), "user": {"id": uid, "email": email}}


@router.post("/auth/login")
async def login(req: AuthRequest):
    email = _norm_email(req.email)
    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
        if user is None or not verify_password(req.password, user.password_hash):
            raise HTTPException(status_code=401, detail="邮箱或密码错误")
        uid, em = user.id, user.email
    return {"ok": True, "token": create_token(uid), "user": {"id": uid, "email": em}}


@router.get("/auth/me")
async def me(user_id: str = Depends(get_current_user_id)):
    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
        if user is None:
            raise HTTPException(status_code=404, detail="user not found")
        return {"ok": True, "user": {"id": user.id, "email": user.email}}
