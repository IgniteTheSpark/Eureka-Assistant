"""
GET /api/input-turns/{id} — fetch a single input_turn (full text + segments).

Used by:
- Asset Detail page's SessionTurnCard (design §7.2) — renders the original
  input that produced an asset
- Day Detail page's source chip on each card → click jumps to detail → uses this
- Future Meeting transcript lazy-load — agents call get_input_turn via MCP,
  but the frontend also needs an HTTP route for direct viewing
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from core.auth import get_current_user_id
from db.database import AsyncSessionLocal
from db.models import InputTurn

router = APIRouter()


@router.get("/input-turns/{turn_id}")
async def get_input_turn(
    turn_id: str,
    user_id: str = Depends(get_current_user_id),
):
    try:
        tid = uuid.UUID(turn_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid input_turn id")

    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(InputTurn).where(
                InputTurn.id == tid,
                InputTurn.user_id == user_id,
            )
        )
        turn = result.scalar_one_or_none()

    if not turn:
        raise HTTPException(status_code=404, detail="input_turn not found")

    return {
        "ok": True,
        "input_turn": {
            "id":                  str(turn.id),
            "session_id":          str(turn.session_id),
            "index":               turn.index,
            "source":              turn.source,
            "text":                turn.text,
            "segments":            turn.segments,
            "file_id":             str(turn.file_id) if turn.file_id else None,
            "source_file_offset":  turn.source_file_offset,
            "asr_provider":        turn.asr_provider,
            "language":            turn.language,
            "created_at":          turn.created_at.isoformat(),
        }
    }
