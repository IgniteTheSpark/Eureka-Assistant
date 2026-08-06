---
name: flash-notes-skill
description: >
  Part of the Eureka flash pipeline. The unified 「随记」 skill (§3.2.1) — the
  free-text catch-all that merged the old idea / notes / misc. Handles ANY
  free-text the dispatcher didn't route to a structured type: ideas, notes,
  meeting summaries, long docs, fleeting jottings. Receives (source_text +
  user_text + session_id + source_input_turn_id) and calls the typed note tool.
  Produces title + content without generating tags.
---

# Flash 随记 Skill

你是「随记」执行步骤 —— 自由文本的统一兜底(原 idea / notes / misc 已合并成这一个)。
dispatcher 把任何**不属于 todo / event / expense / contact** 的自由文本(想法、感悟、笔记、
纪要、长文、随手记的零碎)都路由到这里。

## Input

```
source_text:          "<随记相关的那段原话>"
user_text:            "<完整原始输入>"
session_id:           "<session id>"
source_input_turn_id: "<input_turn id — 透传>"
```

## Step 1 — Operation

恒为 `create`。随记的修改/删除走 Assistant 对话,Flash 只负责快速存下。

## Step 2 — Extract（必出 title + content）

不生成标签;payload 和工具参数里都不要添加 tags。

| Field | Required | Description |
|-------|----------|-------------|
| `title`   | **yes** | **≤24 字**的一句话短摘(从内容概括;哪怕内容很短也给个标题,别留空) |
| `content` | **yes** | 主体内容,忠于原文(可整理分段/列表,**不加事实、不发散**) |

## Step 3 — Call MCP

调 **`tool_create_note`**(随记专属 typed 工具,无需手拼 JSON):
- `content`: 主体内容(忠于原文)
- `title`: ≤24 字一句话短摘
- `session_id`, `source_input_turn_id`: 透传

(不要再用通用 `tool_create_asset` 建随记。)

## Step 3.5 — 建技能建议（可选）

如果这条随记**像在记录某个固定类型**(用户没有对应 skill 才落到这里),比如
「宝宝喝了 150ml 奶」「跑了 5 公里」「血压 120/80」「读了《XX》」——在返回里多带一个
`suggest_skill` 字段,值是你从原话概括的 **2-6 字中文类型名**(如「宝宝喝奶」「跑步」「血压」
「读书笔记」)。Pipeline 会据此提示用户去建技能。**只在确实像可结构化记录的类型时带**;闲聊 /
情绪 / 杂感(「今天天气不错」「那只猫真有意思」)**不要**带 `suggest_skill`。

## Step 4 — Return

```json
{
  "ok": true,
  "operation": "create",
  "asset_id": "<from tool_create_asset>",
  "payload": {"title": "...", "content": "..."},
  "suggest_skill": "宝宝喝奶"
}
```

## Examples

**输入:** `今天天气真不错`
→ `tool_create_note(content="今天天气真不错", title="今天天气不错")`

**输入:** `我觉得可以做一个客户标签系统`
→ `tool_create_note(content="我觉得可以做一个客户标签系统。", title="客户标签系统的想法")`

**输入:** `Q3 复盘会要点:营收增长 32%,新客户主要来自社交媒体投放,下季度需重点优化客服流程`
→ `tool_create_note(content="营收增长 32%,新客户主要来自社交媒体投放,下季度需重点优化客服流程。", title="Q3 复盘要点")`

**输入(像固定记录类型,带 suggest_skill):** `读了 50 页《水浒传》,挺上头`
→ `tool_create_note(content="读了 50 页《水浒传》,挺上头。", title="读《水浒传》50页")` + 返回 `suggest_skill: "读书笔记"`
