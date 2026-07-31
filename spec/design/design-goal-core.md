# Design: Goal Core（手动创建、记录驱动进度）

> 日期：2026-07-24
> 状态：**READY FOR HANDOFF · 产品规则已收口，尚未实施**
> 范围：Goal 类型、时间规则、手动创建、Draft/确认、成功页、My Goals、进度、Asset Evidence、详情页、结束与重建。
> 本稿是下一轮 Goal coding handoff 的产品真值。它不表示代码已经落地。

---

## 0. 一页结论

UReka 的 Goal 不是脱离记录的手工打卡器。每个 Goal：

```text
关联一个已有 Skill
→ 用户在 App 前台描述目标
→ Goal Agent 生成结构化 Draft
→ 用户确认完整规则
→ 后续 Assets 自动提供进度与 Evidence
→ Goal 到期、达成或被提前结束
```

首版支持三种 Goal：

| 类型 | 用户含义 | 代表例子 |
|---|---|---|
| `checkin` | 在重复的自然周期内完成若干次记录 | 未来三个月每周跑步 3 次 |
| `progress` | 在 Goal 期限内累计达到目标 | 一年内累计跑步 100km |
| `guardrail` | 在 Goal 期限内不超过约束 | 一年内累计开销不超过 ¥1,000 |

核心约束：

1. Goal 必须关联一个已经存在的 `user_skill_id`。
2. 所有 Goal 都必须有 `starts_at` 和 `ends_at`；没有期限时默认一年。
3. 同一 Skill + 同一 Goal Type 同时最多有一个未结束 Goal。
4. Goal 在 Draft 阶段可修改；确认后计算规则不可修改。
5. 调整规则 = 提前结束旧 Goal + 创建新 Goal。
6. 再来一轮 = 创建新 Goal。
7. Evidence 就是 Assets；手动打卡也必须创建普通 manual Asset。
8. Goal Detail 的 Evidence 是扁平 Asset 列表，不使用 A2UI，不展示缺口或空槽位。
9. 首版没有暂停、固定提醒、Reka Goal 建议和 Flash/硬件 Goal 创建。
10. `My Goals` 保留资产库一级管理入口，Theme V2 Home Goals Layer 提供高频入口；两者共用 Goal 数据且不增加底部导航。
11. Goal 接入 Theme V2 Home 的 Goals Layer；Home 只消费确定性 Goal 摘要、下一节点、Goal 概览和历史入口，不在 UI 或 LLM 中临时计算进度。

---

## 1. 范围

### 1.1 本稿定义

- Goal 的三种产品类型和确定性计算语义。
- Goal 与 Skill、Asset 的关系。
- 时间归一和自然周期规则。
- App 内四个手动创建入口。
- Goal Setting、Draft、确认页和创建成功页。
- My Goals 的入口、当前目标卡片墙、筛选与历史页。
- Theme V2 Home Goals Layer 的摘要、下一节点、Goal 概览和历史入口。
- Goal Detail 的进度和 Evidence 结构。
- Goal 的不可变规则、提前结束、调整和再来一轮。
- 同 Skill + Type 的冲突规则。
- 为 coding handoff 准备的概念数据契约和验收样例。

### 1.2 明确不包含

- Reka 自动发现和建议 Goal。
- Goal suggestion Candidate、收件箱、dismiss、冷却和去重。
- Flash、硬件或后台任务创建 Goal / Goal Draft。
- Goal 的固定提醒、每个 Goal 的提醒设置和通知 UI。
- 暂停、恢复、暂停期间补算或截止日期顺延。
- A2UI 或 LLM 驱动的 Goal Detail / Evidence 布局。
- Skill schema 修改、字段 CRUD 或 schema versioning。
- 无法由 Assets 自动计算的自由目标。
- My Goals 与 Home Goals Layer 的像素级视觉；统一以 [Theme V2 Coding Handoff](theme-v2-coding-handoff.md) 和 `redesignureka.pen` 为准，本稿只锁定信息架构、组件语义和交互规则。
- 具体数据库迁移和最终 API 路径；由后续 coding handoff 定义。

### 1.3 与其他文档的关系

- [design-goals-proactive-reka.md](design-goals-proactive-reka.md) 保留主动服务的长期方向；其中 Goal 产品定义以本稿为准。
- [theme-v2-coding-handoff.md](theme-v2-coding-handoff.md) 与 `redesignureka.pen` 定义 Goal 的 UI/IA；本稿定义 Goal 的数据、计算和生命周期语义。
- [design-habit-streak.md](design-habit-streak.md) 是历史参考，不再定义用户创建 Habit 对象。
- [§14 主动 Reka](../14-proactive-reka.md) 继续描述当前已实现的 nudge / offer 系统；本轮 Goal Core 不接入新的 Goal 建议。
- `payload_schema` / `render_spec` / Assets 当前真值继续见 [§2](../02-data-model.md) 和 [§4.7](../04-frontend.md)。

---

## 2. 产品对象与不变量

### 2.1 Goal 是一次有限承诺

每个 Goal 都对应一次有明确时间范围的承诺，而不是永久容器：

```text
Goal A：2026.08–2026.10，每周跑步 3 次
Goal B：2026.11–2027.02，每周跑步 4 次
```

Goal A 和 Goal B 是两个独立 Goal、两个 ID。Goal B 可以记录它来自 Goal A 的“再来一轮”或“调整”，但不能覆盖 Goal A 的历史。

### 2.2 Goal 必须由记录自动计算

Goal 必须绑定一个具体 `user_skill_id`。进度来自该 Skill 的 Assets 及其 payload 字段。

支持：

- 每周至少创建 3 条跑步记录。
- 一年内跑步距离累计达到 100km。
- 一年内消费金额累计不超过 ¥1,000。

不支持：

- 成为更好的人。
- 提高工作能力。
- 保持开心。
- 任何没有可追溯 Asset 或字段的自由承诺。

### 2.3 Goal 与 Habit 分离

本稿只实现 Goal。习惯是长期行为状态，不是本轮要创建的数据对象。

- Check-in Goal 可以产生连续周期、完成率等事实。
- “正在形成习惯 / 稳定保持 / 中断 / 恢复”等 Habit 状态留给后续模块。
- 首版不因创建 Goal 自动创建 Habit。

---

## 3. Goal 类型

### 3.1 Check-in

Check-in 表达重复周期内的记录次数要求：

```yaml
type: checkin
cadence: daily | weekly | monthly
required_count: integer
```

例子：

- 每天健身 1 次。
- 每周跑步 3 次。
- 每月记录体重 10 次。

计算：

```text
按用户时区切分自然日 / 自然周 / 自然月
→ 统计每个周期内符合条件的 Assets
→ count >= required_count 则该周期达标
```

Check-in 的周期分桶只服务进度计算。Evidence UI 不显示周期分组、缺失槽位或“还差一次”。

首版默认每一条符合条件的 Asset 算一次。一天或一个周期内多条记录均保留为独立 Evidence；是否达到目标由计数判断。

只结算完整落在 `[starts_at, ends_at]` 内的自然周期。以“连续三个月、每周三次”为例，月初进入第一个完整自然周前、
以及最后一个完整自然周结束后的零散日期不单独形成一个缩水周目标。

### 3.2 Progress

Progress 表达在整个 Goal 期限内累计达到目标：

```yaml
type: progress
metric:
  operator: count | sum
  field: optional
target:
  comparator: gte
  value: number
  unit: optional
```

例子：

- 一年内累计跑步 100km：`sum(distance) >= 100km`。
- 三个月读完 10 本书：`count(asset) >= 10`。

达到目标后可以提前结束：

```text
current_value >= target
→ status = ended
→ outcome = achieved
```

### 3.3 Guardrail

Guardrail 表达在整个 Goal 期限内不超过上限：

```yaml
type: guardrail
metric:
  operator: count | sum
  field: optional
target:
  comparator: lte
  value: number
  unit: optional
```

例子：

- 一年内累计开销不超过 ¥1,000：`sum(amount) <= 1000`。
- 一个月外卖不超过 8 次：`count(asset) <= 8`。

Guardrail 不能提前判定达成。中途超过上限可以显示“已超出”，但仍追踪到 `ends_at`，因为 Asset 可能被修正、删除或冲正。

### 3.4 首版计算能力

首版 handoff 只需要：

- `count(asset)`。
- `sum(numeric_field)`。
- `gte`。
- `lte`。
- `daily / weekly / monthly` 自然周期。

以下后置：

- `average`。
- `condition_rate`。
- `between`。
- rolling window。
- streak 作为 Goal metric。
- 跨 Skill Goal。
- 复杂公式与派生字段。

---

## 4. Skill 与 Asset

### 4.1 关联已有 Skill

Goal 创建前必须存在可承载记录的 Skill：

```text
Goal.user_skill_id → user_skills.id
```

找不到相关 Skill 时：

> 暂时没有可以承载这个目标的资产 Skill，因此还不能创建目标。

可以引导用户去创建 Skill，但首版不自动串联 Skill Wizard 和 Goal Wizard，也不创建残缺 Goal Draft。

### 4.2 Skill 字段契约稳定

当前已创建 Skill 只允许修改：

- `display_name`。
- icon。
- `render_spec` 的标题①、标题②、信息和隐藏位置。

当前不允许用户修改：

- `payload_schema`。
- 字段 key。
- 字段类型。
- 增删字段。

因此 Goal 首版直接引用稳定的 `user_skill_id` 和 payload field key，不引入 Skill schema versioning。

展示配置变化不影响 Goal 计算：

```text
label / icon / 标题位置变化
→ Goal Rule 不变
→ 历史 Assets 不变
```

### 4.3 Skill deprecated

Skill deprecated 时：

- 不删除历史 Assets。
- 所有关联的 `scheduled / active` Goal 结束。
- Goal `outcome = skill_deprecated`。
- Goal Detail 和历史 Evidence 保留。
- 该 Skill 不再允许创建新 Goal。

彻底删除 Skill 与历史数据属于单独的数据删除流程，不是普通 Goal 操作。

### 4.4 Evidence 就是 Assets

产品层不创建一套带独立内容的 Evidence 对象：

```text
Evidence = 计入某个 Goal 的 Asset 引用集合
```

自动路径：

```text
新建 / 修改 / 删除 Asset
→ 检查同 Skill 的未结束 Goal
→ 按 Goal 时间和规则重算
```

手动路径：

- “选择已有记录”：从关联 Skill 的 Assets 中选择。
- “新建记录”：打开该 Skill 的 manual Asset 表单。
- 新建结果是普通 Asset，同时进入资产库、日历和 Goal。
- 不复制已有 Asset。
- 一条 Asset 可以同时贡献同 Skill 下不同类型的 Goal。

例如一条 `5km` 跑步 Asset 可以同时：

- 为 Check-in Goal 增加 1 次。
- 为 Progress Goal 增加 5km。

---

## 5. 时间规则

### 5.1 所有 Goal 都必须有期限

```yaml
created_at: datetime
starts_at: datetime
ends_at: datetime
timezone: user_timezone
```

- 用户明确时间时使用用户时间。
- 没有期限时应用默认一年，并在确认页展示具体日期。
- Goal 不隐式永久运行。

### 5.2 用户明确日期

| 用户表达 | 归一结果 |
|---|---|
| 下个月每天健身 | 下月 1 日至下月最后一天 |
| 从 8 月 1 日开始坚持 30 天 | 8 月 1 日起 30 天 |
| 年底前跑完 100km | 确认后开始，12 月 31 日结束 |
| 从今天起未来三个月每周跑 3 次 | 确认后开始，三个月后结束 |

明确时间优先于所有默认规则。

### 5.3 Check-in 未明确日期

Check-in 不从残缺自然周期开始。

只有打卡频率、没有计划期限：

```text
每天一次 → 明天开始
每周三次 → 下周一开始
每月十次 → 下月 1 日开始
→ 默认持续一年
```

有外层计划期限、没有明确开始日期：

```text
“未来三个月每周跑步三次”
→ 外层单位 = 月
→ 从确认后的下一个月开始
→ 使用下个月第一个完整自然周
→ 持续三个月
```

当前产品默认：

> 从下个月的第一个完整自然周开始，连续三个月，每个自然周至少完成三次跑步记录。

这避免首周只剩一两天却要求完成完整周目标。

### 5.4 Progress / Guardrail 未明确时间

Progress 和 Guardrail 没有明确时间时：

```text
确认后立即开始
→ 默认持续一年
```

例如：

> 完成 100km 跑步。

归一为：

> 从今天起一年内，累计完成 100km 跑步。

> 开销小于 1000 元。

归一为：

> 从今天起一年内，累计开销不超过 ¥1,000。

默认推断必须完整显示在确认页。用户如果想表达“每月不超过 ¥1,000”，需要重新描述后生成另一份 Draft。

### 5.5 自然周期

按 Goal 保存的用户时区：

- 日：当地 `00:00–23:59`。
- 周：周一至周日。
- 月：自然月。

Asset 归属使用项目既有有效时间规则：

```text
effective_time
= occurred_at
?? Skill timeline anchor
?? created_at
```

补录“昨天下午跑了 5km”进入昨天所在周期，不进入创建 Asset 的今天。

---

## 6. 同 Skill + Type 冲突

同一时刻：

```text
同一个 user_skill_id
+ 同一个 goal_type
= 最多一个未结束 Goal
```

未结束包括：

- `scheduled`。
- `active`。

首版没有 `paused`。

允许：

```text
跑步 Check-in：每周 3 次
+ 跑步 Progress：累计 100km
```

不允许：

```text
跑步 Check-in：每周 3 次
+ 跑步 Check-in：每周 2 次
```

也不允许在当前 Goal 尚未结束时，提前排一个未来同类型 Goal。

已经结束的历史 Goal 不阻塞新 Goal。用户可以“再来一轮”或在旧 Goal 结束后重新创建。

确认 Goal 时必须再次进行冲突检查，避免两个页面同时创建导致竞态。

---

## 7. 创建入口

Goal 只在 App 前台的专用流程中创建。

### 7.1 Skill 详情

```text
Skill Detail
→ 设定目标
→ Skill 已预选
→ Goal Setting
```

### 7.2 Asset 详情

```text
Asset Detail
→ 基于这类记录设定目标
→ 预选该 Asset 的 user_skill_id
→ Goal Setting
```

Goal 关联的是该 Asset 的 Skill，不是这条 Asset 本身。Goal 从未来期限开始计算，历史 Asset 不因入口来源自动计入。

### 7.3 我的目标

```text
资产库 → 我的目标
→ + 新目标
→ 先选择 Skill
→ Goal Setting
```

`My Goals` 是 Goal 的独立管理页，但不新增底部导航。首版入口：

- Theme V2 Home 的 Goals Layer；它与 Today 通过两张错位叠放的页面切换，不增加底部导航。
- 资产库一级功能区中的“目标”入口。
- Skill Detail 和 Asset Detail 中保留 §7.1 / §7.2 的上下文入口。
- Notification 不新增独立 Goal 创建入口。

Today 中的 Reka Queue 可以展示由确定性 Goal 状态产生的结算、即将到期或进度变化信息；它不自动创建 Goal，也不引入 Reka Goal 建议。

“目标”不是领域，不新增领域色。入口使用中性图标和现有资产库 surface。

#### 7.3.1 页面信息架构

```text
My Goals
├── Header：我的目标 / 筛选 / + 新目标
├── 摘要：进行中 N · 即将开始 M
├── 进行中：active Goal cards
├── 即将开始：scheduled Goal cards
└── 查看历史目标
```

默认规则：

- `active` 和 `scheduled` 分组展示；空分组直接隐藏。
- 每组均按 `created_at DESC`，最新创建的 Goal 在前。
- 不按风险、截止时间、完成度或 Reka 判断重新排序。
- 历史 Goal 不与当前 Goal 混排；“查看历史目标”进入独立历史页。
- 页面重进时恢复默认全部结果，不保留上次筛选。
- 首版不提供搜索；Goal 数量增长后再评估。

#### 7.3.2 Goal Card

My Goals 使用纵向卡片墙，而不是横向轮播、Tinder 或纯文本列表。页面必须让用户同时看见多个 Goal。

所有 Goal Card 共用骨架：

```text
[Skill 图标] [Skill 名称]                         [状态]
[完整自然语言 Goal 描述]
[类型化进度模块]
[起止日期] / [剩余时间]
```

视觉与交互约束：

- 自然语言 Goal 描述是卡片主体；Skill 名称只是来源标识。
- 不向用户显示 `checkin / progress / guardrail` 内部枚举。
- 卡片背景保持中性；领域色只用于 Skill 图标、进度指示或小型标识，不整卡填色。
- 卡片不嵌套 Evidence Card，也不直接放“编辑 / 提前结束 / 再来一轮”按钮。
- 点击整张卡进入 Goal Detail。
- 不提供左右滑操作，避免与 Today Offer 的 Tinder 手势冲突。
- 同一 Skill 的不同类型 Goal 是两张独立卡片，不再套一层 Skill 容器。

Check-in：

```text
🏃 跑步训练                                      进行中
未来三个月，每周跑步三次

本周                                  ●  ●  ○   2 / 3
8月3日 – 10月31日
```

- 中间模块只表达当前自然周期的 `current_count / required_count`。
- 小目标值可使用节点或分段进度；目标值较大时改为稳定宽度的进度条。
- 不在卡片列 Evidence，也不告诉用户“还差一次”；缺口语义留给后续智能提醒。

Progress：

```text
🏃 跑步训练                                      进行中
一年内累计完成 100km

42.6 / 100km
[累计进度条]
截至 2027年7月23日
```

- 展示 `current_value / target_value + unit`。
- 进度条表达累计达成比例。

Guardrail：

```text
💰 日常记账                                      进行中
一年内开销不超过 ¥5,000

已使用 ¥2,860                         剩余 ¥2,140
[额度区间]
截至 2027年7月23日
```

- 优先展示“已使用”和“剩余”，不使用“完成百分比”。
- 不把继续消耗额度表达为正向完成。
- 超出上限后明确显示“已超出上限”，Goal 仍追踪到期。

Scheduled 卡使用同一骨架，状态为“即将开始”，进度区改为明确的开始时间和 Goal 规则，不绘制 `0%` 进度。

#### 7.3.3 筛选

Header 的筛选图标打开 bottom sheet，不在页面常驻一排 chips。

首版筛选维度：

| 维度 | 选项 |
|---|---|
| Skill | 用户当前可见的 Skills，多选 |
| 目标形式 | 打卡目标 / 累计目标 / 守护目标，多选 |
| 状态 | 当前页：进行中 / 即将开始；历史页：已达成 / 未达成 / 已超出 / 已提前结束 |

筛选组合规则：

```text
不同维度 = AND
同一维度多选 = OR
```

例如：

```text
跑步训练
AND（打卡目标 OR 累计目标）
AND 进行中
```

交互：

- 有筛选时，筛选图标显示激活态和已选条件数量。
- 无结果时显示“没有符合条件的目标”和“清除筛选”。
- 筛选只影响当前列表，不修改 Goal。
- 离开 My Goals 后清空筛选，重进恢复全部。
- 创建新 Goal 时保留当前页面筛选；若新 Goal 不符合条件，不强行插入列表，成功页仍直接进入新 Goal Detail。
- 排序不作为筛选项；始终使用各组 `created_at DESC`。

#### 7.3.4 历史目标

历史页复用 Goal Card 骨架和筛选 bottom sheet：

- 按 `created_at DESC`。
- 卡片展示最终结果、最终数值、起止日期和结束原因。
- 结果文案映射为：已达成 / 未达成 / 已超出 / 已提前结束 / Skill 已停用。
- 列表卡不直接放“再来一轮”；点击进入 Goal Detail 后操作。
- 历史为空时显示简短空状态，不展示无意义图表。

#### 7.3.5 空状态

完全没有 Goal 时：

```text
你还没有目标
从一个已有的记录类型开始设定目标
[创建目标]
```

- 主动作进入 Skill 选择。
- 如果用户没有可用 Skill，解释“目标需要基于一种已有记录”，并引导创建 Skill。
- 不使用 Reka 自动建议填充空状态；该能力属于后续 G5。

### 7.4 Theme V2 Home Goals Layer

```text
Home → Goals Layer
→ + Goal
→ 先选择 Skill
→ Goal Setting
```

- Home 的 `+ Goal` 与 My Goals 的 `+ 新目标` 进入同一创建流程。
- Home 入口不预选 Skill；Skill / Asset Detail 的上下文入口仍按 §7.1 / §7.2 预选。
- Home 只增加高频入口，不建立独立 Draft、确认或成功页。

### 7.5 不作为创建入口

- Flash / 硬件。
- 后台任务。
- Reka Goal 建议。
- 系统推送。

Flash 遇到 Goal 表达只做轻量引导；具体回复、CTA 和路由不属于本稿。

---

## 8. Goal Setting

Goal Setting 是定向引导页，不是长对话，也不是复杂表单。

### 8.1 选择 Skill

从“我的目标”进入时先选择 Skill。从 Skill / Asset 进入时跳过。

已经存在同 Skill + Type 未结束 Goal 时，该类型不能创建，入口改为“查看现有目标”。

### 8.2 描述目标

页面围绕已选 Skill 提问：

> 你想在接下来做到什么？

用户可以直接输入：

> 未来三个月每周跑步三次。

也可以看到由 Skill 能力决定的快捷方向：

- 按频率坚持。
- 达到一个数值。
- 控制在范围内。

这些是输入模板，不要求用户理解 `checkin / progress / guardrail` 机器名。

### 8.3 Goal Agent

Goal Agent 只负责把用户表达转为可验证 Draft：

```text
自然语言
→ Goal Type
→ Skill 字段与计算方式
→ 目标值
→ 时间归一
→ 完整自然语言规则
```

Agent 不负责实际进度计算。

只有阻塞确定性计算时才补问，例如：

- “每天跑 5”中的 5 是公里还是分钟。
- Skill 中存在多个可用数值字段，语义无法判断。

能按既定默认规则补齐的时间不追问，直接在确认页明确展示。

### 8.4 Draft

每个正式 Goal 都必须经历 Draft，但首版 Draft 只存在于当前前台创建流程：

- 可任意修改或重新生成。
- 用户退出即丢弃。
- 不出现在“我的目标”。
- 不参与进度和提醒。
- 正式 Goal 只在用户最终确认后创建。

---

## 9. 确认页

确认页展示一段完整、可理解、可局部修改的自然语言 Goal 描述。

Check-in 例子：

```text
从 [2026年8月3日] 到 [2026年10月31日]，
每个 [自然周] 至少完成 [3次] [跑步记录]。
```

Progress 例子：

```text
从 [今天] 到 [2027年7月23日]，
通过 [跑步记录] 累计完成 [100km]。
```

Guardrail 例子：

```text
从 [今天] 到 [2027年7月23日]，
通过 [记账] 将累计开销控制在 [¥1,000] 以内。
```

### 9.1 局部修改

方括号语义段可以点击修改：

- 日期。
- 自然周期。
- 次数。
- 目标数值和单位。
- 关联 Skill。

局部修改必须同步修改结构化 Draft，不能只改显示文案。

### 9.2 完整重新描述

“重新描述目标”打开自然语言输入，重新运行 Goal Agent，生成一份新的 Draft，再回到确认页。

“重新开始”丢弃 Draft，回到选择 Skill / 描述目标。

不把整段确认句子直接做成无约束 `contenteditable`；否则结构化规则可能与文案失同步。

### 9.3 提醒

首版确认页不展示提醒配置：

```yaml
reminder_policy: smart
```

这是默认产品策略，不代表本轮必须同时实现 Goal 智能提醒引擎。固定提醒、关闭单个 Goal 提醒和自定义时间后置。

---

## 10. 创建成功页

用户确认后进入独立成功页。

`scheduled`：

> 目标准备好了。
> 8 月 3 日开始，每周完成 3 次跑步记录。

`active`：

> 目标开始了。
> 接下来的跑步记录会自动更新进度。

页面包含：

- Goal 完整简述。
- 开始时间。
- “记录会自动计入”的说明。
- `查看目标` 主动作。
- `完成` 次动作。

可以使用 Reka `faceHappy / stars` 和一次轻量庆祝动效，但创建 Goal 不发游戏奖励。建立承诺不等于完成行为。

---

## 11. 生命周期与不可变规则

### 11.1 状态

首版生命周期：

```text
Draft（创建流程内）
→ scheduled
→ active
→ ended
```

无暂停状态。

正式 Goal：

```yaml
status: scheduled | active | ended
outcome: pending | achieved | missed | breached | forfeited | skill_deprecated
```

- `scheduled`：开始时间未到。
- `active`：正在计算。
- `ended`：终态。
- `outcome` 说明结束结果。

### 11.2 确认后规则不可修改

确认后不可修改：

- `user_skill_id`。
- Goal Type。
- metric / field / comparator / target。
- cadence / required_count。
- `starts_at / ends_at / timezone`。

### 11.3 提前结束

用户可以提前结束：

```text
status = ended
outcome = forfeited
ended_at = now
```

UI 文案使用“已提前结束”，不使用带评价意味的失败文案。

### 11.4 调整目标

调整不修改当前 Goal：

```text
Goal Detail
→ 调整目标
→ 基于旧规则生成新 Draft
→ 用户修改
→ 用户确认
→ 原 Goal forfeited
→ 创建新 Goal
```

原子性要求：

- 打开调整页时，旧 Goal 继续运行。
- 用户退出 Draft，旧 Goal 不受影响。
- 只有新 Goal 确认成功时，才在同一事务中结束旧 Goal并创建新 Goal。

新 Goal 保存：

```yaml
previous_goal_id: old_goal_id
creation_reason: adjustment
```

### 11.5 再来一轮

旧 Goal 已结束后：

```text
再来一轮
→ 复制旧规则为新 Draft
→ 用户确认或重新描述
→ 创建新 Goal
```

```yaml
previous_goal_id: old_goal_id
creation_reason: restart
```

旧 Goal 的规则、进度和 Evidence 保持不变。

---

## 12. 进度计算

Goal 计算必须确定性完成，不由 LLM 判断。

### 12.1 Asset 事件

以下事件触发相关 Goal 重算：

- Asset 创建。
- Asset payload 更新。
- Asset effective time 更新。
- Asset 删除。
- Asset 改类到其他 Skill。

### 12.2 Check-in

顶部进度模块展示：

- 当前自然周期 `current / required`。
- Goal 内已经结算多少周期。
- 已达标周期数。

例：

```text
本周 2 / 3
已结算 7 周 · 6 周达标
```

Evidence 区不重复“还差一次”，也不画空槽。

Goal 到期时：

```text
所有要求周期达标 → achieved
至少一个要求周期未达标 → missed
```

即使某周期未达标，Goal 仍继续运行到 `ends_at`，除非用户主动提前结束。

### 12.3 Progress

顶部进度模块展示：

- 当前值。
- 目标值。
- 剩余值。
- 截止日期 / 剩余时间。

例：

```text
42.6 / 100 km
还差 57.4km
```

达到目标后提前结束为 `achieved`。到期仍未达到则 `missed`。

### 12.4 Guardrail

顶部进度模块展示剩余额度，而不是“完成百分比”：

```text
已使用 ¥720
剩余 ¥280
目标上限 ¥1,000
```

中途超过上限：

- UI 可以显示“已超出当前上限”。
- Goal 继续追踪到 `ends_at`。
- Asset 修正或删除后重新计算。

到期：

```text
current_value <= target → achieved
current_value > target → breached
```

---

## 13. Goal Detail

### 13.1 页面结构

```text
Goal 状态 + Skill
→ 完整自然语言规则
→ 起止日期
→ 类型化 Goal Progress
→ 扁平 Evidence List
→ 添加记录
→ 生命周期操作
```

Goal Detail 不提供规则编辑。

### 13.2 Evidence List

所有 Goal 共用一个确定性列表：

```text
只展示实际计入 Goal 的 Assets
→ 按 effective_time 倒序
→ 不做 Check-in 周期分组
→ 不生成缺失项
→ 不展示完成判断
```

统一 Evidence Row：

```text
[时间] [Asset 标题] [关键值]
```

字段来源：

```text
时间
= asset.effective_time

标题
= skill.render_spec.primary_field

关键值
= goal.rule.metric_field
?? skill.render_spec.secondary_field
```

Progress 跑步：

```text
7月24日  夜跑          5.2km
7月21日  公园跑步      8.0km
```

Guardrail 消费：

```text
7月24日  晚餐          ¥86
7月23日  打车          ¥42
```

Check-in 跑步仍是同一扁平列表：

```text
7月24日  晨跑          5.0km
7月21日  夜跑          4.5km
7月12日  公园跑步      6.0km
```

Check-in 周期分桶只存在于计算引擎，不进入 Evidence UI。

### 13.3 Evidence 交互

- 点击 Evidence Row：打开现有 Asset Detail Sheet。
- 修改 / 删除 Asset：Goal 自动重算。
- 默认加载最近 20 条，支持继续加载。
- `添加记录` 打开：
  - 选择已有 Asset。
  - 新建 manual Asset。

已有 Asset picker 只展示同 Skill 的记录。已经计入的记录显示“已计入”；未计入的记录如果缺少有效时间或 Goal
计算字段，选择后进入现有 Asset 编辑页补齐，而不是绕过 Goal Rule 强制计入。

首版不使用：

- A2UI。
- 新 Evidence DSL。
- 每次打开详情调用 LLM。
- 完整 SkillCard 堆叠。

实现只需要确定性 row builder：

```text
buildGoalEvidenceRow(asset, skillRenderSpec, goalRule)
```

### 13.4 生命周期操作

`scheduled / active`：

- 提前结束。
- 调整目标（创建新 Draft）。
- 查看关联 Skill。

`ended`：

- 再来一轮。
- 查看历史 Evidence。

无暂停 / 恢复。

---

## 14. 概念数据契约

本节用于后续 handoff 对齐，不是最终数据库 schema。

```yaml
Goal:
  id: uuid
  user_id: string
  user_skill_id: uuid
  type: checkin | progress | guardrail

  description: string
  rule:
    metric_operator: count | sum
    metric_field: optional
    comparator: gte | lte
    target_value: number
    unit: optional
    cadence: daily | weekly | monthly | null
    required_count: integer | null

  timezone: string
  starts_at: datetime
  ends_at: datetime

  status: scheduled | active | ended
  outcome: pending | achieved | missed | breached | forfeited | skill_deprecated
  ended_at: optional

  previous_goal_id: optional
  creation_reason: new | restart | adjustment
  reminder_policy: smart

  created_at: datetime
  confirmed_at: datetime
```

重要不变量：

```text
同 user_skill_id + type
最多一个 status in (scheduled, active)
```

MySQL 无 partial unique constraint，后续 handoff 必须在确认事务中做加锁 / 冲突检查，不能只依赖 UI。

Draft 可以是 Goal Agent 返回给前端的结构化对象，不要求首版落表。

Evidence 的产品真值是 Asset 引用集合。后续 handoff 可以选择实时查询或轻量关系表，但不得复制 Asset payload 成第二份 Evidence 数据。

---

## 15. 领域操作契约

后续 API handoff 至少需要表达以下操作，不在本稿锁定 URL：

```text
生成 Goal Draft
确认 Draft 并创建 Goal
列出当前 / 历史 Goal（支持 Skill / Type / Status 筛选，created_at DESC）
读取 Goal Detail + Progress + Evidence
选择已有 Asset
创建 manual Asset
提前结束 Goal
原子替换 Goal（forfeit old + create new）
基于历史 Goal 生成“再来一轮” Draft
```

确认和替换必须服务端校验：

- Skill 属于当前用户且未 deprecated。
- Goal Rule 引用的字段存在且类型可计算。
- 起止时间合法。
- 同 Skill + Type 没有其他未结束 Goal。
- 新 Goal 创建与旧 Goal forfeit 的原子性。

---

## 16. 验收样例

### 16.1 Check-in 创建

输入：

> 未来三个月每周跑步三次。

预期 Draft：

- Skill = 跑步。
- Type = `checkin`。
- 下个月第一个完整自然周开始。
- 连续三个月。
- 每个自然周 `count(running assets) >= 3`。
- 确认前可调整语义段。
- 确认后规则冻结。

### 16.2 默认一年

输入：

> 完成 100km 跑步。

预期：

- Type = `progress`。
- 确认后立即开始。
- 一年后结束。
- 确认句明确写出具体日期和 `100km`。

输入：

> 开销小于 1000 元。

预期：

- Type = `guardrail`。
- 确认后立即开始。
- 一年后结束。
- 确认句明确写“未来一年累计开销不超过 ¥1,000”。

### 16.3 不同类型共存

跑步已有 Progress `100km`：

- 可以创建 Check-in `每周 3 次`。
- 不能再创建另一个跑步 Progress。

一条 5km Asset：

- Check-in 增加 1 次。
- Progress 增加 5km。

### 16.4 调整

进行中的 Check-in 为每周 3 次。用户选择调整为每周 4 次：

- 打开调整页不影响旧 Goal。
- 退出 Draft，旧 Goal 继续运行。
- 确认新 Draft 后，旧 Goal `ended / forfeited`。
- 创建新的每周 4 次 Goal，并关联 `previous_goal_id`。

### 16.5 Evidence

- Goal Detail 显示扁平 Asset 列表。
- Check-in 不显示周分组标题和空槽位。
- Progress / Guardrail 行展示 Goal metric 字段。
- 点击打开原 Asset Detail。
- Asset 修改 / 删除后进度重算。

### 16.6 Skill deprecated

- 历史 Assets 保留。
- 当前 Goal 结束为 `skill_deprecated`。
- Goal Detail 和 Evidence 可继续查看。
- 不允许为 deprecated Skill 创建新 Goal。

### 16.7 My Goals

- 资产库一级入口打开 My Goals，不新增底部 tab。
- 默认分组展示 `active` 与 `scheduled`，组内按 `created_at DESC`。
- Check-in / Progress / Guardrail 使用同一卡片骨架和不同的确定性进度模块。
- 点击卡片进入 Goal Detail；卡片不承载生命周期操作。
- Skill / Goal Type / Status 支持多选筛选；同维度 OR、不同维度 AND。
- 历史 Goal 进入独立页面，不与当前 Goal 混排。

### 16.8 Theme V2 Home Goals Layer

- Home 中 Today 与 Goals 是两张错位叠放的页面，不是底部 Tab。
- Goals Layer 顶部显示 `active` 与 `scheduled` 数量摘要。
- “下一 Goal 节点”展示最近一个确定性时间节点，例如 Check-in 周期结算；多个同时需要关注的节点使用可循环的 stacked cards / carousel。
- “所有 Goals”复用 My Goals 的当前 Goal 数据与卡片语义，不建立第二套 Goal 状态。
- 点击 Goal 概览进入同一 Goal Detail；点击历史入口进入同一 Goal History。
- `+ Goal` 进入 §7 的创建流程。
- Home、My Goals 与 Goal Detail 的进度必须来自同一服务端确定性计算结果。

---

## 17. 实施拆分建议

后续 coding handoff 应按以下顺序拆分，不把 Proactive 混入：

在 Theme V2 整体 UI 重构中，Goal 作为主要页面完成后的后置模块进行最终确认与实现；以下 G1–G4 是 Goal 模块内部顺序，不要求 Goal 阻塞 Home 视觉、Calendar、Library 或 Session。

### G1 · 手动创建

- Goal Agent / Draft contract。
- Goal Setting。
- 语义句子确认。
- 冲突校验。
- 创建成功页。

### G2 · 进度与详情

- Goal 数据模型。
- Check-in / Progress / Guardrail 计算。
- My Goals 当前卡片墙、筛选与历史页。
- Goal Detail。
- 扁平 Evidence List。
- Asset 变更重算。

### G3 · 生命周期

- 到期结算。
- Progress 提前达成。
- Guardrail 最终结算。
- 提前结束。
- 原子调整。
- 再来一轮。

### G4 · 智能提醒（后置）

- Goal 风险和最后窗口。
- 复用现有主动服务护栏。
- 不在创建页增加提醒配置。

### G5 · Reka Goal 建议（后置）

- 根据 Skill + Goal Type 判断建议资格。
- Goal suggestion Candidate。
- 收件箱、冷却和处理状态。

本轮 handoff 只应覆盖 G1–G3；G4/G5 不得顺带实施。
