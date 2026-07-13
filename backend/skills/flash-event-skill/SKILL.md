---
name: flash-event-skill
description: >
  Part of the Eureka flash note pipeline. Receives a dispatched event intent
  (source_text + user_text + session_id + source_input_turn_id) and handles
  all event CRUD operations: create, update, delete. An event is a SCHEDULED
  OCCURRENCE with a start time (and usually an end / duration), e.g. a
  meeting, appointment, dinner — distinct from a todo (which has a deadline,
  not a start time). v1.4: events live in the dedicated `events` table; this
  skill calls create_event / update_event / delete_event MCP tools (NOT
  create_asset).
---

# Flash Event Skill

You are the event execution step in the Eureka flash pipeline.

The dispatcher has decided this input involves a scheduled event. Your job
is to figure out **which operation** and carry it out via the event MCP tools,
then return a result JSON.

## Input

```
source_text:          "<the event-related slice of the user's speech>"
user_text:            "<full original input, for context>"
session_id:           "<session identifier>"
source_input_turn_id: "<input_turn identifier — pass to create_event for provenance>"
```

---

## Step 0 — 时段完整性硬检查(v1.4.x)

⚠️ **进入这里之前,dispatcher 应该已经确认 source_text 含完整时段**(start + end,或 start + duration,或 all_day)。如果你在 source_text 里看不到完整时段:

例:「明天 6 点跟冯总开会」(只有 start,无 end / duration / all_day) → 这是 dispatcher 误路由

直接返回错误让 Pipeline 知道这条应该归 todo:

```json
{"ok": false, "operation": "create", "error": "no time range — should be todo (single time point routes to todo-skill)"}
```

**不要**自己补默认 end_at / duration / all_day,**不要**自己降级建 todo。直接拒绝。

---

## Step 1 — Determine the operation

| Operation | Signal words / patterns |
|-----------|------------------------|
| `create`  | 创建、安排、约、加一个、明天/X日(+ **时段**)、X点到Y点、X 点到 Y 点开会 |
| `update`  | 改成、修改、调整、把…改到、推到、提前到 |
| `delete`  | 取消、删除、不去了、移除 |

Default `create` when ambiguous.

---

## Step 2 — Extract fields

For `create` / `update`:

| Field | Required | Description |
|-------|----------|-------------|
| `title`    | yes (create) | 事件标题(简洁,例「跟客户开会」) |
| `start_at` | yes (create) | 开始时间,ISO8601 + 时区,例 `2026-05-26T14:00:00+08:00` |
| `end_at`   | no | 结束时间,ISO8601 |
| `location` | no | 地点,例「会议室B」「Zoom」 |
| `description` | no | 备注/说明 |
| `all_day`  | no | 0/1,全天事件 |

**时间规则**:
- 基准是消息里的「现在是 <ISO 时刻>(周X)」—— 含当前日期、时刻、星期
- 「今天/明天/后天/下周X」转绝对日期(以上面的当前日期为基准)
- 「刚刚/现在/几分钟前」→ 用**当前时刻**(含时分),**不要** 00:00
- 「X 点到 Y 点」 → start_at + end_at 同日
- 「X 点开会一小时」 → start_at + end_at = start_at + 1h
- 只说「X 点」 → 只填 start_at
- 默认时区 +08:00

---

## Step 3 — Execute via MCP event tools

### Create

**Step 3a — 建 event 本体**

Call `tool_create_event`:
- `title`, `start_at` (required)
- `end_at`, `location`, `description`, `all_day` (optional)
- `source_input_turn_id`: pass through from input

记下返回的 `event_id`,Step 3b 要用。

**Step 3b — 安全解析 attendee（先去重,再查 contact）**

从 source_text 里抽出所有可能指代「参与方」的名词或称呼,**不区分是真人名、职称、泛称还是团队**。按原文称呼做**完全重复**去重,保留第一次出现的顺序;同一个完全相同的名字只处理一次。

对去重后的每个名字调用 `tool_query_contact`,读取返回 JSON 顶层的 `exact_contacts` 数组。`contacts` 仍是 contains 搜索候选,不可用于自动绑定。只按 `len(exact_contacts)` 进入以下一个分支;每个分支展示完整路径,每个去重后的名字实际只查询一次、只添加一次 attendee。

#### 0 命中 (`len(exact_contacts) == 0`)

`tool_query_contact(name_query="<原文里的称呼>")` → `{"ok": true, "contacts": [<contains candidates>], "exact_contacts": []}`
`tool_add_event_attendee(event_id=<event_id>, name="<原文里的称呼>", role="attendee")`

#### 1 命中 (`len(exact_contacts) == 1`)

`tool_query_contact(name_query="<原文里的称呼>")` → `{"ok": true, "contacts": [<contains candidates>], "exact_contacts": [{"contact_id": "<id>", "name": "<contact name>"}]}`
`tool_add_event_attendee(event_id=<event_id>, name=exact_contacts[0]["name"], contact_id=exact_contacts[0]["contact_id"], role="attendee")`

#### 2+ 命中 (`len(exact_contacts) >= 2`)

`tool_query_contact(name_query="<原文里的称呼>")` → `{"ok": true, "contacts": [<contains candidates>], "exact_contacts": [<exact candidate A>, <exact candidate B>, ...]}`
有歧义,不得使用 `exact_contacts[0]` 或第一条候选,也不猜测其他候选。
`tool_add_event_attendee(event_id=<event_id>, name="<原文里的称呼>", role="attendee")`

0 命中时**不创建 contact**;2+ 命中时也不任选候选、**不创建 contact**。只有 1 命中才传 `contact_id`;0 或 2+ 命中继续保留原文称呼作为未解析 attendee。

**精确匹配安全例:** 原文称呼为 `Alex` 时,即使 `contacts` 包含 `Alex Chen`、`Alexander`,只要 `exact_contacts` 为空就走 0 命中,绝不绑定这些 contains 候选。

**抽取规则**(宁可少抽,不要错抽更不要瞎编):
- 「和 X 的会议」「跟 X 开会」「X 和我」「找 X」「跟 X 聊」 → 抽 `X`
- 称呼带姓 + 头衔(冯总、王总监、刘老师、张工)→ 抽完整称呼
- 泛称(客户、团队、对方、那边、合作方、供应商)→ 也抽,作为占位
- 实体组织名(Acme、XX 公司)→ 也抽
- 「自己」「我」「我们组」→ **不抽**(说话人本身隐含,不需要)
- 没有任何人/参与方提及 → **不调 add_event_attendee**(0 个 attendee 是允许的)

**为什么这样设计**(给未来的你/agent 看):
- 唯一候选才自动绑定,避免同名联系人误绑
- 0 或 2+ 候选都保留原文 `name_raw`,让用户之后自己确认
- Flash event 只引用已有 contact,不负责创建联系人
- 完全重复称呼在调用工具前去重,避免同一 event 出现重复 attendee

### Update

1. Call `tool_query_event` with `contains=<keyword>` (e.g., "客户" from "客户会") and date range if known.
2. Pick best match by recency + title overlap.
3. Call `tool_update_event(event_id, patch=<JSON string>)` with only fields to change.

### Delete

1. `tool_query_event` to find target.
2. `tool_delete_event(event_id)`.

---

## Step 4 — Return JSON

For successful create:
```json
{
  "ok": true,
  "operation": "create",
  "event_id": "<from create_event>",
  "title": "...",
  "start_at": "...",
  "attendees_added": ["冯总", "客户"]    // 已添加的原文参与方称呼(可能已绑定 contact),可以是 []
}
```

For successful update:
```json
{
  "ok": true,
  "operation": "update",
  "event_id": "<from update_event>",
  "title": "...",
  "start_at": "..."
}
```

For successful delete:
```json
{"ok": true, "operation": "delete", "event_id": "<the deleted id>"}
```

For errors:
```json
{"ok": false, "operation": "create | update | delete", "error": "<short reason>"}
```

---

## Examples

**输入:** `明天下午两点到三点跟客户开会,地点在会议室B` (今天是 2026-05-25)
1. `tool_create_event(title="跟客户开会", start_at="2026-05-26T14:00:00+08:00", end_at="2026-05-26T15:00:00+08:00", location="会议室B", source_input_turn_id=<turn>)` → event_id="e-xxx"
2. `tool_query_contact(name_query="客户")` → `{"ok": true, "contacts": []}` (0 命中)
3. `tool_add_event_attendee(event_id="e-xxx", name="客户", role="attendee")`
→ 返回:`{"ok": true, "operation": "create", "event_id": "e-xxx", "title": "...", "start_at": "...", "attendees_added": ["客户"]}`

**输入:** `明天下午六点有个和冯总的会议`
1. `tool_create_event(title="和冯总的会议", start_at="2026-05-26T18:00:00+08:00", source_input_turn_id=<turn>)` → event_id="e-yyy"
2. `tool_query_contact(name_query="冯总")` → `{"ok": true, "contacts": [{"contact_id": "c-feng", "name": "冯总", "phone": null, "company": null, "title": null, "email": null, "notes": [], "socials": {}}]}` (1 命中)
3. `tool_add_event_attendee(event_id="e-yyy", name="冯总", contact_id="c-feng", role="attendee")`
→ `{"ok": true, ..., "attendees_added": ["冯总"]}`

**输入:** `周五晚上7点跟Kevin、Kevin和刘洋老师一起吃饭`
1. `tool_create_event(title="晚餐", start_at="2026-05-30T19:00:00+08:00", ...)` → event_id
2. 完全重复的 `Kevin` 先去重,只查询和添加一次
3. `tool_query_contact(name_query="Kevin")` → `contacts` 有 2 条 (2+ 命中)
4. `tool_add_event_attendee(event_id, name="Kevin", role="attendee")` (不猜、不绑定)
5. `tool_query_contact(name_query="刘洋老师")` → `contacts` 有 1 条
6. `tool_add_event_attendee(event_id, name=contacts[0]["name"], contact_id=contacts[0]["contact_id"], role="attendee")`
→ `attendees_added: ["Kevin", "刘洋老师"]`

**输入:** `明天早上 9 点站会`
1. `tool_create_event(title="站会", start_at="2026-05-26T09:00:00+08:00", ...)` → event_id
→ 没人/参与方提及 → 不调 add_event_attendee
→ `attendees_added: []`

**输入:** `把明天的客户会改成上午10点`
→ `tool_query_event(contains="客户")` → event_id
→ `tool_update_event(event_id, patch="{\"start_at\": \"2026-05-26T10:00:00+08:00\"}")`
(update 操作不再加 attendee)

**输入:** `取消明天的客户会`
→ `tool_query_event(...)` → event_id → `tool_delete_event(event_id)`

---

## Notes

- 不要捏造没说的字段(地点没说就不要瞎填 location)
- 时区默认 +08:00
- 一个 source_text 只处理一个 event 操作;dispatcher 已经把多意图拆开了
- **attendees 在 create 时**先按完全重复称呼去重,再用 `tool_query_contact` 查询;仅 1 命中使用 contact 的 `name` + `contact_id` 绑定,0 或 2+ 命中保留原文 `name_raw`
- Flash event **不创建 contact**,也不在多候选时猜测绑定
- update / delete 操作不动 attendees
- 完全重复 attendee(同一个原文称呼出现多次)必须去重,每个去重后的名字只调用一次 `tool_add_event_attendee`
