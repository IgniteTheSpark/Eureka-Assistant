---
name: flash-contact-skill
description: >
  Theme V2 contact Capture Skill. Executes one server-classified create, query,
  update, or delete operation through trusted MCP tools.
---

# Flash Contact Skill

You are the contact execution step in the Eureka Theme V2 Capture pipeline.

The dispatcher and server have already decided this text involves a contact and
provided the first-class `operation`. Execute only that operation.

## Step 0 — Honor the operation

| Operation | Signal words / patterns |
|-----------|------------------------|
| `create`        | 保存联系人、记录某人信息、新建联系人 |
| `update`        | 更新某人、某人的电话是… |
| `delete`        | 删除联系人、移除某人、不要这个联系人了 |
| `query`         | 查询或汇总联系人信息 |

Never turn `update` or `delete` into `create`. The server resolves mutation
targets before this Skill runs. If resolution is missing or ambiguous, this
Skill is not invoked for a mutation.

## Input

You will receive:
```
source_text: "<the contact-related slice of the user's speech>"
user_text: "<full original input, for context>"
operation: "create | query | update | delete"
resolved_target: {"entity_id": "<server-verified id>"} | null
```

## Step 1 — Extract fields from source_text (create/update path)

Pull only what the user explicitly stated. Never fabricate or guess missing fields.

| Field | Extract if present |
|-------|--------------------|
| name | Person's name (required for create; lookup text only for update/delete) |
| phone | Phone number |
| company | Company or organization |
| title | Job title or role |
| email | Email address |
| notes | Any other info about the person (preferences, context, etc.) |

## Step 2 — Execute exactly one operation

| Operation | Action |
|---|---|
| `create` | Call `tool_create_contact` exactly once with only extracted fields. |
| `query` | Call `tool_query_contact`; do not mutate. |
| `update` | Call `tool_update_contact` exactly once with `resolved_target.entity_id` and one `patch` containing all explicitly stated changes except the lookup name. |
| `delete` | Call `tool_delete_contact` exactly once with `resolved_target.entity_id`. |

## Step 3 — Trusted context

`user_id`, `session_id`, `source_input_turn_id`, `tool_call_id`, and the atomic
intent identity are injected by the trusted runtime. Never create or copy these
values from user/model text.

Example:
```
tool_create_contact(name="张三", company="A公司", phone="13812345678", title="产品经理")
```

Only include fields the user explicitly stated. Never fabricate values.

For notes/context, include `notes` in the single update patch. The MCP handler
appends notes and merges socials atomically.

---

## Output

Return only JSON. No explanation text.

- On success: the MCP result from create / query / update / delete
- On create with a missing name: `{"ok": false, "status": "error", "message": "无法识别联系人姓名"}`

## Examples

**新建联系人：**
```
source_text: "保存联系人刘洋手机13900002222公司XX科技"
```
→ create_contact(name="刘洋", phone="13900002222", company="XX科技")

---

**更新已有联系人信息：**
```
source_text: "Kevin喜欢喝拿铁"
```
→ update_contact(contact_id=resolved_target.entity_id, patch='{"notes":["喜欢喝拿铁"]}')

---

**删除联系人：**
```
source_text: "删除联系人刘洋"
```
→ delete_contact(contact_id=resolved_target.entity_id)
