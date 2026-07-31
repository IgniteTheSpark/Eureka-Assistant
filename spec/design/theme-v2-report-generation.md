# Design: Theme V2 Report Generation（规划、生成与分享）

> 日期：2026-07-31
>
> 状态：**READY FOR HANDOFF · 产品与底层边界已确认，尚未实施**
>
> 范围：Theme V2 Service 中 Report Generation Run、Report Planner、Template Skill、Report Pipeline、Agent 能力、异步 Job、Report、官方 Renderer、分享链接与摘要分享卡。
> 本稿只定义底层能力和数据契约，不定义 Report 容器、Stepper、方案卡、Viewer 或分享页的具体 UI。

---

## 0. 一页结论

Theme V2 Report Generation 是一条完整的新路径：

```text
用户主动发起
或
用户点击 Trigger Notification

→ ReportGenerationRun
→ Report Planner
→ 用户回答问题 / 调整数据 / 选择方案
→ ReportExecutionPlan
→ Report Pipeline
→ Report
→ Official Report Renderer
→ 私有查看或公开分享
```

系统不保留旧路线：

```text
wish
→ report-dispatcher
→ genre
→ 直接生成
```

新系统的核心不变量：

1. 每份 Report 必须来自一个 `ReportGenerationRun`。
2. 一个 Run 最多产生一份 Report。
3. 所有来源都先经过 Report Planner。
4. Report Pipeline 只接受完整 `ReportExecutionPlan`，不接受自由文本 Wish。
5. Planner 只规划，不执行 Web Search 或 Image Generation。
6. Pipeline 不重新选择 Template，也不擅自扩大 Asset 范围。
7. Template 根据用户提供的数据和 Schema 工作，不依赖固定 Skill Key。
8. Report 只保存 Asset ID 引用；生成时读取对应 Asset 的最新内容。
9. 用户主动报告与 proactive Trigger 完全隔离。
10. 私有 Report URL 和公开 Share URL 使用不同授权边界。

关联文档：

- [Theme V2 Trigger](theme-v2-trigger.md)
- [Theme V2 Notification](theme-v2-notification.md)
- [Theme V2 独立服务运行时设计](../../docs/superpowers/specs/2026-07-31-theme-v2-service-runtime-design.md)

---

## 1. Greenfield 服务架构

Theme V2 Service 使用新的数据库并直接拥有：

```text
UserSkill
Asset
Event
Notification
TriggerTracker
TriggerExecution
ReportGenerationRun
WorkflowJob
Report
ReportShare
File
```

部署可以先采用模块化单体：

```text
Theme V2 HTTP API
├── Notification API
├── Trigger API
├── Report Generation API
├── Report API
└── Share API

Theme V2 Worker
├── Trigger Scheduler
├── Report Planner Worker
├── Report Pipeline Worker
└── Compensation / Expiry Jobs

Official Report Renderer
├── Private Report Viewer
└── Public Share Viewer

Object Storage / CDN
├── Report Illustrations
├── Share Cards
└── Other Report Media
```

API 和 Worker 使用同一个数据库。Phase 1 不要求 Redis 或外部消息队列。

---

## 2. 范围与非兼容声明

### 2.1 本稿定义

- Trigger 与用户主动入口如何创建 Run。
- Planner 的输入、工具、两阶段发现和输出。
- 用户问答、Evidence Scope 调整和 Plan Option 选择。
- Template Skill Package。
- ReportExecutionPlan。
- Web Search、图表、插图和 HTML Pipeline。
- 持久化 Job、失败、重试和恢复。
- Report 数据模型和 Report 容器 Read Model。
- 私有 Report Viewer。
- 公开 Share Token、媒体授权和摘要分享卡。
- Agent 安全、Usage、Observability 和验收。

### 2.2 明确删除的旧概念

新服务没有：

```text
report-dispatcher
genre-first routing
free-text wish pipeline
Nudge / Offer 直接生成
前端 _wishFor()
绕过 Planner 的同步报告接口
旧 Report Pipeline 兼容入口
```

旧 Prompt、Renderer 或分析方法只有在重构为新 Template Skill 后才可以复用；旧调用关系不进入目标架构。

### 2.3 不包含

- Template 社区。
- 用户安装第三方 Template。
- 用户自己创建 Template 的 UI。
- Asset Embedding 或向量数据库。
- Subject 实体。
- Report 容器、Stepper 和 Viewer 的像素级 UI。
- Rhythm Reminder。
- 旧服务迁移和旧数据兼容。

---

## 3. Workflow 入口

### 3.1 Trigger 发起

用户点击：

```text
Notification.type = report_available
Notification.link = report-start:<trigger_execution_id>:<revision>
```

客户端调用：

```http
POST /api/report-generation-runs
```

```json
{
  "origin": "trigger",
  "trigger_execution_id": "execution-id"
}
```

服务端在一个事务中：

1. 验证 Execution 属于当前用户。
2. 验证 `workflow_type = report_generation`。
3. 验证 `status = available` 且未过期。
4. 创建或复用 ReportGenerationRun。
5. 复制 Execution 当前 `payload_json` 到 `launch_context`。
6. 标记 Execution `consumed` 并写入 `workflow_run_id`。
7. 按 Trigger 类型更新 Tracker。
8. 创建 Planner Job。

TriggerExecution 只保存引用。Run 创建后，Execution 的后续变化不再改变本 Run。

### 3.2 用户主动发起

用户明确提出报告需求后调用同一 API：

```http
POST /api/report-generation-runs
```

```json
{
  "origin": "user_initiated",
  "intent": "帮我总结最近的宝宝记录并分析值得关注的变化",
  "skill_ids": ["optional-user-skill-id"],
  "asset_ids": ["optional-asset-id"],
  "time_range": {
    "from": "optional",
    "to": "optional"
  }
}
```

规则：

- 用户可以只提供 Intent。
- Skill、Asset 和时间范围均可选。
- 信息不足时 Planner 通过专业问答补齐。
- 主动报告不读取 Trigger 冷却。
- 主动报告不修改 TriggerTracker。
- 主动报告成功也不重置 proactive Trigger。

### 3.3 创建 Run 的时机

- 仅仅打开 Report 页面不创建 Run。
- 未点击的 TriggerExecution 不创建 Run。
- 用户明确发起报告，或点击 `report_available` 后才创建。
- 重复消费同一个 TriggerExecution 返回同一个 Run。

---

## 4. ReportGenerationRun

### 4.1 数据模型

```text
ReportGenerationRun
- id: UUID
- user_id: string
- origin: trigger | user_initiated
- trigger_execution_id: UUID nullable

- state: string
- active_stage: string nullable
- launch_context: JSON

- intent: text nullable
- answers: JSON
- evidence_scope: JSON
- pending_decision: JSON nullable
- plan_options: JSON
- selected_option_id: string nullable

- execution_plan: JSON nullable
- template_id: string nullable
- template_version: string nullable
- resolved_asset_ids: JSON

- planner_job_id: UUID nullable
- generation_job_id: UUID nullable

- draft_content_md: text nullable
- generation_context: JSON
- usage_json: JSON

- report_id: UUID nullable

- failure_stage: string nullable
- error_code: string nullable
- error_message: text nullable
- retry_from: string nullable

- created_at: timestamptz
- updated_at: timestamptz
- expires_at: timestamptz nullable
- completed_at: timestamptz nullable
- cancelled_at: timestamptz nullable
```

索引：

```text
INDEX(user_id, state, updated_at DESC)
INDEX(user_id, created_at DESC)
UNIQUE(trigger_execution_id) WHERE trigger_execution_id IS NOT NULL
```

### 4.2 不使用 Plan Revision

一个 Run 只保留当前有效的：

```text
answers
evidence_scope
pending_decision
plan_options
execution_plan
```

用户回答问题或调整数据后：

```text
清除旧 plan_options
→ state = planning
→ 创建新的 Planner Job
→ 新结果覆盖旧结果
```

不保留历史方案，也不向用户展示多个版本。

异步写回使用 `planner_job_id` 保证只有当前 Job 可以更新 Run，不需要 `plan_revision`。

---

## 5. 状态机

### 5.1 主状态

```text
planning
→ awaiting_selection
→ planning              // 回答问题或调整数据
→ generating
→ completed
```

终止或异常状态：

```text
failed
cancelled
expired
```

### 5.2 状态语义

#### `planning`

Report Planner 正在：

- 理解 Intent。
- 检查已有 Evidence。
- 提出澄清问题。
- 发现关联 Skill / Asset。
- 选择 Template。
- 生成 Plan Options。

#### `awaiting_selection`

Workflow 等待用户作出一个决定。`pending_decision.type` 可以是：

```text
clarification
plan_selection
```

Phase 1 不增加 `awaiting_questions`、`awaiting_scope` 等更多主状态。

#### `generating`

用户已经选择 Option 并点击生成，Report Pipeline 正在执行。

#### `completed`

- Report 已成功持久化。
- `report_id` 必填。
- Run 不再变化。

#### `failed`

Planner 或 Pipeline 出现致命失败。必须保存：

```text
failure_stage
error_code
error_message
retry_from
```

#### `cancelled`

只能由用户明确取消。Notification 已读、删除或 Dismiss 不取消 Run。

#### `expired`

`awaiting_selection` 超过 7 天没有处理，可以进入 `expired`。Planner 或 Pipeline 超时应进入 `failed`，不是 `expired`。

### 5.3 Active Stage

Planner 阶段：

```text
intake
evidence_discovery
plan_generation
```

Pipeline 阶段：

```text
load_evidence
web_search
content_generation
illustration
html_render
persist
```

Planner 阶段不会出现 `web_search` 或 `illustration`。

---

## 6. Pending Decision

### 6.1 Clarification

当用户主动输入或 Trigger Context 不足时：

```json
{
  "type": "clarification",
  "questions": [
    {
      "id": "report_goal",
      "question": "你更想关注成长变化，还是饮食规律？",
      "options": [
        "成长变化",
        "饮食规律",
        "综合总结"
      ],
      "required": true
    }
  ]
}
```

用户回答后：

```text
answers 更新
→ pending_decision 清空
→ plan_options 清空
→ state = planning
→ 新 Planner Job
```

### 6.2 Plan Selection

信息充分后：

```json
{
  "type": "plan_selection",
  "recommended_option_id": "option-1"
}
```

Run 同时保存当前 `plan_options`。

### 6.3 Evidence 调整

在方案选择阶段，底层必须允许用户：

- 修改开始和结束时间。
- 增加或移除 UserSkill。
- 增加或移除具体 Asset ID。
- 拒绝 Planner 推荐的关联数据。
- 退回 Primary Skill Only。

任何 Evidence Scope 调整都会重新运行 Planner，并直接覆盖当前 Options。

---

## 7. Report Planner

### 7.1 Planner 输入

```text
Run.intent
Run.launch_context
Run.answers
Run.evidence_scope
用户的 UserSkill 元数据
官方 Template Registry
```

一个 UserSkill 默认围绕一个主题，不引入 Subject。

### 7.2 Planner 工具

允许：

```text
list_user_skills
get_skill_schema
query_assets
get_asset_summaries
get_event
get_event_attendees
get_event_files
get_related_sessions
```

禁止：

```text
Web Search
Image Generation
创建或修改 Asset
创建 Skill
直接创建 Report
任意第三方写操作
```

### 7.3 两阶段规划

#### 阶段一：Primary Only

先围绕入口数据形成可靠基线：

```text
读取 Primary Skill / Event
→ 阅读 display_name、description、schema
→ 读取入口 Asset IDs
→ 判断字段和数据完整度
→ 形成 Primary-Only Option
```

#### 阶段二：Related Evidence Discovery

再进行有限关联发现：

```text
查看其他 UserSkill 名称、描述和 Schema
→ 检查 Domain、关键词和时间重合
→ 查询少量相关 Asset 摘要
→ 判断组合数据是否形成更有价值的报告
→ 形成 Combined Option
```

不同 Evidence Scope 可以选择不同 Template。

Planner 不应先固定一个 Template，再强行寻找符合 Template 的数据。

### 7.4 Phase 1 不使用向量

关联发现使用：

- Skill 名称与描述。
- Skill Schema 字段。
- Domain。
- 时间范围重合。
- 关键词。
- 有界 Asset 摘要或样本。

不使用：

- Asset Embedding。
- Vector DB。
- 全量 Asset 扫描。

实现必须设定候选上限、每 Skill 样本上限和总 Context Budget；具体数字属于工程配置，不是用户配置。

### 7.5 Planner 输出数量

Planner 输出：

> 1 个默认推荐方案，最多再提供 2 个备选；如果只有一个方案真正成立，就只返回一个。

不为了凑数制造差异很小的方案。

---

## 8. ReportPlanOption

Phase 1 将 Plan Options 作为 JSON 保存在 Run 中，不建立独立表。

```json
{
  "id": "option-1",
  "recommended": true,
  "title": "宝宝两周综合成长报告",
  "summary": "结合日常、喂养和身高体重记录，分析变化与值得关注的趋势",
  "report_goal": "形成两周成长总结并指出值得继续观察的方向",
  "template_id": "child_growth_review",
  "template_version": "1.0.0",
  "base_family": "professional_evaluation",
  "evidence_scope": {
    "time_range": {
      "from": "2026-07-01T00:00:00+08:00",
      "to": "2026-07-15T23:59:59+08:00"
    },
    "skill_ids": [
      "baby-daily-skill",
      "feeding-skill",
      "growth-skill"
    ],
    "asset_ids": [
      "asset-1",
      "asset-2"
    ],
    "counts_by_skill": {
      "baby-daily-skill": 15,
      "feeding-skill": 12,
      "growth-skill": 4
    }
  },
  "field_bindings": {
    "measurement.weight": "payload.宝宝体重",
    "measurement.height": "payload.身高",
    "intake.amount": "payload.奶量",
    "recorded_at": "effective_at"
  },
  "web_search": {
    "policy": "authoritative_only",
    "reason": "建议部分只使用权威育儿和成长资料"
  },
  "illustration": {
    "policy": "optional",
    "reason": "可以加入一张阶段成长概念插图"
  },
  "render_policy": "report_html_v1"
}
```

Phase 1 不向用户暴露：

```text
template_id
template_version
base_family
内部 Field Binding Key
模型配置
```

用户应能看到：

- 报告会回答什么。
- 时间范围。
- 使用哪些 Skills。
- 各 Skill 有多少条记录。
- 是否会结合公开资料。
- 是否可能生成概念插图。

---

## 9. Template Skill Package

### 9.1 目录

官方 Template 使用版本化 Skill Package：

```text
report-templates/
  child-growth-review/
    template.json
    SKILL.md

  tennis-monthly-review/
    template.json
    SKILL.md

  work-monthly-review/
    template.json
    SKILL.md
```

Phase 1 Registry 从代码仓库加载，不创建 `report_templates` 表。

### 9.2 Manifest

```json
{
  "id": "child_growth_review",
  "version": "1.0.0",
  "base_family": "professional_evaluation",
  "planner_description": "根据一段时间内的成长、饮食和日常记录形成阶段总结",
  "data_fit": [
    "time_series_measurement",
    "daily_log",
    "categorical_intake"
  ],
  "analysis_method": "trend_comparison_with_observation",
  "web_policy": "authoritative_only",
  "illustration_policy": "optional",
  "render_policy": "report_html_v1"
}
```

`SKILL.md` 定义：

- Evidence Bundle 如何解释。
- 字段映射如何使用。
- 分析方法。
- 数据不足时如何降级。
- 报告章节结构。
- 图表约束。
- 外部资料引用方式。
- 建议和免责声明。
- Share Card 摘要输出约束。

### 9.3 不依赖固定 Skill Key

Template 不能要求：

```text
baby_feeding
baby_growth
tennis_record
```

Template 声明数据能力：

```text
time_series_measurement
categorical_log
outcome_record
location
counterparty
free_text
```

Planner 根据实际 Schema 生成 `field_bindings`。

用户把 Skill 命名为“果果日常”“小宝记录”或其他自定义名称，都不影响 Template 适配。

### 9.4 Base Family

Phase 1 提供四个基础分析族：

```text
data_trend
theme_synthesis
professional_evaluation
briefing_research
```

### 9.5 官方场景 Template

Phase 1 目标为 5～8 个：

1. 宝宝阶段成长总结。
2. 消费与财务分析。
3. 灵感串联与升华。
4. 工作月报 / 述职。
5. 网球月度战报。
6. 学习复盘。
7. 会前调研。
8. 通用阶段总结。

场景 Template 可以复用同一 Base Family，但拥有自己的分析方法、章节、语气和降级规则。

---

## 10. 用户选择与 ReportExecutionPlan

用户选择 Option 并点击生成时，系统写入当前唯一 Execution Plan：

```json
{
  "template_id": "child_growth_review",
  "template_version": "1.0.0",
  "base_family": "professional_evaluation",
  "report_goal": "宝宝两周综合成长分析",
  "resolved_asset_ids": [
    "asset-1",
    "asset-2"
  ],
  "field_bindings": {},
  "time_range": {},
  "web_policy": "authoritative_only",
  "illustration_policy": "optional",
  "render_policy": "report_html_v1"
}
```

规则：

- Pipeline 只能读取，不得修改 Execution Plan。
- `resolved_asset_ids` 是引用集合，不是内容快照。
- 生成时读取 Asset 最新内容。
- 用户点击生成后，不允许在同一 Job 运行期间修改 Execution Plan。
- 想修改方案需要取消当前生成或在失败后回到 Planning。

状态：

```text
awaiting_selection
→ execution_plan 写入
→ state = generating
→ 创建 report_pipeline WorkflowJob
```

---

## 11. Report Pipeline

唯一入口：

```python
execute_report_plan(execution_plan)
```

Pipeline 不接受：

```text
free-text wish
genre
dispatcher result
未选择的 plan options
```

固定阶段：

```text
1. load_evidence
2. web_search
3. content_generation
4. chart_validation
5. illustration
6. html_render
7. persist
```

### 11.1 Load Evidence

按 `resolved_asset_ids` 读取当前用户仍可访问的最新 Asset 内容：

```json
{
  "user_evidence": [
    {
      "asset_id": "asset-1",
      "skill_id": "skill-1",
      "effective_at": "2026-07-10T10:00:00+08:00",
      "payload": {}
    }
  ],
  "unavailable_asset_ids": [],
  "field_bindings": {},
  "time_range": {},
  "report_goal": "...",
  "template": {
    "id": "child_growth_review",
    "version": "1.0.0"
  }
}
```

处理：

- Asset 内容更新：使用最新内容。
- Asset 删除：加入 `unavailable_asset_ids`。
- Asset 越权：当作 unavailable，不泄露存在性。
- 剩余 Evidence 足够：继续。
- 不满足 Template 最低要求：进入 `failed`，允许用户调整。

### 11.2 Web Search

Planner Option 只声明 Policy；真正搜索只发生在 Pipeline。

Policy：

```text
none
optional
required
authoritative_only
```

行为：

| Policy | 执行 |
|---|---|
| `none` | 跳过 |
| `optional` | 搜索失败时降级为纯用户数据报告 |
| `required` | 搜索失败为致命失败，可重试 |
| `authoritative_only` | 没有合格权威来源时失败，不用低质量来源补位 |

隐私：

Web Query 不包含：

- 用户姓名。
- 宝宝姓名。
- 联系人私人信息。
- 原始记录全文。
- 地址、账号或其他敏感字段。

只能生成抽象、脱敏查询。

报告必须区分：

```text
用户记录事实
外部资料事实
Agent 推断与建议
```

外部资料必须保存来源 URL、标题、访问时间和引用关系。

### 11.3 Content Generation

Report Generator 执行已选 Template Skill：

```text
Execution Plan
+ Evidence Bundle
+ 合格 Web Sources
→ content_md
+ chart directives
+ illustration_prompt
+ share_card_spec
```

Generator 不得：

- 重新选择 Template。
- 新增 Asset ID。
- 修改用户数据。
- 把网页指令当作系统指令。
- 编造不存在的数字、记录或来源。

### 11.4 图表

图表属于事实表达：

- 使用确定性 SVG / HTML Renderer。
- 数值只能来自 Evidence 或可复算的明确计算。
- Agent 只输出图表结构和数据。
- Image Model 不能生成图表、数字、坐标轴或统计结论。

图表数据无效时：

- 移除图表。
- 保留仍成立的文字分析。
- 在 `generation_context.warnings` 记录原因。

### 11.5 插图

插图只承担概念和氛围：

- 不表达精确数据。
- 不包含文字、数字、图表或品牌标志。
- Image Worker 只接收脱敏后的场景 Prompt。
- 不把完整 Evidence 发送给 Image Model。
- 图片保存为 File / Object Storage，不使用 Base64 内联。

插图失败永远不导致整个 Report 失败。

### 11.6 HTML Render

Official Renderer 使用：

```text
content_md
render_policy
surface / palette / seed
chart directives
media references
```

生成 HTML 内容缓存：

- CSS 和固定 JS 来自官方静态资源。
- 图表可以内联为体积较小的 SVG。
- 插图通过受控 Media URL 加载。
- 图片支持 Lazy Load 和 CDN Cache。
- 不允许 Agent 生成任意可执行脚本。
- 固定交互组件使用官方白名单。

`content_md + spec_json` 是可重新渲染的真值，`html` 是缓存，不是自包含 Base64 文件。

### 11.7 Persist

事务内：

```text
创建 Report
→ Report.generation_run_id = run.id
→ Run.report_id = report.id
→ Run.state = completed
→ Job.status = succeeded
```

提交后：

```text
create_notification(report_done)
```

约束：

```text
Report.generation_run_id UNIQUE
```

防止 Worker 重试产生重复 Report。

---

## 12. Web 与插图执行结果

`generation_context` 记录真实执行结果：

```json
{
  "web_search": {
    "policy": "optional",
    "status": "failed_degraded",
    "sources": []
  },
  "illustration": {
    "policy": "optional",
    "status": "success",
    "file_ids": [
      "file-1"
    ]
  },
  "warnings": []
}
```

Planner 阶段没有真实 Web 或配图状态。

合法状态示例：

```text
not_requested
pending
succeeded
failed_degraded
failed_fatal
skipped
```

---

## 13. Agent Profiles

Template 不写死具体模型名。部署配置使用能力 Profile。

### 13.1 Report Planner Profile

能力：

- 强意图理解。
- Schema 语义映射。
- Evidence 组合。
- Template 适配。
- 结构化 Option 输出。

无 Web、无图片、只读工具。

### 13.2 Report Generator Profile

能力：

- 高质量长内容生成。
- Template Skill 执行。
- 结构化图表输出。
- 引用整理。
- 工具调用。

只有 Execution Plan 允许时才能使用 Web Search。

### 13.3 Illustration Profile

独立 Image Model：

```text
Generator 输出 illustration_prompt
→ Illustration Worker
→ Image Model
→ File
```

### 13.4 Trusted / Untrusted

可信指令：

```text
系统 Policy
官方 Template Skill
ReportExecutionPlan
```

不可信数据：

```text
用户 Asset
Event Description
Web 页面
外部引用文本
```

不可信内容中的指令不能改变工具权限、Template、Execution Plan 或系统规则。

---

## 14. WorkflowJob

Planner 和 Pipeline 使用持久化 Job，不使用进程内临时 Task。

```text
WorkflowJob
- id: UUID
- run_id: UUID
- job_type: planner | report_pipeline
- status: queued | running | succeeded | failed | cancelled

- attempt: integer
- max_attempts: integer
- available_at: timestamptz

- lease_owner: string nullable
- lease_expires_at: timestamptz nullable

- error_code: string nullable
- error_message: text nullable

- created_at: timestamptz
- started_at: timestamptz nullable
- completed_at: timestamptz nullable
- updated_at: timestamptz
```

Job 只保存 `run_id`，输入始终从 Run 读取。

### 14.1 Planner Job

```text
Run.state = planning
→ 创建 Job(planner)
→ Run.planner_job_id = job.id
```

只有：

```text
job.id == run.planner_job_id
```

时可以写回。

### 14.2 Pipeline Job

```text
Run.state = generating
→ 创建 Job(report_pipeline)
→ Run.generation_job_id = job.id
```

重复点击生成返回当前 Job，不创建第二个并行 Pipeline。

### 14.3 Lease

Worker 使用：

```sql
SELECT ... FOR UPDATE SKIP LOCKED
```

领取 Job，并定期续租。

Worker 崩溃后 Lease 到期，其他 Worker 可以接管。

### 14.4 自动重试

可自动重试：

- 模型临时不可用。
- 网络超时。
- Required Web Search 临时失败。
- Object Storage 临时失败。
- Renderer 临时异常。

不自动重试：

- 用户数据不足。
- Template 输入条件不满足。
- Asset 全部失效。
- 权限错误。
- 用户取消。

自动重试耗尽：

```text
Job.failed
→ Run.failed
→ report_failed Notification
```

### 14.5 Checkpoint

阶段性结果保存到 Run：

```text
draft_content_md
generation_context
File IDs
HTML 临时结果或 Render Cache
```

例子：

- Content 成功、Render 失败：从 `html_render` 重试，不重新调用 Generator。
- 插图失败：记录降级，继续 Render。
- Persist 失败：复用已生成内容和 HTML。

---

## 15. 失败与重试

### 15.1 Planner 失败

```text
state = failed
failure_stage = plan_generation
retry_from = planning
```

Planner 不会因为 Web Search 或插图失败，因为这两项尚未执行。

### 15.2 Load Evidence 失败

全部 Asset 不可用或数据不足：

```text
failure_stage = load_evidence
retry_from = planning
```

用户返回调整 Evidence。

### 15.3 Web Search 失败

```text
optional
→ failed_degraded，继续

required / authoritative_only
→ failure_stage = web_search
→ retry_from = web_search
```

### 15.4 Content Generation 失败

```text
failure_stage = content_generation
retry_from = content_generation
```

### 15.5 Illustration 失败

```text
记录 warning
→ 继续
```

### 15.6 Render 失败

```text
draft_content_md 已保存
failure_stage = html_render
retry_from = html_render
```

### 15.7 Persist 失败

```text
failure_stage = persist
retry_from = persist
```

### 15.8 用户操作

失败 Run 可以：

- 重试原阶段。
- 返回 Planning 调整 Evidence。
- 取消。

Completed Run 不重新生成；需要新报告时创建新 Run。

---

## 16. Report

### 16.1 数据模型

```text
Report
- id: UUID
- user_id: string
- generation_run_id: UUID

- title: string(255)
- template_id: string
- template_version: string
- base_family: string

- content_md: text
- html: text nullable
- spec_json: JSON
- share_card_spec: JSON

- tokens_used: integer
- gen_ms: integer
- created_at: timestamptz
```

约束：

```text
UNIQUE(generation_run_id)
INDEX(user_id, created_at DESC)
```

新 Report 不使用 `genre` 作为核心字段。

### 16.2 `spec_json`

```json
{
  "template_id": "child_growth_review",
  "template_version": "1.0.0",
  "base_family": "professional_evaluation",
  "source_asset_ids": [],
  "unavailable_asset_ids": [],
  "field_bindings": {},
  "time_range": {},
  "external_sources": [],
  "web_policy": "authoritative_only",
  "generated_file_ids": [],
  "surface": "report",
  "palette": "calm",
  "seed": 123
}
```

公开 Share View 不返回完整 `spec_json`。

### 16.3 Usage

Run 保存细分 Usage，Report 保存汇总：

```json
{
  "planner": {
    "input_tokens": 0,
    "output_tokens": 0,
    "model_profile": "report_planner"
  },
  "generator": {
    "input_tokens": 0,
    "output_tokens": 0,
    "model_profile": "report_generator"
  },
  "web_search_count": 0,
  "image_generation_count": 0,
  "total_duration_ms": 0
}
```

---

## 17. Report 容器 Read Model

不创建 `report_container` 表。

### 17.1 Active Runs

```http
GET /api/report-generation-runs?active=true
```

返回：

```text
planning
awaiting_selection
generating
failed
```

不返回：

```text
未消费 TriggerExecution
cancelled
expired
completed
```

### 17.2 Run Detail

```http
GET /api/report-generation-runs/{run_id}
```

返回当前：

- State / Active Stage。
- Pending Decision。
- Evidence Scope。
- Plan Options。
- Selected Option。
- Execution Plan。
- Failure。
- Report ID。

### 17.3 Completed Reports

```http
GET /api/reports
GET /api/reports/{report_id}
```

Completed Run 通过 Report 展示，不在 Active Run 中重复出现。

### 17.4 容器边界

Report 容器永远不读取：

- TriggerTracker。
- 未消费的 TriggerExecution。
- 普通 Notification。
- 只达到阈值但用户没点击的建议。

---

## 18. API

### 18.1 创建 Run

```http
POST /api/report-generation-runs
```

支持 `origin = trigger | user_initiated`。

### 18.2 Run 列表与详情

```http
GET /api/report-generation-runs?active=true
GET /api/report-generation-runs/{run_id}
```

### 18.3 提交当前 Decision

```http
POST /api/report-generation-runs/{run_id}/decision
```

请求可以包含：

```json
{
  "answers": {},
  "evidence_scope": {
    "time_range": {},
    "skill_ids": [],
    "asset_ids": []
  }
}
```

结果：

```text
awaiting_selection
→ planning
→ 新 Planner Job
```

### 18.4 选择并生成

```http
POST /api/report-generation-runs/{run_id}/generate
```

```json
{
  "selected_option_id": "option-1"
}
```

结果：

```text
写入 execution_plan
→ generating
→ Pipeline Job
```

重复请求幂等，返回当前 Job。

### 18.5 Retry

```http
POST /api/report-generation-runs/{run_id}/retry
```

按 `retry_from` 创建新 Job。

### 18.6 Cancel

```http
POST /api/report-generation-runs/{run_id}/cancel
```

只允许当前用户；对运行中的 Worker 是 Best Effort，Run 进入 `cancelled` 后 Job 不得再提交结果。

### 18.7 Report

```http
GET /api/reports
GET /api/reports/{report_id}
```

所有私有接口验证：

```text
report.user_id = current_user_id
```

非法或越权 ID 返回 `404`。

---

## 19. Official Report Renderer

### 19.1 私有入口

```text
https://reports.eureka.app/app/reports/{report_id}
```

要求 Eureka 登录态。

服务端验证 Ownership。外部修改 `report_id` 不能访问其他用户 Report，统一返回 `404`。

### 19.2 公开入口

```text
https://reports.eureka.app/r/{share_token}
```

URL 不包含 `report_id`。

公开 Renderer：

- 只读。
- 不需要登录。
- 只读取 Share Snapshot。
- 不调用私有 `/api/reports/{report_id}`。
- 不展示用户其他 Report。
- 不返回 Asset、Skill、Run 或内部 Spec ID。

### 19.3 Static 与 Media

- 固定 CSS / JS 由官方静态资源提供并缓存。
- Report 图片存 Object Storage / CDN。
- Viewer Lazy Load 图片。
- 图表使用内联 SVG 或受控组件。
- 不使用 Base64 内嵌大图。

---

## 20. ReportShare

### 20.1 数据模型

```text
ReportShare
- id: UUID
- report_id: UUID
- user_id: string

- token_hash: string
- status: active | revoked | expired
- expires_at: timestamptz nullable

- snapshot_content_md: text
- snapshot_spec_json: JSON
- snapshot_html: text nullable
- media_map_json: JSON
- share_card_file_id: UUID nullable

- created_at: timestamptz
- revoked_at: timestamptz nullable
```

创建 Share 时复制当前 Report 的可公开内容，形成不可变 Snapshot。原 Report 后续重新渲染不改变已分享版本。

### 20.2 Token

- 使用足够长的随机 Token。
- URL 中只出现 Token。
- 数据库只保存 Hash。
- 非法 Token 返回 `404`。
- 默认 30 天过期。
- 用户可以主动撤销。

### 20.3 API

创建：

```http
POST /api/reports/{report_id}/shares
```

返回：

```json
{
  "share_id": "share-id",
  "url": "https://reports.eureka.app/r/random-token",
  "expires_at": "..."
}
```

撤销：

```http
DELETE /api/report-shares/{share_id}
```

公开读取：

```http
GET /api/public/report-shares/{share_token}
```

公开 API 不接受 `report_id`。

### 20.4 Media

公开媒体地址：

```text
/r/{share_token}/media/{media_key}
```

`media_key` 是当前 Share Snapshot 内部的随机或不透明 Key，不暴露原始 `file_id`。

验证：

```text
share_token
→ ReportShare
→ media_map_json[media_key]
→ File
```

修改 `media_key` 不能访问其他 Report 或用户文件。

撤销或过期后：

- Share 页面失效。
- Media 失效。
- Share Card / OG Image 失效。

---

## 21. 摘要分享卡

Template Skill 在生成 Report 时同时输出：

```json
{
  "headline": "果果的两周成长记录",
  "summary": "饮食逐渐稳定，身高体重保持连续增长",
  "highlights": [
    "两周记录 15 天",
    "平均每日奶量 720ml",
    "体重增长 0.4kg"
  ],
  "time_range": "7 月 1 日—7 月 15 日",
  "illustration_file_id": "optional-file-id"
}
```

规则：

- 不额外调用一次摘要 Agent。
- 最多三个 Highlights。
- 数字必须能回溯到 Report Evidence。
- 不包含 Asset / Skill / Run ID。
- 不包含未经用户选择的私密明细。

确定性 Share Card Renderer 生成：

```text
1080 × 1440 PNG
```

可以包含：

- 标题。
- 一句话摘要。
- 三个亮点。
- 时间范围。
- 报告概念插图或品牌视觉。
- Eureka / Reka 标识。
- Share URL 二维码。

用途：

```text
直接分享 PNG
分享官方 URL 时作为 Open Graph Image
同时分享卡片和链接
```

Share Card 生成失败不影响 Report 完成；分享时可以重试。

---

## 22. Notification 时机

完整顺序：

```text
Trigger 命中
→ report_available

用户点击
→ Run.planning

Planner 产生待决策
→ Run.awaiting_selection
→ report_plan_ready

用户选择并生成
→ Run.generating

Report 成功
→ Run.completed
→ report_done

Planner / Pipeline 致命失败
→ Run.failed
→ report_failed
```

不通知：

- Planning 中间进度。
- Generating 中间进度。
- 用户取消。
- Run 自动过期。
- Optional Web Search 降级。
- 插图失败但 Report 成功。

Phase 1 使用现有 Notification SSE 推送关键结果；页面通过 Run Detail 轮询 State / Active Stage，不新建 Report Progress SSE。

---

## 23. 安全与隐私

### 23.1 Ownership

- 所有 Run、Report、Share 创建和管理 API 校验当前用户。
- 越权对象返回 `404`。
- TriggerExecution 消费与 Run 创建同事务校验。
- Pipeline 读取 Asset 时再次校验 Ownership。

### 23.2 Prompt Injection

- Template Skill 和 Execution Plan 是可信指令。
- Asset、Event Description 和 Web 内容只能作为数据。
- Web 页面不能要求 Agent 改变工具权限或输出规则。
- Generator 只能调用 Execution Plan 允许的工具。

### 23.3 Web 隐私

- Query 脱敏。
- 不上传用户完整 Evidence。
- 外部来源和用户事实分开。
- 权威建议保留来源。

### 23.4 Public Share

- 公开 URL 不含 Report ID。
- Token 不可枚举。
- 数据库只保存 Token Hash。
- 公开 API 不返回内部 IDs。
- Media 必须由 Share Token + Media Key 双重授权。
- 分享页设置 `noindex`。
- 分享撤销立即生效。

### 23.5 Logs

普通日志不输出：

- Asset Payload。
- Event Description 全文。
- Web Query 中的敏感信息。
- Share Token。
- Agent Prompt 全文。

使用：

```text
run_id
job_id
report_id
share_id
trace_id
```

关联执行。

---

## 24. Observability

### 24.1 Planner

```text
planner_duration_ms
planner_tokens
planner_failed_total
planner_clarification_rate
planner_option_count
related_skill_discovery_rate
```

### 24.2 Pipeline

```text
pipeline_duration_ms
pipeline_success_rate
failure_stage
web_search_count
web_search_degraded_total
image_generation_count
image_degraded_total
render_duration_ms
tokens_used
```

### 24.3 Workflow

```text
run_created_total
run_awaiting_selection_total
run_completed_total
run_failed_total
run_cancelled_total
run_expired_total
job_retry_total
job_lease_recovered_total
```

### 24.4 Share

```text
share_created_total
share_opened_total
share_revoked_total
share_expired_total
invalid_share_token_total
invalid_media_access_total
share_card_generated_total
```

访问日志不得记录完整 Share Token。

---

## 25. 验收场景

### 25.1 自定义宝宝 Skill

没有固定 Baby Key。Planner 根据 Skill Schema 识别日常、喂养、身高和体重字段。

### 25.2 组合报告

宝宝主 Skill 触发后：

- 提供 Primary-Only Option。
- 发现相关喂养和成长 Skill。
- 提供 Combined Option。
- 用户可以拒绝关联数据。

### 25.3 网球月度战报

使用对手、地点、胜负字段生成：

- 手下败将。
- 风水宝地。
- 最大敌人。
- 简单趋势。
- 轻炫耀表达。

所有数字可回溯到 Evidence。

### 25.4 灵感升华

Planner Option 声明 Optional Web Search，但 Planner 不执行搜索。用户选择并生成后 Pipeline 才搜索。

### 25.5 手动报告隔离

用户第 3 天主动生成宝宝分析，不影响第 7 天 proactive summary Trigger。

### 25.6 Trigger 未点击

只有 TriggerExecution：

- Report 容器为空。
- 没有 Planner Job。
- 没有 Token 消耗。

### 25.7 Evidence 调整

用户修改时间和 Assets：

- 旧 Option 被覆盖。
- 只有一个当前 Planner Job 可以写回。
- 新 Option 显示更新后的数量和范围。

### 25.8 Asset 更新

用户选择后修改 Asset 内容，Pipeline 按 ID 读取最新内容。

### 25.9 Asset 删除

部分 Asset 删除：

- 加入 unavailable。
- 其余数据足够则继续。
- 全部不足则失败并允许调整。

### 25.10 Web

- `optional` 失败：Report 完成并记录降级。
- `required` 失败：Run failed，可从 Web Search 重试。
- `authoritative_only` 没有合格来源：不得用低质量来源补位。

### 25.11 Illustration

图片生成失败时 Report 仍完成，Share Card 使用无插图布局。

### 25.12 Worker 恢复

Worker 在 Content、Render 或 Persist 阶段崩溃：

- Lease 到期可接管。
- 已完成阶段不重复收费。
- 不产生重复 Report。
- 不产生重复 `report_done`。

### 25.13 Report Container

只展示 Active Runs 和 Completed Reports，不展示 TriggerTracker 或未消费 Execution。

### 25.14 私有访问

用户修改 `/app/reports/{report_id}`：

- 无法读取其他用户报告。
- 越权返回 `404`。

### 25.15 公开访问

外部用户只能通过 `/r/{share_token}`：

- URL 不包含 Report ID。
- 修改 Token 无法推导其他 Report。
- Public API 不返回内部 ID。

### 25.16 Media

修改 `media_key`：

- 无法访问未包含在当前 Share Snapshot 中的 File。
- Share 撤销后 Media 立即失效。

### 25.17 Share Card

- 标题和摘要来自 Report。
- 最多三个 Highlights。
- 数字可回溯。
- 二维码指向当前 Share URL。
- 不泄露内部 ID。

### 25.18 Prompt Injection

Asset 或网页包含“忽略系统规则”等文本：

- 只能作为引用数据。
- 不改变 Template。
- 不扩大工具权限。
- 不修改 Execution Plan。

---

## 26. 实施顺序建议

本稿不拆具体编码任务，但能力依赖顺序为：

```text
R1 · ReportGenerationRun + WorkflowJob
R2 · Report Planner + Pending Decision
R3 · Template Registry + 首批 Template Skills
R4 · ReportExecutionPlan + Report Pipeline
R5 · Web Search + 引用
R6 · Chart / Illustration / File
R7 · Official Report Renderer
R8 · ReportShare + Media Authorization
R9 · Share Card
R10 · Observability + Evals
```

实施计划必须引用本稿和另外两份 Theme V2 Spec，不能重新引入旧 Dispatcher、Genre-First 或 Wish Pipeline。
