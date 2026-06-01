"""
Flash Pipeline — Phase B Step 4 rewrite (decision #4).

Three-step Python orchestration:
  Step 1 — Dispatcher:     1 LLM call → intent list (per skill type)
  Step 2 — Sub-skill agents: parallel LLM calls (one per intent) via asyncio.gather
  Step 3 — Python aggregator: build summary + cards (NO LLM)

Triggered by voice input_turns in flash sessions (per §三.4 routing).
Called from api/flash.py (Step 5).

Each sub-skill agent's create_asset includes source_input_turn_id pointing
back to the triggering input_turn — provenance kept end-to-end.

This is a rewrite of the previous flash_pipeline.py, with these changes:
- Uses agents/skill_factory.py + shared MCPToolset (no per-file tool duplication)
- Output mentions input_turn_id (was input_id)
- Aggregator includes 'event' card_type
- Cleaner _aggregate output for API consumption (derived_assets list)
"""
import asyncio
import json
import re
import uuid
from typing import Any, Optional, Tuple

from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai.types import Content, Part

from agents.skill_factory import (
    make_dispatcher_agent, make_skill_agent, make_custom_skill_agent,
    SKILL_FOLDER_MAP,
)
from core.event_mapper import event_tool_call, event_tool_result
from sqlalchemy import select
from db.database import AsyncSessionLocal
from db.models import GlobalSkill, UserSkill


_session_service = InMemorySessionService()
APP_NAME = "eureka-flash-pipeline"


# ── Utilities ──────────────────────────────────────────────────────────────────

def _parse_json(text: str) -> Optional[dict]:
    """Extract a JSON dict from agent output, tolerating markdown fences + preamble."""
    clean = re.sub(r"```(?:json)?\s*", "", text).replace("```", "").strip()
    for candidate in (clean, text.strip()):
        try:
            result = json.loads(candidate)
            if isinstance(result, dict):
                return result
        except (json.JSONDecodeError, ValueError):
            pass
    for m in reversed(list(re.finditer(r"\{[\s\S]+\}", clean or text))):
        try:
            result = json.loads(m.group())
            if isinstance(result, dict):
                return result
        except (json.JSONDecodeError, ValueError):
            continue
    return None


async def _run_agent(agent, message: str, user_id: str) -> Tuple[str, list]:
    """
    Spin a one-shot ADK Runner for a single agent invocation.

    Returns (final_text, tool_events) where tool_events is a list of
    {name, args, response} dicts captured from tool_call/tool_result events
    during the run. The tool_events fallback is critical: skill agents
    sometimes succeed at calling tool_create_asset (the DB write lands) but
    emit malformed final JSON, so _parse_json returns None and the result
    looks like a failure. With tool_events available, _run_intent can
    reconstruct the success.
    """
    sid = str(uuid.uuid4())
    await _session_service.create_session(
        app_name=APP_NAME, user_id=user_id, session_id=sid,
    )
    runner = Runner(agent=agent, app_name=APP_NAME, session_service=_session_service)
    user_msg = Content(role="user", parts=[Part(text=message)])
    final = ""
    tool_events: list = []
    pending_call: Optional[dict] = None
    async for event in runner.run_async(
        user_id=user_id, session_id=sid, new_message=user_msg,
    ):
        tc = event_tool_call(event)
        if tc:
            pending_call = tc
            continue
        tr = event_tool_result(event)
        if tr:
            tool_events.append({
                "name":     tr.get("name", ""),
                "args":     (pending_call or {}).get("args", {}) if pending_call and pending_call.get("name") == tr.get("name") else {},
                "response": tr.get("response", {}),
            })
            pending_call = None
            continue
        if event.is_final_response() and event.content:
            parts = event.content.parts or []
            if parts:
                final = parts[0].text or ""
    return final, tool_events


def _extract_tool_result_payload(response: Any) -> Optional[dict]:
    """
    FastMCP wraps tool returns as {"content": [{"type": "text", "text": "<json>"}],
    "structuredContent": {"result": "<json>"}, ...}. Pull the inner JSON out.
    Returns the parsed dict, or None if the response isn't shaped as expected.
    """
    if not isinstance(response, dict):
        return None
    # Prefer the explicit structuredContent.result if present
    sc = response.get("structuredContent") or {}
    if isinstance(sc, dict) and sc.get("result"):
        try:
            return json.loads(sc["result"])
        except (json.JSONDecodeError, ValueError, TypeError):
            pass
    # Fall back to content[0].text
    content = response.get("content") or []
    if content and isinstance(content[0], dict):
        text = content[0].get("text") or ""
        try:
            return json.loads(text)
        except (json.JSONDecodeError, ValueError, TypeError):
            return None
    return None


# tool names that, when successful, mean a skill effectively completed —
# even if the skill agent itself emitted garbled final JSON afterwards.
_SUCCESS_TOOL_NAMES = {
    "tool_create_asset", "tool_update_asset", "tool_delete_asset",
    "tool_create_event",  "tool_update_event",  "tool_delete_event",
    "tool_create_contact", "tool_update_contact",
}


def _fallback_result_from_tool_events(tool_events: list) -> Optional[dict]:
    """
    Walk captured tool_events in REVERSE (last successful write wins) and
    synthesize a skill result dict shaped like the skill agents normally
    return: {ok, asset_id|event_id|contact_id, payload, ...}.
    """
    for ev in reversed(tool_events):
        name = ev.get("name", "")
        if name not in _SUCCESS_TOOL_NAMES:
            continue
        data = _extract_tool_result_payload(ev.get("response"))
        if not data or not data.get("ok"):
            continue
        # Re-shape into the skill-return contract
        out: dict = {"ok": True}
        if data.get("asset_id"):   out["asset_id"]   = data["asset_id"]
        if data.get("event_id"):   out["event_id"]   = data["event_id"]
        if data.get("contact_id"): out["contact_id"] = data["contact_id"]
        if data.get("payload"):    out["payload"]    = data["payload"]
        # Some tools (create_event) flatten title/start_at to top level
        for k in ("title", "start_at", "end_at"):
            if data.get(k):
                out[k] = data[k]
        return out
    return None


# ── Step 1: Dispatcher ─────────────────────────────────────────────────────────

async def _load_custom_skill_map(user_id: str) -> dict[str, dict]:
    """
    Return {machine_name: {display_name, payload_schema, render_spec}} for
    every user-registered skill that does NOT have a `flash-<name>-skill`
    SKILL.md (i.e. dynamic, user-created via AddSkillWizard).

    Used by the dispatcher to learn about custom skills at request time and
    by _run_intent to route those intent types through make_custom_skill_agent.
    """
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(UserSkill, GlobalSkill.name.label("skill_name"))
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(UserSkill.user_id == user_id)
        )).all()
    out: dict[str, dict] = {}
    for us, machine_name in rows:
        if machine_name in SKILL_FOLDER_MAP:
            continue  # has a static SKILL.md — not "custom" in our sense
        if us.render_spec is None or us.render_spec == "null":
            continue  # system skills (qa, external_ref) are not user-routed
        out[machine_name] = {
            "display_name":   us.display_name or machine_name,
            "payload_schema": us.payload_schema or {},
            "render_spec":    us.render_spec if isinstance(us.render_spec, dict) else {},
        }
    return out


def _format_custom_skills_hint(custom_map: dict[str, dict]) -> str:
    """Render the custom-skills block injected into the dispatcher prompt."""
    if not custom_map:
        return ""
    lines: list[str] = []
    for machine_name, meta in custom_map.items():
        display = meta["display_name"]
        # Cheap keyword surface = display_name + payload field names.
        keywords = [display] + list((meta.get("payload_schema") or {}).keys())
        kw_str = " / ".join(k for k in keywords if k)
        lines.append(
            f"- `{machine_name}` ({display}): 关键词 = {kw_str}"
        )
    return "\n".join(lines)


async def _dispatch(user_text: str, today_str: str, user_id: str,
                    custom_skills_hint: str = "") -> list:
    """
    Classify a user's free-text input into a list of intents.
    Returns [{"type": "todo|event|expense|idea|contact|qa|note|<custom>", "source_text": "..."}].
    """
    agent = make_dispatcher_agent(custom_skills_hint=custom_skills_hint)
    msg = f"今天是 {today_str}。\nuser_text: {user_text}"
    raw, _tool_events = await _run_agent(agent, msg, user_id)
    parsed = _parse_json(raw)
    if parsed and isinstance(parsed.get("intents"), list):
        return parsed["intents"]
    return [{"type": "note", "source_text": user_text}]


# ── Step 2: Sub-skill agents (parallel) ───────────────────────────────────────

async def _run_intent(
    intent: dict,
    user_text: str,
    session_id: str,
    source_input_turn_id: str,
    today_str: str,
    user_id: str,
    custom_skill_map: dict[str, dict] | None = None,
) -> dict:
    """Dispatch one intent to its skill agent. Returns the skill's result dict."""
    itype = intent.get("type", "misc")

    # v1.4: 'note' (singular, old) → 'notes' (new long-form skill)
    if itype == "note":
        itype = "notes"

    source = intent.get("source_text", user_text)

    # v1.4.x: `task` intent bypasses the SKILL.md skill-agent path entirely —
    # it's a Python orchestrator (task_skill.run_task_intent) that creates a
    # placeholder + kicks off async MCP work. Returns the placeholder card
    # immediately so the user sees "⏳ pending" in <100ms.
    if itype == "task":
        from agents.task_skill import run_task_intent
        result = await run_task_intent(
            user_text=source,
            session_id=session_id,
            source_input_turn_id=source_input_turn_id,
            user_id=user_id,
        )
        result["source_text"] = source
        return result

    # Custom skill (no static SKILL.md). Build a one-shot agent from the
    # user's payload_schema + render_spec at call time. May audit fix:
    # without this branch, voice flash would dump "我跑了 5 公里" into
    # misc because the dispatcher emitted type=running but there's no
    # flash-running-skill folder to dispatch to.
    if custom_skill_map and itype in custom_skill_map:
        meta = custom_skill_map[itype]
        agent = make_custom_skill_agent(
            skill_name=itype,
            display_name=meta["display_name"],
            payload_schema=meta["payload_schema"],
            render_spec=meta["render_spec"],
        )
        msg = (
            f"source_text: {source}\n"
            f"user_text: {user_text}\n"
            f"session_id: {session_id}\n"
            f"source_input_turn_id: {source_input_turn_id}\n"
            f"今天是 {today_str}。"
        )
        raw, tool_events = await _run_agent(agent, msg, user_id)
        result = _parse_json(raw)
        if not result or not result.get("ok") or not result.get("asset_id"):
            synthesized = _fallback_result_from_tool_events(tool_events)
            if synthesized:
                result = synthesized
            elif not result:
                result = {"ok": False, "raw": raw[:200]}
        result["skill"] = f"{itype}-skill"
        result["source_text"] = source
        return result

    # If the dispatcher emitted a type that has neither a static SKILL.md
    # nor a custom-skill registration, fall back to misc instead of raising.
    # Happens when a user deletes a custom skill while a stale prompt is in
    # flight, or when the dispatcher hallucinates a type name.
    if itype not in SKILL_FOLDER_MAP:
        itype = "misc"

    agent = make_skill_agent(itype)
    msg = (
        f"source_text: {source}\n"
        f"user_text: {user_text}\n"
        f"session_id: {session_id}\n"
        f"source_input_turn_id: {source_input_turn_id}\n"
        f"今天是 {today_str}。"
    )
    raw, tool_events = await _run_agent(agent, msg, user_id)
    result = _parse_json(raw)

    # Fallback: even if the agent's final JSON is malformed, the underlying
    # tool_create_asset / create_event / create_contact may have succeeded.
    # Reconstruct from captured tool_events so the user still sees a real
    # asset card instead of an error card.
    if not result or not result.get("ok") or not (
        result.get("asset_id") or result.get("event_id") or result.get("contact_id")
    ):
        synthesized = _fallback_result_from_tool_events(tool_events)
        if synthesized:
            result = synthesized
        elif not result:
            result = {"ok": False, "raw": raw[:200]}

    result["skill"] = f"{itype}-skill"
    result["source_text"] = source

    # v1.4.x: dispatcher mis-routed an event without end_at to event-skill;
    # event tool's hard validation rejected. Auto-rerun as todo so the user
    # gets a usable todo card instead of an error card.
    if (itype == "event" and not result.get("ok")
        and "should be todo" in str(result.get("error", "")).lower()):
        fallback_intent = {"type": "todo", "source_text": source}
        return await _run_intent(
            fallback_intent, user_text, session_id, source_input_turn_id,
            today_str, user_id,
        )

    return result


# ── Step 3: Python aggregator (no LLM) ────────────────────────────────────────
#
# Card construction is driven by each UserSkill's `render_spec` JSON (seeded in
# db/seed.py, mutable later via design-agent). This means a new skill needs
# ZERO code changes here — it just needs a SKILL.md + a UserSkill row.
#
# A few skills genuinely have non-asset shapes and stay hardcoded:
#   - event-skill         (events table, event_id, not assets)
#   - task-skill          (async status flow)
#   - contact-skill       (uses contact_id, has pending_confirmation flow)
#   - error               (when result.ok=false)

def _fmt_dt(dt_str: str, *, as_deadline: bool = True) -> str:
    """
    Format ISO datetime to a compact display string.
      - if input has a time component  → "5月22日 15:00"
      - if input is date-only:
          - as_deadline=True (todo due_date) → "5月22日截止"
          - as_deadline=False (expense date) → "5月22日"
    """
    if not dt_str:
        return ""
    try:
        from datetime import datetime as _dt
        d = _dt.fromisoformat(str(dt_str).replace("Z", "+00:00"))
        if d.hour or d.minute:
            return f"{d.month}月{d.day}日 {d.strftime('%H:%M')}"
        return f"{d.month}月{d.day}日{'截止' if as_deadline else ''}"
    except (ValueError, AttributeError, TypeError):
        return str(dt_str)


# Task-skill status / external-system labels — these are presentation-only
# decoration over a real status enum, not skill-routing.
_TASK_STATUS_ICON = {"pending": "⏳", "running": "⏳", "done": "✅", "failed": "❌"}
_EXTERNAL_SYSTEM_LABEL = {
    "notion":            "Notion",
    "google_calendar":   "Google Calendar",
    "dingtalk":          "钉钉",
    "dingtalk_calendar": "钉钉日历",
    "dingtalk_todo":     "钉钉待办",
    "linear":            "Linear",
    "pending":           "处理中",
    "unknown":           "未知",
}


# ── Render-spec interpreter (the generic path) ────────────────────────────────

def _apply_format(value: Any, fmt: Optional[str]) -> str:
    """
    Apply a render_spec format directive to a single value.
    Format enum (seed.py): relative_date / absolute_date / currency /
                           truncate_30 / truncate_40 / truncate_60 / badge
    """
    if value is None or value == "":
        return ""
    s = str(value)
    if not fmt:
        return s
    if fmt == "relative_date":
        # Deadline-style display ("5月22日截止" when no time)
        return _fmt_dt(s, as_deadline=True)
    if fmt == "absolute_date":
        # Plain date display ("5月22日" when no time) — used for expense/note dates
        return _fmt_dt(s, as_deadline=False)
    if fmt == "currency":
        return f"¥{s}"
    if fmt.startswith("truncate_"):
        try:
            n = int(fmt.split("_", 1)[1])
        except (ValueError, IndexError):
            n = 40
        return s[:n] + ("…" if len(s) > n else "")
    if fmt == "badge":
        return s   # frontend renders it with a pill style; we just pass through
    return s


def _resolve_meta_field(spec_entry: dict, payload: dict) -> Optional[dict]:
    """
    Resolve one meta_field entry like {field:"category", format:"badge"} →
    {field, value, format} for the frontend, or None if there's no value.
    """
    field = spec_entry.get("field")
    if not field:
        return None
    raw = payload.get(field)
    if raw is None or raw == "":
        return None
    return {
        "field":  field,
        "value":  _apply_format(raw, spec_entry.get("format")),
        "format": spec_entry.get("format"),
    }


def _build_card_from_render_spec(
    machine_name: str,
    payload: dict,
    asset_id: Optional[str],
    spec: dict,
) -> dict:
    """
    Construct a Flash card entirely from a UserSkill.render_spec JSON.

    The render_spec drives:
      - primary_field / primary_format  → title
      - secondary_field / secondary_format → subtitle
      - meta_fields[]                   → meta_fields (formatted)
      - icon / accent_color / actions   → presentation passthroughs

    Skill-agnostic — adding a new skill needs no code change here as long as
    its UserSkill row is seeded with a valid render_spec.
    """
    primary = payload.get(spec.get("primary_field") or "")
    secondary = payload.get(spec.get("secondary_field") or "")

    title    = _apply_format(primary,   spec.get("primary_format"))
    subtitle = _apply_format(secondary, spec.get("secondary_format"))

    # Title fallback: empty primary → use the UserSkill's display_name
    if not title:
        title = spec.get("_display_name") or machine_name

    meta_fields = []
    for mf in spec.get("meta_fields") or []:
        resolved = _resolve_meta_field(mf, payload)
        if resolved:
            meta_fields.append(resolved)

    return {
        "card_type":    machine_name,           # frontend keys CSS off this
        "title":        title,
        "subtitle":     subtitle,
        "asset_id":     asset_id,
        "icon":         spec.get("icon", ""),
        "accent_color": spec.get("accent_color", ""),
        "meta_fields":  meta_fields,
        "actions":      spec.get("actions", []),
    }


# ── Special-case card builders (data shapes that don't fit the generic path) ──

def _error_card(r: dict, render_specs: dict) -> dict:
    skill = r.get("skill", "")
    machine_name = skill.removesuffix("-skill") if skill.endswith("-skill") else skill
    display = (render_specs.get(machine_name) or {}).get("_display_name") or machine_name or "未知"
    return {
        "card_type": "error",
        "title":     display,
        "subtitle":  (r.get("message") or r.get("error") or "处理失败")[:50],
        "asset_id":  None,
    }


def _event_card(r: dict) -> dict:
    """event-skill creates rows in the `events` table, not `assets`."""
    payload = r.get("payload") or {}
    return {
        "card_type": "event",
        "title":     r.get("title") or payload.get("title") or "事件",
        "subtitle":  _fmt_dt(r.get("start_at") or payload.get("start_at", "")),
        "event_id":  r.get("event_id"),
        "asset_id":  None,
    }


def _task_card(r: dict) -> dict:
    """task-skill: async status flow with pending/running/done/failed."""
    payload  = r.get("payload") or {}
    status   = payload.get("status", "pending")
    ext_sys  = payload.get("external_system", "pending")
    icon     = _TASK_STATUS_ICON.get(status, "⏳")
    ext_label = _EXTERNAL_SYSTEM_LABEL.get(ext_sys, ext_sys)
    return {
        "card_type":       "task",
        "title":           f"{icon} {payload.get('title', '任务')}",
        "subtitle":        f"→ {ext_label}" + ("" if status in ("done", "failed") else " · 处理中"),
        "asset_id":        r.get("asset_id"),
        "task_id":         r.get("task_id"),
        "status":          status,
        "external_system": ext_sys,
        "external_url":    payload.get("external_url", ""),
    }


def _pending_contact_card(r: dict) -> dict:
    """contact-skill found multiple candidates — user must pick one."""
    candidates = r.get("pending_candidates", [])
    name = (r.get("source_text") or "联系人")[:20]
    return {
        "card_type":  "pending_contact",
        "title":      name,
        "subtitle":   f"找到 {len(candidates)} 个同名联系人,请确认",
        "asset_id":   None,
        "candidates": candidates,
    }


def _contact_card(r: dict, render_specs: dict) -> dict:
    """
    contact-skill normal-path. Uses contact_id (not asset_id) as the handle,
    and the skill agent stashes name/company at the result top level (not in
    payload). The action message ('已新建'/'已更新') is also skill-specific.
    """
    payload  = r.get("payload") or {}
    name     = r.get("name") or payload.get("name") or "联系人"
    company  = r.get("company") or payload.get("company") or ""
    action   = r.get("contact_action", "created")
    subtitle = (f"已新建 · {company}" if company else "已新建") if action == "created" else "已更新"
    spec = render_specs.get("contact") or {}
    return {
        "card_type":    "contact",
        "title":        name,
        "subtitle":     subtitle,
        "asset_id":     r.get("contact_id"),     # contact uses its own id
        "icon":         spec.get("icon", "👤"),
        "accent_color": spec.get("accent_color", "neutral"),
        "actions":      spec.get("actions", []),
    }


# ── _make_card: dispatcher (4 special cases, otherwise generic) ──────────────

def _make_card(r: dict, render_specs: dict) -> dict:
    """
    Build one Flash card from a skill agent's result dict.

    `render_specs` is a pre-fetched dict {machine_name → render_spec}, loaded
    once per request from UserSkill rows. Passed in so this function stays
    sync and avoids per-card DB round-trips.

    Strategy:
      1. ok=false (not pending_confirmation) → error card
      2. 4 hardcoded special cases for genuinely non-standard data shapes
      3. Everything else → generic render_spec-driven path
    """
    skill = r.get("skill", "")
    status = r.get("status", "success")

    # 1. Failures
    if not r.get("ok") and status != "pending_confirmation":
        return _error_card(r, render_specs)

    # 2. Special-case data shapes
    if skill == "event-skill":
        return _event_card(r)
    if skill == "task-skill":
        return _task_card(r)
    if skill == "contact-skill" and status == "pending_confirmation":
        return _pending_contact_card(r)
    if skill == "contact-skill":
        return _contact_card(r, render_specs)

    # qa-skill never produces a card — handled via `reply` field, not here.
    if skill == "qa-skill":
        return _error_card(r, render_specs)   # only reached if something upstream is buggy

    # 3. Generic path — works for todo / idea / notes / misc / expense AND any
    #    future skill whose UserSkill has a render_spec seeded.
    machine_name = skill.removesuffix("-skill")
    spec = render_specs.get(machine_name)
    if not spec:
        return _error_card(r, render_specs)
    return _build_card_from_render_spec(
        machine_name=machine_name,
        payload=r.get("payload") or {},
        asset_id=r.get("asset_id"),
        spec=spec,
    )


def _split_qa_and_assets(results: list) -> tuple:
    """Partition results into (qa-skill results, everything else)."""
    qa_results, asset_results = [], []
    for r in results:
        if r.get("skill") == "qa-skill":
            qa_results.append(r)
        else:
            asset_results.append(r)
    return qa_results, asset_results


def _build_reply(qa_results: list) -> str:
    """
    Concatenate qa-skill answers into a single conversational reply.
    Typically there's exactly one qa intent per flash input, but multi-question
    inputs (rare) get joined with blank-line separators.
    """
    parts = [r.get("answer", "").strip() for r in qa_results if r.get("ok") and r.get("answer")]
    return "\n\n".join(p for p in parts if p)


def _build_summary(asset_results: list, has_reply: bool) -> str:
    """
    Terse status line about asset creation. QA answers live in `reply`,
    not summary — so summary is purely about what got recorded.
    """
    ok_count = sum(
        1 for r in asset_results
        if r.get("ok") and r.get("status") != "pending_confirmation"
    )
    pending_names = [
        (r.get("source_text") or "联系人")[:10]
        for r in asset_results if r.get("status") == "pending_confirmation"
    ]

    if ok_count == 0 and not pending_names:
        # No assets created. If there's a reply, summary stays empty (the reply
        # itself is the response). Otherwise tell the user nothing matched.
        return "" if has_reply else "本次闪念未识别到可保存的内容。"

    summary = f"已记录 {ok_count} 项内容。" if ok_count > 0 else ""
    if pending_names:
        joiner = "" if not summary else "…"
        summary += f"{joiner}联系人「{'、'.join(pending_names)}」需要确认。"
    return summary


async def _load_user_render_specs(user_id: str) -> dict:
    """
    Fetch every UserSkill row for `user_id` and return a dict keyed by the
    GlobalSkill machine name → render_spec (with display_name stashed under
    `_display_name`).

    Called ONCE per flash pipeline run; result is passed through to
    `_make_card` so card construction stays sync and doesn't hit the DB
    per-card.
    """
    from sqlalchemy import select
    from db.database import AsyncSessionLocal
    from db.models import UserSkill, GlobalSkill

    out: dict = {}
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(GlobalSkill.name, UserSkill.render_spec, UserSkill.display_name)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(UserSkill.user_id == user_id)
        )).all()
    for machine_name, render_spec, display_name in rows:
        spec = dict(render_spec) if render_spec else {}
        spec["_display_name"] = display_name or machine_name
        out[machine_name] = spec
    return out


def _aggregate(results: list, session_id: str, input_turn_id: str, render_specs: dict) -> dict:
    qa_results, asset_results = _split_qa_and_assets(results)
    reply = _build_reply(qa_results)
    cards = [_make_card(r, render_specs) for r in asset_results]
    return {
        "ok":              True,
        "session_id":      session_id,
        "input_turn_id":   input_turn_id,
        "reply":           reply,
        "summary":         _build_summary(asset_results, has_reply=bool(reply)),
        "cards":           cards,
        "derived_assets":  [
            {"asset_id": c["asset_id"], "card": c}
            for c in cards if c.get("asset_id")
        ],
        "derived_events":  [   # v1.4: events are not assets — separate list
            {"event_id": c["event_id"], "card": c}
            for c in cards if c.get("event_id")
        ],
        "has_pending":     any(r.get("status") == "pending_confirmation" for r in asset_results),
    }


# ── Public entry point ────────────────────────────────────────────────────────

async def run_flash_pipeline(
    user_text: str,
    session_id: str,
    input_turn_id: str,
    today_str: str,
    user_id: str = "default",
) -> dict:
    """
    Full flash pipeline. Returns a dict shaped for /api/flash response:
      {ok, session_id, input_turn_id, reply, summary, cards, derived_assets, has_pending}

    Sub-skill agents create assets with source_input_turn_id=input_turn_id —
    provenance preserved so Phase D's SessionTurnCard can render it.

    Flash is the *capture* surface (per the capture/question/task/chat
    classification). Each intent emitted by the dispatcher runs in parallel;
    sibling skills do not share output (no cross-skill dependencies).

    For generative work that needs research / multi-step reasoning, Flash
    is intentionally NOT the right entry point — those flows belong to chat
    or to task-skill (third-party MCP wrapper).
    """
    # Pre-fetch render_specs for this user once — drives all generic card
    # rendering. New skills inherit Flash's card pipeline by virtue of having
    # a render_spec, no code change needed in this file.
    render_specs = await _load_user_render_specs(user_id)

    # May audit: load the user's custom-skill map so both the dispatcher
    # (prompt hint) and _run_intent (routing) can dispatch to them. Without
    # this, voice flash never routed to 跑步记录 / 宝宝养育记录 etc. and
    # everything went to misc.
    custom_skill_map = await _load_custom_skill_map(user_id)
    custom_skills_hint = _format_custom_skills_hint(custom_skill_map)

    intents = await _dispatch(user_text, today_str, user_id, custom_skills_hint)
    results = list(
        await asyncio.gather(*[
            _run_intent(
                i, user_text, session_id, input_turn_id, today_str, user_id,
                custom_skill_map=custom_skill_map,
            )
            for i in intents
        ])
    )
    return _aggregate(results, session_id, input_turn_id, render_specs)
