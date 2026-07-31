# Design: Theme V2 Notification（统一通知能力）

> 日期：2026-07-31
>
> 状态：**READY FOR HANDOFF · 产品与底层边界已确认，尚未实施**
>
> 范围：Theme V2 Service 中 Notification 的数据模型、发布、历史、已读、删除、SSE、Deep Link 与报告相关通知类型。
> 本稿不定义通知中心、浮球、卡片、系统推送或其他前端布局。

---

## 0. 一页结论

Theme V2 Notification 是一个轻量、独立的系统级通知能力：

```text
任意领域服务或后台任务
→ create_notification(type, title, body, link)
→ 持久化 Notification
→ SSE 推送
→ 客户端展示、已读或删除
```

Notification 只回答两个问题：

1. 发生了什么。
2. 用户点击后应跳转到哪里。

Notification 不负责：

- 判断是否应该触发某项业务。
- 保存 Trigger、Workflow、Report、Todo 或 Event 的真实状态。
- 执行业务动作。
- 携带复杂 Workflow Input。
- 记录用户对某类业务的偏好或冷却。

核心数据结构保持简单：

```text
id
user_id
type
title
body
link
read
created_at
```

报告系统新增四种通知：

```text
report_available
report_plan_ready
report_done
report_failed
```

Notification 与 Trigger、Report Generation 的完整关系分别见：

- [Theme V2 Trigger](theme-v2-trigger.md)
- [Theme V2 Report Generation](theme-v2-report-generation.md)
- [Theme V2 独立服务运行时设计](../../docs/superpowers/specs/2026-07-31-theme-v2-service-runtime-design.md)

---

## 1. 服务边界

### 1.1 Notification 是通用容器

以下生产者都可以发布 Notification：

```text
Trigger
Report Planner
Report Pipeline
Todo Reminder Scheduler
Event Reminder Scheduler
后台 Task Executor
其他领域服务
```

Notification 不要求生产者必须是 Trigger，也不建立 `trigger_id`、`workflow_id` 或 `source_type` 外键。

例如：

```text
Todo 到期
→ Reminder Scheduler 直接发布 Notification

Report Planner 完成
→ Report Workflow 直接发布 Notification

Asset 达到报告阈值
→ Trigger 发布 Notification
```

### 1.2 Notification 不拥有业务状态

以下状态归对应领域实体所有：

| 状态 | 真值实体 |
|---|---|
| 报告是否可以启动 | `TriggerExecution` |
| Planner 是否完成 | `ReportGenerationRun` |
| 报告是否生成成功 | `ReportGenerationRun` / `Report` |
| Todo 是否完成 | Todo / Asset |
| Event 是否取消或改期 | Event |

Notification 被已读或删除，不改变上述状态。

Notification 内容也不能作为业务判断依据。客户端点击后必须由目标服务再次校验：

- 用户权限。
- 目标是否存在。
- TriggerExecution 是否过期。
- ReportGenerationRun 当前状态。
- Report 是否已经完成。

### 1.3 不引入通用 Action 模型

Phase 1 不增加：

```text
target_type
action_type
action_payload
source_type
source_id
workflow_id
trigger_id
notification_preferences
```

`link` 继续作为不透明 Deep Link，由客户端按 `type + link` 解析。

---

## 2. 数据模型

```text
Notification
- id: UUID
- user_id: string
- type: string(32)
- title: string(255)
- body: text nullable
- link: string(255) nullable
- read: boolean default false
- created_at: timestamptz
```

索引：

```text
INDEX(user_id, created_at DESC)
INDEX(user_id, read, created_at DESC)
```

约束：

- `title` 必填，服务端截断到 255 字符。
- `body` 可以为空。
- `link` 可以为空；无 Link 的通知只展示，不可跳转。
- `type` 是可扩展字符串，不在数据库中做硬编码 Enum。
- Notification 创建后，除 `read` 外不修改内容。
- 用户显式删除时物理删除该行。

### 2.1 保留窗口

Notification 保留 14 天：

```text
created_at < now - 14 days
→ prune
```

清理可以在创建通知后异步执行，也可以由周期任务批量执行。保留窗口按时间计算，不按数量计算。

客户端最多拉取最近 100 条；数据库保留窗口内可以多于 100 条。

---

## 3. 通知类型

### 3.1 通用既有类型

Theme V2 Service 可以继续使用以下通用类型：

```text
flash_done
task_done
task_failed
reminder
```

具体领域可以新增类型，但不得要求 Notification Service 理解其业务含义。

### 3.2 报告相关类型

#### `report_available`

表示某个 TriggerExecution 可以启动 Report Generation：

```text
title: 已经积累了 8 条宝宝记录，可以生成报告了
body: 7 月 1 日—7 月 8 日
link: report-start:<trigger_execution_id>:<revision>
```

点击后由 Report Generation API 消费 TriggerExecution。Notification 本身不启动 Workflow。

#### `report_plan_ready`

表示 Report Planner 已经产生需要用户处理的当前决策：

```text
title: 报告方案已经准备好了
body: 可以选择报告方向和使用的数据
link: report-run:<report_generation_run_id>
```

当 `pending_decision.type = clarification` 时，文案可以改为：

```text
还需要你补充一个信息，才能完成报告方案
```

Notification 类型保持不变。

#### `report_done`

表示最终 Report 已成功持久化：

```text
title: 宝宝两周成长报告已经生成
link: report:<report_id>
```

必须在 `Report` 和 `ReportGenerationRun.completed` 成功提交后发布。

#### `report_failed`

表示 Planner 或 Report Pipeline 出现需要用户处理的致命失败：

```text
title: 报告生成没有完成
body: 可以打开查看并重试
link: report-run:<report_generation_run_id>
```

Optional Web Search 降级、插图失败等非致命情况不发布 `report_failed`。

---

## 4. Deep Link 契约

Phase 1 使用以下 Link：

```text
report-start:<trigger_execution_id>:<revision>
report-run:<report_generation_run_id>
report:<report_id>
reminder:event:<event_id>:<threshold>
reminder:todo:<asset_id>:<threshold>
```

规则：

- Link 是客户端路由契约，不是授权凭据。
- 客户端不得只凭 Link 中的 ID 展示私有数据。
- 所有目标 API 都必须按当前用户重新做 Ownership 检查。
- Link 解析失败时，客户端把通知当作普通不可跳转通知展示。
- 旧 Revision 的 `report-start` Link 仍解析同一个 TriggerExecution；目标服务读取 Execution 当前状态。

公开 Report Share 不使用 Notification Link 中的 `report_id`。公开分享安全模型见 [Theme V2 Report Generation](theme-v2-report-generation.md)。

---

## 5. 发布契约

领域服务通过内部方法发布：

```python
create_notification(
    user_id: str,
    type: str,
    title: str,
    body: str = "",
    link: str | None = None,
) -> NotificationPayload
```

执行顺序：

```text
持久化 Notification
→ commit
→ serialize
→ SSE publish
```

规则：

- SSE 推送失败不能回滚已经持久化的 Notification。
- 慢消费者队列已满时可以丢弃实时帧；客户端重新拉取历史即可恢复。
- 业务实体必须先提交，再发布对应 Notification。
- 创建通知失败不能回滚已经完成的 Report 或 Task，但生产者必须保留可补偿状态。
- 需要严格去重的生产者应在发布前按 `user_id + type + link` 查询，或使用自身 Revision / Dedupe 状态；Notification 表不增加通用 Dedupe 字段。

### 5.1 Report Notification 去重

Trigger 通过 Revision 形成不同 Link：

```text
report-start:exec-123:1
report-start:exec-123:2
```

同一 Revision 重试时检查是否已有相同 `type + link`；新 Revision 可以正常产生下一条提醒。

Report Planner、Pipeline 通过 Run 当前状态和目标 Link 防止重复发布：

```text
report_plan_ready + report-run:<run_id>
report_done + report:<report_id>
report_failed + report-run:<run_id>
```

---

## 6. API

### 6.1 列表

```http
GET /api/notifications?limit=30
```

约束：

- `limit` 默认 30，最大 100。
- 只返回当前用户的 Notification。
- 按 `created_at DESC` 排序。
- 同时返回未读数。

响应：

```json
{
  "notifications": [
    {
      "id": "notification-id",
      "type": "report_plan_ready",
      "title": "报告方案已经准备好了",
      "body": "可以选择报告方向和使用的数据",
      "link": "report-run:run-id",
      "read": false,
      "created_at": "2026-07-31T10:00:00Z"
    }
  ],
  "unread": 1
}
```

Phase 1 不提供游标分页；通知历史仅用于最近 14 天的一屏回溯。

### 6.2 标记单条已读

```http
POST /api/notifications/{notification_id}/read
```

- 只允许操作当前用户的 Notification。
- 重复调用幂等。
- 不改变目标业务状态。

### 6.3 全部已读

```http
POST /api/notifications/read-all
```

只更新当前用户未读 Notification。

### 6.4 删除

```http
DELETE /api/notifications/{notification_id}
```

- 物理删除当前用户的 Notification。
- 重复删除幂等。
- 删除普通 Notification 不影响任何领域实体。
- 删除 `report_available` 时，如果用户选择的是业务意义上的 dismiss，客户端必须先调用 Trigger Dismiss API，再调用本接口。Notification Service 不解释该语义。

### 6.5 SSE

```http
GET /api/notifications/stream
```

行为：

- 需要登录。
- 每条新 Notification 推送一个 `notification` 事件。
- 带心跳，防止代理和移动网络静默断开。
- 断线重连后，客户端调用列表 API 恢复可能错过的通知。
- Phase 1 固定使用 MySQL Transactional Outbox：Notification 与
  `OutboxEvent(notification.created)` 在同一事务写入，单实例 API 轮询
  Outbox 并广播到本进程的 SSE Subscriber Registry。
- API 在推送后再标记 Outbox 已发布，因此极端崩溃窗口允许重复帧；
  客户端按 Notification ID 去重。
- Worker 不调用 API 容器，也不依赖进程内事件跨越 API / Worker 边界。
- Phase 1 不引入 Redis；多 API 实例不属于本阶段部署拓扑。

---

## 7. Dismiss 与领域反馈

Notification 删除不等于业务 Dismiss。

积累型报告建议的完整操作是：

```text
POST /api/trigger-executions/{id}/dismiss
→ TriggerTracker.dismissed_until = now + 7 days

DELETE /api/notifications/{notification_id}
→ 从通知历史移除
```

如果用户只是没有点击 Notification：

- Notification 保留在最近 14 天历史中。
- Trigger 仍可以在下一自然日有新 Asset 时再次提醒。

如果用户只是标记已读：

- 不改变 Trigger 冷却。
- 不消费 TriggerExecution。

---

## 8. 安全与隐私

- 所有私有 API 和 SSE 都必须校验登录态。
- 读取、已读、删除只能作用于 `notification.user_id = current_user_id`。
- 非法或越权 ID 返回 `404`，不暴露对象是否存在。
- Notification 文案不得包含完整敏感记录、账号、地址或大段用户原文。
- Notification Link 不包含 Asset ID 列表或复杂 Payload。
- Error Notification 不包含内部堆栈、模型供应商响应或 Prompt。
- 服务日志不输出 Notification Body 中的敏感内容。

---

## 9. 与其他模块的关系

### 9.1 Trigger

Trigger 命中后：

```text
TriggerExecution
→ create_notification(report_available)
```

Notification 不反向读取 TriggerTracker。具体见 [Theme V2 Trigger](theme-v2-trigger.md)。

### 9.2 Report Generation

Report Planner 或 Pipeline 状态提交后：

```text
awaiting_selection
→ report_plan_ready

completed
→ report_done

failed
→ report_failed
```

具体见 [Theme V2 Report Generation](theme-v2-report-generation.md)。

### 9.3 Reminder Scheduler

Todo 和 Event 普通提醒可以直接发布 `reminder`：

```text
Reminder Scheduler
→ Notification
```

不要求先创建 TriggerExecution。

Event T-60 的普通 Reminder 由 `pre-event-report-trigger` 的 `report_available` 代替，避免同一分钟发送两条重复通知；T-30、T-15 普通提醒仍可保留。

---

## 10. 非目标

Phase 1 不包含：

- Notification 模板编辑器。
- 用户级通知频率配置。
- 通知来源订阅系统。
- 通用 Action / Candidate / Offer 实体。
- Rhythm Reminder。
- Nudge 状态机。
- 手机系统 Push Provider 的具体接入。
- Email、短信或第三方消息渠道。
- 通知中心的视觉与交互设计。
- Notification 与公开 Report Share 的统一链接系统。

---

## 11. 验收标准

1. 任意领域服务可以用同一个 `create_notification` 发布持久化通知。
2. Notification 创建成功后可通过列表 API 和 SSE 获取。
3. SSE 丢帧后重新拉取列表可以恢复。
4. 已读和全部已读不改变目标业务状态。
5. 删除 Notification 不删除 Report、Run、TriggerExecution、Todo 或 Event。
6. `report_available` 可以跳转到对应 TriggerExecution，但 Link 本身不能绕过权限。
7. 同一个 Trigger Revision 重试不会产生重复 Notification。
8. 新 Revision 可以创建新的 Notification。
9. `report_plan_ready` 只在 Run 成功进入 `awaiting_selection` 后发布。
10. `report_done` 只在 Report 和 Run 完成状态提交后发布。
11. Optional Web Search 或插图降级不会产生 `report_failed`。
12. 非法 Notification ID 和越权 ID 返回 `404`。
13. 14 天外 Notification 被清理。
14. 普通 Event 不会在 T-60 同时收到普通 Reminder 和会前报告两条通知。
