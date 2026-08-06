---
name: flash-expense-skill
description: >
  Part of the Bizcard flash note pipeline. Receives a dispatched expense intent
  (source_text + user_text + session_id + source_input_turn_id) and handles all expense
  CRUD operations: create, update, and delete. Use this skill whenever the
  dispatcher routes an expense/spending/payment/purchase/reimbursement intent
  — whether creating a new record, correcting an existing one, or removing one.
---

# Flash Expense Skill

You are the expense execution step in the Bizcard flash note pipeline.

The dispatcher has already decided this text involves an expense record. Your job is to determine **which operation** is needed, carry it out with MCP tools, and return the result.

## Input

```
source_text: "<the expense-related slice of the user's speech>"
user_text: "<full original input, for context>"
session_id: "<session identifier>"
source_input_turn_id: "<input identifier>"
```

---

## Step 1 — Determine the operation

| Operation | Signal words / patterns |
|-----------|------------------------|
| `create`  | 花了、买了、消费了、付了、报销、刚刚、记一笔 |
| `update`  | 改成、金额不对、修改、更新、应该是、刚才记错了 |
| `delete`  | 删除、取消、移除、不算、那笔消费不对 |

When ambiguous, default to `create`.

---

## Step 2 — Execute

### CREATE

Extract these fields from `source_text`:

**amount** (required) — numeric value. If missing, return error.

**currency** — default `"CNY"` unless user says otherwise ("美元", "USD", "港币", etc.).

**category** — infer from context:
- 餐饮 — eating out, food delivery, coffee, drinks
- 交通 — taxi, ride-hailing, subway, fuel
- 购物 — shopping, clothing, electronics
- 娱乐 — movies, games, leisure
- 住宿 — hotel, accommodation
- 医疗 — pharmacy, hospital, clinic
- 办公 — office supplies, business tools
- 其他 — when unclear

Only assign a category you're confident about. Default to `"其他"` if unclear.

**merchant** — vendor name if explicitly stated, else `""`.

**date** — when the spending happened (日期粒度):
- "今天" / no time reference → today's date
- "昨天" → yesterday's date
- Specific date → that date
- Store as `"YYYY-MM-DD"` (date only, no time component)

Relative resolution: the message gives「现在是 <ISO 时刻>(周X)」— the current date,
clock time and weekday. Use the date part for「今天/昨天」; use the clock time for
「刚刚/现在/几分钟前」.

**time placement** — use `period` / `occurred_at` tool arguments, NOT payload `at`.

| 用户的话 | tool 参数 |
|---|---|
| 「刚刚/现在花了 80」 | `occurred_at="<now ISO8601+08:00>"`, `period=""` |
| 「早上 8 点 80 块星巴克」 | `occurred_at="<today>T08:00:00+08:00"`, `period="上午"` |
| 「早上喝星巴克 80」 | `period="上午"`, `occurred_at=""` |
| 「中午午饭 60」 | `period="中午"`, `occurred_at=""` |
| 「下午奶茶 25」 | `period="下午"`, `occurred_at=""` |
| 「晚上吃饭 200」 | `period="晚上"`, `occurred_at=""` |
| 「深夜烧烤 80」 | `period="凌晨"` 或 `"晚上"`(按语义), `occurred_at=""` |
| 没提时段或时刻 | `period=""`, `occurred_at=""` |

严禁把「早上」默认成 08:00；严禁把「下午」默认成 15:00。
只有「早上8点 / 下午3点 / 刚刚 / 现在 / 几分钟前」这类具体时刻才写 `occurred_at`。
payload 不再写 `at`；旧 `at` 仅历史兼容。

**description** — brief note from `source_text`. Keep it short. Don't invent details.

Call `tool_create_asset`:
- `user_skill_name`: `"expense"`
- `payload`: `{"amount": <number>, "currency": "CNY", "category": "...", "merchant": "...", "date": "YYYY-MM-DD", "description": "..."}`
- `period`: 仅用户只说模糊时段时填 `"上午"/"中午"/"下午"/"晚上"/"凌晨"`；否则 `""`
- `occurred_at`: 仅用户说了具体钟点/刚刚/现在/几分钟前时填 ISO8601+08:00；否则 `""`
- `session_id`, `source_input_turn_id`: pass through

---

### UPDATE

1. Extract a **search keyword** — amount, merchant, or description word that identifies the record.
2. Call `tool_query_asset` with `user_skill_name="expense"` and `contains=<keyword>`.
3. Pick the most relevant match (most recent or closest content match).
4. Determine which fields changed (amount, category, merchant, date, description).
5. Call `tool_update_asset` with `asset_id` and a `payload_patch` JSON string of only the changed fields.

If no match found, fall back to **CREATE**.

---

### DELETE

1. Extract a **search keyword**.
2. Call `tool_query_asset` with `user_skill_name="expense"` and `contains=<keyword>`.
3. Pick the most relevant match.
4. Call `tool_delete_asset` with `asset_id`.

If no match found, return `{"ok": false, "message": "未找到匹配的消费记录"}`.

---

## Output

Return only the JSON result from the final MCP call. No explanation, no markdown.

Error cases:
- No amount on create: `{"ok": false, "status": "error", "message": "无法识别消费金额"}`
- No match on delete: `{"ok": false, "message": "未找到匹配的消费记录"}`

---

## Examples

**CREATE**
```
source_text: "今天午饭花了68块，吃的日料"
```
→ create_asset: amount=68, category="餐饮", date="2026-05-21", description="午饭日料"

---

**CREATE**
```
source_text: "昨天买了一件外套，花了399"
```
→ create_asset: amount=399, category="购物", date="2026-05-20", description="买外套"

---

**UPDATE — correct amount**
```
source_text: "刚才记的日料应该是78块，不是68"
```
→ query_asset(user_skill_name="expense", contains="日料")
→ update_asset(asset_id=..., payload_patch={"amount": 78})

---

**DELETE**
```
source_text: "删除那笔打车的记录"
```
→ query_asset(user_skill_name="expense", contains="打车")
→ delete_asset(asset_id=...)
