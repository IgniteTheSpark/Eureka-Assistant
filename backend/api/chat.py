"""
POST /api/chat — Unified Assistant via SSE (Phase B Step 5, decision #6).

Per-request lifecycle:
1. Resolve / create chat session (sessions table, type=chat)
2. Create input_turn(source=typed) for this turn — provenance for any assets
   the agent creates in this turn
3. Load recent N=20 messages from messages table (decision #3 window)
4. Build the Assistant agent with this turn's session_id + input_turn_id
   woven into the prompt
5. Run ADK Runner; stream events out as SSE; collect for persistence
6. After the run, persist user message + agent message (with tool_call/result)
   to messages table

The "刚刚那个" cross-turn CRUD reference (Phase B v1.3) works because:
- Step 3 loads prior messages including tool_call+tool_result rows
- Those are formatted into the assistant's prompt context
- Assistant identifies the referenced asset_id from prior tool_call history
"""
import asyncio
import json
import re as _re
import time
import uuid
from datetime import datetime, timezone, timedelta
from typing import AsyncIterator

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai.types import Content, Part

from agents.assistant import make_assistant_agent
from agents.flash_pipeline import run_flash_pipeline
from core.auth import get_current_user_id
from core import chat_turns
from core.event_mapper import (
    event_role, event_text, event_usage,
    event_tool_calls, event_tool_results, is_streamable_token,
)
from core.session_service import (
    get_or_create_chat_session,
    create_input_turn_for_message,
    load_recent_messages,
    load_session_assets_hint,
    load_session_context_hint,
    load_session_subject_hint,
    load_user_skills_hint,
    persist_user_message,
    create_pending_agent_message,
    finalize_agent_message,
)

# Asia/Shanghai is the canonical user timezone for v1.4 demo data.
# Inject "today" into Assistant prompt so relative dates ("明天" / "下周")
# resolve from the actual current date, not the model's training cutoff.
_LOCAL_TZ = timezone(timedelta(hours=8))
from core.streaming import sse_event, with_heartbeats
from db.database import AsyncSessionLocal
from db.models import Message

router = APIRouter()


# ── Request / response ─────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    user_text: str
    session_id: str = ""   # empty = create new chat session
    event_id:   str = ""   # v1.4: anchor this chat to an event (event detail page → ask agent)


# ── History formatting ────────────────────────────────────────────────────────

def _format_history(messages: list[Message]) -> str:
    """
    Format recent messages as a text block to prefix to the new user input.

    Demo-grade approach: stringify the conversation. Cleaner alternative is
    to pre-populate ADK session events with typed objects, but that requires
    deeper ADK API binding. Text prefix gives the agent enough context to
    resolve "刚刚那个" references (it can see prior tool_calls + their results)
    and is robust to ADK API drift.
    """
    if not messages:
        return ""
    lines = ["【最近对话历史】"]
    for m in messages:
        if m.role == "user":
            lines.append(f"用户: {m.text}")
        elif m.role == "agent":
            if m.text:
                lines.append(f"助手: {m.text}")
            if m.tool_call:
                name = m.tool_call.get("name", "?")
                args = json.dumps(m.tool_call.get("args", {}), ensure_ascii=False)
                lines.append(f"[助手调用工具 {name} args={args}]")
        elif m.role == "tool":
            if m.tool_result:
                resp = json.dumps(m.tool_result.get("response", m.tool_result), ensure_ascii=False)
                lines.append(f"[工具返回: {resp}]")
    return "\n".join(lines) + "\n\n"


# ── Card extraction for persistence ───────────────────────────────────────────
# A multi-intent turn ("把上面每一项都生成待办" → 10 todos) calls create_* N
# times, but the messages table holds only ONE tool_call/result pair — so on
# reload only the first card replayed. Extract every created/updated card here
# and persist them in Message.cards (the frontend replay already renders that
# array, same as flash). Mirrors the frontend extractCardsFromToolResult.

_QUERY_TOOLS = {
    "tool_query_asset", "tool_query_event", "tool_query_contact",
    "tool_query_input_turn", "tool_query_digest",
    "tool_get_event", "tool_get_asset", "tool_get_contact", "tool_get_input_turn",
    # Defensive aliases: ADK/MCP wrappers have changed tool names across
    # versions. Read-only query results must remain transient even if the
    # prefix is stripped from the emitted tool name.
    "query_asset", "query_event", "query_contact", "query_input_turn",
    "query_digest", "get_event", "get_asset", "get_contact", "get_input_turn",
}


def _unwrap_tool_payloads(response) -> list[dict]:
    """FastMCP envelope → candidate payload dicts (top-level / structuredContent
    / JSON in content[0].text)."""
    out: list[dict] = []
    if not isinstance(response, dict):
        return out
    out.append(response)
    sc = response.get("structuredContent")
    if isinstance(sc, dict):
        out.append(sc)
    content = response.get("content")
    if isinstance(content, list) and content and isinstance(content[0], dict):
        text = content[0].get("text")
        if isinstance(text, str):
            try:
                parsed = json.loads(text)
                if isinstance(parsed, dict):
                    out.append(parsed)
            except (ValueError, TypeError):
                pass
    return out


def _tag_card(d) -> dict | None:
    """Stamp card_type so the frontend picks the right renderer (mirrors
    tagByIdField). None = nothing renderable (e.g. a delete's {ok, asset_id})."""
    if not isinstance(d, dict):
        return None
    if d.get("task_id"):       return {**d, "card_type": "task"}
    if d.get("asset_id") and d.get("payload"):  return d   # create/update asset
    if d.get("event_id") and d.get("title"):    return {**d, "card_type": "event"}
    if d.get("contact_id") and d.get("name"):   return {**d, "card_type": "contact"}
    return None


def _cards_from_tool_result(name: str, response) -> list[dict]:
    """Renderable card dict(s) from a create/update tool_result, for persistence.
    Query tools contribute none (queries are intermediate)."""
    if name in _QUERY_TOOLS:
        return []
    for c in _unwrap_tool_payloads(response):
        for key in ("assets", "events", "contacts", "tasks"):
            arr = c.get(key)
            if isinstance(arr, list) and arr:
                return [t for t in (_tag_card(x) for x in arr) if t]
        single = _tag_card(c)
        if single:
            return [single]
    return []


# ── Bulk-record routing (§1.5.1.3 batch B) ──────────────────────────────────────
# A single message that's really「捕捉 / 批量导入」(pasting dozens of records) is
# the WRONG job for chat's sequential single-LLM tool loop — it's slow (168s),
# fragile (truncates mid-run), and pricey. Detect it with a server-side heuristic
# (no LLM) and route to the Flash pipeline (dispatcher → PARALLEL sub-skills), then
# report the TRUE count. Conservative: only fires on clearly-bulk input so normal
# conversational turns ("帮我记一笔午餐 38 元") stay on the chat path.
_DATE_RE = _re.compile(r"(?:\d{4}\s*[-/年.]\s*\d{1,2}|\d{1,2}\s*[-/月.]\s*\d{1,2})")
_AMOUNT_RE = _re.compile(
    r"(?:[¥$￥]\s?\d+(?:\.\d+)?)|(?:\d+(?:\.\d+)?\s*(?:元|块|刀|usd|rmb|卡|kcal|页|km|公里|分钟|小时))",
    _re.I,
)


# A "handful" (≈3–7 records) is FINE in chat — the sequential tool loop handles it
# and keeps the turn conversational. Only a genuine bulk dump (≥ this) overwhelms
# chat (slow + truncates, §1.5.1.2) and is worth routing to the parallel Flash
# pipeline. One knob — raise it to keep more in chat, lower it to route sooner.
_BULK_MIN_RECORDS = 8


def _looks_like_bulk(text: str) -> bool:
    """Heuristic (no LLM): is this ONE message actually a bulk record dump?
    Estimates record count = max(total dates, total amounts, record-ish lines) and
    only fires at _BULK_MIN_RECORDS+. A handful (3–7) stays in chat by design, so
    a normal multi-item message keeps its conversational handling."""
    t = text or ""
    dates = len(_DATE_RE.findall(t))
    amounts = len(_AMOUNT_RE.findall(t))
    # One expense line usually carries a date AND/OR an amount, so the larger of
    # the two ≈ record count; record_lines covers inline-or-multiline either way.
    record_lines = sum(
        1 for ln in t.splitlines()
        if ln.strip() and (_DATE_RE.search(ln) or _AMOUNT_RE.search(ln))
    )
    return max(dates, amounts, record_lines) >= _BULK_MIN_RECORDS


def _group_cards(cards: list) -> dict:
    """Regroup already-tagged Flash cards into the typed arrays the frontend's
    extractCards() walks (assets/events/contacts/tasks) — so the LIVE viewer
    renders every card via one synthetic tool_result, no frontend change."""
    out: dict = {"assets": [], "events": [], "contacts": [], "tasks": []}
    for c in cards:
        if not isinstance(c, dict):
            continue
        if c.get("task_id"):
            out["tasks"].append(c)
        elif c.get("event_id") and c.get("title"):
            out["events"].append(c)
        elif c.get("contact_id") and c.get("name"):
            out["contacts"].append(c)
        else:
            out["assets"].append(c)
    return {k: v for k, v in out.items() if v}


# ── ADK runner helper ─────────────────────────────────────────────────────────

_adk_session_service = InMemorySessionService()
APP_NAME = "eureka-chat"


def _looks_like_leaked_call(text: str) -> bool:
    """deepseek intermittently writes a tool call as plain text content
    (function_call:{"call": ..., "arguments": ...}) instead of making a
    structured call — ADK never executes it, so the raw JSON would surface as
    the reply. Detect it so we can retry rather than show garbage."""
    if not text:
        return False
    t = text.strip()
    return "function_call" in t and ('"call"' in t or '"arguments"' in t)


async def _stream_assistant(
    user_text: str,
    history_text: str,
    session_id: str,
    input_turn_id: str,
    user_id: str,
    event_id: str = "",
    today_str: str = "",
    user_skills_hint: str = "",
    session_assets_hint: str = "",
    session_context_hint: str = "",
    session_subject_hint: str = "",
) -> AsyncIterator[tuple[str, dict]]:
    """
    Run the Assistant agent and yield (event_type, payload) tuples that the
    SSE wrapper can format. Also accumulates state for post-run persistence.
    """
    agent = make_assistant_agent(
        session_id,
        input_turn_id,
        event_id=event_id,
        today_str=today_str,
        user_skills_hint=user_skills_hint,
        session_assets_hint=session_assets_hint,
        session_context_hint=session_context_hint,
        session_subject_hint=session_subject_hint,
        user_id=user_id,
    )

    enriched = history_text + f"用户: {user_text}"

    # deepseek sometimes emits a tool call as plain text instead of executing it
    # (see _looks_like_leaked_call). When it does, no tool runs and nothing has
    # streamed yet — so retry once with a nudge, suppressing the leaked attempt.
    MAX_ATTEMPTS = 2
    # Sum reported token usage across the whole run (including a retry, which
    # really does cost tokens) so the turn-cost footer reflects actual spend.
    usage_total = 0
    for attempt in range(MAX_ATTEMPTS):
        # Fresh ADK in-memory session per attempt (no leaked-text contamination).
        adk_sid = str(uuid.uuid4())
        await _adk_session_service.create_session(
            app_name=APP_NAME, user_id=user_id, session_id=adk_sid,
        )
        runner = Runner(
            agent=agent, app_name=APP_NAME, session_service=_adk_session_service,
        )
        msg = enriched if attempt == 0 else (
            enriched + "\n\n(系统提示:请直接调用工具完成,不要把工具调用写成文字输出。)"
        )
        new_message = Content(role="user", parts=[Part(text=msg)])

        tool_seen = False
        final_text = ""
        async for event in runner.run_async(
            user_id=user_id, session_id=adk_sid, new_message=new_message,
        ):
            # Accumulate token usage whenever the model reports it (LiteLLM
            # forwards the provider's usage block through ADK usage_metadata).
            u = event_usage(event)
            if u.get("total_tokens"):
                usage_total += u["total_tokens"]
            # Tool calls → emit one SSE 'tool_call' per call. ADK batches parallel
            # calls into one event; emit them ALL or multi-intent turns lose every
            # card after the first.
            calls = event_tool_calls(event)
            if calls:
                tool_seen = True
                for tc in calls:
                    yield ("tool_call", tc)
                continue
            # Tool results → emit one SSE 'tool_result' per result.
            results = event_tool_results(event)
            if results:
                for tr in results:
                    yield ("tool_result", tr)
                continue
            # Final response → hold the text until we know it's not a leak.
            if hasattr(event, "is_final_response") and event.is_final_response():
                t = event_text(event)
                if t:
                    final_text = t

        is_leak = _looks_like_leaked_call(final_text)
        # The turn produced nothing usable: no tool ran AND no (non-leak) text.
        # DeepSeek intermittently returns an EMPTY completion (0 tokens) — it's
        # transient, so treat it like a leak and retry. Without this the user got
        # a silent "用时 Xs" with no reply and no cards.
        is_empty = not tool_seen and not final_text.strip()
        # Clean leak / empty (no tool ran) → retry once, suppressing this attempt.
        if (is_leak or is_empty) and not tool_seen and attempt < MAX_ATTEMPTS - 1:
            continue
        if is_leak:
            # Out of retries (or leak after a tool) — never dump raw JSON.
            yield ("token", {"text": "抱歉,刚才没能完成这个操作,请再说一次。"})
            if usage_total:
                yield ("usage", {"total_tokens": usage_total})
            return
        if is_empty:
            # Still empty after a retry — give a real prompt, never silence.
            yield ("token", {"text": "抱歉,我刚才没太理解,能换个说法再说一次吗?"})
            if usage_total:
                yield ("usage", {"total_tokens": usage_total})
            return
        if final_text:
            yield ("token", {"text": final_text})
        if usage_total:
            yield ("usage", {"total_tokens": usage_total})
        return


# ── Durable turn background task (§1.5.1.3 batch A) ─────────────────────────────
# The turn's work + persistence live HERE, decoupled from the SSE connection, so
# the client disconnecting (leaving the session page) can't cancel it. The SSE
# response is only a live *view* (core/chat_turns). Hold refs so tasks aren't GC'd.
_turn_tasks: set = set()


async def _run_chat_turn(
    *,
    turn_id: str,            # the running placeholder agent-message id (= channel key)
    user_text: str,
    history_text: str,
    session_id: str,
    input_turn_id: str,
    user_id: str,
    event_id: str,
    today_str: str,
    user_skills_hint: str,
    session_assets_hint: str,
    session_context_hint: str,
    session_subject_hint: str,
    t0: float,
) -> None:
    """Run the agent to completion and finalize the placeholder message — ALWAYS
    lands a terminal status (done/failed), even if the client never connected or
    left mid-generation. Publishes live events to the turn channel for any viewer."""
    agent_text_parts: list[str] = []
    persist_cards: list = []
    usage_total = 0
    status = "done"
    try:
        if _looks_like_bulk(user_text):
            # §1.5.1.3 batch B — this message is a bulk paste, not a conversation.
            # Route to the Flash pipeline (PARALLEL extraction) and report the
            # TRUE count. Fast (not 168s sequential), complete (no truncation).
            result = await run_flash_pipeline(
                user_text=user_text, session_id=session_id,
                input_turn_id=input_turn_id, today_str=today_str, user_id=user_id,
            )
            persist_cards = result.get("cards", []) or []
            n = len(persist_cards)
            summary = (result.get("summary") or result.get("reply") or "").strip()
            # Faithful receipt: prefer Flash's own count line, else state the truth.
            agent_text = summary or (
                f"已为你记录 {n} 条。" if n else "这条里没找到可记录的内容,换个说法再试试?"
            )
            agent_text_parts = [agent_text]
            chat_turns.publish(turn_id, ("token", {"text": agent_text}))
            if persist_cards:   # one synthetic tool_result → live viewer renders ALL cards
                chat_turns.publish(turn_id, ("tool_result", {
                    "name": "bulk_import", "response": _group_cards(persist_cards),
                }))
        else:
            async for evt_type, payload in _stream_assistant(
                user_text, history_text, session_id, input_turn_id, user_id,
                event_id=event_id,
                today_str=today_str,
                user_skills_hint=user_skills_hint,
                session_assets_hint=session_assets_hint,
                session_context_hint=session_context_hint,
                session_subject_hint=session_subject_hint,
            ):
                if evt_type == "usage":
                    usage_total = payload.get("total_tokens", 0) or usage_total
                    continue   # folded into the final `done`, not forwarded (parity)
                # Forward to any live viewer as it happens.
                chat_turns.publish(turn_id, (evt_type, payload))
                if evt_type == "token":
                    agent_text_parts.append(payload.get("text", ""))
                elif evt_type == "tool_result":
                    persist_cards.extend(
                        _cards_from_tool_result(payload.get("name", ""), payload.get("response", {}))
                    )
    except Exception as e:
        status = "failed"
        # Never leave the user staring at 「分析中…」: land a real, gentle reply.
        if not agent_text_parts:
            agent_text_parts.append("抱歉,刚才处理这条时出了点问题,请再试一次。")
        chat_turns.publish(turn_id, ("token", {"text": agent_text_parts[-1]}))
        chat_turns.publish(turn_id, ("error", {"message": str(e)[:200]}))

    agent_text = "".join(agent_text_parts).strip()
    elapsed_ms = int((time.monotonic() - t0) * 1000)
    try:
        async with AsyncSessionLocal() as db:
            await finalize_agent_message(
                db, turn_id,
                agent_text=agent_text,
                cards=persist_cards,
                elapsed_ms=elapsed_ms,
                status=status,
            )
    except Exception:
        pass

    # Final `done` for the live viewer (carries the same shape as before), then
    # the end-of-turn sentinel so the viewer closes its SSE.
    chat_turns.publish(turn_id, ("done", {
        "elapsed_ms": elapsed_ms, "message_id": turn_id, "total_tokens": usage_total,
    }))
    await chat_turns.close(turn_id)


# ── Endpoint ───────────────────────────────────────────────────────────────────

@router.post("/chat")
async def chat(req: ChatRequest, user_id: str = Depends(get_current_user_id)):
    """
    Unified Assistant chat (SSE) — durable turn (§1.5.1.3 batch A).

    The user message + a `running` agent placeholder persist BEFORE the response
    is returned, and generation runs as a background task that survives the client
    disconnecting. The SSE stream is a live view of that task. A returning client
    reconciles via the persisted message `status` (running → 「分析中…」 + poll).

    Streams events (unchanged for the connected client):
      meta         → {session_id, input_turn_id, turn_id}
      token        → {text}
      tool_call    → {name, args}
      tool_result  → {name, response}
      done         → {elapsed_ms, message_id, total_tokens}
    """
    t0 = time.monotonic()

    # ── Sync setup (awaited before the response): persist the input + placeholder
    # so they survive even if the client never reads the stream. ──
    async with AsyncSessionLocal() as db:
        session = await get_or_create_chat_session(
            db, user_id,
            session_id=req.session_id or None,
            title_hint=req.user_text,
            event_id=req.event_id or None,   # v1.4: anchor to event if provided
        )
        session_id = str(session.id)
        input_turn = await create_input_turn_for_message(
            db, session_id, user_id, req.user_text, source="typed",
        )
        input_turn_id = str(input_turn.id)
        recent = await load_recent_messages(db, session_id)
        # Pull assets / events already created in this session (typically by an
        # earlier Flash run) — the「刚刚那个 X」candidates the chat agent needs
        # before deciding update vs create. Flash doesn't write the messages table.
        session_assets_hint = await load_session_assets_hint(db, session_id, user_id)
        # M2.2: explicit user-attached context assets (from「在 chat 里讨论」).
        session_context_hint = await load_session_context_hint(db, session_id, user_id)
        # M2.3: subject hint = the entity/asset this session is anchored to.
        session_subject_hint = await load_session_subject_hint(db, session_id, user_id)
        # User's registered skill dictionary → dispatch to custom skills by name.
        user_skills_hint = await load_user_skills_hint(db, user_id)

        # Durable turn: land the user message NOW (leaving never loses input) and
        # a running agent placeholder (the in-flight marker a returning client
        # renders as 「分析中…」 and reconciles against).
        await persist_user_message(db, session_id, user_id, req.user_text)
        placeholder = await create_pending_agent_message(db, session_id, user_id)
        turn_id = str(placeholder.id)

    _now_local = datetime.now(_LOCAL_TZ)
    today_str = (
        f"{_now_local.isoformat(timespec='minutes')}"
        f"(周{'一二三四五六日'[_now_local.weekday()]})"
    )
    history_text = _format_history(recent)

    # Open the live-view channel, then spawn the turn as a background task that
    # OWNS the work — it is not tied to this request's lifetime.
    chat_turns.open_channel(turn_id)
    task = asyncio.create_task(_run_chat_turn(
        turn_id=turn_id,
        user_text=req.user_text,
        history_text=history_text,
        session_id=session_id,
        input_turn_id=input_turn_id,
        user_id=user_id,
        event_id=req.event_id or "",
        today_str=today_str,
        user_skills_hint=user_skills_hint,
        session_assets_hint=session_assets_hint,
        session_context_hint=session_context_hint,
        session_subject_hint=session_subject_hint,
        t0=t0,
    ))
    _turn_tasks.add(task)
    task.add_done_callback(_turn_tasks.discard)

    async def stream() -> AsyncIterator[str]:
        # meta first so the client learns the (possibly new) session + turn id even
        # if it disconnects immediately — the turn still completes server-side.
        yield sse_event("meta", {
            "session_id": session_id,
            "input_turn_id": input_turn_id,
            "turn_id": turn_id,
        })
        ch = chat_turns.get_channel(turn_id)
        if ch is None:   # turn already finished + reaped (very fast turn) → reconcile via reload
            yield sse_event("done", {"elapsed_ms": 0, "message_id": turn_id, "total_tokens": 0})
            return
        # Drain the live view until the end-of-turn sentinel. If the client
        # disconnects, this generator is cancelled but the background task runs on.
        # The 1s timeout + `finished` guard ends the stream even in the rare case
        # the DONE sentinel was dropped (bounded queue overflowed with no viewer).
        while True:
            try:
                evt = await asyncio.wait_for(ch.q.get(), timeout=1.0)
            except asyncio.TimeoutError:
                if ch.finished:
                    return
                continue
            if evt is chat_turns.DONE:
                return
            evt_type, payload = evt
            yield sse_event(evt_type, payload)

    return StreamingResponse(
        with_heartbeats(stream()),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # disable nginx buffering if behind proxy
        },
    )
