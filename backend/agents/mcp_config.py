"""
Third-party MCP server registry — Phase B v1.4.x.

Each entry boots an additional stdio MCP subprocess. The task-skill attaches
ALL *enabled* toolsets to its ephemeral LlmAgent so the model can pick the
right tool based on user_text (e.g. "synch to Notion" → notion.create_page,
"放到日历" → google_calendar.create_event).

## Enable toggle

`EUREKA_MCP_ENABLED` (env var, comma-separated) selects which MCPs from
the catalog below get spawned. Defaults to `fake_external` so dev/demo
always has a working stub.

Example:
    EUREKA_MCP_ENABLED=google_calendar,dingtalk

## Add a new MCP

1. Add an entry to MCP_SERVER_CATALOG below
2. Provide env vars in docker-compose.yml so credentials reach the subprocess
3. Add the name to EUREKA_MCP_ENABLED in your `.env`
4. Restart backend — task-skill auto-discovers it
"""
import os
import sys
from typing import TypedDict


class MCPConfig(TypedDict, total=False):
    # Universal
    transport:   str   # "stdio" (default) | "streamable_http" | "sse"
    description: str   # human-readable purpose, surfaced to the routing LLM

    # For transport=stdio
    command:  str
    args:     list
    env_keys: list     # env vars to forward into the subprocess (credentials etc.)

    # For transport=streamable_http / sse
    url_env:     str             # name of env var holding the full URL (with secrets)
    headers_env: dict            # header_name → env_var_name; for Bearer tokens etc.


# Full catalog of MCPs the codebase knows about. Whether each is *spawned*
# is decided by EUREKA_MCP_ENABLED at startup (see MCP_SERVERS below).
MCP_SERVER_CATALOG: dict[str, MCPConfig] = {

    # ─────────────────────────────────────────────────────────────────────────
    # Fake MCP — testing fallback. Always available; safe to leave enabled.
    # Drop this in production by removing it from EUREKA_MCP_ENABLED.
    # ─────────────────────────────────────────────────────────────────────────
    "fake_external": {
        "command":  sys.executable,
        "args":     ["-m", "mcp_server.fake_external_mcp"],
        "env_keys": [],
        "description": (
            "测试用外部系统 MCP(替代品)。能力:\n"
            "  - create_notion_page(title, content)\n"
            "  - create_calendar_event(title, start_at, duration_minutes)\n"
            "  - send_dingtalk(message, channel)"
        ),
    },

    # ─────────────────────────────────────────────────────────────────────────
    # Google Calendar — nspady/google-calendar-mcp via npx
    #   Tools: list-calendars / list-events / search-events / create-event /
    #          update-event / delete-event / get-event / get-freebusy /
    #          respond-to-event / list-colors / get-current-time
    #
    # Setup:
    #   1. Google Cloud Console → create project → enable Calendar API
    #   2. Create OAuth 2.0 client ID ("Desktop app" type)
    #   3. Download credentials.json → save as ./mcp-credentials/google-calendar-creds.json
    #   4. One-time auth (host machine, OUT of docker — needs browser):
    #        cd <project root>
    #        export GOOGLE_OAUTH_CREDENTIALS=./mcp-credentials/google-calendar-creds.json
    #        export GOOGLE_CALENDAR_MCP_TOKEN_PATH=./mcp-credentials/google-calendar-token.json
    #        npx @cocal/google-calendar-mcp
    #        # follow the browser OAuth flow; token gets cached to TOKEN_PATH
    #        Ctrl-C once you see "ready" — token is now saved
    #   5. Add `google_calendar` to EUREKA_MCP_ENABLED in your .env, restart backend
    # ─────────────────────────────────────────────────────────────────────────
    "google_calendar": {
        "command":  "npx",
        "args":     ["-y", "@cocal/google-calendar-mcp"],
        "env_keys": ["GOOGLE_OAUTH_CREDENTIALS", "GOOGLE_CALENDAR_MCP_TOKEN_PATH"],
        "description": (
            "Google Calendar — 在用户的日历里管理事件。能力:\n"
            "  - create-event(summary, start, end, location?, description?, attendees?)\n"
            "      → 创建一个日历事件,start/end 是 ISO8601 + 时区\n"
            "  - list-events(timeMin, timeMax, q?) → 查事件\n"
            "  - update-event / delete-event / get-event\n"
            "  - get-freebusy → 查空闲时段\n"
            "  - list-calendars → 列出用户所有日历\n"
            "用户说「同步到日历」「放到 Google Calendar」「明天三点会议加到我日历」时用此 MCP"
        ),
    },

    # ─────────────────────────────────────────────────────────────────────────
    # Dingtalk AIHub — 官方托管的 Streamable HTTP MCP(aihub.dingtalk.com 的实例)
    #
    # 这跟最早调研的 npx 自托管 dingtalk-mcp 不同 —— 这是钉钉官方在云端 host 的
    # MCP gateway,每个实例(instanceId)有一个唯一的接入 URL,URL 里带 key。
    # 你订阅 / instantiate 一个 MCP 后,在 AIHub 实例页面能拿到「接入 URL」。
    #
    # 接入 URL 形如:
    #   https://mcp-gw.dingtalk.com/server/<server_id>?key=<long_random_key>
    #
    # 因为 URL 里嵌了密钥,我们把它存到 env(不放代码里),`url_env` 指定 env 变量名。
    #
    # 用户当前订阅了两个实例:
    #   - mcpId=1050  instanceId=3331396  → 占位条目 `dingtalk_aihub_1`,需要你确认是哪个能力
    #   - mcpId=2034  instanceId=3331426  → 占位条目 `dingtalk_aihub_2`,需要你确认是哪个能力
    #
    # 设置步骤:
    #   1. 打开 AIHub 实例详情页(就是你给我的两个 URL),找到「接入信息」/「接入方式」/
    #      「如何调用」之类的 tab,复制完整接入 URL(含 ?key=…)
    #   2. 把 URL 填到项目根目录 .env:
    #        DINGTALK_AIHUB_URL_1=https://mcp-gw.dingtalk.com/server/xxxxx?key=xxxxx
    #        DINGTALK_AIHUB_URL_2=https://mcp-gw.dingtalk.com/server/yyyyy?key=yyyyy
    #   3. 更新下面的 description 字段,告诉路由 LLM 这两个 MCP 各自的能力
    #      (例如:1050 是「钉钉日历」,2034 是「钉钉机器人消息」)
    #   4. `EUREKA_MCP_ENABLED=fake_external,dingtalk_aihub_1,dingtalk_aihub_2`
    #   5. restart backend
    # ─────────────────────────────────────────────────────────────────────────
    "dingtalk_calendar": {
        # AIHub mcpId=1050 — 钉钉日历(官方,streamable-http,身份随 URL 中的 key 自动绑定)
        "transport":   "streamable_http",
        "url_env":     "DINGTALK_AIHUB_URL_CALENDAR",
        "description": (
            "钉钉日历 — 当前用户的钉钉日程。\n"
            "\n"
            "## 创建日程工具的精确参数名(关键!不要弄错):\n"
            "  - `summary`        (string,必填) 日程标题。**不是 title,不是 subject**\n"
            "  - `startDateTime`  (string,必填) 起始时间,ISO8601+TZ,例 '2026-05-27T15:00:00+08:00'。**不是 start_at,不是 start**\n"
            "  - `endDateTime`    (string,必填) 结束时间,ISO8601+TZ。**不是 end_at,不是 duration**。\n"
            "                     用户给「下午3-4点」时算出 endDateTime = startDateTime + 1h\n"
            "  - `description`    (string,可选) 详情备注\n"
            "  - `location`       (string,可选) 地点\n"
            "  - `attendees`      (array,可选) 参会人列表\n"
            "\n"
            "## 调用例\n"
            "  用户说「明天下午3-4点项目周会」(假设明天=2026-05-27):\n"
            "  → create_calendar_event(\n"
            "       summary='项目周会',\n"
            "       startDateTime='2026-05-27T15:00:00+08:00',\n"
            "       endDateTime='2026-05-27T16:00:00+08:00'\n"
            "    )\n"
            "\n"
            "## 用户什么时候选这个 MCP\n"
            "用户说「同步到钉钉日历」「钉钉日历建一个会议」「跟 X 约时间开会」时。\n"
            "注意:这是【钉钉日历】,跟 Google Calendar 不一样,用户没明确说「Google」就默认钉钉。"
        ),
    },
    "dingtalk_todo": {
        # AIHub mcpId=2034 — 钉钉待办(官方,streamable-http)
        "transport":   "streamable_http",
        "url_env":     "DINGTALK_AIHUB_URL_TODO",
        "description": (
            "钉钉待办 — 当前用户在钉钉里的待办任务。\n"
            "\n"
            "## 创建待办工具的精确参数(关键!):\n"
            "工具名:create_personal_todo\n"
            "参数结构:外层包一个 `PersonalTodoCreateVO` 对象,内含:\n"
            "  - `subject`     (string,必填) 待办标题。**不是 title,不是 name**\n"
            "  - `dueTime`     (number,必填) 截止时间,**Unix 毫秒时间戳(epoch ms)**,基于「今天上下文」给的当前日期计算。\n"
            "                  **不是** ISO 字符串,**不是** 秒级时间戳\n"
            "  - `executorIds` (array,可选) 执行人 staff_id 列表,默认 `[]`(自己)\n"
            "\n"
            "## dueTime 计算的常见错误(避开!)\n"
            "用户给的相对时间(「今天下午6点」「明天9点」)必须先换算成基于「今天」的绝对日期,\n"
            "再算 epoch ms。**永远不要用模型记得的年份**(常见错误:写成 2024 而不是当前年)。\n"
            "公式:dueTime = int(datetime(<year>, <month>, <day>, <hour>, <min>, tzinfo=+08:00).timestamp() * 1000)\n"
            "\n"
            "## 调用例\n"
            "假设今天=2026-05-26,用户说「提交周报,今天下午6点截止」:\n"
            "  目标时间 = 2026-05-26T18:00:00+08:00\n"
            "  → epoch_ms = 1779789600000\n"
            "  → create_personal_todo(PersonalTodoCreateVO={\n"
            "       subject='提交项目周报',\n"
            "       dueTime=1779789600000,\n"
            "       executorIds=[]\n"
            "    })\n"
            "\n"
            "## 用户什么时候选这个 MCP\n"
            "用户**明确**说「钉钉里建个待办」「同步到钉钉待办」「钉一个 todo」时。\n"
            "**默认不走**钉钉 todo;Eureka 自己有本地 todo skill 兜底常规情况。"
        ),
    },
    "dingtalk_notes": {
        # AIHub — 钉钉文档(官方,streamable-http)
        # 内部名沿用 dingtalk_notes 以保持命名一致性;对应 AIHub 上的「钉钉文档」服务。
        "transport":   "streamable_http",
        "url_env":     "DINGTALK_AIHUB_URL_NOTES",
        "description": (
            "钉钉文档 — 当前用户在钉钉里的文档(知识库 / 笔记)。\n"
            "\n"
            "## 工具签名(真实!严格按这个传参)\n"
            "create_document(name, markdown):\n"
            "  - name(必填):文档标题,字符串。**注意是 `name` 不是 `title`!**\n"
            "  - markdown(必填):正文内容,markdown 格式字符串。**注意是 `markdown` 不是 `content` / `body`!**\n"
            "  - 返回:{success, name, docUrl, nodeId, folderId, createTime, message}\n"
            "    docUrl 是给用户跳转打开文档的链接(`https://alidocs.dingtalk.com/i/nodes/<nodeId>`)\n"
            "\n"
            "## 改 / 查现有文档(本 MCP 也支持!不止 create)\n"
            "  - **更新**已有文档:`update_document(nodeId, ...)`(或 `update_document_block` /\n"
            "    `insert_document_block`)—— 给了文档 nodeId 就用它改,**不要**重新 create。\n"
            "  - **查找**文档:`search_documents`(按名搜)、`list_nodes`、`get_document_info`、\n"
            "    `get_document_content`、`list_document_blocks`。\n"
            "  - 还有 rename_document / move_document / copy_document / delete_document 等。\n"
            "\n"
            "## 调用例\n"
            "用户:「在钉钉文档里建一篇『产品周报』,内容是这周完成 X / Y / Z」\n"
            "  → create_document(name='产品周报', markdown='本周完成:\\n- X\\n- Y\\n- Z')\n"
            "用户:「把内容更新到刚刚那篇文档」(已给 nodeId)\n"
            "  → update_document(nodeId='<那篇的 nodeId>', markdown='<新正文>')\n"
            "\n"
            "## 用户什么时候选这个 MCP\n"
            "用户**明确**说「记到钉钉文档」「同步到钉钉文档」「在钉钉里建一篇文档/笔记」时。\n"
            "**默认不走**钉钉 notes;Eureka 自己有本地 notes skill 兜底常规情况。"
        ),
    },
}


def _enabled_names() -> list[str]:
    """Parse EUREKA_MCP_ENABLED into a list, with sensible default."""
    raw = os.environ.get("EUREKA_MCP_ENABLED", "fake_external").strip()
    if not raw:
        return []
    return [n.strip() for n in raw.split(",") if n.strip()]


def _build_enabled() -> dict[str, MCPConfig]:
    """Return only the MCPs flagged in EUREKA_MCP_ENABLED."""
    enabled = _enabled_names()
    out: dict[str, MCPConfig] = {}
    for name in enabled:
        cfg = MCP_SERVER_CATALOG.get(name)
        if cfg is None:
            # Don't crash on typo — log to stderr and skip. Configured MCPs
            # missing from catalog are usually a misnamed env var.
            print(f"[mcp_config] WARN: unknown MCP in EUREKA_MCP_ENABLED: {name!r}",
                  file=sys.stderr)
            continue
        out[name] = cfg
    return out


# Snapshot of currently-enabled MCPs. Computed at import time; restart backend
# to pick up env changes.
MCP_SERVERS: dict[str, MCPConfig] = _build_enabled()
