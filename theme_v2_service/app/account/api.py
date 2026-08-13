from app.db.base import utc_now

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.api import ChangePasswordRequest
from app.auth.dependencies import get_current_user_id
from app.auth.models import UserAccount
from app.auth.security import create_token, hash_password, verify_password
from app.db.session import get_session


router = APIRouter(prefix="/api/account", tags=["account"])


@router.patch("/password")
async def change_password(
    body: ChangePasswordRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    user = await session.scalar(
        select(UserAccount).where(UserAccount.id == user_id)
    )
    if user is None or user.password_hash is None:
        raise HTTPException(status_code=401, detail="账号不存在或未设置密码")
    if not verify_password(body.current_password, user.password_hash):
        raise HTTPException(status_code=400, detail="当前密码不正确")

    user.password_hash = hash_password(body.new_password)
    user.auth_version += 1
    user.password_updated_at = utc_now()
    await session.flush()

    return {
        "ok": True,
        "token": create_token(user.id, auth_version=user.auth_version),
    }


from typing import Literal

from fastapi.responses import PlainTextResponse
from pydantic import BaseModel, Field

from app.account.deletion import DeletePasswordError, delete_account
from app.account.export import (
    build_export,
    export_options,
    suggested_filename,
)


class ExportRequest(BaseModel):
    types: list[str] = Field(default_factory=list)
    format: Literal["md", "csv"] = "md"


class DeleteRequest(BaseModel):
    password: str


@router.get("/export-options")
async def get_export_options(
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    return await export_options(session, user_id)


@router.post("/export")
async def export_data(
    body: ExportRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> PlainTextResponse:
    content = await build_export(
        session,
        user_id,
        selected_types=body.types,
        output_format=body.format,
    )
    media_type = "text/csv" if body.format == "csv" else "text/markdown"
    return PlainTextResponse(
        content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{suggested_filename(body.format)}"'},
    )


@router.delete("")
async def delete_user_account(
    body: DeleteRequest,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    try:
        await delete_account(session, user_id, password=body.password)
    except DeletePasswordError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return {"ok": True}
