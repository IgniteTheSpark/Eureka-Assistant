# UReka Theme V2 独立服务运行时设计

> 日期：2026-07-31
>
> 状态：**架构边界已批准，等待文档终审后进入实施计划**
>
> 范围：Theme V2 Service 的代码隔离、Docker 拓扑、MySQL 事务边界、数据库 Job Queue、Transactional Outbox、SSE、存储、可靠性，以及四份最新 spec 的实施准入。

关联真值：

- `spec/design/theme-v2-trigger.md`
- `spec/design/theme-v2-notification.md`
- `spec/design/theme-v2-report-generation.md`
- `spec/design/theme-v2-today-handoff.md`
- `spec/design/docs/superpowers/plans/2026-07-31-remove-goals-home-adjustment.md`

---

## 1. 已确认决策

Theme V2 使用一套完全独立的运行时：

1. 新代码放在 `theme_v2_service/`，不在旧 `backend/` 内直接改造成 V2。
2. 新服务使用独立 Docker Compose 项目、网络、端口、数据库和数据卷。
3. 新数据库为空库，不迁移或读取旧数据库。
4. 旧 `backend/`、旧 Compose 和旧数据库卷保留，可停止但不删除，作为回退路径。
5. 延续 FastAPI、SQLAlchemy 2、Alembic、MySQL 8，不做框架级重构。
6. Phase 1 使用 **MySQL + Transactional Outbox + 数据库 Job Queue**。
7. Phase 1 不引入 Redis、Kafka、Celery 或独立消息代理。
8. API 与 Worker 使用同一份代码和同一个镜像，但以不同进程运行。
9. Phase 1 只运行一个 API 实例；Worker 的 Job 领取协议允许以后横向扩容。
10. Official Report Renderer 先作为同一代码库中的模块运行，不拆成独立微服务。

这些决策覆盖各业务 spec 中尚未明确的运行时选择。业务状态机、API 语义和产品行为仍以各自 spec 为准。

---

## 2. 目标与非目标

### 2.1 目标

- Theme V2 可以在不启动旧后端的情况下独立运行和开发。
- API、后台任务和实时通知之间没有进程内隐式依赖。
- 关键业务写入、Job 创建和通知发布都有可恢复的数据库真值。
- Trigger、Notification 和 Report Generation 可以在同一服务内按清晰事务边界协作。
- Docker 开发环境和生产部署沿用同一进程职责划分。
- 保留以后引入 Redis、对象存储或多 API 实例的替换点，但 Phase 1 不提前实现。

### 2.2 非目标

- 不拆微服务。
- 不把 Trigger、Notification、Report 分成不同数据库。
- 不复用旧 MySQL 容器、旧数据卷或旧 Alembic 历史。
- 不建立跨新旧后端的数据库连接、内部 HTTP 调用或双写。
- 不迁移旧 Report Dispatcher、Wish Pipeline、Nudge、Offer 或 Goal。
- 不在本设计中重新定义四份业务 spec 已确认的产品规则。

---

## 3. 代码与目录边界

目标结构：

```text
theme_v2_service/
├── app/
│   ├── main.py                  # FastAPI 入口
│   ├── worker.py                # Worker 入口
│   ├── api/                     # HTTP / SSE transport
│   ├── auth/                    # Bearer token 校验与当前用户
│   ├── domains/
│   │   ├── assets/
│   │   ├── events/
│   │   ├── notifications/
│   │   ├── triggers/
│   │   └── reports/
│   ├── jobs/                    # Job claim、lease、retry、scheduler
│   ├── outbox/                  # Outbox dispatcher 与 SSE fan-out
│   ├── rendering/               # Official Report Renderer
│   ├── storage/                 # local / S3-compatible adapter
│   └── db/
├── migrations/
├── templates/                   # 官方 Template Skill packages
├── tests/
│   ├── unit/
│   ├── integration/
│   └── contract/
├── Dockerfile
├── alembic.ini
└── requirements.txt

docker-compose.theme-v2.yml
.env.theme-v2.example
```

约束：

- `theme_v2_service/` 不 import `backend/` 中的运行时代码。
- 可以在实施时复制并重构稳定的小型工具，但复制后由 V2 自己拥有。
- 新 Alembic 从空白 revision 开始；旧迁移历史不能被复制为 V2 的前置依赖。
- 领域模块可以互相调用应用服务，但只能通过同一个 SQLAlchemy session 共享事务，不能自行 commit。
- `api/` 只负责鉴权、校验、序列化和调用应用服务，不承载领域状态机。

---

## 4. Docker 拓扑

基线 Compose 项目名为 `eureka-theme-v2`：

```text
eureka-theme-v2
├── mysql       MySQL 8.0
├── migrate     一次性 Alembic upgrade
├── api         FastAPI + SSE + Outbox dispatcher
└── worker      WorkflowJob + Trigger scheduler + compensation
```

建议的本机端口：

| 能力 | Theme V2 | 旧服务 |
|---|---:|---:|
| HTTP API | `8100` | `8000` |
| MySQL host port | `3307` | `3306` |

容器内部仍使用：

```text
mysql:3306
api:8000
```

Compose 约束：

- 不设置固定 `container_name`，由 Compose project name 形成隔离命名。
- MySQL 使用 project-scoped `mysql_data` volume。
- 本地媒体使用 project-scoped `media_data` volume，由 API 和 Worker 共同挂载。
- 不接入旧 Compose network，也不声明 external volume。
- `migrate` 等待 MySQL healthy，成功退出后 API 与 Worker 才启动。
- API、Worker 使用相同 build target 和镜像 digest。
- MySQL host port 仅绑定 `127.0.0.1`；生产环境不暴露数据库端口。
- 健康检查至少覆盖数据库连接、迁移版本和 API liveness/readiness。

旧环境允许执行：

```bash
docker compose stop
```

不得把下列命令作为 Theme V2 启动步骤：

```bash
docker compose down -v
```

因为旧数据卷仍是回退资产。

---

## 5. 进程职责

### 5.1 API

API 进程负责：

- REST API 与 Bearer token 校验。
- 所有用户数据的 ownership 检查。
- 短事务内的领域写入。
- Notification SSE 连接与心跳。
- 轮询 Outbox 并向本进程的 SSE Subscriber Registry fan-out。
- 私有 Report Viewer、公开 Share Viewer 和媒体授权入口。

Phase 1 保持单 API 实例。原因是 SSE Subscriber Registry 在进程内；Outbox 解决的是 Worker 到 API 的跨进程传递，不是多 API 实例广播。

### 5.2 Worker

Worker 进程负责：

- Report Planner Job。
- Report Pipeline Job。
- Trigger 的时间扫描与补偿扫描。
- Notification 保留窗口清理。
- Outbox、Job、临时媒体和过期 Share 的维护任务。
- Job lease 心跳、失败分类、重试和恢复。

Worker 不持有用户 SSE 连接，也不直接调用 API 容器。

### 5.3 Renderer

Renderer Phase 1 是 `theme_v2_service/app/rendering/` 中的可信模块：

- Pipeline Worker 调用它生成并持久化正式 Report。
- API 调用同一渲染契约读取私有或公开 Report。
- Renderer 不拥有单独数据库，也不通过内部 HTTP 与 Worker 通信。

当渲染负载或隔离要求出现真实证据时，才评估拆为独立服务。

---

## 6. MySQL 数据约定

数据库名建议使用 `eureka_theme_v2`，字符集为 `utf8mb4`。

跨 spec 的物理类型统一为：

| 逻辑类型 | MySQL 8 表达 |
|---|---|
| UUID | `CHAR(36)` |
| timestamptz | UTC `DATETIME(6)` |
| JSON | 原生 `JSON` |
| 可扩展状态/类型 | 有长度上限的 `VARCHAR` |
| local date | `DATE` |

规则：

- 数据库中的所有时间都写 UTC，API 使用带 `Z` 或明确 offset 的 ISO 8601。
- spec 中的 `timestamptz` 是逻辑语义，不表示改用 PostgreSQL。
- 自然日 Trigger 计算显式传入用户时区；Phase 1 缺省为 `Asia/Shanghai`，不得用数据库 session 时区隐式推导。
- 所有领域表包含稳定主键和必要的 `created_at` / `updated_at`。
- 不使用数据库 Enum，以免业务类型扩展必须修改底层类型。
- JSON 只保存自然为文档的数据；需要唯一约束和并发判断的数据必须进入关系表。

因此，积累型 Trigger 的已计数 Asset 推荐使用：

```text
TriggerCountedAsset
- tracker_id
- asset_id
- counted_at

UNIQUE(tracker_id, asset_id)
```

不把不断增长的 `counted_asset_ids` JSON 作为最终并发真值。

---

## 7. 统一事务边界

领域写入遵循一个规则：

> 业务真值、需要执行的 Job、需要对外提示的 Notification 和对应 OutboxEvent，在同一个数据库事务中落库。

典型流程：

### 7.1 Asset 创建与积累型 Trigger

```text
创建 Asset
→ 锁定或创建 TriggerTracker
→ UNIQUE(tracker_id, asset_id) 计数
→ 更新或创建 TriggerExecution
→ 如需提醒，创建 Notification + OutboxEvent
→ 一次 commit
```

这条事务内不调用 Agent、网络、Renderer 或 SSE。

### 7.2 Trigger 消费与 Planner

```text
锁定 TriggerExecution
→ 创建或复用 ReportGenerationRun
→ 标记 Execution consumed
→ 创建 planner WorkflowJob
→ 一次 commit
```

重复消费同一 Execution 返回已有 Run。

### 7.3 用户选择方案与 Pipeline

```text
锁定 ReportGenerationRun
→ 验证 pending decision / selected option
→ 保存 ReportExecutionPlan
→ 创建或复用 report_pipeline WorkflowJob
→ 一次 commit
```

重复点击不能产生并行 Pipeline。

### 7.4 Worker 完成

```text
写入阶段 checkpoint 或最终 Report
→ 更新 Run / Job 状态
→ 创建 Notification + OutboxEvent
→ 一次 commit
```

外部 LLM、Web Search、插图和渲染调用均在数据库事务外执行；执行结果再通过短事务写回。

---

## 8. 数据库 Job Queue

`WorkflowJob` 是异步执行的唯一真值，不创建进程内后台 Task 作为业务任务。

除业务 spec 已定义字段外，物理实现补充：

```text
WorkflowJob
- id
- run_id nullable
- job_type
- status
- attempt
- max_attempts
- available_at
- lease_owner nullable
- lease_expires_at nullable
- checkpoint_json
- input_dedupe_key nullable
- error_code nullable
- error_message nullable
- created_at / started_at / completed_at / updated_at

UNIQUE(input_dedupe_key)
INDEX(status, available_at, lease_expires_at)
```

领取协议：

1. 开启短事务。
2. 使用 `SELECT ... FOR UPDATE SKIP LOCKED` 选择一条可运行或 lease 已过期的 Job。
3. 更新为 `running`，写入 `lease_owner`、`lease_expires_at` 和 attempt。
4. commit 后执行外部工作。
5. 长任务定期用条件更新续租；只有当前 lease owner 可以续租或写最终结果。
6. 成功、失败、取消和 checkpoint 都使用短事务。

可靠性语义：

- 交付语义是 at-least-once。
- Handler 必须依据 Run 当前状态、当前 Job ID 和幂等键判断是否仍可写回。
- Worker 崩溃后由 lease 到期恢复。
- 可重试错误使用有上限的指数退避和 jitter。
- 权限、输入、Template 条件和用户取消属于不可自动重试错误。
- Job 错误信息不得记录 Asset 正文、Token 或外部搜索原文。

---

## 9. Transactional Outbox 与 SSE

MySQL 不使用 PostgreSQL `LISTEN/NOTIFY`。跨进程 Notification 传递固定采用 Outbox：

```text
OutboxEvent
- id
- event_type
- aggregate_type
- aggregate_id
- user_id
- payload_json
- created_at
- available_at
- attempt
- published_at nullable
- last_error nullable

INDEX(published_at, available_at, id)
```

发布流程：

```text
业务事务
├── 写 Notification
└── 写 OutboxEvent(notification.created)

API Outbox dispatcher
→ 领取未发布 Event
→ 重新读取仍存在的 Notification
→ 向该 user_id 的 SSE subscribers 推送 notification event
→ 标记 published_at
```

语义：

- 先推送、后标记，因此 API 在极端崩溃窗口可能重复推送。
- 客户端以 Notification ID 去重。
- Notification 已被删除时，dispatcher 跳过该事件并标记完成。
- SSE 队列满或用户不在线时允许丢实时帧；Notification 列表是恢复真值。
- 断线重连后客户端重新调用 `GET /api/notifications`。
- API 单实例是 Phase 1 的明确部署约束。
- Outbox 发布失败按退避重试，并有积压、年龄和失败指标。
- 已发布 Outbox 记录按保留策略清理，不作为永久事件日志。

Redis 只有在 API 必须多实例并共享实时广播时才进入评估；Kafka 只有在出现跨服务、多消费者、长时间事件回放需求时才进入评估。

---

## 10. Scheduler 与补偿

Worker 内包含轻量 scheduler loop，不新增 Scheduler 服务：

- 每分钟扫描需要 T-1h 判断的 scheduled Event。
- 扫描 `available` 但 Notification revision 未发布的 TriggerExecution。
- 恢复 lease 过期的 WorkflowJob。
- 清理 14 天以前的 Notification。
- 执行 Report、Share 和临时媒体的过期维护。

所有扫描必须：

- 使用数据库时间窗口和稳定 dedupe key。
- 允许同一窗口被重复扫描。
- 不依赖“某分钟只运行一次”的进程内假设。
- 通过唯一约束、行锁或状态条件实现幂等。

---

## 11. Auth、安全与存储

### 11.1 Auth

- Theme V2 API 继续接受移动端现有 Bearer token 形态。
- `user_id` 来自已验证 token 的 subject，不信任请求体中的 user ID。
- Theme V2 不查询旧后端用户表，也不把旧 API 当作鉴权依赖。
- OAuth/token exchange 所需逻辑由 V2 自己拥有；签名 secret、issuer、audience 通过独立 `.env.theme-v2` 配置。
- `USER_ID` 绕过只允许本地开发和测试，生产启动时必须拒绝该模式。

### 11.2 私有与公开数据

- 所有私有实体按当前 `user_id` 重新校验 ownership。
- Notification deep link 不是授权凭据。
- ReportShare 使用不可预测 token，并与私有 Report ID 授权边界分离。
- 日志、Job 错误和指标不记录 Asset 正文、Report 正文、凭据或 Share token。

### 11.3 媒体

Phase 1 Docker 使用存储接口的 local driver：

- API 与 Worker 共享独立 `media_data` volume。
- 私有媒体只能经鉴权 API 读取。
- 公开媒体必须验证有效 Share token 或使用受控派生 URL。
- 文件表保存 owner、用途、mime、大小、校验值和 storage key。

生产环境可切换 S3-compatible driver，不改变 Report、File 或 Share 的领域模型。Phase 1 不需要额外启动 MinIO 容器。

---

## 12. Today 前端接入边界

Today 的视觉实现与 Theme V2 Service 的运行时隔离是两个独立工作流，但最终不能依赖旧 Docker。

当前 `loadToday(ApiClient)` 会读取：

```text
/api/timeline
/api/assets
/api/events
/api/contacts
/api/sessions
/api/skills
```

因此在把移动端默认 API 地址切到 `http://localhost:8100` 之前，实施计划必须二选一并写成明确任务：

1. Theme V2 Service 提供上述 Today 所需的兼容读契约；或
2. `ThemeV2HomeRepository` 改用一个 V2 Today Read Model，并映射为现有 `TodayData`。

本设计推荐第二种：保留 legacy `TodayPage` 和 `loadToday` 不动，让新的 Theme V2 Home repository 消费一个聚合读接口，例如：

```http
GET /api/today
```

响应一次性提供：

- Next Moment。
- 过滤 Goal 后的 Reka Queue。
- 今日 Asset bubble 数据及真实总数。
- Skill display metadata。
- Agenda/Fishbone 所需事件与 Todo。
- Flash/Session 摘要（如果当前产品仍展示）。

这样不会为了一个新页面复制六个旧 API 的偶然组合，也不会让 Theme V2 Home 继续依赖旧容器。`TodayData` 可以继续作为前端展示模型，旧 `loadToday` 仍服务 legacy shell。

在 `/api/today` 契约正式落盘前，前端可以用注入 repository 和 fixtures 开始视觉、交互、状态与 golden 实现，但不能宣称完成真实数据集成。

---

## 13. 可观测性与验证

### 13.1 基础日志字段

```text
request_id
user_id_hash
run_id
job_id
job_type
trigger_type
execution_id
notification_id
outbox_event_id
attempt
lease_owner
duration_ms
result
error_code
```

### 13.2 最小指标

```text
http_request_total
http_request_duration
workflow_job_queued_total
workflow_job_completed_total
workflow_job_failed_total
workflow_job_lease_recovered_total
workflow_job_oldest_queued_seconds
outbox_pending_total
outbox_oldest_pending_seconds
outbox_publish_failed_total
sse_connections
sse_dropped_frames_total
trigger_fired_total
trigger_notification_total
report_run_total
report_run_completed_total
report_run_failed_total
```

### 13.3 测试层级

- 领域单元测试：状态机、冷却、revision、幂等和失败分类。
- MySQL 集成测试：事务回滚、唯一约束、行锁、`SKIP LOCKED`、lease 恢复和 Outbox。
- API contract 测试：鉴权、ownership、Deep Link、Run 和 Notification。
- Worker 集成测试：使用 fake LLM/search/storage，禁止测试依赖真实外部模型。
- SSE 测试：Worker 写 Notification 后 API 能发布，重复帧可去重，列表可恢复丢帧。
- 端到端 smoke：空数据库 migration → seed → Trigger → Notification → Run → fake Report。
- Today 测试：repository contract、411 × 960 Light/Dark golden、Agenda、Dock、inactive ticker 和 Goal 过滤。

并发与队列测试必须使用真实 MySQL 8；SQLite 不能替代。

---

## 14. 四份 spec 的实施准入结论

| Spec | 结论 | 开始前必须处理 |
|---|---|---|
| Notification | **可直接启动基础实现** | 已收敛为 MySQL Outbox；先实现表、API、SSE 和恢复语义 |
| Trigger | **可启动，依赖 Notification/Outbox 基础层** | 使用关系表保证 Asset 计数幂等；scheduler 与补偿归 Worker |
| Report Generation | **产品设计完整，可先做 R1；全量实现需拆计划** | 先落 Run、WorkflowJob、lease、checkpoint、fake provider，再进入 Planner/Pipeline |
| Today | **视觉与交互可启动；真实数据集成尚有契约门槛** | 明确 `/api/today` Read Model；修正现有实施计划中的响应式、active、Queue 来源和 Dock golden |

### 14.1 Notification

主体 API、数据模型、14 天保留、Deep Link 和 SSE 恢复语义已经足够明确。原文中的 PostgreSQL `LISTEN/NOTIFY` 候选已收敛为 MySQL Transactional Outbox，现在可以直接进入基础实现。

### 14.2 Trigger

两个 Phase 1 Trigger 的规则、Tracker、Execution、Dismiss、消费和补偿语义已经足够开始。实施先依赖 Asset/UserSkill/Event 基础表和 Notification 创建服务。计数幂等使用关系表，不把增长 JSON 当并发真值。

### 14.3 Report Generation

该 spec 已达到产品和底层能力设计级别，但尚未拆成可逐任务执行的 coding plan。可以立即开始 R1：

```text
ReportGenerationRun
+ WorkflowJob
+ worker lease
+ fake Planner/Pipeline handler
+ 状态查询
```

R2 以后必须另写实施计划，尤其是 Template registry、Agent profile、Web、Renderer、媒体和 Share。

### 14.4 Today

Pencil 与 handoff 已能驱动页面视觉实现，但当前 plan 仍需修正：

- 宽屏 Panel 必须水平居中，不能固定 `left = 8`。
- 新 Home 必须接收 `active`，离开 Home 时暂停 BubblePool ticker、传感器和重复动画。
- Reka Queue 需要明确字段和过滤契约，不能从含糊的旧 Goal 数据推断。
- Home page golden 不等于验证 shell 中的 Floating Dock；Dock 需要 shell-level golden/test。
- Theme V2 独立后端必须提供 Today 数据，不能在旧 Docker 停止后继续调用 legacy API。

因此 Today 可以先并行完成纯前端组件、状态、动画与 golden；真实数据联调以 `/api/today` contract 为准入条件。

---

## 15. 实施依赖顺序

正式 coding plan 应按以下依赖切片：

```text
S0  独立目录、Compose、MySQL、migration、health、auth 骨架
S1  Outbox、SSE、WorkflowJob、Worker lease 与测试
S2  UserSkill / Asset / Event 基础与 Today Read Model
S3  Notification API
S4  Trigger Tracker / Execution / scheduler / compensation
S5  ReportGenerationRun + fake Planner/Pipeline
S6  Planner + Template Registry + Decision
S7  Pipeline + Renderer + File
S8  ReportShare + Share Card
S9  Today 真实数据联调与端到端验收
```

允许并行的工作：

- S0/S1 契约稳定后，Today 纯 UI 可以用 fixture repository 并行。
- Trigger 规则单元测试可以与基础设施并行，但数据库集成必须等待 S1/S2。
- Template Skill 内容准备可以与 R1 并行，但不能绕过 Run/Job 状态机接入生产。

---

## 16. 启动与回退原则

Theme V2 第一次启动必须从空卷完成：

```text
build image
→ mysql healthy
→ alembic upgrade head
→ api /ready
→ worker ready
→ seed isolated test user/data
→ smoke workflow
```

切换移动端前必须通过：

- 新服务无旧容器依赖。
- 新数据库无旧数据库连接。
- API、Worker 重启后 Job 可恢复。
- Worker 创建的 Notification 可经 API SSE 到达。
- SSE 丢帧可经列表恢复。
- Today 所需读契约已完成。
- 回退只需要恢复旧 API base URL 并重新启动旧 Compose。

停止 Theme V2 不删除任何旧服务或旧卷；删除 Theme V2 数据也必须是单独、显式、可确认的运维动作。
