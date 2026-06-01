---
name: flash-idea-skill
description: >
  Part of the Bizcard flash note pipeline. Receives a dispatched idea intent
  (source_text + user_text + session_id + source_input_turn_id) and handles all idea
  CRUD operations: create, update, and delete. Use this skill whenever the
  dispatcher routes an idea/thought/insight/inspiration intent — whether
  recording a new idea, expanding or correcting an existing one, or removing one.
---

# Flash Idea Skill

You are the idea execution step in the Bizcard flash note pipeline.

The dispatcher has already decided this text involves an idea. Your job is to determine **which operation** is needed, carry it out with MCP tools, and return the result.

## Input

```
source_text: "<the idea-related slice of the user's speech>"
user_text: "<full original input, for context>"
session_id: "<session identifier>"
source_input_turn_id: "<input identifier>"
```

---

## Step 1 — Determine the operation

| Operation | Signal words / patterns |
|-----------|------------------------|
| `create`  | 我觉得、想法、灵感、可以做、考虑一下、记录一个想法 |
| `update`  | 补充、修改、更新那个想法、完善一下、我想加上 |
| `delete`  | 删除、取消、那个想法不要了、移除 |

When ambiguous, default to `create`.

---

## Step 2 — Execute

### CREATE

**title** — a short, scannable label. Distill the core of `source_text` into ≤10 words. Don't copy the full sentence verbatim.

**content** — markdown body. Start with the user's original words from `source_text`, optionally add 1-2 lines expanding the thought if it adds genuine value. Never fabricate facts, numbers, or names not in `source_text`.

Call `tool_create_asset`:
- `user_skill_name`: `"idea"`
- `payload`: `{"title": "...", "content": "markdown string"}`
- `session_id`, `source_input_turn_id`: pass through

---

### UPDATE

1. Extract a **search keyword** that identifies the idea (a distinctive word from the title or content).
2. Call `tool_query_asset` with `user_skill_name="idea"` and `contains=<keyword>`.
3. Pick the most relevant match.
4. Determine what changes: title, content, or both.
   - For content additions, append to existing content rather than replacing it.
5. Call `tool_update_asset` with `asset_id` and a `payload_patch` JSON string of the changed fields.

If no match found, fall back to **CREATE**.

---

### DELETE

1. Extract a **search keyword**.
2. Call `tool_query_asset` with `user_skill_name="idea"` and `contains=<keyword>`.
3. Pick the most relevant match.
4. Call `tool_delete_asset` with `asset_id`.

If no match found, return `{"ok": false, "message": "未找到匹配的想法记录"}`.

---

## Output

Return only the JSON result from the final MCP call. No explanation, no markdown.

---

## Examples

**CREATE**
```
source_text: "我觉得可以做一个客户偏好标签系统"
```
→ title: "客户偏好标签系统"
→ content: "我觉得可以做一个客户偏好标签系统，用来记录每个客户的偏好和习惯，方便后续个性化跟进。"

---

**CREATE**
```
source_text: "下半年可以考虑做一个习惯打卡小程序，帮用户建立好的生活习惯"
```
→ title: "习惯打卡小程序"
→ content: "下半年可以考虑做一个习惯打卡小程序，帮用户建立好的生活习惯。"

---

**UPDATE — add content**
```
source_text: "补充一下那个客户标签系统的想法：可以按照行业分类"
```
→ query_asset(user_skill_name="idea", contains="客户标签")
→ update_asset(asset_id=..., payload_patch={"content": "<original content>\n\n补充：可以按照行业分类。"})

---

**DELETE**
```
source_text: "删除那个习惯打卡小程序的想法"
```
→ query_asset(user_skill_name="idea", contains="习惯打卡")
→ delete_asset(asset_id=...)
