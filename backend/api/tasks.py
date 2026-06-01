"""
/api/tasks — Phase B v1.4.x.

Read-only surface for the async task system:
  GET /api/tasks                   — list user's tasks (optional status filter)
  GET /api/tasks/{task_id}         — single task detail + linked external_ref payload

Creation happens via:
  - Flash dispatcher emitting `{type: "task"}` → flash_pipeline → task_skill.run_task_intent
  - Assistant calling `tool_create_task` (MCP tool) → task_skill.run_task_intent

Frontend polls /api/tasks/{id} (or just re-fetches the placeholder asset) to
discover when an async task transitions from pending → running → done/failed.
"""
import uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select

from core.auth import get_current_user_id
from db.database import AsyncSessionLocal
from db.models import Task, Asset

router = APIRouter()


def _task_to_dict(t: Task, asset: Optional[Asset] = None) -> dict:
    return {
        "id":                   str(t.id),
        "user_text":            t.user_text,
        "mcp_target":           t.mcp_target,
        "status":               t.status,
        "error_message":        t.error_message,
        "result_asset_id":      str(t.result_asset_id) if t.result_asset_id else None,
        "result_asset_payload": asset.payload if asset is not None else None,
        "session_id":           str(t.session_id) if t.session_id else None,
        "source_input_turn_id": str(t.source_input_turn_id) if t.source_input_turn_id else None,
        "started_at":           t.started_at.isoformat() if t.started_at else None,
        "completed_at":         t.completed_at.isoformat() if t.completed_at else None,
        "created_at":           t.created_at.isoformat(),
    }


@router.get("/tasks")
async def list_tasks(
    status:  Optional[str] = Query(None, description="pending | running | done | failed"),
    limit:   int           = Query(30, le=100),
    user_id: str           = Depends(get_current_user_id),
):
    async with AsyncSessionLocal() as db:
        stmt = select(Task).where(Task.user_id == user_id)
        if status:
            stmt = stmt.where(Task.status == status)
        stmt = stmt.order_by(Task.created_at.desc()).limit(limit)
        tasks = (await db.execute(stmt)).scalars().all()
    return {
        "ok":    True,
        "tasks": [_task_to_dict(t) for t in tasks],
    }


@router.get("/tasks/{task_id}")
async def get_task(
    task_id: str,
    user_id: str = Depends(get_current_user_id),
):
    try:
        tid = uuid.UUID(task_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid task id")

    async with AsyncSessionLocal() as db:
        t = (await db.execute(
            select(Task).where(Task.id == tid, Task.user_id == user_id)
        )).scalar_one_or_none()
        if not t:
            raise HTTPException(status_code=404, detail="task not found")
        asset = None
        if t.result_asset_id:
            asset = (await db.execute(
                select(Asset).where(Asset.id == t.result_asset_id)
            )).scalar_one_or_none()

    return {"ok": True, "task": _task_to_dict(t, asset)}
