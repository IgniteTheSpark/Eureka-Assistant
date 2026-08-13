from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse

from app.auth.dependencies import get_current_user_id
from app.domains.sessions.chat import SessionChatProvider, get_session_chat_provider
from app.domains.sessions.schemas import ChatRequest
from app.domains.sessions.turns import prepare_chat_turn, start_chat_turn


router = APIRouter(prefix="/api", tags=["session-chat"])


def _frame(event: str, payload: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"


@router.post("/chat")
async def chat(
    command: ChatRequest,
    user_id: str = Depends(get_current_user_id),
    provider: SessionChatProvider = Depends(get_session_chat_provider),
):
    try:
        prepared = await prepare_chat_turn(
            user_id=user_id,
            session_id=command.session_id,
            question=command.user_text,
        )
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="session not found") from exc

    completion = start_chat_turn(provider=provider, prepared=prepared)

    async def stream():
        yield _frame(
            "meta",
            {
                "session_id": prepared.session_id,
                "input_turn_id": prepared.input_turn_id,
            },
        )
        completed = await asyncio.shield(completion)
        if completed.result is not None:
            for event in completed.result.tool_events:
                event_type = str(event.get("event", "tool_result"))
                yield _frame(event_type, event.get("data", {}))
            yield _frame("token", {"text": completed.result.text})
            yield _frame(
                "done",
                {
                    "elapsed_ms": completed.elapsed_ms,
                    "total_tokens": completed.result.total_tokens,
                },
            )
        elif completed.public_error is not None:
            yield _frame(
                "error",
                {
                    "message": completed.public_error,
                    "elapsed_ms": completed.elapsed_ms,
                },
            )

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
