"""One durable Chat turn service shared by ordinary and daily Flash Sessions."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from time import monotonic

from sqlalchemy import select

from app.config import get_settings
from app.db.base import utc_now
from app.db.session import session_scope
from app.domains.sessions import service
from app.domains.sessions.chat import (
    SessionChatProvider,
    SessionChatResult,
)
from app.domains.sessions.legacy_assistant import LegacyChatContext
from app.domains.sessions.models import SessionMessage
from app.domains.sessions.schemas import SessionCreate
from app.domains.sessions.tools import SessionToolExecutor


@dataclass(frozen=True)
class PreparedChatTurn:
    user_id: str
    session_id: str
    input_turn_id: str
    agent_message_id: str
    question: str
    context: LegacyChatContext
    history: list[dict]
    tool_executor: SessionToolExecutor
    started: float


@dataclass(frozen=True)
class CompletedChatTurn:
    prepared: PreparedChatTurn
    result: SessionChatResult | None
    elapsed_ms: int
    public_error: str | None = None


_active_tasks: set[asyncio.Task] = set()


def _history_item(message: SessionMessage) -> dict:
    return {
        "role": message.role,
        "text": message.text,
        "status": message.status,
        "input_turn_id": message.input_turn_id,
        "tool_call": message.tool_call_json,
        "tool_result": message.tool_result_json,
        "cards": message.cards_json or [],
    }


async def prepare_chat_turn(
    *,
    user_id: str,
    session_id: str,
    question: str,
) -> PreparedChatTurn:
    started = monotonic()
    normalized = question.strip()
    async with session_scope() as database:
        if session_id:
            model = await service.get_session(database, user_id, session_id)
            if model is None:
                raise LookupError("session not found")
        else:
            model = await service.create_or_peek_session(
                database,
                user_id,
                SessionCreate(session_type="chat"),
            )
            assert model is not None

        previous = await service.list_messages(database, user_id, model.id)
        history = [
            _history_item(message)
            for message in previous
            if message.status == "done"
            and (message.text or message.tool_call_json or message.tool_result_json)
        ]
        user_message, agent_message = await service.create_turn(
            database,
            model,
            normalized,
        )
        input_turn_id = user_message.input_turn_id
        assert input_turn_id is not None
        context = await service.build_chat_context(
            database,
            model,
            input_turn_id=input_turn_id,
            timezone_name=get_settings().default_user_timezone,
        )
        return PreparedChatTurn(
            user_id=user_id,
            session_id=model.id,
            input_turn_id=input_turn_id,
            agent_message_id=agent_message.id,
            question=normalized,
            context=context,
            history=history,
            tool_executor=SessionToolExecutor(
                user_id=user_id,
                session_id=model.id,
                input_turn_id=input_turn_id,
            ),
            started=started,
        )


def _tool_snapshots(events: list[dict]) -> tuple[dict | None, dict | None]:
    calls = [
        dict(event.get("data") or {})
        for event in events
        if event.get("event") == "tool_call"
    ]
    results = [
        dict(event.get("data") or {})
        for event in events
        if event.get("event") == "tool_result"
    ]
    return (
        {"calls": calls} if calls else None,
        {"results": results} if results else None,
    )


async def complete_chat_turn(
    *,
    provider: SessionChatProvider,
    prepared: PreparedChatTurn,
) -> CompletedChatTurn:
    try:
        result = await provider.answer(
            context=prepared.context,
            history=prepared.history,
            question=prepared.question,
            tool_executor=prepared.tool_executor,
        )
        elapsed_ms = int((monotonic() - prepared.started) * 1000)
        tool_calls, tool_results = _tool_snapshots(result.tool_events)
        async with session_scope() as database:
            stored = await database.scalar(
                select(SessionMessage).where(
                    SessionMessage.id == prepared.agent_message_id,
                    SessionMessage.user_id == prepared.user_id,
                )
            )
            if stored is not None:
                stored.status = "done"
                stored.text = result.text
                stored.tool_call_json = tool_calls
                stored.tool_result_json = tool_results
                stored.cards_json = result.cards
                stored.elapsed_ms = elapsed_ms
                stored.token_count = result.total_tokens
                stored.updated_at = utc_now()
                model = await service.get_session(
                    database,
                    prepared.user_id,
                    prepared.session_id,
                )
                if model is not None:
                    await service.publish_session_changed(
                        database,
                        model,
                        reason="chat_agent_done",
                    )
        return CompletedChatTurn(
            prepared=prepared,
            result=result,
            elapsed_ms=elapsed_ms,
        )
    except Exception:
        elapsed_ms = int((monotonic() - prepared.started) * 1000)
        public_error = "Agent 暂时不可用，请重试"
        async with session_scope() as database:
            stored = await database.scalar(
                select(SessionMessage).where(
                    SessionMessage.id == prepared.agent_message_id,
                    SessionMessage.user_id == prepared.user_id,
                )
            )
            if stored is not None:
                stored.status = "failed"
                stored.text = public_error
                stored.elapsed_ms = elapsed_ms
                stored.updated_at = utc_now()
                model = await service.get_session(
                    database,
                    prepared.user_id,
                    prepared.session_id,
                )
                if model is not None:
                    await service.publish_session_changed(
                        database,
                        model,
                        reason="chat_agent_failed",
                    )
        return CompletedChatTurn(
            prepared=prepared,
            result=None,
            elapsed_ms=elapsed_ms,
            public_error=public_error,
        )


def start_chat_turn(
    *,
    provider: SessionChatProvider,
    prepared: PreparedChatTurn,
) -> asyncio.Task[CompletedChatTurn]:
    task = asyncio.create_task(
        complete_chat_turn(provider=provider, prepared=prepared)
    )
    _active_tasks.add(task)
    task.add_done_callback(_active_tasks.discard)
    return task
