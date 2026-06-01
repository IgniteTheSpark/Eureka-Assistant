"""
Events API — Phase B v1.4.

Events are first-class entities (like contacts/files), NOT assets.
This router exposes CRUD + attendee/file management endpoints, delegating
to the same functions the MCP server exposes (mcp_server/tools.py).

Endpoints:
- GET    /api/events                    — list/filter events
- GET    /api/events/{event_id}         — single event with attendees + files
- POST   /api/events                    — create
- PUT    /api/events/{event_id}         — partial update
- DELETE /api/events/{event_id}         — delete (cascades)
- POST   /api/events/{event_id}/attendees  — add an attendee
- POST   /api/events/{event_id}/files      — link a file (kind: prep/recording/notes/attachment)

Powers:
- CalendarPage (Schedule / Month / Year / DayDetail views — Phase B §八)
- EventDetail page
- Chat-from-event flow (session has event_id, Assistant gets event context)
"""
import json
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from typing import Optional

from core.auth import get_current_user_id
from mcp_server.tools import (
    create_event, query_event, get_event, update_event, delete_event,
    add_event_attendee, link_event_file,
)

router = APIRouter()


# ── Request bodies ────────────────────────────────────────────────────────────

class EventCreate(BaseModel):
    title: str
    start_at: str                           # ISO8601 with TZ
    end_at: Optional[str] = ""
    location: Optional[str] = ""
    description: Optional[str] = ""
    all_day: Optional[int] = 0
    recurrence_rule: Optional[str] = ""
    source_input_turn_id: Optional[str] = ""


class EventPatch(BaseModel):
    title:           Optional[str] = None
    start_at:        Optional[str] = None
    end_at:          Optional[str] = None
    location:        Optional[str] = None
    description:     Optional[str] = None
    status:          Optional[str] = None   # scheduled | cancelled | done
    all_day:         Optional[int] = None
    recurrence_rule: Optional[str] = None


class AttendeeCreate(BaseModel):
    name:       Optional[str] = ""
    contact_id: Optional[str] = ""
    role:       Optional[str] = "attendee"  # organizer | attendee | optional


class EventFileLink(BaseModel):
    file_id: str
    kind:    Optional[str] = "attachment"   # prep | recording | notes | attachment


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/events")
async def list_events(
    contains:  str = Query("", description="keyword in title/location/description"),
    from_date: str = Query("", description="ISO8601 lower bound on start_at"),
    to_date:   str = Query("", description="ISO8601 upper bound on start_at"),
    status:    str = Query("", description="scheduled | cancelled | done"),
    limit:     int = Query(50, ge=1, le=500),
    user_id:   str = Depends(get_current_user_id),
):
    result = await query_event(contains, from_date, to_date, status, limit, user_id)
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("error", "query failed"))
    return result


@router.get("/events/{event_id}")
async def get_event_detail(
    event_id: str,
    user_id:  str = Depends(get_current_user_id),
):
    result = await get_event(event_id, user_id)
    if not result.get("ok"):
        raise HTTPException(status_code=404, detail=result.get("error", "not found"))
    return result


@router.post("/events")
async def create_event_endpoint(
    body:    EventCreate,
    user_id: str = Depends(get_current_user_id),
):
    result = await create_event(
        title=body.title,
        start_at=body.start_at,
        end_at=body.end_at or "",
        location=body.location or "",
        description=body.description or "",
        all_day=body.all_day or 0,
        recurrence_rule=body.recurrence_rule or "",
        source_input_turn_id=body.source_input_turn_id or "",
        user_id=user_id,
    )
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("error", "create failed"))
    return result


@router.put("/events/{event_id}")
async def update_event_endpoint(
    event_id: str,
    body:     EventPatch,
    user_id:  str = Depends(get_current_user_id),
):
    # Build patch dict from non-None fields only
    patch = {k: v for k, v in body.model_dump().items() if v is not None}
    if not patch:
        raise HTTPException(status_code=400, detail="empty patch")
    result = await update_event(event_id, json.dumps(patch, ensure_ascii=False), user_id)
    if not result.get("ok"):
        code = 404 if "not found" in result.get("error", "") else 400
        raise HTTPException(status_code=code, detail=result.get("error", "update failed"))
    return result


@router.delete("/events/{event_id}")
async def delete_event_endpoint(
    event_id: str,
    user_id:  str = Depends(get_current_user_id),
):
    result = await delete_event(event_id, user_id)
    if not result.get("ok"):
        raise HTTPException(status_code=404, detail=result.get("error", "not found"))
    return result


@router.post("/events/{event_id}/attendees")
async def add_attendee_endpoint(
    event_id: str,
    body:     AttendeeCreate,
    user_id:  str = Depends(get_current_user_id),
):
    if not body.name and not body.contact_id:
        raise HTTPException(status_code=400, detail="name or contact_id required")
    result = await add_event_attendee(
        event_id=event_id,
        name=body.name or "",
        contact_id=body.contact_id or "",
        role=body.role or "attendee",
        user_id=user_id,
    )
    if not result.get("ok"):
        code = 404 if "not found" in result.get("error", "") else 400
        raise HTTPException(status_code=code, detail=result.get("error", "add attendee failed"))
    return result


@router.post("/events/{event_id}/files")
async def link_file_endpoint(
    event_id: str,
    body:     EventFileLink,
    user_id:  str = Depends(get_current_user_id),
):
    result = await link_event_file(
        event_id=event_id,
        file_id=body.file_id,
        kind=body.kind or "attachment",
        user_id=user_id,
    )
    if not result.get("ok"):
        code = 404 if "not found" in result.get("error", "") else 400
        raise HTTPException(status_code=code, detail=result.get("error", "link file failed"))
    return result
