from __future__ import annotations

import asyncio
import json
from time import monotonic

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import select

from app.auth.dependencies import get_current_user_id
from app.db.base import utc_now
from app.db.session import session_scope
from app.domains.sessions import service
from app.domains.sessions.chat import SessionChatProvider, get_session_chat_provider
from app.domains.sessions.models import SessionMessage
from app.domains.sessions.schemas import ChatRequest, SessionCreate
from app.domains.sessions.tools import SessionToolExecutor


router = APIRouter(prefix="/api", tags=["session-chat"])


def _frame(event: str, payload: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n"


async def _complete_turn(
    *,
    provider: SessionChatProvider,
    context: str,
    history: list[dict[str, str]],
    question: str,
    agent_message_id: str,
    session_id: str,
    user_id: str,
    started: float,
    tool_executor: SessionToolExecutor,
):
    try:
        result = await provider.answer(
            context=context,
            history=history,
            question=question,
            tool_executor=tool_executor,
        )
        elapsed_ms = int((monotonic() - started) * 1000)
        async with session_scope() as database:
            stored = await database.scalar(
                select(SessionMessage).where(
                    SessionMessage.id == agent_message_id,
                    SessionMessage.user_id == user_id,
                )
            )
            if stored is not None:
                stored.status = "done"
                stored.text = result.text
                stored.cards_json = result.cards
                stored.elapsed_ms = elapsed_ms
                stored.token_count = result.total_tokens
                stored.updated_at = utc_now()
                model = await service.get_session(database, user_id, session_id)
                if model is not None:
                    await service.publish_session_changed(
                        database,
                        model,
                        reason="chat_agent_done",
                    )
        return result, elapsed_ms, None
    except Exception:
        async with session_scope() as database:
            stored = await database.scalar(
                select(SessionMessage).where(
                    SessionMessage.id == agent_message_id,
                    SessionMessage.user_id == user_id,
                )
            )
            if stored is not None:
                stored.status = "failed"
                stored.text = ""
                stored.updated_at = utc_now()
                model = await service.get_session(database, user_id, session_id)
                if model is not None:
                    await service.publish_session_changed(
                        database,
                        model,
                        reason="chat_agent_failed",
                    )
        return None, None, "Agent 暂时不可用，请重试"


@router.post("/chat")
async def chat(
    command: ChatRequest,
    user_id: str = Depends(get_current_user_id),
    provider: SessionChatProvider = Depends(get_session_chat_provider),
):
    if command.session_id:
        async with session_scope() as database:
            if (
                await service.get_session(database, user_id, command.session_id)
                is None
            ):
                raise HTTPException(status_code=404, detail="session not found")

    async def stream():
        started = monotonic()
        async with session_scope() as database:
            model = None
            if command.session_id:
                model = await service.get_session(database, user_id, command.session_id)
            else:
                model = await service.create_or_peek_session(
                    database, user_id, SessionCreate(session_type="chat")
                )
            assert model is not None
            previous = await service.list_messages(database, user_id, model.id)
            history = [
                {"role": item.role, "text": item.text}
                for item in previous
                if item.status == "done" and item.text
            ]
            context = await service.build_chat_context(database, model)
            user_message, agent_message = await service.create_turn(
                database, model, command.user_text.strip()
            )
            session_id = model.id
            agent_message_id = agent_message.id
            input_turn_id = user_message.input_turn_id

        yield _frame(
            "meta",
            {"session_id": session_id, "input_turn_id": input_turn_id},
        )
        # Shield provider work from a disconnected mobile client: leaving the
        # page cancels only the SSE reader, while the durable turn still lands.
        completion = asyncio.create_task(
            _complete_turn(
                provider=provider,
                context=context,
                history=history,
                question=command.user_text.strip(),
                agent_message_id=agent_message_id,
                session_id=session_id,
                user_id=user_id,
                started=started,
                tool_executor=SessionToolExecutor(
                    user_id=user_id,
                    session_id=session_id,
                    input_turn_id=input_turn_id,
                ),
            )
        )
        result, elapsed_ms, public_error = await asyncio.shield(completion)
        if result is not None and elapsed_ms is not None:
            for event in result.tool_events:
                event_type = str(event.get("event", "tool_result"))
                yield _frame(event_type, event.get("data", {}))
            yield _frame("token", {"text": result.text})
            yield _frame(
                "done",
                {"elapsed_ms": elapsed_ms, "total_tokens": result.total_tokens},
            )
        elif public_error is not None:
            yield _frame("error", {"message": public_error})

    return StreamingResponse(
        stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
