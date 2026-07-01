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
from datetime import datetime, timedelta, timezone
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
from core.agent_runner import run_agent
from core.event_mapper import event_tool_call, event_tool_result
from sqlalchemy import delete, select
from db.database import AsyncSessionLocal
from db.models import GlobalSkill, UserSkill


_session_service = InMemorySessionService()
APP_NAME = "eureka-flash-pipeline"
_BEIJING = timezone(timedelta(hours=8))


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


_PERIOD_KEYWORDS: tuple[tuple[str, str], ...] = (
    ("凌晨", "凌晨"),
    ("早上", "上午"),
    ("上午", "上午"),
    ("中午", "中午"),
    ("下午", "下午"),
    ("晚上", "晚上"),
    ("今晚", "晚上"),
    ("夜里", "晚上"),
)


def _parse_today(today_str: str) -> datetime:
    raw = (today_str or "").split("(", 1)[0].strip()
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(_BEIJING)
    except (ValueError, TypeError):
        return datetime.now(_BEIJING)


def _asset_time_hints(source_text: str, today_str: str) -> dict[str, str]:
    """Best-effort fallback for custom skills when the LLM misses tool args.

    Main extraction still lives in the custom-skill prompt. This only prevents
    the deterministic fallback from storing explicit relative dates like
    "昨天下午跑了5km" under today's capture timestamp.
    """
    text = source_text or ""
    now = _parse_today(today_str)
    day = now.date()
    date_mentioned = False
    for key, delta in (("前天", -2), ("昨天", -1), ("昨日", -1),
                       ("今天", 0), ("明天", 1), ("后天", 2)):
        if key in text:
            day = (now + timedelta(days=delta)).date()
            date_mentioned = True
            break

    period = ""
    for key, value in _PERIOD_KEYWORDS:
        if key in text:
            period = value
            break

    occurred_at = ""
    if any(k in text for k in ("刚刚", "刚才", "现在", "这会儿")):
        occurred_at = now.isoformat(timespec="seconds")
    clock = re.search(r"(凌晨|早上|上午|中午|下午|晚上|今晚)?\s*(\d{1,2})(?:[:：点时])(\d{1,2})?分?", text)
    if clock:
        hour = int(clock.group(2))
        minute = int(clock.group(3) or 0)
        marker = clock.group(1) or ""
        if marker in {"下午", "晚上", "今晚"} and 1 <= hour <= 11:
            hour += 12
        if marker == "中午" and hour == 12:
            hour = 12
        if marker in {"凌晨"} and hour == 12:
            hour = 0
        if 0 <= hour <= 23 and 0 <= minute <= 59:
            occurred_at = datetime(
                day.year, day.month, day.day, hour, minute, tzinfo=_BEIJING,
            ).isoformat(timespec="seconds")

    created_at = ""
    if date_mentioned and not occurred_at:
        created_at = datetime(day.year, day.month, day.day, tzinfo=_BEIJING).isoformat(timespec="seconds")

    return {
        "period": period,
        "occurred_at": occurred_at,
        "created_at": created_at,
        "anchor_date": day.isoformat() if date_mentioned or period or occurred_at else "",
    }


async def _run_agent(agent, message: str, user_id: str) -> Tuple[str, list]:
    """
    Run a single agent once, returning (final_text, tool_events).

    Thin wrapper over the canonical `core.agent_runner.run_agent` (codex review
    §AgentRunner — the run loop now lives in one place, with usage accounting).
    Kept here as a `(text, tool_events)` tuple so existing callers (report_pipeline,
    task_skill, this module) need no changes. The tool_events fallback is still
    the critical bit: a skill can land a DB write yet emit malformed final JSON,
    and tool_events lets `_run_intent` reconstruct the success.
    """
    r = await run_agent(agent, message, user_id)
    return r.text, r.tool_events


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
        # create_contact returns its display fields flat (MCP tool: name=…) OR
        # nested under "contact" (HTTP API: {ok, contact:{name,…}, contact_id}).
        # Lift the nested shape up so the name survives either way.
        if isinstance(data.get("contact"), dict):
            for k in ("name", "company", "phone", "email"):
                data.setdefault(k, data["contact"].get(k))
        # Some tools flatten display fields to the top level:
        #   create_event   → title / start_at / end_at
        #   create_contact → name / company / phone / email (NOT in payload)
        # Without these, a contact synthesized from tool_events loses its name →
        # _contact_card falls back to the generic "联系人 / 已新建".
        for k in ("title", "start_at", "end_at",
                  "name", "company", "phone", "email", "contact_action"):
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
            # Active-set: only enabled=1 custom skills enter the dispatcher hint +
            # get routed (deactivated ones fall back to misc/notes).
            .where(UserSkill.user_id == user_id, UserSkill.enabled == 1)
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
        # Keyword surface = display_name + each field's Chinese description (falls
        # back to the field name). Descriptions give the dispatcher a far better
        # semantic hook than English field names alone (读书笔记 → 书名/摘录/感想).
        keywords = [display]
        for fname, fmeta in (meta.get("payload_schema") or {}).items():
            desc = (fmeta.get("description") or "").strip() if isinstance(fmeta, dict) else ""
            keywords.append(desc or fname)
        kw_str = " / ".join(k for k in dict.fromkeys(keywords) if k)  # dedupe, keep order
        lines.append(
            f"- `{machine_name}` ({display}): 关键词 = {kw_str}"
        )
    return "\n".join(lines)


def _match_custom_skill(itype: str, custom_map: dict[str, dict]) -> Optional[str]:
    """Resolve a dispatcher-emitted intent type to a real custom-skill key.
    The LLM may normalize the machine name (emit "running" for "running_178…"),
    so match exact → case-insensitive → display_name → shared prefix."""
    if not itype or not custom_map:
        return None
    if itype in custom_map:
        return itype
    low = itype.strip().lower()
    for key, meta in custom_map.items():
        kl = key.lower()
        if kl == low or kl.startswith(low) or low.startswith(kl):
            return key
        if (meta.get("display_name") or "").strip().lower() == low:
            return key
    return None


def _first_string_field(schema: dict) -> Optional[str]:
    for fname, fmeta in (schema or {}).items():
        if isinstance(fmeta, dict) and fmeta.get("type", "string") == "string":
            return fname
    return None


def _custom_anchor_field(meta: dict) -> Optional[str]:
    schema = meta.get("payload_schema") or {}
    rspec = meta.get("render_spec") or {}
    anchor = rspec.get("timeline_anchor")
    if isinstance(anchor, str) and anchor and anchor in schema:
        return anchor
    for candidate in ("date", "played_at", "occurred_at", "happened_at"):
        if candidate in schema:
            return candidate
    return None


def _custom_anchor_value(meta: dict, hints: dict[str, str]) -> tuple[Optional[str], Optional[str]]:
    field = _custom_anchor_field(meta)
    if not field:
        return None, None
    schema = meta.get("payload_schema") or {}
    fmeta = schema.get(field) if isinstance(schema.get(field), dict) else {}
    ftype = fmeta.get("type", "")
    if hints.get("occurred_at") and ftype == "datetime":
        return field, hints["occurred_at"]
    if hints.get("anchor_date"):
        return field, hints["anchor_date"]
    return None, None


async def _force_create_custom_asset(
    skill_name: str, meta: dict, source_text: str,
    session_id: str, source_input_turn_id: str, user_id: str, today_str: str,
) -> dict:
    """Deterministic fallback when the LLM sub-skill agent fails to create the
    asset: store source_text in the skill's primary (or first string) field, so
    a custom-skill capture always yields a real card instead of an error."""
    from mcp_server.tools import create_asset as mcp_create_asset
    schema = meta.get("payload_schema") or {}
    rspec = meta.get("render_spec") or {}
    field = rspec.get("primary_field") or _first_string_field(schema) or "content"
    payload = {field: source_text}
    time_hints = _asset_time_hints(source_text, today_str)
    anchor_field, anchor_value = _custom_anchor_value(meta, time_hints)
    if anchor_field and anchor_field not in payload:
        payload[anchor_field] = anchor_value
    try:
        created = await mcp_create_asset(
            user_skill_name=skill_name,
            payload=json.dumps(payload, ensure_ascii=False),
            session_id=session_id,
            source_input_turn_id=source_input_turn_id,
            user_id=user_id,
            period=time_hints["period"],
            occurred_at=time_hints["occurred_at"],
            created_at=time_hints["created_at"],
        )
    except Exception as e:
        return {"ok": False, "error": f"custom fallback failed: {e}"}
    aid = created.get("asset_id") if isinstance(created, dict) else None
    if aid:
        return {"ok": True, "asset_id": aid, "user_skill_name": skill_name, "payload": payload}
    return created if isinstance(created, dict) else {"ok": False}


async def _apply_custom_time_hints(asset_id: Optional[str], source_text: str,
                                   today_str: str, user_id: str, meta: Optional[dict] = None) -> None:
    """Backstop dynamic custom skills that created an asset but omitted time args."""
    if not asset_id:
        return
    hints = _asset_time_hints(source_text, today_str)
    if not any(hints.values()):
        return
    anchor_field, anchor_value = _custom_anchor_value(meta or {}, hints)
    try:
        aid = uuid.UUID(str(asset_id))
    except (ValueError, TypeError):
        return
    from db.models import Asset, AssetField
    from db.queries import index_asset_fields
    try:
        async with AsyncSessionLocal() as db:
            a = (await db.execute(
                select(Asset).where(Asset.id == aid, Asset.user_id == user_id)
            )).scalar_one_or_none()
            if a is None:
                return
            changed = False
            if hints["period"] and not a.period:
                a.period = hints["period"]
                changed = True
            if hints["occurred_at"] and not a.occurred_at:
                parsed = datetime.fromisoformat(hints["occurred_at"])
                a.occurred_at = parsed
                changed = True
            if hints["created_at"] and not a.occurred_at:
                parsed = datetime.fromisoformat(hints["created_at"])
                if a.created_at.date() != parsed.date():
                    a.created_at = parsed
                    changed = True
            if anchor_field and anchor_value:
                payload = dict(a.payload or {})
                current = str(payload.get(anchor_field) or "")
                if current[:10] != anchor_value[:10]:
                    payload[anchor_field] = anchor_value
                    a.payload = payload
                    await db.execute(delete(AssetField).where(AssetField.asset_id == a.id))
                    await index_asset_fields(db, a.id, user_id, a.user_skill_id, payload)
                    changed = True
            if changed:
                await db.commit()
    except Exception:  # noqa: BLE001 — time placement is best-effort; capture must survive.
        pass


async def _apply_domain(asset_id: Optional[str], domain: Optional[str], user_id: str) -> None:
    """Stamp the dispatcher's content-domain onto a freshly-created asset (§8).

    The flash sub-skill agents call create_asset without a domain, so it falls
    back to the skill prior (e.g. notes→灵感). The dispatcher judges domain from
    content; this overrides the prior with that content-domain. Best-effort.
    """
    from core.domains import normalize_domain
    from db.models import Asset
    d = normalize_domain(domain)
    if not d or not asset_id:
        return
    try:
        aid = uuid.UUID(str(asset_id))
    except (ValueError, TypeError):
        return
    try:
        async with AsyncSessionLocal() as db:
            a = (await db.execute(
                select(Asset).where(Asset.id == aid, Asset.user_id == user_id)
            )).scalar_one_or_none()
            if a is not None and a.domain != d:
                a.domain = d
                await db.commit()
    except Exception:  # noqa: BLE001 — domain is a soft label; never fail the capture
        pass


async def _dispatch(user_text: str, today_str: str, user_id: str,
                    custom_skills_hint: str = "") -> list:
    """
    Classify a user's free-text input into a list of intents.
    Returns [{"type": "todo|event|expense|idea|contact|qa|note|<custom>", "source_text": "..."}].
    """
    agent = make_dispatcher_agent(custom_skills_hint=custom_skills_hint)
    msg = f"现在是 {today_str}。\nuser_text: {user_text}"
    raw, _tool_events = await _run_agent(agent, msg, user_id)
    parsed = _parse_json(raw)
    if parsed and isinstance(parsed.get("intents"), list):
        return parsed["intents"]
    return [{"type": "note", "source_text": user_text}]


async def _load_user_tags(user_id: str, limit: int = 40) -> list[str]:
    """The user's existing 随记 topic tags (most-recent first, deduped). Injected
    into the 随记 skill so it reuses tags instead of minting synonyms (§3.2.1)."""
    from db.models import Asset
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(Asset.payload)
            .join(UserSkill, Asset.user_skill_id == UserSkill.id)
            .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
            .where(Asset.user_id == user_id, GlobalSkill.name == "notes")
            .order_by(Asset.created_at.desc()).limit(150)
        )).scalars().all()
    seen: list[str] = []
    for p in rows:
        for t in ((p or {}).get("tags") or []):
            if isinstance(t, str) and t.strip() and t not in seen:
                seen.append(t)
        if len(seen) >= limit:
            break
    return seen[:limit]


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
    matched = _match_custom_skill(itype, custom_skill_map) if custom_skill_map else None
    if matched:
        itype = matched
        meta = custom_skill_map[itype]
        agent = make_custom_skill_agent(
            skill_name=itype,
            display_name=meta["display_name"],
            payload_schema=meta["payload_schema"],
            render_spec=meta["render_spec"],
            user_id=user_id,
        )
        msg = (
            f"source_text: {source}\n"
            f"user_text: {user_text}\n"
            f"session_id: {session_id}\n"
            f"source_input_turn_id: {source_input_turn_id}\n"
            f"现在是 {today_str}(含当前时刻+星期)。「刚刚/现在/几分钟前」要用这个时刻"
            f"(含时分),不要写成 00:00。"
        )
        raw, tool_events = await _run_agent(agent, msg, user_id)
        result = _parse_json(raw)
        if not result or not result.get("ok") or not result.get("asset_id"):
            synthesized = _fallback_result_from_tool_events(tool_events)
            if synthesized:
                result = synthesized
        # Deterministic safety net: if the LLM sub-skill agent didn't actually
        # create an asset (DeepSeek tool-call miss), write one from source_text
        # into the skill's primary text field — a custom-skill capture must
        # never silently fail to an error card.
        if not result or not result.get("asset_id"):
            result = await _force_create_custom_asset(
                itype, meta, source, session_id, source_input_turn_id, user_id, today_str
            )
        await _apply_custom_time_hints(result.get("asset_id"), source, today_str, user_id, meta)
        result["skill"] = f"{itype}-skill"
        result["source_text"] = source
        return result

    # idea / misc merged into 随记 (notes, §3.2.1). Normalize legacy/hallucinated
    # types — and the unknown-type fallback — to `notes`, the free-text catch-all.
    if itype in ("idea", "misc") or itype not in SKILL_FOLDER_MAP:
        itype = "notes"

    agent = make_skill_agent(itype, user_id=user_id)
    msg = (
        f"source_text: {source}\n"
        f"user_text: {user_text}\n"
        f"session_id: {session_id}\n"
        f"source_input_turn_id: {source_input_turn_id}\n"
        f"今天是 {today_str}。"
    )
    # 随记: inject the user's existing tag vocabulary so the skill reuses tags
    # instead of minting synonyms (§3.2.1 anti-drift).
    if itype == "notes":
        tags = await _load_user_tags(user_id)
        msg += f"\nexisting_tags: {', '.join(tags) if tags else '(无)'}"
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

    # 单时点的「约/会」没拿到真实 event_id 就转 todo —— 不只匹配 "should be todo"
    # 字符串:event agent 偶发幻觉式 ok=true 却没真建 event,旧条件(需 ok=false)会漏,
    # 导致既无 todo 又渲染幽灵日程卡。改判 event_id 缺失,可靠落成 todo。
    if itype == "event" and not result.get("event_id"):
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

def _maybe_fmt_iso(s: str) -> Optional[str]:
    """If `s` clearly looks like an ISO date/datetime, format it friendly via
    _fmt_dt; else None. Gated tightly (needs a 'T' or a YYYY-MM-DD prefix) so it
    never mangles plain values like "5:00" or "120ml"."""
    if not isinstance(s, str):
        return None
    t = s.strip()
    if len(t) < 8:
        return None
    if "T" in t or (len(t) >= 10 and t[4] == "-" and t[7] == "-"):
        from datetime import datetime as _dt
        try:
            _dt.fromisoformat(t.replace("Z", "+00:00"))
        except (ValueError, AttributeError, TypeError):
            return None
        return _fmt_dt(t, as_deadline=False)
    return None


def _apply_format(value: Any, fmt: Optional[str]) -> str:
    """
    Apply a render_spec format directive to a single value.
    Format enum (seed.py): relative_date / absolute_date / currency /
                           truncate_30 / truncate_40 / truncate_60 / badge
    """
    if value is None or value == "":
        return ""
    # Array fields (e.g. 随记 tags) → join cleanly instead of "['其它']".
    if isinstance(value, (list, tuple)):
        items = [str(x).strip() for x in value if str(x).strip()]
        if not items:
            return ""
        return " · ".join(items)
    s = str(value)
    if not fmt or fmt == "text":
        # Defensive: a time/datetime field whose render_spec gave no (or a plain
        # "text") format would leak a raw ISO string ("...T05:00:00+08:00"). Custom
        # skills (esp. auto-built via /skills/promote) often store times as ISO →
        # format friendly even without an explicit directive.
        iso = _maybe_fmt_iso(s)
        return iso if iso is not None else s
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
        # 只有真正落库(有 event_id)才出 event 卡。event agent 偶发幻觉式 ok=true
        # 却没真建 event(硬检查拒单时点)→ 不渲染幽灵日程卡;_run_intent 已转 todo。
        if r.get("event_id"):
            return _event_card(r)
        return _error_card(r, render_specs)
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
    card = _build_card_from_render_spec(
        machine_name=machine_name,
        payload=r.get("payload") or {},
        asset_id=r.get("asset_id"),
        spec=spec,
    )
    # §1.8「一键升级成本子」(B):随记/misc 命中了某个可结构化的中文类型却没有
    # 对应技能 → 子技能把识别到的类型放进 `suggest_skill`。带上卡片,前端据此显
    # 「✨ 长期记成『XX』本子?」chip,点一下走 POST /api/skills/promote 即时建技能
    # + 把这条迁过去(design-agent 当场建,不让用户填技能表单)。
    suggest = r.get("suggest_skill")
    if suggest and card.get("asset_id"):
        card["suggest_skill"] = str(suggest)[:12]
    return card


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
    # Fallback skill suggestion: a misc/notes capture that looks like a fixed
    # record type → nudge the user to create a skill (the misc sub-skill sets
    # `suggest_skill` to the recognized 中文类型 when applicable).
    suggest = next(
        (r.get("suggest_skill") for r in asset_results
         if r.get("ok") and r.get("suggest_skill")),
        None,
    )
    if suggest:
        summary += f" 想长期、结构化地记录「{suggest}」的话,可以去资产库创建一个对应技能。"
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

async def _reconcile_turn_orphans(user_id: str, input_turn_id: str, results: list) -> None:
    """Bug fix: a flash sub-skill agent sometimes calls create_asset / create_contact
    more than once for the same item (DeepSeek tool-call double-fire). The extra
    rows persist in the DB but are NOT surfaced as cards — orphan duplicates the
    user sees in the library / 流 but never as a session card (e.g. 3 cards but 5
    expense assets; 1 contact card but 2 高强 rows). Prune any asset / event /
    contact / task created for THIS turn whose id isn't in the pipeline's
    surfaced-id set.

    Type-agnostic: keys ONLY on the surfaced ids (one per intent result), never on
    a skill's payload schema — so built-in AND custom skills, and ALL created
    kinds, are covered uniformly. Guard: only prune a kind when ≥1 surfaced id
    actually belongs to this turn (keep ∩ turn-ids non-empty), so a lone legit
    entity whose id wasn't surfaced is never wrongly deleted. AssetField cascades
    (FK). Best-effort: any failure leaves the dup rather than risk real data."""
    if not input_turn_id:
        return
    try:
        tid = uuid.UUID(str(input_turn_id))
    except (ValueError, TypeError):
        return
    from sqlalchemy import delete as _sa_delete
    from db.models import Asset, Event, Contact, Task
    # FK-safe order: Task.result_asset_id → assets (prune Task before its
    # placeholder Asset); assets may reference contact/event → those last.
    registry = [(Task, "task_id"), (Asset, "asset_id"),
                (Contact, "contact_id"), (Event, "event_id")]
    try:
        async with AsyncSessionLocal() as db:
            pruned = False
            for model, key in registry:
                keep = {str(r[key]) for r in results
                        if isinstance(r, dict) and r.get(key)}
                if not keep:                      # nothing of this kind surfaced
                    continue
                ids = (await db.execute(
                    select(model.id).where(
                        model.user_id == user_id,
                        model.source_input_turn_id == tid,
                    )
                )).scalars().all()
                id_strs = {str(i) for i in ids}
                if not (keep & id_strs):          # surfaced ids not from this turn → skip
                    continue
                orphans = [i for i in ids if str(i) not in keep]
                if orphans:
                    await db.execute(_sa_delete(model).where(model.id.in_(orphans)))
                    pruned = True
            if pruned:
                await db.commit()
    except Exception:
        # FK / transient — leave dups rather than risk deleting real data.
        pass


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
    # §8: apply the dispatcher's per-intent content-domain to each created asset
    # (overrides the skill prior). Skipped for events/contacts/tasks (no asset_id).
    for intent, r in zip(intents, results):
        if isinstance(r, dict) and r.get("asset_id"):
            await _apply_domain(r.get("asset_id"), intent.get("domain"), user_id)
    # Bug fix: drop orphan duplicates (sub-agent double create_asset/create_contact)
    # before the user sees the library — keep only the ids surfaced as cards.
    await _reconcile_turn_orphans(user_id, input_turn_id, results)
    return _aggregate(results, session_id, input_turn_id, render_specs)
