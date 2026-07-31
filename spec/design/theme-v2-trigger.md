# Design: Theme V2 Trigger（Workflow 触发系统）

> 日期：2026-07-31
>
> 状态：**READY FOR HANDOFF · 产品与底层边界已确认，尚未实施**
>
> 范围：Theme V2 Service 中 Trigger 的定义、Tracker、Execution、积累型报告触发、会前报告触发、Dismiss、消费、可靠性与 API 契约。
> 本稿不定义 Rhythm Reminder、Nudge、Offer、报告内容生成或前端布局。

---

## 0. 一页结论

Trigger 是独立的 Workflow 触发系统：

```text
领域事件或时间信号
→ Trigger 规则判断
→ TriggerExecution
→ Notification
→ 用户点击
→ 目标 Workflow 消费 Execution
```

Trigger 不等于 Notification：

- Trigger 判断“现在是否值得启动某个 Workflow”。
- Notification 只告诉用户“有一件事值得关注”。
- Notification 可以由非 Trigger 生产者直接发布。

Trigger 不等于 Report：

- Trigger 命中只创建内部 TriggerExecution。
- 用户不点击，就不会创建 ReportGenerationRun。
- TriggerExecution 不进入 Report 容器。

Phase 1 只实现两个 Trigger：

```text
proactive-summary-trigger
pre-event-report-trigger
```

核心规则：

```text
积累型报告：
至少 7 天 + 至少 7 条新 Assets
→ report_available

未点击：
下一自然日第一条新 Asset 到来时可以再次提醒

dismiss：
至少 7 天不再提醒；Assets 继续累计

所有 scheduled、非全天 Event：
T-1h 产生一次会前报告建议
```

Trigger Phase 1 不调用 Agent，不选择 Template，不执行 Web Search。

通知契约见 [Theme V2 Notification](theme-v2-notification.md)，后续 Workflow 见 [Theme V2 Report Generation](theme-v2-report-generation.md)。

---

## 1. 服务与范围

### 1.1 Greenfield Theme V2 Service

本稿属于一套全新的 Theme V2 Service：

```text
UserSkill / Asset / Event
+ Notification / Trigger / Report
```

服务使用新的数据库并直接拥有 UserSkill、Asset、Event。Trigger 与 Asset 创建可以在同一服务和数据库事务边界内协作。

本稿不考虑：

- 旧后端兼容。
- 旧数据迁移。
- RhythmProfile。
- Nudge / Offer。
- 旧积累规则。
- 旧 Report Dispatcher。

### 1.2 Trigger Definition

Trigger Definition 在 Phase 1 由代码注册，不建立 `trigger_definitions` 数据表：

```text
trigger_type
signal_type
evaluator
workflow_type
notification_factory
```

Phase 1：

| Trigger | 信号 | Evaluator | Workflow |
|---|---|---|---|
| `proactive_summary` | `AssetCreated` | 确定性规则 | `report_generation` |
| `pre_event_report` | 时间 Scheduler / Event 变更 | 确定性规则 | `report_generation` |

以后可以增加不同规则和不同 Workflow，但不得要求所有 Trigger 都只能启动 Report。

### 1.3 Trigger 不负责

Trigger 不：

- 运行 Report Planner。
- 选择 Template。
- 发现关联 Skills。
- 搜索 Web。
- 生成报告内容或插图。
- 创建 Report。
- 修改用户 Asset。
- 保存用户可见的“待生成报告”。

---

## 2. 核心对象

### 2.1 TriggerTracker

TriggerTracker 保存持续变化的规则状态，Phase 1 主要服务积累型报告。

```text
TriggerTracker
- id: UUID
- user_id: string
- trigger_type: string
- scope_type: string
- scope_id: UUID

- cycle_started_at: timestamptz
- new_asset_count: integer
- active_execution_id: UUID nullable

- last_notified_at: timestamptz nullable
- last_notified_local_date: date nullable
- dismissed_until: timestamptz nullable
- proactive_suppressed_until: timestamptz nullable
- last_consumed_at: timestamptz nullable

- metadata_json: JSON
- created_at: timestamptz
- updated_at: timestamptz
```

积累型 Scope：

```text
scope_type = user_skill
scope_id = user_skill_id
```

约束：

```text
UNIQUE(user_id, trigger_type, scope_type, scope_id)
```

它回答：

> 这个 Skill 的主动报告周期从什么时候开始、已经新增多少条、当前是否有可消费的 Execution、是否处于 Dismiss 或主动冷却期。

### 2.2 TriggerExecution

TriggerExecution 保存某个 Workflow 可以消费的内部启动上下文。

```text
TriggerExecution
- id: UUID
- user_id: string
- trigger_type: string
- workflow_type: string

- tracker_id: UUID nullable
- scope_type: string
- scope_id: UUID

- status: available | consumed | expired
- dedupe_key: string
- revision: integer
- payload_json: JSON

- first_fired_at: timestamptz
- last_fired_at: timestamptz
- last_notified_revision: integer nullable
- consumed_at: timestamptz nullable
- expires_at: timestamptz nullable

- workflow_run_id: UUID nullable
- created_at: timestamptz
- updated_at: timestamptz
```

约束：

```text
UNIQUE(dedupe_key)
INDEX(user_id, status, created_at)
INDEX(tracker_id, status)
```

TriggerExecution 是内部实体：

- 不在 Report 容器展示。
- 不提供用户列表 API。
- 不表示报告正在生成。
- `available` 只表示可以被目标 Workflow 消费。

---

## 3. Asset 引用原则

Trigger 只保存 Asset ID，不保存内容快照：

```text
payload_json.asset_ids = [asset_id...]
```

规则：

- Asset 创建后加入当前 Tracker / Execution。
- Asset 内容更新不增加计数，不要求更新 TriggerExecution。
- Report Planner 和 Pipeline 按 ID 读取最新内容。
- Asset 删除后，ID 可以保留在 Execution 中；下游读取时过滤不存在或无权限的 ID。
- Trigger 统计基于 `AssetCreated`，不是 Asset 内容中的业务日期变更。
- 用户最终可以在 Report Generation 中调整时间范围和 Asset 引用。

同一 AssetCreated 信号重复处理时：

```text
asset_id 已存在于当前周期
→ 不增加 new_asset_count
→ 不增加 revision
→ 不再次通知
```

Phase 1 可以在 `metadata_json.counted_asset_ids` 中记录已计入 ID，或使用等价的关系表；产品契约是同一 Asset 在同一周期只能计数一次。

---

## 4. `proactive-summary-trigger`

### 4.1 Scope

一个 Tracker 对应：

```text
user_id + user_skill_id
```

系统不依赖固定 Skill Key：

```text
baby_feeding
baby_growth
expense
idea
```

都不是 Trigger 的硬编码前提。Trigger 只知道 UserSkill 和新增 Assets；Template 选择由用户点击后的 Report Planner 完成。

### 4.2 初次命中条件

Phase 1 使用两个条件同时满足：

```text
cycle_age >= 7 days
AND
new_asset_count >= 7
```

例子：

| 情况 | 是否触发 |
|---|---|
| 2 天记录 7 条 | 否，跨度不足 |
| 7 天记录 3 条 | 否，数量不足 |
| 第 7 天记录第 7 条 | 是 |
| 第 20 天累计第 7 条 | 是，默认范围为这 20 天 |

判断发生在 `AssetCreated`：

- 不建立“第七天准时唤醒”的额外 Scheduler。
- 如果用户第 2 天已有 7 条，之后停止记录，第 7 天不会突然推送。
- 用户再次创建 Asset 时重新判断。

参数在代码中作为 Trigger 配置保存，未来可以内部调整；Phase 1 不向用户暴露配置。

### 4.3 初次命中

命中后创建：

```text
TriggerExecution.status = available
TriggerExecution.revision = 1
TriggerTracker.active_execution_id = execution.id
```

Payload：

```json
{
  "primary_skill_id": "user-skill-id",
  "asset_ids": ["asset-1", "asset-2"],
  "scope_started_at": "2026-07-01T00:00:00Z",
  "scope_ended_at": "2026-07-07T12:00:00Z",
  "asset_count": 7
}
```

发布：

```text
Notification.type = report_available
Notification.link = report-start:<execution_id>:1
```

### 4.4 未点击后的再次提醒

用户没有点击时，Execution 仍然 `available`，不创建 ReportGenerationRun。

后续 AssetCreated：

```text
把 Asset ID 加入当前 Execution
→ asset_count + 1
→ scope_ended_at 更新
→ revision + 1
```

如果满足：

```text
当前不在 dismissed_until
AND 当前不在 proactive_suppressed_until
AND 本地自然日 != last_notified_local_date
```

则发布本自然日的新提醒：

```text
report-start:<execution_id>:<revision>
```

Phase 1 的固定防打扰规则：

> 达到初始阈值后，用户未点击也未 Dismiss 时，每个用户自然日最多在第一条新增 Asset 到来时提醒一次。

没有新增 Asset，就不因时间经过而重复提醒。

例子：

```text
第 7 天：7 条 → Notification
第 8 天：新增 1 条 → 更新为 8 条 → Notification
第 8 天：再新增 3 条 → 更新为 11 条，但不再发当天第二条 Notification
```

### 4.5 Dismiss

用户明确 Dismiss 报告建议：

```http
POST /api/trigger-executions/{id}/dismiss
```

效果：

```text
TriggerTracker.dismissed_until = now + 7 days
```

规则：

- Execution 保持 `available`。
- Assets 继续加入当前周期。
- 七天内不再产生 Notification。
- 七天后不会仅因时间到了自动推送。
- 七天后第一条新 Asset 到来时恢复判断和提醒。

客户端随后使用现有 Notification Delete API 删除当前通知。Notification Service 不解释 Dismiss 语义。

### 4.6 用户点击

用户点击任意 Revision 的 Notification：

```text
Report Generation Service
→ 按 execution_id 读取当前最新 Execution
→ 原子消费
```

事务内：

```text
TriggerExecution.status: available → consumed
TriggerExecution.consumed_at = now
TriggerExecution.workflow_run_id = run.id

TriggerTracker.active_execution_id = null
TriggerTracker.last_consumed_at = now
TriggerTracker.proactive_suppressed_until = now + 7 days
TriggerTracker.cycle_started_at = now
TriggerTracker.new_asset_count = 0
清空当前周期 counted_asset_ids
```

点击后创建的 ReportGenerationRun 使用消费当时 Execution 中的 Asset ID 引用。

用户点击以后新创建的 Assets 进入下一轮周期。

七天冷却从消费 Execution 时开始，不等待最终报告生成。Report Planner、Pipeline 的成功、失败或取消由 Report Generation 自己管理。

### 4.7 用户主动报告完全隔离

```text
ReportGenerationRun.origin = user_initiated
```

不得：

- 读取 Trigger 冷却来阻止用户生成。
- 修改 TriggerTracker。
- 重置 `new_asset_count`。
- 修改 `cycle_started_at`。
- 设置主动报告冷却。

例子：

```text
第 3 天用户主动生成宝宝阶段分析
→ 正常生成

第 7 天主动报告 Trigger 条件满足
→ 仍然发布宝宝周报建议
```

即使两份报告引用了部分相同 Assets，也不合并，因为用户主动查询和系统阶段性建议是两个不同意图。

---

## 5. `pre-event-report-trigger`

### 5.1 准入条件

Phase 1 不使用 Agent Evaluate。所有符合以下条件的 Event 都触发一次：

```text
status = scheduled
AND all_day = false
AND start_at > now
```

不要求：

- Description。
- Attendee。
- 附件。
- 关联 Session。
- Meeting Keyword。
- Agent 判断。

这些信息存在时由 Report Planner 在用户点击后使用。

### 5.2 触发时间

```text
T-1h
```

Scheduler 扫描即将开始的 Event，在开始前一小时创建 TriggerExecution。

如果 Event 创建时距离开始不足一小时：

- 只要尚未开始，立即触发一次。
- 已开始或已结束，不触发。

### 5.3 Execution

Payload：

```json
{
  "event_id": "event-id",
  "event_start_at": "2026-07-31T14:00:00+08:00",
  "event_title": "和张总讨论合作"
}
```

数据仍以 `event_id` 为引用；Planner 读取 Event 最新内容。

Dedupe：

```text
pre_event_report:<event_id>:<start_at>
```

Notification：

```text
type = report_available
title = “和张总讨论合作”将在 1 小时后开始
body = 需要准备一份会前调研吗？
link = report-start:<execution_id>:1
```

### 5.4 与普通 Event Reminder 的关系

这条 `report_available` 同时承担 T-60 日程提醒：

```text
T-60
→ 只发 pre-event report_available

T-30 / T-15
→ 可以继续发普通 reminder
```

同一个 Event 在 T-60 不得同时收到两条通知。

### 5.5 Event 变化

取消：

```text
status = cancelled
→ 未消费 Execution.status = expired
```

改期：

```text
start_at 变化
→ 旧 start_at 对应 Execution.expired
→ 按新 start_at 重新建立 Dedupe 和触发时间
```

开始：

```text
now >= event.start_at
→ 未消费 Execution.expired
```

一个 Event 只主动建议一次，不做未点击后的重复提醒。

---

## 6. Workflow 消费契约

Trigger 不提供独立的通用 `/consume` API。消费必须由目标 Workflow 在创建 Run 的同一个事务中完成。

Report Generation 调用：

```http
POST /api/report-generation-runs
```

```json
{
  "origin": "trigger",
  "trigger_execution_id": "execution-id"
}
```

事务内：

1. 验证 Execution 属于当前用户。
2. 验证 `workflow_type = report_generation`。
3. 验证 `status`。
4. 验证未过期。
5. 创建或复用 ReportGenerationRun。
6. 写入 `workflow_run_id`。
7. 标记 `consumed`。
8. 更新 Tracker；Event Trigger 没有 Tracker 时跳过。

幂等行为：

```text
available
→ 创建 Run 并消费

consumed + workflow_run_id
→ 返回已有 Run

expired
→ 410 Gone

不属于当前用户
→ 404
```

---

## 7. Dismiss API

```http
POST /api/trigger-executions/{execution_id}/dismiss
```

规则：

- 只允许当前用户操作。
- 只对 `proactive_summary` 生效。
- `available` 时写入 Tracker `dismissed_until = now + 7 days`。
- 重复调用幂等，可以把起点更新为最近一次明确 Dismiss 时间。
- `consumed` 返回当前 Run，不回退状态。
- `expired` 返回 `410 Gone`。
- `pre_event_report` 不需要七天 Dismiss；用户不点击即自然过期。

---

## 8. 可靠性与并发

### 8.1 AssetCreated 执行

Asset 创建成功后：

```text
锁定对应 TriggerTracker
→ 检查 Asset ID 是否已计入
→ 更新 Tracker 和 active Execution
→ 判断是否需要 Notification
→ commit
→ 发布 Notification
```

Phase 1 的 Tracker 更新必须足够轻量，不调用 Agent 或外部服务。

### 8.2 Tracker 锁

使用行锁或等价原子更新：

```sql
SELECT ... FOR UPDATE
```

保证并发创建多条 Assets 时：

- 不产生多个 Tracker。
- 不产生多个 active Execution。
- 同一 Asset 不重复计数。
- 每个自然日最多发布一次未点击提醒。

### 8.3 Notification Revision 去重

Link：

```text
report-start:<execution_id>:<revision>
```

发布前按：

```text
user_id + type=report_available + link
```

查询。

执行结果：

- 相同 Revision 已存在：视为发布成功，只补写 `last_notified_revision`。
- 新 Revision：创建新 Notification。
- Notification 创建失败：不更新 `last_notified_revision`，后续重试。

### 8.4 补偿扫描

周期任务扫描：

- `available` 且应通知、但 `last_notified_revision < revision` 的 Execution。
- 已开始、取消或改期但仍 `available` 的 Event Execution。
- Tracker 与 active Execution 引用不一致的异常状态。

补偿必须遵守相同 Dedupe 和自然日规则。

Phase 1 不要求 Redis 或外部消息队列。

---

## 9. 安全与权限

- 所有 Execution 和 Tracker 都按 `user_id` 隔离。
- 外部客户端不能列出 TriggerTracker。
- 外部客户端不能列出 TriggerExecution。
- 用户只能通过 Notification Link 或已有 Workflow Run 操作自己的 Execution。
- 越权 Execution ID 返回 `404`。
- Trigger Payload 不包含完整 Asset 内容。
- Trigger Notification 不包含 Asset ID 列表或敏感 Payload。
- 服务日志只记录 Trigger Type、Execution ID、计数、状态和时间，不记录 Asset 内容。

---

## 10. Observability

基础指标：

```text
trigger_evaluated_total
trigger_fired_total
trigger_notification_total
trigger_consumed_total
trigger_dismissed_total
trigger_expired_total
trigger_compensation_total
```

按以下维度聚合：

```text
trigger_type
result
error_code
```

不按用户原文、Skill 名称或 Asset Payload 聚合。

关键转化：

```text
proactive_summary Notification → consumed
pre_event_report Notification → consumed
dismiss rate
expired rate
```

---

## 11. 非目标

Phase 1 不包含：

- Rhythm Profile。
- “该记账了”“该喝水了”等节律提醒。
- Nudge / Offer / Candidate。
- Trigger Agent Evaluate。
- 根据 Event Description 判断是否值得调研。
- Trigger Template 匹配。
- Asset Embedding 或向量数据库。
- 用户可配置 Trigger 阈值。
- 每个 Skill 自定义提醒频率。
- Trigger UI 或管理页。
- 未点击 Event 报告建议的重复提醒。
- 用户主动报告与主动 Trigger 的合并或去重。

---

## 12. 验收场景

### 12.1 初次积累触发

```text
第 7 天创建第 7 条 Asset
→ 创建一个 TriggerExecution
→ 创建一条 report_available Notification
```

### 12.2 时间不足

```text
第 2 天已有 7 条 Asset
→ 不触发
```

### 12.3 数量不足

```text
第 14 天只有 6 条 Asset
→ 不触发
```

### 12.4 第 20 天达到数量

```text
第 20 天创建第 7 条 Asset
→ 触发
→ 默认 Scope 为该周期 20 天
```

### 12.5 未点击再次提醒

```text
第 7 天：7 条 → Notification
第 8 天：第 8 条 → Revision 更新 → 新 Notification
第 8 天：继续新增 → 不发当天第二条
```

### 12.6 Dismiss

```text
第 8 天 Dismiss
→ dismissed_until + 7 days
→ 中间 Assets 继续累计但不提醒
→ 七天后第一条新 Asset 到来时恢复提醒
```

### 12.7 用户不点击

TriggerExecution 存在，但：

- 不创建 ReportGenerationRun。
- 不进入 Report 容器。
- 不执行 Planner。
- 不产生 Token 消耗。

### 12.8 用户点击

重复点击同一个或不同 Revision：

- 只产生一个 ReportGenerationRun。
- 返回同一个 `workflow_run_id`。
- Tracker 从点击时间开始下一周期。

### 12.9 手动报告隔离

第 3 天手动生成报告，不改变第 7 天的积累型 Trigger。

### 12.10 自定义 Skill

Skill 没有固定 Baby、Expense 或 Idea Key，仍可按 UserSkill ID 和 Asset 数量触发。

### 12.11 Event

所有 scheduled、非全天 Event 在 T-1h 触发一次；没有 Description、Attendee 或附件也不影响。

### 12.12 Event 改期

修改 `start_at`：

- 旧 Execution 过期。
- 新时间生成新的 Dedupe。
- 不在旧时间重复通知。

### 12.13 T-60 去重

同一个 Event 在 T-60 只有 `report_available`，没有第二条普通 Reminder。

### 12.14 并发

同一 Skill 同时创建多条 Assets：

- 计数准确。
- 只有一个 active Execution。
- 每个自然日最多一条未点击提醒。

### 12.15 Notification 发布失败

Execution 已提交但 Notification 失败：

- 不丢失 Execution。
- 后续补偿成功。
- 不产生重复 Notification。
