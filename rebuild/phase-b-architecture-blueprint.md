# Phase B — Eureka 架构蓝图

> 版本：v1.4 | 2026-05-25
> 状态：定稿(集成测试通过,LLM 真调验证 4 个核心场景)
> 用途：Eureka 从零重建的架构基线。定义数据模型、模块边界、Agent 编排、API 契约、前端组件地图。Phase C(后端重建)、Phase D(前端重建)按此为准。
> 演进:
> - v1.0 → v1.1:接受 design `Session + InputTurn` 数据模型(分歧 2)
> - v1.1 → v1.2:接受 design Timeline 被 Calendar Schedule 吸收(分歧 1);接受 File 在资产库的 FileList 入口(分歧 3)
> - v1.2 → v1.3:`input_turn.source` 语义从「session_type 同义」改为「输入模态」(voice / typed / imported),与 session_type 正交;支持混合模态会话(flash session 内可有 typed turn 做 CRUD 跟进 —— 例:语音建待办后打字「改成 4 点」);跨 turn 引用通过 messages 表里的 tool_call 历史解决
> - **v1.3 → v1.4:Event 升级为一级实体(parallel to contacts/files);新增 notes / misc 资产类型;Sessions 可锚定 event(chat-from-event 工作流)**
> - **v1.4.x:Task-skill + external_ref(异步第三方 MCP);render_spec-driven 卡片管线(skill 加新 = 0 代码);Streamable HTTP MCP transport(钉钉 AIHub 等托管 MCP)**
>
> **运行时调用流程图谱(Mermaid)**:`runtime-flow.md`(本目录) —— 完整覆盖 Flash / Chat / Task-skill / MCP 边界 / 卡片管线 / 数据沉淀路径。开发时找「这个请求到底怎么走」的就看那个。

---

## 一、与 Phase A 的关系

本文档建立在 [Phase A 产品定义](phase-a-product-definition.md) 之上,把 Phase A 的产品决定 + 四条架构原则,落实成具体架构。

Phase A 的四条架构原则贯穿全文:
1. 生产级核心 + demo 级边缘,干净接缝
2. AI 体验生产级(流式 / 低延迟 / 自然)
3. 资产类型由 skill 产出、可扩展
4. 数据模型按生产级设计(多用户-ready / InputTurn 一等实体 / 会议留位)

---

## 二、八项核心决定

| # | 主题 | 决定 |
|---|---|---|
| 1 | 多用户准备 | 不建 User 表;FastAPI 依赖 `get_current_user_id()` 做单一来源,demo 返回常量,上线时换鉴权实现 |
| 2 | MCP 接口形态 | 真 FastMCP server,stdio 子进程;ADK `MCPToolset` 标准接入;部署仍是单服务 |
| 3 | 对话上下文窗口 | 固定近 N=20 条消息窗口;长 input_turn(会议)**不进 chat history**,走 MCP 工具(`query_input_turn` / `get_input_turn`)按需检索 |
| 4 | agent 编排 | 双形态 ADK:统一助手(单 LlmAgent + tools)+ Flash Pipeline(Python 编排 3 步、内部用 LlmAgent 实例);共用 MCPToolset;自定义 `PostgresSessionService` |
| 5 | InputTurn / File / flash 关系 | 新增 `File`、`InputTurn` 表(InputTurn 取代原 Transcript 概念);**取消 `flash` 资产类型**;所有派生资产用 `source_input_turn_id` FK 关联 InputTurn |
| 6 | 流式输出 | SSE。后端 `StreamingResponse` + `text/event-stream`;前端 `EventSource` |
| 7 | 呈现模式存储 | localStorage + `usePresentationMode()` hook 抽象;上线接鉴权时改 hook 内部实现,调用方不动 |
| 8 | 资产类型渲染 | D2 完整愿景:`UserSkill.render_spec` 受限 DSL 驱动统一 `SkillCard` 渲染器;5 个初始 skill 预置 spec;**demo 阶段就含 add-skill UI + design agent**,用户加 skill 时 AI 帮设计 card |

---

## 三、数据模型

PostgreSQL 16 + pgvector。**12 张表(v1.4 新增 events / event_attendees / event_files)**。

### v1.4 新增(Event 一级实体)

```
events(id, user_id, title, start_at, end_at, all_day, location, description,
       recurrence_rule, status, sync_source, sync_external_id,
       source_input_turn_id FK input_turns, created_at, updated_at)
event_attendees(event_id FK, contact_id FK NULL, name_raw, role, ...)
event_files(event_id FK, file_id FK, kind, attached_at)
sessions += event_id FK events(id) NULL   ← chat session 锚定到 event
```

事件不走 assets 表 —— 它有结构性关系(参与人 link contacts、文件 link files、可来自第三方同步)。事件 UI 走专门的 EventCard / CalendarPage,**不走 SkillCard render_spec**。

event-skill (Flash Pipeline) 现在调 `create_event` MCP 工具(不再 `create_asset`);events 通过 GET /api/events 暴露给 CalendarPage 渲染。

**Attendee 抽取策略**(v1.4 polish):event-skill 在创建 event 后,会从 source_text 抽取所有「可能的参与方」(具体人名、称呼带头衔、泛称如「客户/团队」、组织名)用 `tool_add_event_attendee(name_raw=X)` 占位,**不查不创建联系人**。前端把 attendee chip 渲染成可点击,用户点击进联系人匹配/创建。理由:不出错的兜底策略好过自动的不准确出错的策略。未来升级智能匹配时,只改 SKILL.md 那一段抽取规则即可。

### 三.5 timeline 锚点(effective_at)—— 跨 kind 统一规则

CalendarPage 的 Schedule 视图下「全部」tab 把所有 kind 混排,需要每种 entity 都有一个**在时间线上的「有效时刻」**。我们引入派生字段 `effective_at`(不存 DB,按规则计算),跟 `created_at` 正交:

| Kind | effective_at = |
|---|---|
| `event` | `start_at` |
| `asset / todo` | `payload.due_date`,无则 `created_at` |
| `asset / expense` | `payload.date`,无则 `created_at` |
| `asset / idea / notes / misc / contact` | `created_at` |
| `input_turn`(voice / imported) | `created_at`(对同步 ASR = 录音瞬间;异步 ASR = 完成瞬间) |
| `input_turn`(typed)| **不上 timeline**(跟 AI 的对话历史,不是生活事件) |
| `file`(上传) | `created_at`(上传瞬间) |

**核心语义**:`created_at` 是审计字段(行什么时候写入 DB),`effective_at` 是 UX 字段(用户视角下这件事什么时候发生 / 生效 / 该出现)。**timezone 一律保留原值透传,前端按浏览器 TZ 渲染**。

**实施**:`backend/core/timeline.py` 是规则实现;`GET /api/timeline?from=&to=&kinds=&skills=` 是 endpoint(Schedule view 「全部」 tab 的数据源)。**timeline 不是独立页面**,只是 CalendarPage Schedule 视图下一个 tab 的数据源。具体类型 tab(event / todo / ...)用各自的专用 endpoint 拿更丰富的 per-kind 数据。

边界细节:
- **typed input_turn 不上 timeline** —— 跟 AI 的对话(chat 提问、flash session 内打字跟进)是 AI 交互历史,不是生活事件;**派生的资产**(todo / event / ...)仍然上 timeline(它们是真实记录,只是被 typed 触发)
- 「同一 effective_at」的 tie-break: `created_at` 升序(确定性)
- 过期 todo:仍按原 `due_date` 出现在原位置,前端用 red accent + 「已逾期 N 天」chip 标记,不「拖到今天」破坏时间线
- 未来 todo / event:正常出现在未来日期(用户往未来滚就能看到)

### v1.4 新增资产类型

`notes`(📝 长文档,会议纪要/报告/briefing)+ `misc`(🗂 兜底,「沉淀为资产」picker 默认目标)。Phase A 把 note 合进 idea 是当时的判断错位,v1.4 拆回来。

### 3.1 总览(ER)

```
User(隐式,demo 阶段不建表;user_id 字符串)
    │
    ├─ owns ─→ File             (音频元数据,demo 不写,真实硬件上线后启用)
    │
    ├─ owns ─→ Session          (4 种类型:flash / chat / meeting / manual)
    │              │
    │              ├─ holds ─→ InputTurn   (一对多,session 内的逐次输入)
    │              │              │
    │              │              ├─ refs ─→ File   (可空;flash/meeting 有,chat 无)
    │              │              │
    │              │              └─ derives ─→ Asset  (派生资产 source_input_turn_id)
    │              │
    │              ├─ holds ─→ Asset       (含 manual session 直接创建的)
    │              └─ holds ─→ Message     (服务统一助手对话流)
    │
    ├─ owns ─→ Asset            (todo / event / idea / expense / ...,payload JSONB)
    │              └─ indexed_by ─→ AssetField (倒排索引)
    │
    ├─ owns ─→ Contact          (名片,独立实体)
    │
    └─ owns ─→ UserSkill        (skill 注册表,含 payload_schema + render_spec)
                   └─ ref ─→ GlobalSkill
```

> **设计细节**:File 直接挂在 InputTurn 上,**不挂 Session** —— 这样一个 session 可以含多个带各自文件的 input_turn(flash 一天多次、多片段会议)。

### 3.2 表定义

**file** —— 音频文件元数据(demo 不写,留位)
```
id              uuid pk
user_id         varchar(50) not null
storage_url     text                  ← 上线时填 GCS / OSS URL
file_type       varchar(50)           ← audio/mp4, audio/wav, ...
duration_sec    integer
source_tag      varchar(20)           ← flash | meeting
asr_status      varchar(20)           ← pending | processing | completed | failed
created_at      timestamptz
```

**input_turn** —— 一次输入(取代 Transcript 概念,一等实体)
```
id                  uuid pk
user_id             varchar(50) not null
session_id          uuid fk session(id) not null
index               integer not null       ← session 内 0-based 序号
file_id             uuid fk file(id)        ← 可空;chat 无 file,flash/meeting 有
source_file_offset  integer                 ← ms in audio(meeting 切片用)
text                text not null
segments            jsonb                   ← 可选 speaker / per-token 细节
source              varchar(20) not null    ← voice | typed | imported(模态,跟 session_type 正交)
asr_provider        varchar(50)
language            varchar(10)
created_at          timestamptz
UNIQUE(session_id, index)
INDEX(user_id, session_id, index)
INDEX(user_id, source, created_at)
```
> `input_turn.source` 是**模态**(voice / typed / imported),跟 session_type **正交**。典型组合:
> - flash session 主要含 source=voice 的 input_turn(每次闪念一次)自带 file_id;**也可能含 source=typed**(用户对刚捕捉的资产做 CRUD 跟进,例:语音建完待办又打字「改成 4 点」)
> - chat session 主要含 source=typed,无 file_id;**也可能含 source=voice**(用户在对话中语音输入)
> - meeting session 含 source=voice 的 input_turn(按 speaker 切,共享 file_id 不同 source_file_offset);**也可能含 source=typed**(用户对会议内容提问)
> - manual session 无 input_turn(用户直接创建资产)

**session** —— App 层组织
```
id              uuid pk
user_id         varchar(50) not null
session_type    varchar(20) not null  ← flash | chat | meeting | manual
title           varchar(255)
date            date                  ← flash session 按天有;其它可空
created_at      timestamptz
INDEX(user_id, date desc)
INDEX(user_id, session_type, created_at)
```
> session_type 说明:
> - `flash`:按自然日聚合的闪念容器(标题如「5月21日闪念」),内部多个 input_turn
> - `chat`:统一助手对话(标题取首条用户消息),内部多个 input_turn(user 消息)
> - `meeting`:会议(本轮不做,数据模型留位)
> - `manual`:用户直接创建资产时挂的占位 session,无 input_turn

**asset** —— 派生资产
```
id                    uuid pk
user_id               varchar(50) not null
user_skill_id         uuid fk user_skill(id) not null   ← 强约束:asset 必属于某 skill
session_id            uuid fk session(id)
source_input_turn_id  uuid fk input_turn(id)             ← 可空(manual session 时为空)
payload               jsonb not null                     ← 字段集由 user_skill.payload_schema 约束
created_at            timestamptz
INDEX(user_id, created_at desc)
INDEX(user_id, user_skill_id, created_at desc)
INDEX(user_id, source_input_turn_id)
```
> 注:`payload.asset_type` 字段移除 —— 类型由 `user_skill_id` 链回 GlobalSkill.name 得到,不再硬编码进 payload。

**asset_field** —— 字段倒排索引(保留)
```
asset_id        uuid fk asset(id) on delete cascade
user_id         varchar(50)
field_name      varchar(100)
value_text      text
value_number    numeric
value_date      timestamptz
PK(asset_id, user_id, field_name)
INDEX(user_id, field_name, value_text)
INDEX(user_id, field_name, value_number)
INDEX(user_id, field_name, value_date)
```

**contact** —— 名片(轻量容器,保留)
```
id              uuid pk
user_id         varchar(50) not null
name            varchar(255) not null
phone           varchar(50)
company         varchar(255)
title           varchar(255)
email           varchar(255)
notes           text[]
created_at      timestamptz
INDEX(user_id, name)
```
> 未来手动 speaker↔contact 匹配预留:`input_turn_speaker_link` 表,但本轮不建。

**message** —— 对话消息(服务统一助手 + Flash Pipeline 出的 agent_summary 也写这里)
```
id              uuid pk
session_id      uuid fk session(id) on delete cascade
user_id         varchar(50)
role            varchar(10)            ← user | agent | tool
text            text
tool_call       jsonb                  ← {name, args} when role=agent and tool was called
tool_result     jsonb                  ← when role=tool
cards           jsonb                  ← 资产卡片渲染数据(派生 asset 的引用 + 渲染快照)
elapsed_ms      integer
created_at      timestamptz
INDEX(session_id, created_at)
```

**global_skill** —— 全局 skill 元定义
```
id              serial pk
name            varchar(50) unique not null     ← todo, event, idea, contact, expense, qa
description     text
created_at      timestamptz
```

**user_skill** —— 用户启用的 skill(含 schema 与 render_spec)
```
id                  uuid pk
user_id             varchar(50) not null
skill_id            integer fk global_skill(id)
display_name        varchar(100)
payload_schema      jsonb              ← 字段定义,可空(qa 系统 skill 为 null)
render_spec         jsonb              ← 受限 DSL,可空(qa 系统 skill 为 null)
queryable_fields    jsonb              ← [{field, index_type}]
created_at          timestamptz
UNIQUE(user_id, skill_id)
```

### 3.3 关键关系说明

- **Asset 一定从某个 UserSkill 出**(强 FK):新加资产类型 = 加 UserSkill,不需要改架构。
- **Asset.source_input_turn_id 可空**:仅 manual session 中用户直接创建的资产无 input_turn 来源;chat 中由 agent 创建的资产**也有** input_turn(指向触发它的用户消息)—— 这是相对 v1.0 修正的 provenance 漏洞。
- **InputTurn 一对多 Asset**:一次输入可能派生多个 asset(一次闪念说出 todo + expense + contact;一句 chat 提问让 agent 建多个待办)。
- **InputTurn ↔ Session 多对一**:一个 flash session(按天)有多次闪念 input_turns;一个 chat session 有多次 user-message input_turns;一个 meeting session 有多个 speaker-切片 input_turns;manual session 无 input_turn。
- **混合模态在同一 session 内被允许**:flash session 既可以有 source=voice 又可以有 source=typed 的 input_turns。后续 CRUD 跟进(「把刚才那个改成 4 点」)由 Assistant 处理,通过加载本 session 最近 N=20 条 messages 看到 prior tool_call+tool_result,识别「刚刚那个」=哪个 asset_id。
- **3.4 处理路径路由**(纯按 input_turn.source 决定,跟 session_type 正交,但 session_type 影响 voice 的具体处理):

| input_turn.source | session_type | 处理路径 |
|---|---|---|
| `voice` | `flash` | **Flash Pipeline**(dispatcher → 并行 skill agents) |
| `voice` | `meeting` | Meeting Pipeline(未来) |
| `voice` | `chat` | **Assistant**(转录文本当 user message 处理) |
| `typed` | 任意 | **Assistant**(意图识别 → CRUD/query/converse) |
| `imported` | 任意 | importer(本轮不实现) |
- **Message 服务于对话流**:统一助手的对话历史 + Flash Pipeline 完成后的 agent_summary 都写进 message,前端用统一接口拉取。

---

## 四、后端模块结构

```
backend/
├── main.py                   FastAPI app 入口,挂路由,初始化生命周期
├── config.py                 settings(已存在,扩展)
│
├── core/
│   ├── auth.py               get_current_user_id() FastAPI 依赖(决定 #1)
│   ├── session_service.py    PostgresSessionService(继承 ADK BaseSessionService,决定 #4)
│   ├── streaming.py          SSE 工具:event 编码、心跳、断连处理(决定 #6)
│   └── llm.py                LLM 客户端配置(LiteLLM via OpenRouter)
│
├── db/
│   ├── database.py           async engine + session(已存在)
│   ├── models.py             SQLAlchemy 模型(按 §三 重定义)
│   ├── queries.py            通用查询工具(asset_fields 索引、结构化查询)
│   ├── migrations/           Alembic
│   └── seed.py               初始化 GlobalSkill + 5 个 UserSkill 的 spec(开发用)
│
├── api/
│   ├── chat.py               POST /api/chat   (SSE,统一助手对话)
│   ├── flash.py              POST /api/flash  (闪念 input_turn ingest → Flash Pipeline)
│   ├── input_turns.py        GET  /api/input-turns/{id}
│   ├── sessions.py           GET  /api/sessions, GET /api/sessions/{id}/messages
│   ├── assets.py             CRUD /api/assets
│   ├── files.py              GET  /api/files (资产库的文件视图)
│   ├── contacts.py           CRUD /api/contacts
│   └── skills.py             GET  /api/skills, POST /api/skills (add-skill + design agent)
│
├── agents/
│   ├── assistant.py          统一助手 LlmAgent + MCPToolset
│   ├── flash_pipeline.py     Python 编排 3 步:dispatcher → 并行 skill agents → 聚合
│   ├── design_agent.py       生成 payload_schema + render_spec 的 LLM agent
│   └── skill_factory.py      根据 UserSkill 注册表造 sub-skill LlmAgent
│
├── mcp/
│   ├── server.py             真 FastMCP server,暴露所有工具(决定 #2)
│   └── tools.py              工具实现,被 server.py 调用(保留并清理)
│
└── skills/
    └── (6 个 SKILL.md prompts:todo / event / idea / contact / expense / qa)
```

死代码 / 旧文件,在 Phase C 全部删除:
- `agents/root_agent.py`、`agents/flash_agent.py`(被 assistant.py / flash_pipeline.py 替代)
- `agents/query_agent.py` (并入 assistant.py)
- `api/query.py`、`api/flash_audio.py`(被 chat.py 替代;audio 暂缓)
- `scripts/fix_skills.py`(临时迁移脚本)
- 各文件里重复的 `tool_*` 包装

---

## 五、API 契约

### 5.1 POST /api/chat —— 统一助手(SSE)

请求:
```json
{
  "session_id": "uuid (optional, empty = create new chat session)",
  "user_text": "用户这一轮的输入"
}
```

服务端处理:
1. 拿到或创建 chat session
2. 为本轮 user_text **创建一个 input_turn**(source=typed, index = session 内下一个)
3. 把 input_turn_id 传给 assistant;任何 agent 创建的 asset 都挂这个 input_turn_id

响应:`text/event-stream`,逐条 SSE event:
```
event: meta
data: {"session_id": "uuid", "input_turn_id": "uuid"}

event: token
data: {"text": "已经"}

event: token
data: {"text": "为你"}

event: tool_call
data: {"name": "create_asset", "args": {...}}

event: tool_result
data: {"asset_id": "uuid", "card": {...spec + payload...}}

event: token
data: {"text": "创建了一个待办。"}

event: precipitate_option
data: {"text": "<最终的 agent 文字回复,可被用户『沉淀为资产』>"}  # 仅当本轮无 tool_call 时发

event: done
data: {"elapsed_ms": 2341, "message_id": "uuid"}
```

### 5.2 POST /api/flash —— 闪念 ingest

请求:
```json
{
  "text": "转录或文字内容",
  "session_id": "optional, default = today's flash session(按天聚合)",
  "source": "voice"
}
```

服务端处理:
1. 拿到或创建当天 flash session(`session_type=flash`, `date=today`)
2. 创建一个 input_turn(source=voice, index = session 内下一个, file_id 若有)
3. 运行 Flash Pipeline,所有派生 asset 挂这个 input_turn_id

响应:`text/event-stream`(同 SSE)或同步 JSON。最终产物:
```json
{
  "input_turn_id": "uuid",
  "session_id": "uuid",
  "derived_assets": [
    {"asset_id": "uuid", "user_skill_id": "uuid", "card": {...}}
  ],
  "summary": "已记录 3 项内容。",
  "elapsed_ms": 3214
}
```

### 5.3 GET /api/skills —— 获取 skill 注册表(前端启动用)

响应:
```json
{
  "skills": [
    {
      "user_skill_id": "uuid",
      "name": "todo",
      "display_name": "待办",
      "payload_schema": { ... },
      "render_spec": { ... }
    },
    ...
  ]
}
```

### 5.4 POST /api/skills —— 加 skill(design agent)

请求:
```json
{
  "description": "我想记录跑步训练"
}
```

响应:`text/event-stream`(design agent 流式输出):
```
event: payload_schema_draft
data: {"fields": [...]}

event: render_spec_draft
data: {...}

event: preview_payload
data: {...mock data for preview...}

event: done
data: {"draft_id": "uuid"}    # 用户审核后 POST /api/skills/{draft_id}/confirm 落库
```

### 5.5 其它(CRUD)

- `GET /api/sessions?type=flash&date=YYYY-MM-DD`
- `GET /api/sessions/{id}/messages`
- `GET /api/sessions/{id}/input-turns`
- `GET /api/assets?type=todo&limit=50&contains=...`
- `PUT /api/assets/{id}` (payload_patch 合并)
- `DELETE /api/assets/{id}`
- `GET /api/input-turns/{id}` —— 拉取完整 input_turn text(给 MCP 工具用,也可直接调)
- `CRUD /api/contacts`
- `GET /api/files` —— 资产库的文件视图入口
- **`CRUD /api/events`(v1.4)** —— 含 attendees / file linking 子路径
- POST /api/chat 接收 **`event_id`** 字段(v1.4):非空时 chat session 锚定到 event,Assistant 系统提示自动注入 event 上下文,可调 get_event/update_event 等
- **`GET /api/timeline?from&to&kinds&skills`(v1.4.x)** —— CalendarPage Schedule view「全部」tab 的数据源;按 effective_at(见 §三.5)合并 events + assets + input_turns + files;**不是独立页面**

不再有 `/api/query`(并入 `/api/chat`);不再有 `/api/flash/audio`(暂缓)。

---

## 六、MCP server 工具集

`backend/mcp_server/server.py` 暴露 **17 个**工具(v1.4 +7 event tools):

| 工具 | 用途 |
|---|---|
| `create_asset(user_skill_name, payload, session_id?, source_input_turn_id?)` | 创建资产,根据 skill 名查 user_skill_id |
| `query_asset(user_skill_name?, contains?, limit?)` | 查询资产 |
| `update_asset(asset_id, payload_patch)` | 更新 |
| `delete_asset(asset_id)` | 删除 |
| `create_contact(name, phone?, company?, title?, email?, notes?)` | 新建名片 |
| `query_contact(name_query?)` | 查名片 |
| `update_contact(contact_id, field, value)` | 更新名片字段 |
| `delete_contact(contact_id)` | 删除名片 |
| `query_input_turn(contains, source?)` | 全文关键词搜索 input_turns |
| `get_input_turn(input_turn_id)` | 拉取完整 input_turn(长 transcript 懒加载) |
| `create_event(title, start_at, end_at?, location?, ...)` | **v1.4** 新建日程事件 |
| `query_event(contains?, from_date?, to_date?, status?)` | **v1.4** 查询事件(含参与人/文件 inline) |
| `get_event(event_id)` | **v1.4** 拿单个 event 详情 |
| `update_event(event_id, patch)` | **v1.4** 改 event 字段 |
| `delete_event(event_id)` | **v1.4** 删除(级联 attendees + files) |
| `add_event_attendee(event_id, name? / contact_id?, role?)` | **v1.4** 加参与人 |
| `link_event_file(event_id, file_id, kind?)` | **v1.4** 绑定文件(prep/recording/notes/...) |

所有工具签名稳定 —— 跟 Phase A skill prompt 兼容,只是从「直接 import 函数」改为「ADK 通过 stdio 调」。

---

## 七、Agent 编排

### 7.1 统一助手(对话)

```python
# backend/agents/assistant.py
def make_assistant(user_id: str, session_id: str) -> LlmAgent:
    mcp_tools = MCPToolset(connection_params=StdioServerParameters(
        command="python", args=["-m", "mcp.server"],
        env={"USER_ID": user_id}
    ))
    return LlmAgent(
        name="assistant",
        model=ASSISTANT_MODEL,
        instruction=_load_prompt("assistant.md", session_id=session_id),
        tools=[mcp_tools],
    )
```

调用:`Runner(agent=..., session_service=PostgresSessionService()).run_async(...)` —— 流式 event 透传到 SSE。

System prompt 包含:
- 用户身份(为 personalization 留位)
- 当前日期、当前 session 信息
- 关联的 long input_turn ID 列表(让 agent 知道可以调 `query_input_turn`)
- 行为规则:意图明确直接 CRUD,模糊则对答(Phase A §五)
- 可用工具说明(从 MCP server 自动获取)

### 7.2 Flash Pipeline

```python
# backend/agents/flash_pipeline.py
async def run_flash_pipeline(input_turn_id: str, user_id: str) -> FlashResult:
    turn = await get_input_turn(input_turn_id)

    # Step 1: dispatcher
    intents = await dispatch(turn.text, user_id, today_str())

    # Step 2: 并行 sub-skill agents
    results = await asyncio.gather(*[
        run_intent(i, turn, user_id) for i in intents
    ])

    # Step 3: Python 聚合(无 LLM)
    return aggregate(results, turn.id)
```

`run_intent` 内部:
- 根据 intent.type 找 UserSkill,造一个 LlmAgent + MCPToolset
- 单回合调用,产出 result 含 asset_id
- 创建 asset 时带上 `source_input_turn_id = turn.id`

### 7.3 Design Agent

```python
# backend/agents/design_agent.py
async def design_skill(description: str) -> SkillDraft:
    # 一个 LlmAgent,输出受限 JSON schema:
    # { payload_schema: {...}, render_spec: {...}, sample_payload: {...} }
    # 用 response_schema 强约束
```

仅在加 skill 流程中用。

### 7.4 Session 管理

`core/session_service.py` 自定义 `PostgresSessionService(BaseSessionService)`:
- ADK 调 `get_session` / `append_event` 时读写 `session` + `message` 表
- 注入 context 时,用决定 #3 的策略:近 N=20 条消息 + system prompt(含 long input_turn IDs)

---

## 八、前端模块结构

```
frontend-next/
├── app/
│   ├── layout.tsx
│   ├── page.tsx              入口(根据 presentation_mode 决定 home)
│   └── ...
│
├── components/
│   ├── AppShell.tsx
│   ├── shell/                top bar, fab, tab bar
│   ├── pages/
│   │   ├── ChatPage.tsx          AI 对话(决定 #6 SSE)
│   │   ├── CalendarPage.tsx      日历(5 状态:Schedule / Month / Year / DayDetail / EventEditor;Schedule 吸收时间流功能)
│   │   ├── LibraryPage.tsx       资产库(6 类型 grid:5 skill + 文件)
│   │   └── AssetDetailPage.tsx   资产详情(含 SessionTurnCard 显示来源)
│   ├── files/
│   │   └── FileList.tsx          专门的文件列表组件(不走 SkillCard,设计 §6.3)
│   ├── chat/
│   │   ├── MessageList.tsx
│   │   ├── MessageBubble.tsx
│   │   ├── AssetCardInChat.tsx
│   │   └── PrecipitateButton.tsx 「沉淀为资产」交互
│   ├── skill/
│   │   ├── SkillCard.tsx         统一 card 渲染器,读 render_spec
│   │   ├── GenericField.tsx      根据 spec 元素画字段
│   │   └── AddSkillWizard.tsx    加 skill UI(design agent 交互)
│   └── ui/                       基础 UI 元素
│
├── hooks/
│   ├── useChat.ts                SSE EventSource 封装
│   ├── useFlashCapture.ts        闪念输入 → /api/flash SSE
│   ├── useSkillRegistry.ts       skill 注册表加载 + SWR 缓存
│   ├── useAssets.ts              资产查询
│   ├── useSessions.ts
│   ├── useInputTurn.ts
│   └── usePresentationMode.ts    localStorage 模式开关(决定 #7)
│
├── lib/
│   ├── api.ts                    HTTP / SSE 客户端
│   ├── sse.ts                    EventSource 工具(决定 #6)
│   ├── render-spec.ts            render_spec 类型 + 解析
│   └── types.ts
│
└── context/
    ├── NavContext.tsx
    └── PresentationModeContext.tsx
```

> 不再有独立 `TimelinePage`/`DayViewPage` —— 设计 §4.4 把时间流功能吸收进 CalendarPage 的 Schedule 视图(分歧 1 已采纳)。
> 文件单独走 `FileList` 组件,不走 SkillCard —— 设计 §6.3 自觉的「一处例外」(分歧 3 已采纳)。

旧组件 Phase D 删除:
- `pages/StreamPage.tsx`、`pages/WorkspacePage.tsx`、`pages/LibraryPage.tsx`(旧) → 重写
- `pages/FlashSessionPage.tsx`、`pages/FlashOverallPage.tsx` → 删
- `pages/DayViewPage.tsx`、`pages/PlaceholderPage.tsx` → 删
- 旧 `pages/AgentChatPage.tsx`、`AssetDetailPage.tsx` → 重写

---

## 九、渲染系统(render_spec DSL)

### 9.1 受限词汇表

```typescript
type RenderSpec = {
  card_layout: 'horizontal' | 'stacked' | 'inline' | 'compact'
  icon: string                            // emoji 或预定义 icon token
  accent_color: AccentColor               // 枚举,不允许任意 hex
  primary_field: string                   // payload 字段名
  primary_format?: FieldFormat            // 可选格式化
  secondary_field?: string
  secondary_format?: FieldFormat
  meta_fields?: Array<{field: string, format?: FieldFormat, label?: string}>
  actions?: Array<'check' | 'edit' | 'delete' | 'open'>
  // 位置渲染元数据
  timeline_position?: {time_field?: string, fallback: 'created_at'}
  calendar_render?: {date_field: string, time_field?: string}
}

type FieldFormat = 'text' | 'relative_date' | 'absolute_date' | 'time' | 'currency' | 'duration' | 'badge' | 'truncate_40'

type AccentColor = 'blue' | 'amber' | 'green' | 'red' | 'purple' | 'gray' | 'neutral'
```

### 9.2 5 个初始 skill 的预置 render_spec

详见 `backend/db/seed.py`(代码已落地)。摘要:

- **todo**:horizontal · ✅ · blue · primary=content · secondary=due_date(relative_date)· actions=check/edit
- **event**:horizontal · 📅 · purple · primary=title · secondary=start_at(absolute_date)· meta=duration/location · calendar_render
- **idea**:stacked · 💡 · amber · primary=title · secondary=content(truncate_40)
- **expense**:horizontal · 💰 · green · primary=amount(currency)· secondary=description · meta=category(badge)/date
- **contact**:horizontal · 👤 · neutral · primary=name · secondary=company · meta=title/phone

### 9.3 统一渲染器

```typescript
// components/skill/SkillCard.tsx
<SkillCard
  spec={userSkill.render_spec}
  payload={asset.payload}
  onAction={(action) => ...}
/>
```

内部根据 `spec.card_layout` 选布局组件,根据 `primary_field` / `meta_fields` 等读 payload 画字段。**没有任何 if-type-equals**。

### 9.4 Add-skill Wizard

`AddSkillWizard.tsx`:
1. 用户描述新 skill —— textarea
2. 调 `POST /api/skills` —— SSE 流式接收 design agent 的 draft
3. 实时显示 schema + spec 预览,带 sample payload 渲染
4. 用户微调(改 icon / 改颜色 / 改字段顺序)
5. 确认 → 落库 → skill 立即可用

---

## 十、迁移策略(Phase C / Phase D 入口)

### 10.1 Phase C(后端)的实施顺序

1. **数据层先行**:写新 Alembic migration(`0001_initial`)按 §三 重塑表;`seed.py` 写入 6 个 UserSkill 的 spec **(Step 1 已完成,v1.1 集成后再校验)**
2. **MCP server 实写**:`mcp/server.py` 暴露所有工具(决定 #2);`mcp/tools.py` 调整签名以适配新 schema(`user_skill_name` 替代 `asset_type`,`source_input_turn_id` 替代 `source_transcript_id`)
3. **core 层**:`auth.py`(决定 #1)、`session_service.py`(决定 #4)、`streaming.py`(决定 #6)、`llm.py`
4. **agents 层**:`assistant.py`、`flash_pipeline.py`(重写)、`design_agent.py`、`skill_factory.py`
5. **API 层**:`chat.py`、`flash.py`、`skills.py`、其它 CRUD
6. **清理死代码**:删 §四 列出的旧文件
7. **`nest_asyncio` 根因排查并清除**(实施时定位,大概率是 LiteLLM 内部 async pattern)

### 10.2 Phase D(前端)的实施顺序

1. **基础设施**:`lib/sse.ts`、`useChat.ts`、`useSkillRegistry.ts`、`render-spec.ts`、`usePresentationMode.ts`、design tokens 接入(`design-tokens.css` + `.theme-atmosphere` 类)
2. **SkillCard 系统**:`SkillCard.tsx` + `GenericField.tsx` —— 渲染核心
3. **ChatPage**:统一对话,SSE 流式 + 沉淀交互
4. **CalendarPage / LibraryPage / AssetDetailPage** —— 用 SkillCard 统一渲染;Calendar 含 5 状态(Schedule/Month/Year/DayDetail/EventEditor)
5. **AddSkillWizard**:add-skill 工作流 + design agent 接入
6. **应用 PresentationMode**:home 根据模式跳转
7. **删除旧组件**(§八列出)

### 10.3 数据迁移

demo 阶段无生产数据。Phase C 实施前清库重建:
```bash
docker compose down -v
docker compose up db -d
alembic upgrade head
python -m db.seed
```

---

## 十一、Phase B 输出验收

完成 Phase B = 本文档定稿 + 已得到用户同意。验收标准:
- ✅ 八项核心决定都有明确选择
- ✅ 数据模型可直接生成 Alembic migration(Step 1 已落地)
- ✅ API 契约可直接写 OpenAPI / 前端 SDK
- ✅ 后端 / 前端模块树可直接对应文件夹结构
- ✅ Phase C、Phase D 的实施顺序明确
- ✅ 三个设计分歧全部集成:Session+InputTurn(2)、Schedule 吸收时间流(1)、FileList 入口(3)

Phase C / Phase D 各自启动时,会基于本文档展开各自的 spec(细化到任务 / 测试 / 校验标准)。
