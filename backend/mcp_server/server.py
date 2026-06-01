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
    create_contact, query_contact, update_contact, delete_contact,
    query_input_turn, get_input_turn,
    create_event, query_event, get_event, update_event, delete_event,   # v1.4
    add_event_attendee, link_event_file,                                  # v1.4
    render_report,                                                        # html-summary
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
) -> str:
    """
    Create a new asset under a skill the user has registered.

    user_skill_name: machine name of the skill (todo | event | idea | contact | expense | ...)
    payload: JSON string with fields matching the skill's payload_schema
    session_id: optional session UUID this asset belongs to
    source_input_turn_id: optional input_turn UUID that produced this asset

    The skill must exist in user_skills for the current user. An unregistered
    skill name returns an error — do NOT retry with a different name without
    consulting the skill registry.
    """
    return _jsonify(await create_asset(user_skill_name, payload, session_id, source_input_turn_id))


@mcp.tool()
async def tool_query_asset(
    user_skill_name: str = "",
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    limit: int = 100,
) -> str:
    """
    Query assets. Filter by skill name, keyword in payload (case-insensitive),
    and/or capture-date range (from_date/to_date, ISO8601+tz, filters created_at).

    Returns newest-first list with skill_name + payload + session_id + source_input_turn_id.
    Empty user_skill_name = all skills — use that (+ a date range) for a whole-day/
    period SUMMARY so you get every type, not just one.
    """
    return _jsonify(await query_asset(user_skill_name, contains, from_date, to_date, limit))


@mcp.tool()
async def tool_query_digest(
    from_date: str = "",
    to_date: str = "",
) -> str:
    """
    Compact, pre-grouped snapshot of a time window for a SUMMARY/日报/周报/月报.

    Use THIS (not tool_query_asset) when building a whole-day / period report:
    it returns counts + per-type payload lists + events, lean enough that you
    can reliably go straight on to tool_render_report. Pass ISO8601+tz dates
    (e.g. a single day = 00:00:00 .. 23:59:59 of that date in +08:00).

    Returns: { counts: {<type>: n}, by_type: {<type>: [payload, ...]},
               events: [{title, start_at, end_at, location, all_day}] }
    """
    return _jsonify(await query_digest(from_date, to_date))


@mcp.tool()
async def tool_update_asset(asset_id: str, payload_patch: str) -> str:
    """
    Merge payload_patch (JSON string) into existing asset; re-indexes queryable
    fields automatically.
    """
    return _jsonify(await update_asset(asset_id, payload_patch))


@mcp.tool()
async def tool_delete_asset(asset_id: str) -> str:
    """Delete an asset by ID. Cascades to asset_fields."""
    return _jsonify(await delete_asset(asset_id))


@mcp.tool()
async def tool_render_report(title: str, html: str) -> str:
    """
    Render a rich, well-designed HTML report for the user (图文并茂的总结).

    Use when the user asks to 总结 / 汇总 / 复盘 / 生成报告 over their data.
    The report opens FULL-SCREEN — treat it like a designed dashboard, not a
    dump of rows.

    ── WORKFLOW ──────────────────────────────────────────────────────────
    1. query_asset / query_event / query_input_turn → pull the real rows.
    2. ANALYZE, don't list. Compute aggregates and find the story.
    3. Compose ONE self-contained HTML doc and pass as `html`.

    ── 内容:行为汇总(必做,这是报告的灵魂)────────────────────────────
    报告**不是把记录抄一遍**,而是**算出洞察**:
      · 汇总数字:总计 / 平均 / 最高·最低 / 次数 / 完成率
      · 趋势:这段 vs 上一段、按天/周分布、是涨是跌
      · 模式 & 亮点:连续打卡天数、最长的一次、异常值、习惯规律
      · 一句话结论放最前面(headline),先给判断再给数据支撑
    没有数据的部分**如实说**「这段时间没有 X 记录」,绝不编造。

    ── 结构(从上到下)──────────────────────────────────────────────
      ① 标题 + 一句话总结(headline insight)
      ② 关键数字:3-4 个大号 stat 卡片并排(总计/平均/最高/次数)
      ③ 趋势图:一张手画 inline <svg> 图(柱状或折线)
      ④ 明细:干净的列表或表格(最多 ~8 行,多了截断 + "等 N 条")
      ⑤ 亮点/建议:1-3 条 bullet(连续天数、提醒、规律)

    ── 设计系统(深色,跟 app 一致;别再用 Arial 白底)──────────────
    在 <style> 里内联这套 token,然后用它们:
      :root{
        --bg:#0b0e16; --bg2:#11151f;
        --card:rgba(255,255,255,.045); --line:rgba(255,255,255,.09);
        --hi:#e9eef7; --mid:#9aa6b8; --lo:#5d6675;
        --brand:#b79dff; --blue:#6f9eff; --green:#5fd6a0;
        --amber:#f5c879; --red:#ff8a8a;
      }
      body{margin:0;padding:20px 18px 40px;background:var(--bg);
        color:var(--hi);font:14px/1.6 -apple-system,"Noto Sans SC",system-ui,sans-serif;}
      h1{font-size:24px;font-weight:700;letter-spacing:-.01em;margin:0 0 4px;}
      .headline{color:var(--mid);font-size:14px;margin:0 0 20px;}
      .stats{display:flex;gap:10px;margin:0 0 22px;}
      .stat{flex:1;background:var(--card);border:1px solid var(--line);
        border-radius:14px;padding:12px 10px;text-align:center;}
      .stat .n{font-size:26px;font-weight:700;color:var(--brand);
        font-variant-numeric:tabular-nums;line-height:1.1;}
      .stat .k{font-size:11px;color:var(--lo);margin-top:4px;letter-spacing:.08em;}
      .card{background:var(--card);border:1px solid var(--line);
        border-radius:14px;padding:16px;margin:0 0 16px;}
      .sec{font-size:11px;letter-spacing:.18em;color:var(--lo);
        text-transform:uppercase;margin:0 0 12px;font-weight:600;}
      table{width:100%;border-collapse:collapse;font-size:13px;}
      td{padding:8px 0;border-top:1px solid var(--line);color:var(--hi);}
      td.r{text-align:right;color:var(--mid);font-variant-numeric:tabular-nums;}
      ul{margin:0;padding-left:18px;color:var(--mid);}
      li{margin:6px 0;}
    数字用 --brand 高亮;正向用 --green、提醒用 --amber、紧急用 --red。

    ── 图表配方(inline SVG,圆角柱状)─────────────────────────────
      <svg viewBox="0 0 320 160" width="100%" style="display:block">
        <!-- 网格线 -->
        <line x1="0" y1="130" x2="320" y2="130" stroke="rgba(255,255,255,.12)"/>
        <!-- 每根柱子(高度按比例算,用品牌渐变色)-->
        <rect x="20" y="60" width="46" height="70" rx="6" fill="#6f9eff"/>
        <text x="43" y="148" fill="#9aa6b8" font-size="11" text-anchor="middle">周一</text>
        <text x="43" y="52" fill="#e9eef7" font-size="12" text-anchor="middle">12</text>
        <!-- …重复 …  -->
      </svg>
    折线同理:<polyline points="..." fill="none" stroke="#b79dff" stroke-width="2"/>
    + 圆点。**自己按数据算坐标**,别留占位。

    ── 硬规则 ───────────────────────────────────────────────────────
      · 渲染在 ~393px 宽的 sandbox iframe:单列、max-width 100%、长表格套
        可横向滚动容器。
      · 所有 CSS 内联;不引外部样式/字体/JS;**没有 <script>**(沙箱拦截)。
      · 紧凑——一份 1-2 屏、信息密度高的报告,胜过又长又空的。

    title: 给聊天里那张回执卡片用的短标题,如 "跑步月报"。
    html: 完整 HTML 文档字符串(遵循以上设计系统)。
    """
    return _jsonify(await render_report(title, html))


# ── Contact tools ──────────────────────────────────────────────────────────────

@mcp.tool()
async def tool_create_contact(
    name: str,
    phone: str = "",
    company: str = "",
    title: str = "",
    email: str = "",
    notes: str = "",
) -> str:
    """Create a new contact. name is required; other fields optional."""
    return _jsonify(await create_contact(name, phone, company, title, email, notes))


@mcp.tool()
async def tool_query_contact(name_query: str = "") -> str:
    """Query contacts by name substring (case-insensitive). Newest-first."""
    return _jsonify(await query_contact(name_query))


@mcp.tool()
async def tool_update_contact(contact_id: str, field: str, value: str) -> str:
    """
    Update a single field on a contact.
    Notes field appends to the array; all other fields overwrite.
    """
    return _jsonify(await update_contact(contact_id, field, value))


@mcp.tool()
async def tool_delete_contact(contact_id: str) -> str:
    """Delete a contact by ID."""
    return _jsonify(await delete_contact(contact_id))


# ── InputTurn tools (lazy-load for long-form content) ─────────────────────────

@mcp.tool()
async def tool_query_input_turn(
    contains: str = "",
    source: str = "",
    limit: int = 50,
) -> str:
    """
    Full-text search input_turns by keyword and/or source (modality).

    source: voice | typed | imported (empty = all)
    Returns text snippets truncated to 200 chars. Use tool_get_input_turn
    with the returned input_turn_id to fetch full text when needed.
    """
    return _jsonify(await query_input_turn(contains, source, limit))


@mcp.tool()
async def tool_get_input_turn(input_turn_id: str) -> str:
    """
    Fetch the full text + segments of a single input_turn.

    Use this for long-form content (e.g. meeting transcripts) that is not
    auto-included in chat history per decision #3 — agent calls this on
    demand when the user references specific content.
    """
    return _jsonify(await get_input_turn(input_turn_id))


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
        recurrence_rule, source_input_turn_id,
    ))


@mcp.tool()
async def tool_query_event(
    contains: str = "",
    from_date: str = "",
    to_date: str = "",
    status: str = "",
    limit: int = 50,
) -> str:
    """
    Query events. Filter by date range (from_date/to_date, ISO8601), status
    (scheduled | cancelled | done), and/or keyword in title/location/description.

    Returns events newest-start_at first, with attendees and file refs inlined
    for each (no need to call get_event for basic listing).
    """
    return _jsonify(await query_event(contains, from_date, to_date, status, limit))


@mcp.tool()
async def tool_get_event(event_id: str) -> str:
    """Fetch a single event by id, with attendees and files inlined."""
    return _jsonify(await get_event(event_id))


@mcp.tool()
async def tool_update_event(event_id: str, patch: str) -> str:
    """
    Update event fields. `patch` is a JSON string of field→value.
    Allowed fields: title | start_at | end_at | location | description |
                    status | all_day | recurrence_rule
    Example: {"start_at": "2026-05-26T16:00:00+08:00", "location": "Zoom"}
    """
    return _jsonify(await update_event(event_id, patch))


@mcp.tool()
async def tool_delete_event(event_id: str) -> str:
    """Delete an event. Cascades to event_attendees and event_files."""
    return _jsonify(await delete_event(event_id))


@mcp.tool()
async def tool_add_event_attendee(
    event_id: str,
    name: str = "",
    contact_id: str = "",
    role: str = "attendee",
) -> str:
    """
    Add an attendee to an event. Either contact_id (link existing contact)
    or name (unresolved string for later matching) must be set.
    role: organizer | attendee | optional
    """
    return _jsonify(await add_event_attendee(event_id, name, contact_id, role))


@mcp.tool()
async def tool_link_event_file(
    event_id: str,
    file_id: str,
    kind: str = "attachment",
) -> str:
    """
    Attach a file to an event. kind: prep | recording | notes | attachment
    Use case: pre-meeting docs, post-meeting recording, summary notes.
    """
    return _jsonify(await link_event_file(event_id, file_id, kind))


# ── v1.4.x: task-skill bridge ─────────────────────────────────────────────────

@mcp.tool()
async def tool_create_task(
    user_text: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    content: str = "",
    target_external_id: str = "",
    target_external_system: str = "",
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
    ))


if __name__ == "__main__":
    mcp.run(transport="stdio")
