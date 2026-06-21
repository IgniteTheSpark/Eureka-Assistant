"""
FastMCP server — Phase B Step 2.

Exposes 10 tools to ADK agents via the stdio MCP protocol:
- 4 asset tools (create / query / update / delete)
- 4 contact tools (create / query / update / delete)
- 2 input_turn tools (query / get)
  → agents READ input_turns only; rows are created by the API layer
    (POST /api/chat, POST /api/flash) before invoking the agent, so the
    input_turn_id is known up front and passed via source_input_turn_id.

Run standalone:
    python -m mcp_server.server

Used by ADK agents as a subprocess MCP server (decision #2):
    MCPToolset(StdioServerParameters(command="python", args=["-m", "mcp_server.server"]))
"""
import json
from fastmcp import FastMCP

from mcp_server.tools import (
    create_asset, query_asset, query_digest, update_asset, delete_asset,
    create_todo, create_note,                                             # typed built-in creates

    create_contact, query_contact, update_contact, delete_contact,
    query_input_turn, get_input_turn,
    create_event, query_event, get_event, update_event, delete_event,   # v1.4
    add_event_attendee, link_event_file,                                  # v1.4
)

mcp = FastMCP("eureka")


def _jsonify(result: dict) -> str:
    return json.dumps(result, ensure_ascii=False)


# ── Asset tools ────────────────────────────────────────────────────────────────

@mcp.tool()
async def tool_create_asset(
    user_skill_name: str,
    payload: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
    period: str = "",
    occurred_at: str = "",
) -> str:
    """
    Create a new asset under a skill the user has registered.

    user_skill_name: machine name of the skill (todo | event | idea | contact | expense | ...)
    payload: JSON string with fields matching the skill's payload_schema
    session_id: optional session UUID this asset belongs to
    source_input_turn_id: optional input_turn UUID that produced this asset
    domain: §8 life-domain by content — REQUIRED, one of
            工作/学习/健康/运动/社交/娱乐/生活/灵感. Always pick the closest by content;
            default 生活 for general daily things. Never leave empty.
    occurred_at / period (§4.5.0a 落段) — set ONLY when the user states a time,
            never invent:
            · 说了钟点("下午3点买的")→ occurred_at = ISO8601+08:00 精确时刻;
            · 只说了模糊时段("早上花了8块")→ period ∈ 凌晨/上午/中午/下午/晚上;
            · 没说时间("买了瓶水")→ 两个都留空(前端按捕捉时刻落段)。

    The skill must exist in user_skills for the current user. An unregistered
    skill name returns an error — do NOT retry with a different name without
    consulting the skill registry.

    ⚠️ For the built-in 待办/随记, prefer the typed `tool_create_todo` /
    `tool_create_note` below — fewer payload mistakes. Use this generic tool for
    expense and custom skills.
    """
    return _jsonify(await create_asset(
        user_skill_name, payload, session_id, source_input_turn_id, domain, user_id, period, occurred_at))


@mcp.tool()
async def tool_create_todo(
    content: str,
    due_date: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
) -> str:
    """
    Create a 待办 (todo). Typed — no JSON payload to assemble.

    content: the task, faithful to the user's words.
    due_date: ISO8601 + +08:00 when a time is given (e.g. 2026-06-05T15:00:00+08:00);
              'YYYY-MM-DD' when only a date is given (don't invent a time);
              '' when no time reference.
    domain: §8 life-domain by content — REQUIRED (工作/学习/健康/运动/社交/娱乐/生活/灵感),
            e.g. "交报告"→工作, "买菜"→生活, "陪家人"→生活. Default 生活 when unclear; never empty.
    Storage is the unified assets table (user_skill_name='todo').
    """
    return _jsonify(await create_todo(content, due_date, session_id, source_input_turn_id, domain, user_id))


@mcp.tool()
async def tool_create_note(
    content: str,
    title: str = "",
    tags: str = "",
    session_id: str = "",
    source_input_turn_id: str = "",
    domain: str = "",
    user_id: str = "default",
) -> str:
    """
    Create a 随记 (the free-text catch-all that merged idea/notes/misc). Typed.

    content: the text, faithful to the original (may tidy structure, no new facts).
    title:   a ≤24-char one-line summary (give one even for short content).
    tags:    comma-separated open topic tags, ≤3 kept (e.g. '天气,心情');
             reuse the user's existing tags, don't mint synonyms.
    domain:  §8 life-domain — always give one. 随记 defaults to 灵感; set another
             (工作/学习/…) when the content clearly belongs elsewhere. Never empty.
    Storage is the unified assets table (user_skill_name='notes').
    """
    return _jsonify(await create_note(content, title, tags, session_id, source_input_turn_id, domain, user_id))


@mcp.tool()
async def tool_query_asset(
    user_skill_name: str = "",
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    domain: str = "",
    limit: int = 100,
    user_id: str = "default",
) -> str:
    """
    Query assets. Filter by skill name, keyword in payload (case-insensitive),
    domain (§8 life-domain: 工作/学习/健康/运动/社交/娱乐/生活/灵感), and/or
    capture-date range (from_date/to_date, ISO8601+tz, filters created_at).

    Returns newest-first list with skill_name + payload + domain + session_id + source_input_turn_id.
    Empty user_skill_name = all skills — use that (+ a date range) for a whole-day/
    period SUMMARY so you get every type, not just one. Use `domain` for a
    by-domain fact query (e.g. "我最近娱乐花了多少" → domain=娱乐).
    """
    return _jsonify(await query_asset(user_skill_name, contains, from_date, to_date, domain, limit, user_id))


@mcp.tool()
async def tool_query_digest(
    from_date: str = "",
    to_date: str = "",
    domain: str = "",
    user_id: str = "default",
) -> str:
    """
    Compact, pre-grouped snapshot of a time window (日报/周报/月报 概况).

    Use THIS (not tool_query_asset) for a whole-day / period overview: it
    returns counts + per-type payload lists + events, lean enough to summarize
    in one shot. Pass ISO8601+tz dates
    (e.g. a single day = 00:00:00 .. 23:59:59 of that date in +08:00).
    domain: optional §8 life-domain scope (events excluded when set, since they
            carry no domain in v1).

    Returns: { counts: {<type>: n}, by_type: {<type>: [payload, ...]},
               events: [{title, start_at, end_at, location, all_day}] }
    """
    return _jsonify(await query_digest(from_date, to_date, domain, user_id))


@mcp.tool()
async def tool_update_asset(asset_id: str, payload_patch: str, user_id: str = "default") -> str:
    """
    Merge payload_patch (JSON string) into existing asset; re-indexes queryable
    fields automatically.
    """
    return _jsonify(await update_asset(asset_id, payload_patch, user_id))


@mcp.tool()
async def tool_delete_asset(asset_id: str, user_id: str = "default") -> str:
    """Delete an asset by ID. Cascades to asset_fields."""
    return _jsonify(await delete_asset(asset_id, user_id))


# ── Contact tools ──────────────────────────────────────────────────────────────

@mcp.tool()
async def tool_create_contact(
    name: str,
    phone: str = "",
    company: str = "",
    title: str = "",
    email: str = "",
    notes: str = "",
    socials: dict = None,
    source_input_turn_id: str = "",
    user_id: str = "default",
) -> str:
    """Create a new contact. name is required; other fields optional.

    socials: a dict {platform: handle} for the person's social-media accounts,
    chosen from the SUPPORTED set ONLY — keys must be one of:
    x, telegram, linkedin, wechat, xiaohongshu, instagram. Store just the
    handle/account (e.g. {"wechat": "alex_88", "x": "@alex"}). Unknown
    platforms are dropped.

    source_input_turn_id: when this contact was extracted from a voice flash,
    pass the current input_turn UUID (provenance) — it links the contact to its
    capture for the timeline's ⚡ summary. Leave empty for chat/manual creation.
    """
    return _jsonify(await create_contact(
        name, phone, company, title, email, notes, socials, source_input_turn_id, user_id))


@mcp.tool()
async def tool_query_contact(name_query: str = "", user_id: str = "default") -> str:
    """Query contacts by name substring (case-insensitive). Newest-first.
    Each contact includes `notes` (annotation lines) and `socials`
    ({platform: handle})."""
    return _jsonify(await query_contact(name_query, user_id))


@mcp.tool()
async def tool_update_contact(contact_id: str, field: str, value: str, user_id: str = "default") -> str:
    """
    Update one field on a contact (field, value).

    - field="notes": APPENDS `value` as a new annotation line (where/how you met,
      etc.). NEVER replaces existing notes — call it once per new remark.
    - field is a social platform (x / telegram / linkedin / wechat / xiaohongshu /
      instagram): sets that platform's handle (value=the account); blank unsets it.
      To record "他的微信是 alex_88" call field="wechat", value="alex_88".
    - field in name/phone/company/title/email: overwrites that scalar field.
    """
    return _jsonify(await update_contact(contact_id, field, value, user_id))


@mcp.tool()
async def tool_delete_contact(contact_id: str, user_id: str = "default") -> str:
    """Delete a contact by ID."""
    return _jsonify(await delete_contact(contact_id, user_id))


# ── InputTurn tools (lazy-load for long-form content) ─────────────────────────

@mcp.tool()
async def tool_query_input_turn(
    contains: str = "",
    source: str = "",
    limit: int = 50,
    user_id: str = "default",
) -> str:
    """
    Full-text search input_turns by keyword and/or source (modality).

    source: voice | typed | imported (empty = all)
    Returns text snippets truncated to 200 chars. Use tool_get_input_turn
    with the returned input_turn_id to fetch full text when needed.
    """
    return _jsonify(await query_input_turn(contains, source, limit, user_id))


@mcp.tool()
async def tool_get_input_turn(input_turn_id: str, user_id: str = "default") -> str:
    """
    Fetch the full text + segments of a single input_turn.

    Use this for long-form content (e.g. meeting transcripts) that is not
    auto-included in chat history per decision #3 — agent calls this on
    demand when the user references specific content.
    """
    return _jsonify(await get_input_turn(input_turn_id, user_id))


# ── Event tools (v1.4: Event is a first-class entity) ────────────────────────

@mcp.tool()
async def tool_create_event(
    title: str,
    start_at: str,
    end_at: str = "",
    location: str = "",
    description: str = "",
    all_day: int = 0,
    recurrence_rule: str = "",
    source_input_turn_id: str = "",
    user_id: str = "default",
) -> str:
    """
    Create a calendar event (scheduled time block — distinct from todo's deadline).

    title: short event name (e.g. "跟客户开会")
    start_at: ISO8601 with timezone (required), e.g. "2026-05-26T14:00:00+08:00"
    end_at:   ISO8601 (optional)
    location: free-form (e.g. "会议室B", "Zoom")
    all_day:  0 or 1
    source_input_turn_id: when this event was extracted from a voice flash, pass the turn id
    """
    return _jsonify(await create_event(
        title, start_at, end_at, location, description, all_day,
        recurrence_rule, source_input_turn_id, user_id,
    ))


@mcp.tool()
async def tool_query_event(
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    status: str = "",
    limit: int = 50,
    user_id: str = "default",
) -> str:
    """
    Query events. Filter by date range (from_date/to_date, ISO8601), status
    (scheduled | cancelled | done), and/or keyword in title/location/description.

    Returns events newest-start_at first, with attendees and file refs inlined
    for each (no need to call get_event for basic listing).
    """
    return _jsonify(await query_event(contains, from_date, to_date, status, limit, user_id))


@mcp.tool()
async def tool_get_event(event_id: str, user_id: str = "default") -> str:
    """Fetch a single event by id, with attendees and files inlined."""
    return _jsonify(await get_event(event_id, user_id))


@mcp.tool()
async def tool_update_event(event_id: str, patch: str, user_id: str = "default") -> str:
    """
    Update event fields. `patch` is a JSON string of field→value.
    Allowed fields: title | start_at | end_at | location | description |
                    status | all_day | recurrence_rule
    Example: {"start_at": "2026-05-26T16:00:00+08:00", "location": "Zoom"}
    """
    return _jsonify(await update_event(event_id, patch, user_id))


@mcp.tool()
async def tool_delete_event(event_id: str, user_id: str = "default") -> str:
    """Delete an event. Cascades to event_attendees and event_files."""
    return _jsonify(await delete_event(event_id, user_id))


@mcp.tool()
async def tool_add_event_attendee(
    event_id: str,
    name: str = "",
    contact_id: str = "",
    role: str = "attendee",
    user_id: str = "default",
) -> str:
    """
    Add an attendee to an event. Either contact_id (link existing contact)
    or name (unresolved string for later matching) must be set.
    role: organizer | attendee | optional
    """
    return _jsonify(await add_event_attendee(event_id, name, contact_id, role, user_id))


@mcp.tool()
async def tool_link_event_file(
    event_id: str,
    file_id: str,
    kind: str = "attachment",
    user_id: str = "default",
) -> str:
    """
    Attach a file to an event. kind: prep | recording | notes | attachment
    Use case: pre-meeting docs, post-meeting recording, summary notes.
    """
    return _jsonify(await link_event_file(event_id, file_id, kind, user_id))


# ── v1.4.x: task-skill bridge ─────────────────────────────────────────────────

@mcp.tool()
async def tool_create_task(
    user_text: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    content: str = "",
    target_external_id: str = "",
    target_external_system: str = "",
    user_id: str = "default",
) -> str:
    """
    Kick off an async task that calls a third-party MCP (Notion / Google
    Calendar / Dingtalk / etc.).

    Use when the user wants to perform an action in an EXTERNAL system —
    e.g. "把这次会议同步到我的 Google Calendar", "存到 Notion", "发到钉钉".
    NOT for native Eureka assets (use tool_create_asset / tool_create_event
    for those).

    Returns immediately with task_id + placeholder asset_id. The actual MCP
    invocation runs in the background; poll GET /api/tasks/{task_id} to see
    when status transitions to done/failed.

    Args:
        user_text:            User's original request describing the action.
        session_id:           Current session UUID (from this turn's context).
        source_input_turn_id: Current input_turn UUID (provenance).
        content:              The actual BODY to write, when the action saves
                              content the request only references (e.g. "把上面那段
                              分析同步到钉钉文档" — pass the full analysis text here).
                              The task agent itself can't see prior chat turns, so
                              YOU must put the real text here or the doc/note ends
                              up empty. Leave "" for pure actions (calendar/todo).
        target_external_id:   When UPDATING an EXISTING external object (e.g. "把内容
                              更新到刚刚那个钉钉文档"), pass that object's external_id
                              (the prior external_ref asset's external_id, found via
                              query_asset user_skill_name="external_ref"). The task
                              then UPDATES it instead of creating a new one. Leave ""
                              to create new.
        target_external_system: The external_system of the object being updated
                              (e.g. "dingtalk_notes") — pair with target_external_id.
    """
    from agents.task_skill import run_task_intent
    return _jsonify(await run_task_intent(
        user_text=user_text,
        session_id=session_id,
        source_input_turn_id=source_input_turn_id,
        content=content,
        target_external_id=target_external_id,
        target_external_system=target_external_system,
        user_id=user_id,
    ))


if __name__ == "__main__":
    mcp.run(transport="stdio")
