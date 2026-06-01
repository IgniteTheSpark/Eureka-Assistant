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
import json
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
from core.auth import get_current_user_id
from core.event_mapper import (
    event_role, event_text,
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
    persist_chat_turn,
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
    Query/report tools contribute none (queries are intermediate; the report has
    its own receipt via the tool_result pair)."""
    if name in _QUERY_TOOLS or name == "tool_render_report":
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
    )

    enriched = history_text + f"用户: {user_text}"

    # deepseek sometimes emits a tool call as plain text instead of executing it
    # (see _looks_like_leaked_call). When it does, no tool runs and nothing has
    # streamed yet — so retry once with a nudge, suppressing the leaked attempt.
    MAX_ATTEMPTS = 2
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
        # Clean leak (no tool ran) → retry once, suppressing this attempt.
        if is_leak and not tool_seen and attempt < MAX_ATTEMPTS - 1:
            continue
        if is_leak:
            # Out of retries (or leak after a tool) — never dump raw JSON.
            yield ("token", {"text": "抱歉,刚才没能完成这个操作,请再说一次。"})
            return
        if final_text:
            yield ("token", {"text": final_text})
        return


# ── Endpoint ───────────────────────────────────────────────────────────────────

@router.post("/chat")
async def chat(req: ChatRequest, user_id: str = Depends(get_current_user_id)):
    """
    Unified Assistant chat (SSE).

    Streams events:
      meta         → {session_id, input_turn_id}
      token        → {text} (currently emitted as one chunk per agent step;
                     true per-token streaming is a Phase D polish item)
      tool_call    → {name, args}
      tool_result  → {name, response}
      done         → {elapsed_ms, message_id}
    """
    t0 = time.monotonic()

    async def stream() -> AsyncIterator[str]:
        # Phase 1 — session / input_turn setup
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
            # Pull assets / events already created in this session (typically
            # by an earlier Flash Pipeline run) — these are the「刚刚那个 X」
            # candidates the chat agent needs to find before deciding update
            # vs create. Without this, Flash-created assets are invisible to
            # the chat agent (Flash doesn't write to the messages table).
            session_assets_hint = await load_session_assets_hint(
                db, session_id, user_id,
            )
            # M2.2: explicit user-attached context assets (from「在 chat 里
            # 讨论」). Different from assets_hint (which is "things created
            # in this session"); context is "what the user wants the agent
            # to focus on right now."
            session_context_hint = await load_session_context_hint(
                db, session_id, user_id,
            )
            # M2.3: subject hint = the entity/asset this session is anchored to
            # (sessions.contact_id / event_id / file_id / subject_asset_id).
            # Distinct from context (additive) and assets_hint (in-session created).
            session_subject_hint = await load_session_subject_hint(
                db, session_id, user_id,
            )
            # User's registered skill dictionary — injected into the prompt so
            # the agent dispatches to user-created skills (跑步记录 / 宝宝养
            # 育记录 / …) by name + payload schema instead of falling back to
            # 'misc'. May audit, custom-skill dispatch bug.
            user_skills_hint = await load_user_skills_hint(db, user_id)

        # Date the agent will use to resolve "明天" / "下周" / ... — local TZ
        today_str = datetime.now(_LOCAL_TZ).date().isoformat()

        yield sse_event("meta", {
            "session_id": session_id,
            "input_turn_id": input_turn_id,
        })

        # Phase 2 — stream agent run, collect state for persistence
        history_text = _format_history(recent)
        agent_text_parts: list[str] = []
        # Persist EVERY created/updated card so a multi-intent turn replays all
        # of them on reload (was: only the first tool pair → one card survived).
        persist_cards: list = []
        # html-summary: a SUMMARY turn calls tool_render_report; keep that pair
        # so the report-receipt card (rendered from tool_result) survives reload.
        report_tool_call: dict | None = None
        report_tool_result: dict | None = None

        try:
            async for evt_type, payload in _stream_assistant(
                req.user_text, history_text, session_id, input_turn_id, user_id,
                event_id=req.event_id or "",
                today_str=today_str,
                user_skills_hint=user_skills_hint,
                session_assets_hint=session_assets_hint,
                session_context_hint=session_context_hint,
                session_subject_hint=session_subject_hint,
            ):
                yield sse_event(evt_type, payload)
                if evt_type == "token":
                    agent_text_parts.append(payload.get("text", ""))
                elif evt_type == "tool_call":
                    if payload.get("name") == "tool_render_report":
                        report_tool_call = payload
                elif evt_type == "tool_result":
                    if payload.get("name") == "tool_render_report":
                        report_tool_result = payload
                    else:
                        persist_cards.extend(
                            _cards_from_tool_result(payload.get("name", ""), payload.get("response", {}))
                        )
        except Exception as e:
            yield sse_event("error", {"message": str(e)[:200]})

        # Phase 3 — persist user + agent messages. The report pair (if any)
        # renders the receipt card via tool_result; all create/update cards
        # persist via `cards` so every one replays (no first-only truncation).
        persist_tool_call   = report_tool_call
        persist_tool_result = report_tool_result
        # Strip the bulky html out of the *tool_call* args — the frontend reads
        # the report from tool_result.response, so keeping it would double it.
        if report_tool_call:
            rc = dict(report_tool_call)
            args = dict(rc.get("args") or {})
            if isinstance(args.get("html"), str):
                args["html"] = f"⟨{len(args['html'])} chars⟩"
            rc["args"] = args
            persist_tool_call = rc

        agent_text = "".join(agent_text_parts).strip()
        elapsed_ms = int((time.monotonic() - t0) * 1000)
        try:
            async with AsyncSessionLocal() as db:
                _, agent_msg = await persist_chat_turn(
                    db, session_id, user_id,
                    user_text=req.user_text,
                    agent_text=agent_text,
                    tool_call=persist_tool_call,
                    tool_result=persist_tool_result,
                    cards=persist_cards,
                    elapsed_ms=elapsed_ms,
                )
                msg_id = str(agent_msg.id)
        except Exception:
            msg_id = ""

        yield sse_event("done", {"elapsed_ms": elapsed_ms, "message_id": msg_id})

    return StreamingResponse(
        with_heartbeats(stream()),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",  # disable nginx buffering if behind proxy
        },
    )
