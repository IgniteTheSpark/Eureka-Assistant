from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user_id
from app.config import get_settings
from app.db.session import get_session
from app.domains.timeline.service import assemble_timeline


router = APIRouter(prefix="/api", tags=["timeline"])


@router.get("/timeline")
async def get_timeline(
    limit: int = Query(default=500, ge=1, le=1000),
    user_id: str = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    return {
        "items": await assemble_timeline(
            session,
            user_id,
            timezone_name=get_settings().default_user_timezone,
            limit=limit,
        )
    }
