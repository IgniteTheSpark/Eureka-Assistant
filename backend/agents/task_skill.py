"""
task-skill — async orchestrator for third-party MCP calls — Phase B v1.4.x.

Two-phase execution:
  1. **Sync head** (<100ms): create `tasks` row + placeholder `external_ref`
     asset, return immediately so the caller (Flash or Assistant) gets a
     "⏳ pending" card right away.
  2. **Async tail** (3-60s): asyncio.create_task runs an ephemeral LlmAgent
     with all configured external MCPToolsets attached. The model picks the
     right tool (e.g. create_notion_page) and calls it. On return we extract
     external_id / external_url from the tool response, update the asset
     payload to status=done.

This skill is reachable from:
  - Flash: dispatcher emits `{type: "task"}` → flash_pipeline._run_intent
    detects it and calls `run_task_intent`
  - Chat: Assistant calls `tool_create_task` (MCP tool registered in
    mcp_server/tools.py) which delegates here

Failure modes are explicit: status=failed + error_message captured + asset
payload reflects the failure so the user sees what went wrong.
"""
import asyncio
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

# Asia/Shanghai — canonical user timezone for v1.4 demo. Used to compute
# "today" for the task runner prompt so the LLM doesn't hallucinate a
# 2023/2024 year from its training cutoff.
_LOCAL_TZ = timezone(timedelta(hours=8))

from google.adk.agents import LlmAgent
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from agents.flash_pipeline import _run_agent, _extract_tool_result_payload
from agents.mcp_config import MCP_SERVERS
from agents.mcp_toolset import get_all_external_toolsets
from core.llm import TASK_MODEL
from core.notifications import create_notification
from db.database import AsyncSessionLocal
from db.models import Task, Asset, UserSkill, GlobalSkill


# ── Prompt for the async MCP runner agent ─────────────────────────────────────

def _build_task_runner_prompt() -> str:
    """
    Build the runner prompt at call time so newly-added MCPs in MCP_SERVERS
    appear in the catalog without code changes.
    """
    catalog_lines = ["可用 MCP 服务及其能力:"]
    for name, cfg in MCP_SERVERS.items():
        catalog_lines.append(f"\n[{name}]")
        catalog_lines.append(cfg.get("description", ""))

    today = datetime.now(_LOCAL_TZ).strftime("%Y-%m-%d (%A)")

    return f"""
你是 task-skill 的 MCP 路由器。用户的请求需要调用一个第三方系统(钉钉日历 /
钉钉待办 / Notion / Google Calendar 等)完成一个动作。

## 时间上下文(关键!!)

- **今天是 {today}**(时区 +08:00)
- 「今天 / 明天 / 后天 / 本周X / 下周X」一律基于这个日期换算成 ISO8601 + +08:00
- **永远以这里给的「今天」为准**,不要用模型自己记得的年份(常见错误:写成 2023 / 2024)

你拿到的工具来自下面这些 MCP 服务,**选最匹配用户意图的工具**调用,完成动作。

{chr(10).join(catalog_lines)}

## 核心规则

1. **仔细读每个工具的参数定义**(name / description / required) —— 工具的参数名是
   什么就传什么。**不要猜参数名**(常见坑:有的日历工具叫 `summary` 不是 `title`;
   有的待办工具叫 `subject` 不是 `title`)。
2. **所有 required 参数都要填**。从 `user_text` 抽,抽不出来的用合理默认值
   (比如 description 留空字符串,duration 默认 60 分钟)。
3. 如果用户说了具体时间("明天下午三点"),换算成 ISO8601 + 时区(+08:00 默认)
   再传 —— **不要**传中文时间。
4. **不要凭空编参数**(比如不要给 attendees 编名字)。用户没说就不填非必需字段。
5. **正文内容(关键!别建空文档)**:如果输入里带了
   「======== 要写入的正文内容 ========」这一段,**那段就是文档/笔记的完整正文**。
   调创建文档/笔记的工具时,**必须**把它原样填进正文参数(钉钉文档的 `markdown`、
   Notion 的 `content` 等)。标题归标题、正文归正文,**绝不**只填标题把正文丢掉。
   没带这一段时才只创建标题。
6. **更新 vs 新建(关键)**:如果输入里带了「======== 这是【更新现有对象】========」
   这一段,说明用户要改的是一个**已存在**的对象,里面给了它的 external_id。这时
   **必须**用该系统的**更新**工具(钉钉文档 → `update_document`,改不动整篇就用
   `update_document_block` / `insert_document_block`;日历 → `update_calendar_event`;
   待办 → `update_todo_task`),把那个 id 传进对应的 node/doc/event id 参数,把正文
   设置进去。**绝对不要** create 新对象。没有这一段才用 create。

## 失败重试(关键)

工具调用后:
- 如果返回 `{{"ok": true, ...}}` 或类似 success → **结束**,不再调
- 如果返回 `{{"ok": false, "error": "..."}}`:
  * **认真读 error 字段** —— 它会告诉你缺什么 / 错什么
  * 用**纠正后的参数****再调一次同一个工具**
  * 例:error 说「Event summary cannot be blank」→ 上次你没填 summary,
    这次把用户描述的事件标题填到 `summary` 参数里再调
  * 例:error 说「dueTime is required」→ 你漏了 dueTime,这次补上
- 最多重试 **1 次**;两次都失败就停,后端会显示错误给用户

## 不要做的事

- 不要链式调多个工具(先 query 再 create 这种)
- 不要在最终输出里写解释文字 —— 工具结果就是答案
- 没有合适工具就返回 `{{"ok": false, "error": "no matching MCP tool"}}`,不要乱挑

输入是用户的原话(`user_text`)。
"""


# ── Sync head: create placeholder + kick off async tail ───────────────────────

async def run_task_intent(
    user_text: str,
    session_id: str = "",
    source_input_turn_id: str = "",
    user_id: str = "default",
    content: str = "",
    target_external_id: str = "",
    target_external_system: str = "",
) -> dict:
    """
    Entry point for both Flash (`{type: "task"}` intent) and Chat (Assistant
    calling `tool_create_task`).

    `content` is the body to write when the action carries real content the
    instruction only *references* (e.g. "把上面那段分析同步到钉钉文档" — the
    analysis lives in a prior chat message the ephemeral task agent can't see).
    The caller (Assistant) passes the actual text here so the MCP doc/note gets
    a body instead of just a title.

    Returns the placeholder card immediately. Real MCP work runs in the
    background via asyncio.create_task; clients poll /api/tasks/{id} or
    re-fetch the asset to see status=done.
    """
    # ── Resolve the external_ref UserSkill (seeded once at boot) ──
    async with AsyncSessionLocal() as db:
        user_skill_id = await _resolve_external_ref_skill(db, user_id)
        if user_skill_id is None:
            return {
                "ok":     False,
                "skill":  "task-skill",
                "error":  "external_ref skill not seeded; run `python -m db.seed`",
            }

        sid = uuid.UUID(session_id)             if session_id           else None
        itid = uuid.UUID(source_input_turn_id)  if source_input_turn_id else None

        task_row = Task(
            user_id=user_id,
            user_text=user_text,
            status="pending",
            session_id=sid,
            source_input_turn_id=itid,
        )
        db.add(task_row)
        await db.flush()   # populate task_row.id

        placeholder = Asset(
            user_id=user_id,
            user_skill_id=user_skill_id,
            session_id=sid,
            source_input_turn_id=itid,
            payload={
                "external_system": "pending",
                "status":          "pending",
                "title":           _derive_title(user_text),
                "task_id":         str(task_row.id),
            },
        )
        db.add(placeholder)
        await db.flush()   # populate placeholder.id

        task_row.result_asset_id = placeholder.id
        await db.commit()
        await db.refresh(task_row)
        await db.refresh(placeholder)

        task_id  = str(task_row.id)
        asset_id = str(placeholder.id)
        title    = placeholder.payload["title"]

    # ── Kick off the async tail (fire-and-forget) ──
    asyncio.create_task(_run_task_async(
        task_id=task_id,
        asset_id=asset_id,
        user_text=user_text,
        user_id=user_id,
        content=content,
        target_external_id=target_external_id,
        target_external_system=target_external_system,
    ))

    # ── Sync return: placeholder card so Flash/Chat shows ⏳ immediately ──
    return {
        "ok":       True,
        "skill":    "task-skill",
        "task_id":  task_id,
        "asset_id": asset_id,
        "status":   "pending",
        "payload": {
            "external_system": "pending",
            "status":          "pending",
            "title":           title,
            "task_id":         task_id,
        },
    }


# ── Async tail: run agent, call MCP, update DB ────────────────────────────────

async def _run_task_async(
    task_id: str,
    asset_id: str,
    user_text: str,
    user_id: str,
    content: str = "",
    target_external_id: str = "",
    target_external_system: str = "",
) -> None:
    """
    Background worker. Spawns an ephemeral LlmAgent with all external MCPs
    attached, lets it pick + call one tool, then updates the placeholder
    asset with the real external_id/url.

    All exceptions are caught and surfaced as status=failed — never let an
    unhandled exception bubble out of asyncio.create_task or it dies silent.
    """
    try:
        # Mark running so the frontend's status badge can show "in progress"
        async with AsyncSessionLocal() as db:
            await db.execute(update(Task).where(Task.id == uuid.UUID(task_id)).values(
                status="running", started_at=datetime.now(timezone.utc),
            ))
            await db.commit()

        # Build ephemeral agent with ALL external toolsets — model picks
        toolsets = get_all_external_toolsets()
        if not toolsets:
            raise RuntimeError("no external MCPs configured in MCP_SERVERS")

        agent = LlmAgent(
            name="task_runner",
            model=TASK_MODEL,
            instruction=_build_task_runner_prompt(),
            tools=toolsets,
        )

        # Compose the runner input. When `content` is provided, hand it to the
        # agent explicitly as the body to write — otherwise a doc/note tool gets
        # only a title and the user ends up with an empty document.
        runner_input = user_text
        if target_external_id.strip():
            # UPDATE an existing external object — give the runner the id + system
            # so it picks the update tool (not create).
            runner_input += (
                f"\n\n======== 这是【更新现有对象】,不要新建 ========\n"
                f"目标系统: {target_external_system or '(见 user_text)'}\n"
                f"目标对象 external_id: {target_external_id}\n"
                f"动作: 用该系统的【更新】工具(如 update_document / update_calendar_event /"
                f" update_todo_task),把这个 id 传进它的节点/文档/事件 id 参数,"
                f"再把下面的正文设置进去。**不要 create 新对象。**"
            )
        if content.strip():
            runner_input += (
                f"\n\n======== 要写入的正文内容(原样作为文档/笔记/markdown 正文) ========\n"
                f"{content}"
            )

        # Run agent (reuses _run_agent from flash_pipeline → captures tool events)
        raw, tool_events = await _run_agent(agent, runner_input, user_id)
        ext_info = _extract_external_ref(tool_events)

        if not ext_info:
            # Surface the actual MCP error if there was one, instead of a
            # generic "no usable result" wrapper.
            inner_err = _extract_inner_error(tool_events)
            if inner_err:
                raise RuntimeError(f"MCP 返回错误: {inner_err}")
            # No tool was called at all (tool_events == 0). This almost always
            # means the request lacked the detail the MCP needs (no title / no
            # due time), so the agent asked a clarifying question instead of
            # acting. Surface THAT question — it's actionable — rather than the
            # cryptic internal "did not produce a usable tool result". It flows
            # to the asset error, the failure toast, and the drawer.
            if not tool_events and raw.strip():
                raise RuntimeError(raw.strip()[:400])
            raise RuntimeError(
                f"task agent did not produce a usable tool result "
                f"(tool_events_count={len(tool_events)}, raw={raw[:120]!r})"
            )

        # Success — fill in the placeholder
        async with AsyncSessionLocal() as db:
            await db.execute(update(Asset).where(Asset.id == uuid.UUID(asset_id)).values(
                payload={
                    **ext_info,
                    "status":  "done",
                    "task_id": task_id,
                },
            ))
            await db.execute(update(Task).where(Task.id == uuid.UUID(task_id)).values(
                status="done",
                mcp_target=ext_info.get("external_system", ""),
                completed_at=datetime.now(timezone.utc),
            ))
            await db.commit()

        # M6: notify — async tasks finish minutes after the user moved on, so
        # this is the high-value case for the notification system.
        await create_notification(
            user_id=user_id,
            type="task_done",
            title="任务已完成",
            body=(ext_info.get("title") or user_text)[:200],
            link=asset_id,
        )

    except Exception as exc:   # broad-catch is intentional for fire-and-forget worker
        async with AsyncSessionLocal() as db:
            await db.execute(update(Task).where(Task.id == uuid.UUID(task_id)).values(
                status="failed",
                error_message=str(exc)[:500],
                completed_at=datetime.now(timezone.utc),
            ))
            await db.execute(update(Asset).where(Asset.id == uuid.UUID(asset_id)).values(
                payload={
                    "external_system": "unknown",
                    "status":          "failed",
                    "error":           str(exc)[:200],
                    "task_id":         task_id,
                },
            ))
            await db.commit()

        # M6: notify on failure so the user learns the background task didn't
        # land (otherwise it fails silently).
        await create_notification(
            user_id=user_id,
            type="task_failed",
            title="任务失败",
            body=f"{user_text[:120]} — {str(exc)[:120]}",
            link=asset_id,
        )


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _resolve_external_ref_skill(db: AsyncSession, user_id: str) -> Optional[uuid.UUID]:
    """Look up the user's external_ref UserSkill id (seeded by db/seed.py)."""
    result = await db.execute(
        select(UserSkill.id)
        .join(GlobalSkill, UserSkill.skill_id == GlobalSkill.id)
        .where(UserSkill.user_id == user_id, GlobalSkill.name == "external_ref")
    )
    return result.scalar_one_or_none()


def _derive_title(user_text: str) -> str:
    """Short placeholder title for the in-flight card."""
    s = user_text.strip()
    return s[:50] + ("…" if len(s) > 50 else "")


_ID_KEYS = (
    "external_id", "id", "event_id", "todo_id",
    "scheduleId", "schedule_id", "taskId", "task_id",
    "iCalUID", "icalUID", "ical_uid",        # Dingtalk Calendar's id field
    "pageId", "page_id",                     # Notion
    "nodeId", "node_id", "docId", "doc_id",  # Dingtalk Docs(钉钉文档): create_document returns nodeId
)
_SUCCESS_KEYS = ("ok", "success")
_TITLE_KEYS   = ("title", "summary", "subject", "name")
_URL_KEYS     = (
    "external_url", "url", "htmlLink", "html_link", "deepLink", "link",
    "docUrl", "doc_url", "webUrl", "web_url",  # Dingtalk Docs: docUrl
)


def _first_present(d: dict, keys) -> Optional[str]:
    """Return the first non-empty value among given keys (case-sensitive)."""
    if not isinstance(d, dict):
        return None
    for k in keys:
        v = d.get(k)
        if v:
            return v
    return None


def _is_success(d: dict) -> bool:
    """ok=true or success=true — accept both."""
    return any(d.get(k) is True for k in _SUCCESS_KEYS)


def _extract_external_ref(tool_events: list) -> Optional[dict]:
    """
    Walk captured tool_events, find first successful tool result, extract a
    reference (id + optional url + title) shaped to fit external_ref payload.

    Real MCPs return wildly different shapes:
      - Our fake one:           {ok: true, external_id, external_url, ...}
      - Dingtalk Calendar:      {success: true, result: {iCalUID, summary, end: {dateTime}, ...}}
      - Dingtalk Todo:          (TBD — likely {success: true, result: {taskId, ...}})
      - Notion (when wired):    {ok: true, id: "page-uuid", url: "https://notion.so/..."}

    Strategy: union of common key names + descent into `result` / `data` /
    `body` sub-objects.
    """
    for ev in tool_events:
        outer = _extract_tool_result_payload(ev.get("response"))
        if not outer:
            continue
        if not _is_success(outer):
            continue

        # Look for ID in outer level, OR nested in 'result' / 'data' / 'body'
        candidates = [outer]
        for key in ("result", "data", "body"):
            sub = outer.get(key)
            if isinstance(sub, dict):
                candidates.append(sub)

        ext_id = None
        rich_layer: dict = outer
        for layer in candidates:
            found = _first_present(layer, _ID_KEYS)
            if found:
                ext_id = found
                rich_layer = layer
                break

        if not ext_id:
            continue

        ext_sys = (
            outer.get("external_system")
            or rich_layer.get("external_system")
            or _infer_system_from_tool(ev.get("name", ""))
        )
        return {
            "external_system": ext_sys,
            "external_id":     str(ext_id),
            "external_url":    _first_present(rich_layer, _URL_KEYS)
                                or _first_present(outer, _URL_KEYS)
                                or "",
            "external_type":   outer.get("external_type") or _infer_type(ext_sys),
            "title":           str(_first_present(rich_layer, _TITLE_KEYS)
                                   or _first_present(outer, _TITLE_KEYS)
                                   or "")[:120],
            "summary":         str(rich_layer.get("description")
                                   or outer.get("description")
                                   or "")[:200],
        }
    return None


_ERROR_KEYS = (
    "error", "errorMsg", "errorMessage", "developerMessage",
    "message", "msg", "errorCode",
)


def _extract_inner_error(tool_events: list) -> Optional[str]:
    """Surface the MCP's own error message when the last tool call failed."""
    for ev in reversed(tool_events):
        data = _extract_tool_result_payload(ev.get("response"))
        if not data:
            continue
        # Failure markers: ok=false, success=false, or presence of errorCode/errorMsg
        if (
            data.get("ok") is False
            or data.get("success") is False
            or data.get("errorCode")
        ):
            err = _first_present(data, _ERROR_KEYS)
            if err:
                return str(err)[:300]
    return None


def _infer_system_from_tool(tool_name: str) -> str:
    """Map MCP tool names back to a friendly external_system label."""
    t = tool_name.lower()
    if "calendar" in t or "schedule" in t or "event" in t:
        # Heuristic: 钉钉日历 tool names usually have schedule/event;
        # google calendar's are like create-event. Without per-MCP namespacing
        # we default to "dingtalk_calendar" — true for current setup.
        return "dingtalk_calendar"
    if "todo" in t:
        return "dingtalk_todo"
    if "document" in t or "doc" == t or t.startswith("doc_") or "note" in t:
        # Dingtalk 文档 exposes create_document / update_document / etc.
        # Notion's create_page goes to "page" branch below — keep these
        # exclusive. If we wire real Notion docs later, refine here.
        return "dingtalk_notes"
    if "page" in t and "notion" in t:
        return "notion"
    if "notion" in t:
        return "notion"
    if "task" in t:
        # Generic 'task' fallback — most likely todo-ish work. Put AFTER specific
        # checks so it doesn't shadow them.
        return "dingtalk_todo"
    if "dingtalk" in t or "ding" in t:
        return "dingtalk"
    return "unknown"


def _infer_type(system: str) -> str:
    return {
        "dingtalk_calendar": "schedule",
        "dingtalk_todo":     "todo",
        "dingtalk_notes":    "document",
        "notion":            "page",
        "google_calendar":   "event",
    }.get(system, "")
