"""
Timeline API — Phase B v1.4.x.

GET /api/timeline?from=...&to=...&kinds=...&skills=...&limit=...

Powers the「全部」filter tab inside CalendarPage's Schedule view.
NOT a separate page — design (DESIGN.md §5.2) + Phase B §八 put
Schedule as the default state of CalendarPage with type-filter tabs,
and 「全部」 is one of those tabs.

Other concrete-kind tabs (event/todo/expense/...) typically use their
own endpoints which return per-type richer data; this endpoint is for
the unified-merge view only.
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, Query, HTTPException

from core.auth import get_current_user_id
from core.timeline import assemble_timeline
from db.database import AsyncSessionLocal

router = APIRouter()


def _parse_iso(s: Optional[str]) -> Optional[datetime]:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


@router.get("/timeline")
async def get_timeline(
    from_:   Optional[str] = Query(None, alias="from", description="ISO8601 lower bound on effective_at"),
    to:      Optional[str] = Query(None,                description="ISO8601 upper bound on effective_at"),
    kinds:   Optional[str] = Query(None, description="csv subset of: asset,event,input_turn,file (default: all)"),
    skills:  Optional[str] = Query(None, description="csv of skill_names to restrict asset kind"),
    limit:   int           = Query(500, ge=1, le=2000),
    user_id: str           = Depends(get_current_user_id),
):
    """
    Unified timeline for the 「全部」 tab.

    Returns items sorted by effective_at descending (newest first). Each
    item has a `kind` discriminator + kind-specific fields. Frontend
    renders per-kind:
      - kind=event       → calendar block / event chip
      - kind=asset       → SkillCard with skill_name's render_spec
      - kind=input_turn  → flash row (text snippet) or transcript row
      - kind=file        → file chip (upload moment)
    """
    from_dt = _parse_iso(from_)
    to_dt   = _parse_iso(to)
    if from_ and from_dt is None:
        raise HTTPException(400, f"invalid `from`: {from_}")
    if to and to_dt is None:
        raise HTTPException(400, f"invalid `to`: {to}")

    kinds_set:   Optional[set] = set(s.strip() for s in kinds.split(",")  if s.strip()) if kinds else None
    skills_set:  Optional[set] = set(s.strip() for s in skills.split(",") if s.strip()) if skills else None

    async with AsyncSessionLocal() as db:
        items = await assemble_timeline(
            db, user_id,
            from_dt=from_dt, to_dt=to_dt,
            kinds=kinds_set, skill_names=skills_set,
            limit=limit,
        )

    return {"ok": True, "items": items, "count": len(items)}
