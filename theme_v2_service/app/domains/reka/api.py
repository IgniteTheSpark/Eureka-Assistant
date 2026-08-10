from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.config import get_settings
from app.db.base import utc_now
from app.db.session import get_session
from app.domains.reka.schemas import RekaDismissResponse, RekaSignalsResponse
from app.domains.reka.service import SignalNotFound, dismiss_signal, list_signals


router = APIRouter(prefix="/api/reka/signals", tags=["reka"])


def _timezone_name(value: str | None) -> str:
    timezone_name = (value or get_settings().default_user_timezone).strip()
    try:
        ZoneInfo(timezone_name)
    except (ZoneInfoNotFoundError, ValueError) as exc:
        raise HTTPException(status_code=422, detail="invalid timezone") from exc
    return timezone_name


@router.get("", response_model=RekaSignalsResponse)
async def get_reka_signals(
    timezone_name: str | None = Query(default=None, alias="timezone"),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    return await list_signals(
        session,
        user_id=user_id,
        now=utc_now(),
        timezone_name=_timezone_name(timezone_name),
    )


@router.post("/{signal_id}/dismiss", response_model=RekaDismissResponse)
async def dismiss_reka_signal(
    signal_id: str,
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
):
    try:
        nudge = await dismiss_signal(
            session,
            user_id=user_id,
            signal_id=signal_id,
            now=utc_now(),
        )
    except SignalNotFound as exc:
        raise HTTPException(status_code=404, detail="not found") from exc
    return {"ok": True, "status": nudge.status}
