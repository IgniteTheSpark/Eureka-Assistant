# Handoff · 模糊时段不造假钟点 + todo 承接 period

> 给 coding agent。目标是修复 UReka 日历 / 流视图里「用户只说早上/下午」被错误落成具体时间或无时段的问题。
> **真值**：[§1.3 时段/时刻抽取](../01-agent-architecture.md) · [§2 §3.6 assets.period/occurred_at](../02-data-model.md) · [§3.4/3.8 API](../03-api-reference.md) · [§4.5.0a DayRender](../04-frontend.md) · [§99 prompt 附录](../99-prompts-appendix.md)。

---

## 0. 现在的问题

用户实测：

1. 「早上吃包子花了8」
   当前：创建成今天上午 **8:00** 的 8 元消费记录。
   目标：创建成今天上午 section 的**没具体时间**消费记录，**不显示 8:00**。

2. 「下午要开一个会」
   当前：创建成今天「没有时间」section 的开会待办。
   目标：创建成今天下午 section 的**没具体时间**待办，**不显示时间前缀**。

这不是前端 DayRender 规则错，而是 **skill/tool 产出字段没有闭环**：

- `flash-expense-skill` 仍有旧规则：`早上 -> 08:00`、`下午 -> 15:00`。
- `tool_create_todo` / `create_todo` 没有 `period` / `occurred_at` 参数，todo skill 即使识别出「下午」也写不进去。
- 自定义 skill agent 也必须注入同一套时间规则；例如用户创建「跑步记录」后说「昨天下午跑了5km」，应落到昨天·下午「没具体时间」，而不是今天或 15:00。

---

## 1. 产品规则（不可改）

一条 asset 的时间落位按这三态：

| 用户说法 | 写入字段 | 展示 |
|---|---|---|
| 说了具体钟点：`早上8点` / `下午3点` | `occurred_at=<精确 ISO8601+08:00>`；可同时推 `period` | 落对应时段，显示 `HH:MM` |
| 只说模糊时段：`早上` / `下午` / `晚上` | `period=上午/下午/晚上`；`occurred_at=null` | 落该时段的「没具体时间」组，不显示时间 |
| 啥时间都没说 | `period=null`；`occurred_at=null` | 按 `created_at` 捕捉时刻兜底，显示捕捉 `HH:MM` |

**铁律**：

- `早上` 不是 08:00。
- `下午` 不是 15:00。
- 只有 `早上8点` / `下午3点` 这种明确钟点才写 `occurred_at`。
- 单点开会仍是 `todo`，不是 `event`；完整时段（start+end / start+duration / 全天）才是 `event`。
- 内置 skill 和用户自定义 skill 完全同规；`make_custom_skill_agent` 生成的 prompt 也必须要求填写 `period` / `occurred_at`。

---

## 2. 后端工具改动

### 2.1 `create_todo` 补 period / occurred_at

文件：

- `backend/mcp_server/tools.py`
- `backend/mcp_server/server.py`

把 typed todo 工具从：

```python
tool_create_todo(content, due_date, session_id, source_input_turn_id, domain, user_id)
```

扩展为：

```python
tool_create_todo(
    content,
    due_date="",
    session_id="",
    source_input_turn_id="",
    domain="",
    user_id="default",
    period="",
    occurred_at="",
)
```

`create_todo(...)` 同步加 `period` / `occurred_at`，并传给 `create_asset(...)`。

示意：

```python
return await create_asset(
    "todo",
    payload,
    session_id,
    source_input_turn_id,
    domain,
    user_id,
    period,
    occurred_at,
)
```

注意：参数顺序如果容易错，建议改成 keyword 调用，避免 `created_at` 后续参数错位。

### 2.2 MCP docstring 同步

`tool_create_todo` 文档必须写清楚：

- `due_date`：只有具体截止日期/时刻才写。
- `period`：只说模糊时段时写。
- `occurred_at`：只有具体钟点才写。
- 不要把「下午」写成 `due_date=...T15:00`。

---

## 3. Skill prompt 改动

### 3.1 `flash-expense-skill`

文件：

- `backend/skills/flash-expense-skill/SKILL.md`

删除旧的 `at` canonical 表：

- `早上喝星巴克 80 -> 08:00`
- `下午奶茶 25 -> 15:00`
- `晚上吃饭 -> 19:00`

替换为：

```md
时间落位字段：

- 具体钟点：「早上8点」「下午3点」→ tool_create_asset(..., occurred_at="YYYY-MM-DDTHH:mm:00+08:00")
- 只说模糊时段：「早上/下午/晚上」→ tool_create_asset(..., period="上午/下午/晚上", occurred_at="")
- 没说时间 → period="", occurred_at=""

严禁把「早上」默认成 08:00；严禁把「下午」默认成 15:00。
payload 不再写 at；旧 at 仅历史兼容。
```

调用 `tool_create_asset` 时传：

```text
user_skill_name="expense"
payload={"amount":..., "currency":"CNY", "category":"...", "merchant":"", "date":"YYYY-MM-DD", "description":"..."}
period="上午"   # 仅模糊时段时
occurred_at=""  # 仅无具体钟点时
```

### 3.2 `flash-todo-skill`

文件：

- `backend/skills/flash-todo-skill/SKILL.md`

更新 CREATE 规则：

```md
Call tool_create_todo:
- content: 任务原文
- due_date:
  - 有具体日期+钟点 → ISO8601+08:00
  - 只有日期 → "YYYY-MM-DD"
  - 没有日期/截止 → ""
- period:
  - 只说「早上/下午/晚上」但没说钟点 → "上午/下午/晚上"
  - 否则 ""
- occurred_at:
  - 说了具体钟点 → ISO8601+08:00
  - 否则 ""
```

关键例子必须写进 prompt：

```text
source_text: "下午要开一个会"
→ tool_create_todo(content="开一个会", due_date="", period="下午", occurred_at="")

source_text: "下午3点要开会"
→ tool_create_todo(content="开会", due_date="<today>T15:00:00+08:00", period="下午", occurred_at="<today>T15:00:00+08:00")

source_text: "明天下午要开一个会"
→ tool_create_todo(content="开一个会", due_date="YYYY-MM-DD", period="下午", occurred_at="")

source_text: "明天下午3点要开会"
→ tool_create_todo(content="开会", due_date="YYYY-MM-DDT15:00:00+08:00", period="下午", occurred_at="YYYY-MM-DDT15:00:00+08:00")
```

> `due_date` 负责 todo 的到期 / 提醒语义；`period`/`occurred_at` 负责日历段落展示。只说「下午」时，不制造 `15:00`。

### 3.3 `make_custom_skill_agent`

文件：

- `backend/agents/flash_pipeline.py` 或实际定义 `make_custom_skill_agent` 的文件

自定义 skill prompt 必须和内置 skill 一样注入时间落位规则：

```md
时间落位：
- 具体钟点：「下午4点跑了5km」→ occurred_at="YYYY-MM-DDT16:00:00+08:00"
- 只说模糊时段：「昨天下午跑了5km」→ period="下午", occurred_at=""
- 没说时间：「跑了5km」→ period="", occurred_at=""
- 相对日期：「昨天/前天/明天」要解析到对应日期；今天流里不出现跨天产出的结构卡，只闪念数 +1。
- 严禁把「下午」默认成 15:00。
```

示例：

```text
用户自定义 skill: 跑步记录
source_text: "昨天下午跑了5km"
→ tool_create_asset(user_skill_name="<跑步记录 machine_name>", payload={...distance: "5km"...}, period="下午", occurred_at="")
→ 展示: 昨天 · 下午 · 没具体时间

source_text: "昨天下午4点跑了5km"
→ tool_create_asset(..., occurred_at="<yesterday>T16:00:00+08:00", period="下午")
→ 展示: 昨天 · 下午 · 16:00
```

---

## 4. Timeline 兼容检查

文件：

- `backend/core/timeline.py`

确认 asset effective time 优先级：

```text
occurred_at -> skill anchor / due_date / date -> created_at
```

expense 新写入不再产生 payload `at`。如果代码还读 legacy `payload.at`，只能作为旧数据兼容，不能让新 prompt 继续生成。

DayRender 依赖：

- `period`：模糊时段。
- `has_clock_time`：`occurred_at is not None`。

只有 `has_clock_time=true` 才显示时间前缀；只有 `period` 且无 `occurred_at` 时进入段内「没具体时间」。

---

## 5. API / schema 检查

文件：

- `backend/db/models.py`
- `backend/db/migrations/versions/0028_asset_period_occurred_at.py`
- `backend/api/assets.py` 或实际 assets route 文件
- `backend/schemas` 下的 `CreateAssetRequest` / response schema（按实际项目结构）

检查点：

- `Asset.period` / `Asset.occurred_at` 已存在。
- `/api/assets` create request 支持 `period` / `occurred_at`。
- `_serialize_asset` 返回 `period` / `occurred_at`，方便前端详情和调试。
- MCP `create_asset` 已有 `_norm_period` / `_parse_occurred`。

如果当前 API 手动创建路径还没有 `period/occurred_at`，补上，和 spec [§3.4](../03-api-reference.md) 对齐。

---

## 6. 必加回归测试 / 手测用例

至少覆盖下面 8 条。可以是 skill eval、backend integration test，或先用真实 app 手测记录结果。

### 6.1 Expense

| 输入 | 期望字段 | 期望展示 |
|---|---|---|
| `早上吃包子花了8` | `period=上午`, `occurred_at=null`, payload 无 `at` | 今天上午「没具体时间」，不显 08:00 |
| `早上8点吃包子花了8` | `occurred_at=<today>T08:00:00+08:00` | 今天上午，显 08:00 |
| `下午奶茶25` | `period=下午`, `occurred_at=null`, payload 无 `at` | 今天下午「没具体时间」，不显 15:00 |
| `刚刚买水花了3块` | `period=null`, `occurred_at=<now>` 或按现有「刚刚/现在」规则使用当前时刻 | 当前时段，显当前时刻 |

> `刚刚/现在` 是具体当前时刻，不是模糊时段，可以写 `occurred_at=now`。

### 6.2 Todo

| 输入 | 期望字段 | 期望展示 |
|---|---|---|
| `下午要开一个会` | `period=下午`, `occurred_at=null`, `due_date=""` | 今天下午「没具体时间」，不显时间 |
| `下午3点要开会` | `period=下午`, `occurred_at=<today>T15:00:00+08:00`, `due_date=<today>T15:00:00+08:00` | 今天下午，显 15:00 |
| `明天下午要开一个会` | `period=下午`, `occurred_at=null`, `due_date=<tomorrow date-only>` | 明天下午「没具体时间」；今天流里无此条，只闪念 +1 |
| `记得买D3` | `period=null`, `occurred_at=null`, `due_date=""` | 今天按捕捉时刻兜底 |

### 6.3 Custom skill

| 输入 | 期望字段 | 期望展示 |
|---|---|---|
| `昨天下午跑了5km` | `period=下午`, `occurred_at=null`, payload 保留 `5km` | 昨天下午「没具体时间」；今天流里无此条，只闪念 +1 |
| `昨天下午4点跑了5km` | `period=下午`, `occurred_at=<yesterday>T16:00:00+08:00` | 昨天下午，显 16:00 |

---

## 7. 验收标准

完成后在真实 app 验证：

1. 说「早上吃包子花了8」
   - 不显示 08:00。
   - 在上午 section 的「没具体时间」组。
   - DB asset `period="上午"`，`occurred_at is null`，payload 无新 `at`。

2. 说「下午要开一个会」
   - 是 todo，不是 event。
   - 不显示时间前缀。
   - 在下午 section 的「没具体时间」组。
   - DB asset `period="下午"`，`occurred_at is null`。

3. 说「下午3点要开会」
   - 是 todo，不是 event。
   - 显示 15:00。
   - DB asset `occurred_at` 有值。

4. 说「明天下午要开一个会」
   - 今天流里不出现这条结构卡。
   - 明天流里下午 section 出现，无具体时间。
   - 今天闪念数量 +1。

---

## 8. 不要做

- 不要改 DayRender 的产品规则来迁就旧数据。
- 不要继续在 expense payload 里生成 `at`。
- 不要把模糊时段转成默认钟点。
- 不要把「下午要开会」升级成 event；没有完整时段就是 todo。
- 不要为了提醒逻辑给无钟点 todo 填一个假 `due_date` 时间。
- 不要只修内置 skill；自定义 skill 的 agent prompt 也必须接同一套规则。

---

## 9. 参考代码路径

- `backend/mcp_server/tools.py`
- `backend/mcp_server/server.py`
- `backend/skills/flash-expense-skill/SKILL.md`
- `backend/skills/flash-todo-skill/SKILL.md`
- `backend/core/timeline.py`
- `mobile/lib/render/day_render.dart`
- `mobile/lib/timeline/timeline.dart`

相关 spec：

- [01-agent-architecture.md](../01-agent-architecture.md)
- [02-data-model.md](../02-data-model.md)
- [03-api-reference.md](../03-api-reference.md)
- [04-frontend.md](../04-frontend.md)
- [99-prompts-appendix.md](../99-prompts-appendix.md)
