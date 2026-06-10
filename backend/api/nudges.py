"""
/api/nudges — §14 主动 REKA (Phase 2).

  GET   /api/nudges/pending      — today's un-acted nudges (app start: restore
                                   the「...」quiet state / peek without re-push)
  GET   /api/nudges?limit=       — recent nudges with outcome (feed 回溯)
  POST  /api/nudges/{id}/outcome — body {status: seen|acted|dismissed}
  GET   /api/nudges/prefs        — {nudges_enabled}
  PATCH /api/nudges/prefs        — body {nudges_enabled: bool} (§14.8 总开关)

Outcome states power both the feed display (「✓ 已记 / 未处理」) and the
server-side adaptive backoff (core/companion.py).
"""
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select

from core.auth import get_current_user_id
from db.database import AsyncSessionLocal
from db.models import Nudge, User

router = APIRouter()

_BEIJING = timezone(timedelta(hours=8))
_OUTCOMES = {"seen", "acted", "dismissed"}


def _ser(n: Nudge) -> dict:
    return {
        "id": str(n.id),
        "type": n.type,
        "kind": n.kind,
        "text": n.text,
        "body": n.body or "",
        "ref": n.ref or "",
        "cta": n.cta or "",
        "status": n.status,
        "created_at": n.created_at.isoformat() if n.created_at else None,
        "acted_at": n.acted_at.isoformat() if n.acted_at else None,
    }


@router.get("/nudges/pending")
async def pending_nudges(user_id: str = Depends(get_current_user_id)):
    """Un-acted nudges from today (Beijing) — the mobile shell restores the
    quiet「...」state from this on launch (no double-push)."""
    bj = datetime.now(timezone.utc).astimezone(_BEIJING)
    day_start = bj.replace(hour=0, minute=0, second=0, microsecond=0).astimezone(timezone.utc)
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Nudge).where(
                Nudge.user_id == user_id,
                Nudge.status.in_(("pending", "delivered", "seen")),
                Nudge.created_at >= day_start,
            ).order_by(Nudge.created_at.desc()).limit(10)
        )).scalars().all()
    return {"ok": True, "nudges": [_ser(n) for n in rows]}


@router.get("/nudges")
async def list_nudges(
    limit: int = Query(30, le=100),
    user_id: str = Depends(get_current_user_id),
):
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Nudge).where(Nudge.user_id == user_id)
            .order_by(Nudge.created_at.desc()).limit(limit)
        )).scalars().all()
    return {"ok": True, "nudges": [_ser(n) for n in rows]}


class OutcomeRequest(BaseModel):
    status: str


@router.post("/nudges/{nudge_id}/outcome")
async def nudge_outcome(
    nudge_id: str,
    req: OutcomeRequest,
    user_id: str = Depends(get_current_user_id),
):
    """Record what the user did with a nudge (§14.7). Transitions are one-way:
    a terminal outcome (acted/dismissed) is never downgraded back to seen."""
    status = (req.status or "").strip()
    if status not in _OUTCOMES:
        raise HTTPException(status_code=400, detail=f"invalid status: {status}")
    try:
        nid = uuid.UUID(nudge_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid nudge id")
    async with AsyncSessionLocal() as db:
        n = (await db.execute(
            select(Nudge).where(Nudge.id == nid, Nudge.user_id == user_id)
        )).scalar_one_or_none()
        if n is None:
            raise HTTPException(status_code=404, detail="nudge not found")
        terminal = n.status in ("acted", "dismissed")
        if not (terminal and status == "seen"):
            n.status = status
            if status == "acted":
                n.acted_at = datetime.now(timezone.utc)
            await db.commit()
            await db.refresh(n)
        payload = _ser(n)
    return {"ok": True, "nudge": payload}


class PrefsRequest(BaseModel):
    nudges_enabled: bool


@router.get("/nudges/prefs")
async def get_prefs(user_id: str = Depends(get_current_user_id)):
    async with AsyncSessionLocal() as db:
        u = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    prefs = (u.prefs if u else None) or {}
    return {"ok": True, "nudges_enabled": prefs.get("nudges_enabled") is not False}


@router.patch("/nudges/prefs")
async def set_prefs(req: PrefsRequest, user_id: str = Depends(get_current_user_id)):
    """§14.8 the one master switch (「球球提醒」). Default ON; stored in
    users.prefs so it survives reinstalls."""
    async with AsyncSessionLocal() as db:
        u = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
        if u is None:
            raise HTTPException(status_code=404, detail="user not found")
        u.prefs = {**(u.prefs or {}), "nudges_enabled": bool(req.nudges_enabled)}
        await db.commit()
    return {"ok": True, "nudges_enabled": bool(req.nudges_enabled)}
