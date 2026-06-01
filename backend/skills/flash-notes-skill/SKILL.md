---
name: flash-notes-skill
description: >
  Part of the Eureka flash pipeline. Handles long-form recorded content
  (notes asset type — Phase B v1.4). Distinct from idea (creative spark,
  short) — notes is for meeting summaries, briefings, reference docs,
  reports. Receives (source_text + user_text + session_id +
  source_input_turn_id) and calls tool_create_asset with user_skill_name="notes".
---

# Flash Notes Skill

You are the notes execution step.

The dispatcher routes long-form content here when the user wants to record
a substantive document, summary, or reference (not a fleeting idea).

## Input

```
source_text:          "<the notes-related slice of the user's speech>"
user_text:            "<full original input>"
session_id:           "<session id>"
source_input_turn_id: "<input_turn id — pass through>"
```

## Step 1 — Operation

Default `create`. Notes are rarely modified/deleted via Flash; updates
typically come via Assistant chat. For Flash, treat as create-only.

## Step 2 — Extract

| Field | Required | Description |
|-------|----------|-------------|
| `title`   | no  | 短标题(可选,Agent 可从内容自动总结一句话作为标题) |
| `content` | yes | 主体内容,markdown 友好,可多段 |
| `tags`    | no  | 标签数组,自由词 |

**忠于原文**:不要替用户「润色」或「加观点」。整理结构(分段、列表)可以;
增加事实性内容不可以。

## Step 3 — Call MCP

`tool_create_asset`:
- `user_skill_name`: `"notes"`
- `payload`: JSON string of `{title?, content, tags?}`
- `session_id`, `source_input_turn_id`: pass through

## Step 4 — Return

```json
{
  "ok": true,
  "operation": "create",
  "asset_id": "<from tool_create_asset>",
  "payload": {"title": "...", "content": "..."}
}
```

## Examples

**输入:** `Q3 复盘会要点:营收增长 32%,新客户主要来自社交媒体投放,下季度需重点优化客服流程`
→ `create_asset(user_skill_name="notes", payload="{\"title\": \"Q3 复盘要点\", \"content\": \"营收增长 32%,新客户主要来自社交媒体投放,下季度需重点优化客服流程。\"}")`

**输入(会议转录总结产物,典型未来用法):** `跟产品团队的需求评审会议:确定 v2 优先级 1) 协作功能 2) 数据导出 3) 主题切换。技术评估下周三给出。`
→ `create_asset(user_skill_name="notes", payload="{\"title\": \"v2 需求评审\", \"content\": \"v2 优先级:\\n1. 协作功能\\n2. 数据导出\\n3. 主题切换\\n\\n技术评估下周三给出。\", \"tags\": [\"会议纪要\", \"v2\"]}")`
