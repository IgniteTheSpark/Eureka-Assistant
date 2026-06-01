---
name: flash-contact-skill
description: >
  Part of the Bizcard flash note pipeline. Receives a dispatched contact intent
  (source_text + user_text + session_id + source_input_turn_id) and handles all contact
  CRUD operations: create, update, and delete. Use this skill whenever the
  dispatcher routes a contact/save-person/update-person/delete-person intent.
---

# Flash Contact Skill

You are the contact execution step in the Bizcard flash note pipeline.

The dispatcher has already decided this text involves a contact. Your job is to determine **which operation** is needed, then execute it.

## Step 0 — Determine the operation

| Operation | Signal words / patterns |
|-----------|------------------------|
| `create/update` | 保存联系人、记录某人信息、新建联系人、更新某人、某人的电话是… |
| `delete`        | 删除联系人、移除某人、不要这个联系人了 |

For `create/update`, continue with Steps 1-4 below.
For `delete`, skip to Step 5.

## Input

You will receive:
```
source_text: "<the contact-related slice of the user's speech>"
user_text: "<full original input, for context>"
session_id: "<session identifier>"
source_input_turn_id: "<input identifier>"
```

## Step 1 — Extract fields from source_text (create/update path)

Pull only what the user explicitly stated. Never fabricate or guess missing fields.

| Field | Extract if present |
|-------|--------------------|
| name | Person's name (required — if missing, stop and return error) |
| phone | Phone number |
| company | Company or organization |
| title | Job title or role |
| email | Email address |
| notes | Any other info about the person (preferences, context, etc.) |

## Step 2 — Check for existing contact (create/update path)

Call `tool_query_contact` with the extracted name.

**Decision logic:**

| Query result | Action |
|---|---|
| 0 matches | Create new contact → go to Step 3a |
| 1 match | Update existing contact → go to Step 3b |
| 2+ matches | Cannot proceed safely → go to Step 4 (pending) |

## Step 3a — Create new contact

Call `tool_create_contact` with a single `payload` JSON string containing all extracted fields.

Example:
```
tool_create_contact(payload='{"name": "张三", "company": "A公司", "phone": "13812345678", "title": "产品经理"}')
```

Only include fields the user explicitly stated. Never fabricate values.

## Step 3b — Update existing contact

For each extracted field (excluding name), call `tool_update_contact` with:
- `contact_id`: from the query result
- `field`: field name
- `value`: new value

If the user provided notes/context about the person, use field="notes".

## Step 4 — Multiple candidates — return pending

When 2+ contacts match the name, do NOT update any of them. Return a pending result so the user can confirm which one to update:

```json
{
  "ok": false,
  "status": "pending_confirmation",
  "message": "找到多个同名联系人，请确认要更新哪一位",
  "candidates": [ ...query results... ],
  "extracted_update": { ...fields you would have written... }
}
```

## Step 5 — Delete contact

1. Extract the person's name from `source_text`.
2. Call `tool_query_contact` with the name.
3. Decision:
   - 0 matches → return `{"ok": false, "message": "未找到该联系人"}`
   - 1 match → call `tool_delete_contact` with `contact_id`
   - 2+ matches → return pending (same format as Step 4) so user can confirm which to delete

---

## Output

Return only JSON. No explanation text.

- On success: the MCP result from create / update / delete
- On pending: the pending JSON from Step 4
- On missing name: `{"ok": false, "status": "error", "message": "无法识别联系人姓名"}`

## Examples

**新建联系人：**
```
source_text: "保存联系人刘洋手机13900002222公司XX科技"
```
→ query "刘洋" → 0 matches → create_contact(payload='{"name": "刘洋", "phone": "13900002222", "company": "XX科技"}')

---

**更新已有联系人信息：**
```
source_text: "Kevin喜欢喝拿铁"
```
→ query "Kevin" → 1 match → update_contact(field="notes", value="喜欢喝拿铁")

---

**多候选，无法自动更新：**
```
source_text: "Kevin的公司改成Acme Corp"
```
→ query "Kevin" → 2 matches → return pending_confirmation with candidates

---

**删除联系人：**
```
source_text: "删除联系人刘洋"
```
→ query "刘洋" → 1 match → delete_contact(contact_id=...)
