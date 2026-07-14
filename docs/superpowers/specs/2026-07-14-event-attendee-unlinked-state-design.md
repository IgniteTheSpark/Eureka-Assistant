# Event Attendee 未关联状态设计

日期：2026-07-14

## 背景

Flash 创建 event 时，用户可能只说出参会人的名字。系统可以在联系人库中遇到以下三种情况：

- 恰好一个同名联系人：安全绑定该联系人的 `contact_id`。
- 没有同名联系人：保留用户说出的名字，不自动创建联系人。
- 有多个同名联系人：保留用户说出的名字，不猜测绑定其中任何一个。

event 卡片的展示空间固定且紧凑，完整卡片也只有标题和一行摘要。卡片不可能展示所有参会人的逐人状态，也不应把联系人整理变成日程创建后的待办任务。

## 目标

- Flash 始终先快速、正确地创建 event，不因联系人缺失或重名打断用户。
- 未绑定联系人的参会人仍是合法、完整的 attendee。
- 用户进入 Event 详情或编辑页时，可以看见哪些名字没有关联联系人，并可选择处理。
- 所有卡片入口保持一致、克制的展示，不增加 `?N`、待确认数量或额外状态行。

## 非目标

- 不要求用户把每位参会人加入联系人库。
- 不建立“待确认联系人”的任务、提醒或红点系统。
- 不在 Flash 完成后自动弹出联系人选择器。
- 不新增 `pending`、`name_only` 等持久化状态。
- 不在日历流/月视图中展示 attendee 关联状态。

## 核心语义

`event_attendees.contact_id == null` 是一种长期合法状态，表示“这个名字属于本次日程，但没有关联到用户联系人库”。它不代表数据错误，也不代表用户必须处理。

未关联 attendee 保留：

```text
name_raw = 用户原始称呼
contact_id = null
```

已关联 attendee 使用联系人作为展示真值，同时继续保留可读的原始名字作为解绑兜底。

## Flash 创建规则

对于每个去重后的参会人原始称呼：

1. 按完整名字查询联系人。
2. 只有一个 exact match 时写入 `contact_id`。
3. exact match 为零或大于一个时，仅写入 `name_raw`。
4. 不因 event attendee 自动创建联系人。

例如联系人库同时存在 Google Kevin 和 abccc Kevin 时：

```text
输入：下午 5–6 点和 Kevin 在 3 楼会议室讨论未来 roadmap

event:
  start_at: 17:00
  end_at: 18:00
  location: 3 楼会议室

attendee:
  name_raw: Kevin
  contact_id: null
```

## UI 设计

### 方案取舍

- **采用：卡片无特殊标识，详情内弱提示。** 保持两行卡片信息密度，用户需要时仍能完成关联。
- **不采用：在人名后显示 `?`。** 卡片只展示第一位名字和 `+N`，隐藏 attendee 的状态无法被准确表达。
- **不采用：卡片显示 `?N` / “N 位待确认”。** 会挤占唯一摘要行，并把可选的联系人整理误导成待办任务。
- **不采用：Flash 后自动要求选择。** 会打断快速记录，而且一次性或低频日程通常不值得强制整理联系人。

### EventCard

完整 EventCard 继续使用现有两行结构，不增加待确认标识：

```text
未来 Roadmap 讨论
17:00–18:00 · 3楼会议室 · Kevin +2
```

摘要只表达参会人规模，不表达逐人关联状态。Flash 结果、资产库和每日详情中的完整 EventCard 使用相同规则。

### 日历流/月

继续使用紧凑单行 event item，不展示 attendee meta 或关联状态：

```text
17:00  📅 未来 Roadmap 讨论
```

### Event 详情与编辑

详情与编辑页完整列出 attendees。未关联 attendee 使用弱提示文案“未关联联系人”，不使用“待确认”：

```text
Kevin
未关联联系人                         关联
```

已关联 attendee 显示联系人副信息：

```text
Kevin
Google · 工程师
```

“关联”是可选操作，不使用警告色、未读红点或强提醒样式。

### 关联联系人

点击“关联”后打开单选联系人 sheet：

1. 搜索框自动填入 attendee 的 `name_raw`，立即触发搜索。
2. 重名结果展示公司、职位、电话等副信息，由用户选择具体联系人。
3. 没有结果时提供“新增联系人”入口；姓名默认预填当前 `name_raw`。
4. 选择或创建成功后，PATCH 当前 attendee 的 `contact_id`，不新建第二条 attendee。
5. 用户关闭 sheet 时不改变 attendee，原名字继续有效。

## 状态变化

```text
裸名 attendee
  ├─ 用户选择已有联系人 → 已关联 attendee
  ├─ 用户新增联系人     → 已关联 attendee
  └─ 用户不处理         → 永久保留裸名 attendee

已关联 attendee
  └─ 联系人被删除       → 保留可读名字并回到裸名 attendee
```

移除 attendee 只删除 `event_attendees` 行，不删除联系人。

## 错误处理

- 联系人搜索失败：sheet 内显示重试，不影响 event 和 attendee。
- 绑定 PATCH 失败：保留原来的裸名 attendee，显示轻量错误提示，可重试。
- 新增联系人成功但绑定失败：联系人保留；attendee 仍为裸名，并允许再次关联。
- 联系人已被其他操作删除：刷新候选并提示重新选择。

## 验收标准

- 0 个 exact match 时，Flash 创建裸名 attendee，不创建联系人。
- 2 个及以上 exact match 时，Flash 创建裸名 attendee，不随机绑定。
- 卡片仅显示正常 attendee 摘要，不显示 `?`、`?N` 或“待确认”。
- 日历流/月保持单行 event item。
- Event 详情和编辑页对裸名 attendee 显示“未关联联系人”和“关联”。
- 点击“关联”会以当前名字自动搜索。
- 重名候选可以通过公司、职位、电话区分并绑定正确 `contact_id`。
- 搜索无结果时可以新建联系人并绑定原 attendee。
- 用户不做任何关联操作时，event 的查看、编辑和提醒均不受影响。
