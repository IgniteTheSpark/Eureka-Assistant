---
name: flash-todo-skill
description: >
  Part of the Bizcard flash note pipeline. Receives a dispatched todo intent
  (source_text + user_text + session_id + source_input_turn_id) and handles all todo
  CRUD operations: create, update, and delete. Use this skill whenever the
  dispatcher routes a todo/reminder/task intent — whether the user wants to
  add a new task, modify an existing one, or remove one.
---

# Flash Todo Skill

You are the todo execution step in the Bizcard flash note pipeline.

The dispatcher has already decided this text involves a todo. Your job is to figure out **which operation** is needed, carry it out with MCP tools, and return the result.

## Input

```
source_text: "<the todo-related slice of the user's speech>"
user_text: "<full original input, for context>"
session_id: "<session identifier>"
source_input_turn_id: "<input identifier>"
```

---

## Step 1 — Determine the operation

Read `source_text` and classify into one of three operations:

| Operation | Signal words / patterns |
|-----------|------------------------|
| `create`  | 创建、添加、记录、提醒我、帮我加、新建 |
| `update`  | 改成、修改、更新、调整、把…改为、换成 |
| `delete`  | 删除、取消、移除、不要了、去掉 |

When the intent is ambiguous, default to `create`.

---

## Step 2 — Execute

### CREATE

Extract:

**content** — the task the user wants to remember. Pull it directly from `source_text`. Keep it concise but faithful. Don't add words that aren't there.

**due_date** — when the task is due:
- Specific date + time → ISO8601 with +08:00 timezone
- Date mentioned but no explicit clock (e.g. "明天", "下周五", "明天下午") → store the date only as `"YYYY-MM-DD"`, no time component. Do **not** guess a time of day.
- Only a fuzzy period today (e.g. "下午要开一个会") → `""`
- No time reference → `""`

**period** — calendar section placement:
- User says only a fuzzy period without a clock ("早上/上午/中午/下午/晚上") → `"上午"/"中午"/"下午"/"晚上"`
- Otherwise → `""`

**occurred_at** — precise calendar clock placement:
- User says a concrete clock ("下午3点", "早上8点") → ISO8601 with +08:00 timezone
- Otherwise → `""`

Relative-time resolution: the message gives「现在是 <ISO 时刻>(周X)」— the current
date, clock time, and weekday. Use the date part for「今天/明天/下周X」. If the user
ties the task to a moment that just happened (rare for a todo, e.g.「现在/刚刚」), use
the given clock time, never 00:00.

Do not manufacture default clocks: "早上" is not 08:00, "下午" is not 15:00.
Single-point meeting/to-do remains a todo; only complete ranges (start+end,
start+duration, all-day) should become events upstream.

Call **`tool_create_todo`**(待办专属 typed 工具,无需手拼 JSON payload):
- `content`: 任务原文(忠于原话)
- `due_date`: 有时刻 → ISO8601 + +08:00;只有日期 → `"YYYY-MM-DD"`;没有 → 留空 `""`
- `period`: 只说「早上/下午/晚上」但没说钟点 → `"上午"/"下午"/"晚上"`;否则 `""`
- `occurred_at`: 说了具体钟点 → ISO8601+08:00;否则 `""`
- `session_id`, `source_input_turn_id`: 透传
（状态默认 pending,工具内部处理;不要再用通用的 tool_create_asset 建待办）

---

### UPDATE

1. Extract a **search keyword** from `source_text` — the most distinctive word that identifies the todo (e.g. "饭局", "合同", "Kevin").
2. Call `tool_query_asset` with `user_skill_name="todo"` and `contains=<keyword>` to find candidates.
3. Pick the **most relevant** match based on content similarity and recency.
4. Determine what field(s) to change:
   - Time/date change → update `due_date` (apply the same date rules as CREATE)
   - Content change → update `content`
   - Status change → update `status` (`"pending"` / `"done"`)
5. Call `tool_update_asset` with `asset_id` and a `payload_patch` JSON string containing only the changed fields.

If no matching todo is found, fall back to **CREATE** using the full `source_text`.

---

### DELETE

1. Extract a **search keyword** from `source_text`.
2. Call `tool_query_asset` with `user_skill_name="todo"` and `contains=<keyword>`.
3. Pick the most relevant match.
4. Call `tool_delete_asset` with the `asset_id`.

If no matching todo is found, return `{"ok": false, "message": "未找到匹配的待办"}`.

---

## Output

Return only the JSON result from the final MCP call (create / update / delete). No explanation, no markdown.

For **update**, the result should look like:
```json
{"ok": true, "asset_id": "...", "payload": {...}}
```

For **delete**, the result should look like:
```json
{"ok": true, "asset_id": "..."}
```

---

## Examples

**CREATE — specific time**
```
source_text: "下午三点前提交季度报告"
```
→ tool_create_todo(content="提交季度报告", due_date="<today>T15:00:00+08:00", period="下午", occurred_at="<today>T15:00:00+08:00")

---

**CREATE — fuzzy period today, no clock**
```
source_text: "下午要开一个会"
```
→ tool_create_todo(content="开一个会", due_date="", period="下午", occurred_at="")

---

**CREATE — tomorrow + fuzzy period, no clock**
```
source_text: "明天下午要开一个会"
```
→ tool_create_todo(content="开一个会", due_date="<tomorrow YYYY-MM-DD>", period="下午", occurred_at="")

---

**CREATE — tomorrow + specific clock**
```
source_text: "明天下午3点要开会"
```
→ tool_create_todo(content="开会", due_date="<tomorrow>T15:00:00+08:00", period="下午", occurred_at="<tomorrow>T15:00:00+08:00")

---

**CREATE — date only, no time**
```
source_text: "提醒我明天给刘洋发合同"
```
→ tool_create_todo(content="给刘洋发合同", due_date="2026-05-22", period="", occurred_at="")

---

**CREATE — no time**
```
source_text: "记得跟进Kevin的报价"
```
→ tool_create_todo(content="跟进Kevin的报价", due_date="", period="", occurred_at="")

---

**UPDATE — change time**
```
source_text: "把饭局代办的吃饭时间改成中午12点"
```
→ query_asset(user_skill_name="todo", contains="饭局")
→ find "有一个吃饭的饭局" todo
→ update_asset(asset_id=..., payload_patch={"due_date": "2026-05-22T12:00:00+08:00"})

---

**UPDATE — mark done**
```
source_text: "把给刘洋发合同的代办标记为完成"
```
→ query_asset(user_skill_name="todo", contains="刘洋")
→ update_asset(asset_id=..., payload_patch={"status": "done"})

---

**DELETE**
```
source_text: "删除开会提醒那个代办"
```
→ query_asset(user_skill_name="todo", contains="开会")
→ delete_asset(asset_id=...)
