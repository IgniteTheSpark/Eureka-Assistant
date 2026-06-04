# 02 · 数据模型（Data Model）

> 权威来源：`backend/db/models.py`、`backend/db/seed.py`、`backend/db/seed_demo.py`、
> `backend/db/queries.py`、`backend/db/migrations/versions/`。
> 本章描述**已构建的 schema**，不是规划意图。⚠️ 数据库是 **MySQL**，不是 Postgres。

---

## 1. 总览：14 张表

| # | 表 | 角色 | 一句话 |
|---|---|---|---|
| 1 | `global_skills` | skill 目录 | machine_name + 描述，全局共享（无 user_id）|
| 2 | `user_skills` | skill 实例 | 某用户启用的一个 skill：payload_schema + render_spec + queryable_fields + position |
| 3 | `sessions` | 会话容器 | `flash / chat / meeting / manual` 四类；持有 subject FK + context_asset_ids |
| 4 | `files` | 原始文件 | 录音 / 文档；ASR 状态机；**留位，demo 不实现 pipeline** |
| 5 | `input_turns` | 一次输入 | 一等实体（取代旧 Transcript）；`source = voice/typed/imported` |
| 6 | `assets` | 通用资产 | JSON payload 行；类型经 FK 链推导，**不存 payload 里** |
| 7 | `asset_fields` | 倒排索引 | 每个 queryable 字段一行，供结构化 SQL 查询 |
| 8 | `contacts` | 名片（一级实体）| 真身在此；asset 仅作时间流指针 |
| 9 | `events` | 日程（一级实体）| start_at/end_at；**无 render_spec**，专用 EventCard |
| 10 | `event_attendees` | 事件↔联系人 | 参与人（可链 contact，可裸名）|
| 11 | `event_files` | 事件↔文件 | 会前文档 / 录音 / 纪要 |
| 12 | `messages` | 对话消息 | `role = user/agent/tool`；带 tool_call/tool_result/cards |
| 13 | `tasks` | 异步任务 | 包装第三方 MCP 调用；pending→running→done/failed |
| 14 | `notifications` | 通知 | flash_done/task_done/task_failed/reminder；read=0/1 |

> 旧文档说「12 张表」——那是 v1.4 之前。`tasks`、`notifications` 是后加的。

---

## 2. MySQL 适配（移植者必看）

代码原本为 Postgres 写，后整体迁到 MySQL。三个可移植性 shim 定义在
`models.py` 顶部，**Flutter / 其它后端复刻时必须保持等价语义**：

### 2.1 `GUID` —— UUID 存为 `CHAR(36)`
- MySQL 无原生 UUID。所有主键是 `CHAR(36)`，**应用层用 `uuid.uuid4()` 生成**
  （`default=uuid.uuid4`），不依赖 DB 的 `gen_random_uuid()`。
- 绑定时 `str(uuid)`，读取时转回 `uuid.UUID`。

### 2.2 `UTCDateTime`（别名 `TIMESTAMPTZ`）—— 时区 + 精度
MySQL `DATETIME` 无时区。该 TypeDecorator 解决两个 MySQL 专属坑：
1. **时区**：写入时归一化到 UTC、读取时重新挂上 `+00:00`，使每个序列化时间戳
   都带 `+00:00`，前端 `new Date(...)` 才能正确转本地。**漏掉就会有 N 小时偏移。**
2. **精度**：MySQL 用 `DATETIME(fsp=6)`（微秒）。普通 `DATETIME` 截断到秒 →
   同一轮插入的行 `created_at` 撞值 → `ORDER BY` 随机定序（聊天回放倒序、列表乱序）。
   Postgres 分支用 `TIMESTAMPTZ`。

### 2.3 布尔 = `Integer` 0/1
全库**没有 Boolean 列**。`events.all_day`、`notifications.read` 等都是
`Integer` + `server_default="0"`，序列化时 `bool(...)`。

### 2.4 数组 / JSONB → `JSON`
PG 的 `ARRAY(UUID)` / `ARRAY(Text)` 改为 MySQL `JSON`：
- `sessions.context_asset_ids` —— was `ARRAY(UUID)`，现 `JSON`（默认 `list`）
- `contacts.notes` —— was `ARRAY(Text)`，现 `JSON`（默认 `list`）

### 2.5 MySQL `TEXT` 不能有 `server_default`
`messages.text` 用 Python 端 `default=""`，不是 DB server_default。
`asset_fields.value_text` 是 `TEXT`（无界），建索引须给前缀长度
（`mysql_length={"value_text": 255}`）。

### 2.6 无 `INSERT ... RETURNING`
MySQL 没有。所以 `created_at` 等用 **Python 端 `default=_utcnow`**（flush 时填值），
不能依赖 DB `server_default=func.now()`——否则 session 关闭后读
`obj.created_at` 抛 `DetachedInstanceError`。

---

## 3. 逐表 schema

下列字段定义**逐字对照** `models.py`。类型记法：`GUID`=CHAR(36)、
`TS`=UTCDateTime(带时区)、`JSON`=MySQL JSON、`int(0/1)`=布尔语义。

### 3.1 `global_skills`
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | Integer | PK, autoincrement | **唯一用自增 int PK 的表** |
| `name` | String(50) | unique, not null | machine_name（todo/event/...）|
| `description` | Text | | 人类可读 |
| `created_at` | TS | default now | |

### 3.2 `user_skills`
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null, default `"default"` | 多租户-ready |
| `skill_id` | Integer | FK→global_skills.id | |
| `display_name` | String(100) | | 中文显示名 |
| `payload_schema` | JSON | nullable | 系统 skill（qa）为 null |
| `render_spec` | JSON | nullable | 不产可见资产的 skill 为 null |
| `queryable_fields` | JSON | nullable | 倒排索引字段定义 |
| `position` | Integer | not null, default 0 | 库 SKILLS 网格顺序，拖拽改写 |
| `enabled` | Integer | not null, default 1 | **0/1 活跃标志（设计中，见 §3 skills API / §4.4.5 / §1.3）**。活跃 = 进资产库格子 + agent 路由到它；停用 = 隐藏 + 不路由（该类输入回退 misc），但**历史记录仍可查询**。 |
| `created_at` | TS | | |

> **技能上限（设计中）**：`USER_SKILL_CAP=30`（可**创建**的技能数）；新增 `ACTIVE_SKILL_CAP=9`（同时
> **活跃**的技能数，`enabled=1`）。即「最多写 30 个模板，同时激活 ≤9 个」。系统/常驻 skill（qa /
> external_ref / contact）不计入、不可停用。

唯一约束 `uq_user_skills_user_skill (user_id, skill_id)`。

### 3.3 `sessions`
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null, default `"default"` | |
| `session_type` | String(20) | not null | `flash / chat / meeting / manual` |
| `title` | String(255) | | |
| `date` | Date | nullable | flash 按自然日分组；其它为 null |
| `event_id` | GUID | FK→events.id | **subject FK，四选一** |
| `contact_id` | GUID | FK→contacts.id | subject FK |
| `file_id` | GUID | FK→files.id | subject FK |
| `subject_asset_id` | GUID | FK→assets.id | subject FK |
| `context_asset_ids` | JSON | not null, default `[]` | **附加上下文**（「+ 添加资产」），可变 |
| `created_at` | TS | | |

> **subject FK vs context_asset_ids**：一个 chat-discussion session 恰好设置一个
> subject FK（home subject，永久焦点）；context_asset_ids 是用户临时拉进来的辅料列表。
> 二者在 assistant prompt 里分别注入「本 session 主语」「附加上下文资产」。
> manual / flash session 四个 subject FK 都为 null。

索引：`(user_id,date)`、`(user_id,session_type,created_at)`、`(user_id,event_id)`。

### 3.4 `files`（留位，demo 不跑 pipeline）
| 列 | 类型 | 说明 |
|---|---|---|
| `id` | GUID PK | |
| `user_id` | String(50) not null | |
| `storage_url` | Text | |
| `file_type` | String(50) | |
| `duration_sec` | Integer | |
| `source_tag` | String(20) | `flash / meeting` |
| `asr_status` | String(20) | `pending/processing/completed/failed` |
| `created_at` | TS | |

### 3.5 `input_turns`（一等实体，取代旧 Transcript）
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null | |
| `session_id` | GUID | FK→sessions.id, not null | |
| `index` | Integer | not null | session 内 0-based 位置 |
| `file_id` | GUID | FK→files.id, nullable | typed/chat 无 file |
| `source_file_offset` | Integer | | 音频内 ms（会议分段）|
| `text` | Text | not null | 转录 / 输入文本 |
| `segments` | JSON | | 可选 speaker / per-token |
| `source` | String(20) | not null | **`voice / typed / imported`（模态）** |
| `asr_provider` | String(50) | | |
| `language` | String(10) | | |
| `created_at` | TS | | |

> **两个维度正交**（核心设计）：`session.session_type`（容器）与
> `input_turn.source`（模态）**独立**。API 层路由用 `source`，不是 `session_type`：
> - voice + flash → Flash Pipeline（多意图 fan-out）
> - voice + meeting → Meeting Pipeline（未来）
> - voice + chat → Assistant（转录当作 user text）
> - typed + 任意 → Assistant
> - imported → importer（demo 不做）

唯一约束 `uq_input_turns_session_index (session_id, index)`。

### 3.6 `assets`
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null, default `"default"` | |
| `user_skill_id` | GUID | FK→user_skills.id, **not null** | 类型来源 |
| `session_id` | GUID | FK→sessions.id, nullable | |
| `source_input_turn_id` | GUID | FK→input_turns.id, nullable | provenance；manual 无 |
| `payload` | JSON | not null | 全部业务字段 |
| `created_at` | TS | | |

> **类型不在 payload 里**。`skill_name` 经 FK 链推导：
> `assets.user_skill_id → user_skills.skill_id → global_skills.name`。
> 旧 `payload.asset_type` 字段已彻底移除。

索引：`(user_id,created_at)`、`(user_id,user_skill_id,created_at)`、`(user_id,source_input_turn_id)`。

### 3.7 `asset_fields`（queryable 倒排索引）
复合主键 `(asset_id, user_id, field_name)`。

| 列 | 类型 | 说明 |
|---|---|---|
| `asset_id` | GUID | FK→assets.id **ON DELETE CASCADE** |
| `user_id` | String(50) | |
| `field_name` | String(100) | |
| `value_text` | Text | 文本值（索引前缀 255）|
| `value_number` | Numeric | 数值 |
| `value_date` | TS | 日期 |

写路径：`index_asset_fields()`（`db/queries.py`）在每次 asset 创建/更新后，
按 user_skill.queryable_fields 抽字段写入；`_classify_value()` 决定值落 text/number/date
哪一列。索引：`(user_id,field_name,value_number)`、`(...value_text[255])`、`(...value_date)`。

### 3.8 `contacts`（一级实体）
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null, default `"default"` | |
| `name` | String(255) | not null | |
| `phone` | String(50) | | |
| `company` | String(255) | | |
| `title` | String(255) | | |
| `email` | String(255) | | |
| `notes` | JSON | default `[]` | was ARRAY(Text)；append-only |
| `source_input_turn_id` | GUID | FK→input_turns.id, nullable | provenance（驱动时间流 ⚡「联系人 ×1」）|
| `created_at` | TS | | |

> contact 的「真身」在此表。`contact` skill 的 asset 只是时间流/库里的**引用指针**，
> payload 形如 `{contact_id, name, company, title, phone}`，指向真身。

### 3.9 `events`（一级实体，v1.4）
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null, default `"default"` | |
| `title` | String(255) | not null | |
| `start_at` | TS | **not null** | |
| `end_at` | TS | nullable | |
| `all_day` | int(0/1) | default 0 | |
| `location` | String(255) | | |
| `description` | Text | | |
| `recurrence_rule` | String(255) | | iCal RRULE；null=不重复 |
| `status` | String(20) | default `scheduled` | `scheduled/cancelled/done` |
| `sync_source` | String(20) | | `manual/google/outlook/...`；null=manual |
| `sync_external_id` | String(255) | | 上游 id，同步去重 |
| `source_input_turn_id` | GUID | FK→input_turns.id | 语音创建时的 provenance |
| `created_at` | TS | | |
| `updated_at` | TS | onupdate | |

> **Event 没有 render_spec**——它是一级实体，前端用专用 `EventCard` / `CalendarPage`
> tile 渲染，不走 SkillCard。`event` 仍在 `global_skills` 里（dispatcher 识别 event 意图），
> 但**不在** `USER_SKILL_CONFIGS` 里（v1.4 从 skill 提升为一级实体）。
>
> **硬校验**（`create_event`）：event 必须有可渲染时段——`end_at` 或 `all_day=1`
> 至少其一。裸 `start_at` 会被**大声拒绝**（应是 todo）。见 [§01](01-agent-architecture.md) dispatcher 规则。

唯一约束 `uq_events_sync (user_id, sync_source, sync_external_id)`。
索引：`(user_id,start_at)`、`(user_id,status,start_at)`。

### 3.10 `event_attendees`
`id` GUID PK · `event_id` FK→events **CASCADE** not null · `contact_id` FK→contacts nullable
（裸名时 null）· `name_raw` String(255)（contact_id 为 null 时的显示）· `role` String(20)
default `attendee`（`organizer/attendee/optional`）· `created_at`。

### 3.11 `event_files`
`id` GUID PK · `event_id` FK→events **CASCADE** not null · `file_id` FK→files not null ·
`kind` String(20) default `attachment`（`prep/recording/notes/attachment`）· `attached_at`。
唯一约束 `uq_event_files (event_id, file_id)`。

### 3.12 `messages`
| 列 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `session_id` | GUID | FK→sessions.id **CASCADE**, not null | |
| `user_id` | String(50) | not null, default `"default"` | |
| `role` | String(10) | not null | `user / agent / tool` |
| `text` | Text | default `""`（Python 端）| |
| `tool_call` | JSON | | agent 调工具时 `{name, args}` |
| `tool_result` | JSON | | 工具输出（role=tool）|
| `cards` | JSON | default `[]` | 渲染卡片快照 |
| `elapsed_ms` | Integer | | |
| `created_at` | TS | | |

索引 `(session_id, created_at)`。

### 3.13 `tasks`（异步第三方 MCP）
`id` GUID PK · `user_id` · `user_text` Text not null（原始指令）· `mcp_target` String(50)
（agent 选完工具后填，notion/google_calendar/...）· `status` String(20) default `pending`
（`pending/running/done/failed`）· `error_message` Text · `result_asset_id` FK→assets.id
（最终持 external_ref payload 的占位 asset）· `session_id` FK→sessions.id ·
`source_input_turn_id` FK→input_turns.id · `started_at` · `completed_at` · `created_at`。
索引 `(user_id,status,created_at)`、`(session_id,created_at)`。
两阶段生命周期见 [§01 Task Pipeline](01-agent-architecture.md)。

### 3.14 `notifications`
`id` GUID PK · `user_id` · `type` String(20) not null
（`flash_done/task_done/task_failed/reminder`）· `title` String(255) not null · `body` Text ·
`link` String(255)（不透明 deep-link 目标，通常 asset/event id）· `read` int(0/1) default 0 ·
`created_at`。索引 `(user_id, created_at)`。

### 3.15 `reports`（设计规格 · 待实现 —— 合成/报告引擎，见 [§6](06-synthesis-report.md)）

> 第 15 张表(上方「14 张表」是当前已实现的快照;reports 为新 feature 新增)。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null | 多租户隔离 |
| `title` | String(255) | not null | dispatcher 给的标题 |
| `genre` | String(30) | not null | `data-report / idea-synthesis / proposal / digest` |
| `content_md` | Text(LONGTEXT) | not null | 注解 Markdown(substance,可重渲染) |
| `html` | Text(LONGTEXT) | not null | 渲染快照(用户当下看到的单文件 HTML) |
| `spec_json` | JSON | not null | `{time_range, asset_types, source_asset_ids, surface, palette, seed}`(可重跑) |
| `created_at` | TS | default now | |

索引 `(user_id, created_at)`。新增 `session_type='report'`(第 5 种会话类型,引导对话挂在它上)。
`source_asset_ids` 存进 `spec_json` 做来源可追溯(不建外键表,beta 从简)。

### 3.16 `connected_apps`（设计规格 · 待实现 —— Connected Apps，见 [§1.7.1](01-agent-architecture.md)）

> 第 16 张表。per-user 的外部 MCP 连接 + 加密凭据。**connector 目录本身不入库**(开发者维护在
> `MCP_SERVER_CATALOG`,通过 `/api/connectors` 暴露);本表只存"某用户连了某 connector + 他的凭据/状态"。

| 字段 | 类型 | 约束 | 说明 |
|---|---|---|---|
| `id` | GUID | PK | |
| `user_id` | String(50) | not null | 多租户隔离 |
| `connector_id` | String(50) | not null | 指向 catalog 的 key(`dingtalk_calendar` / `notion` / …) |
| `display_name` | String(100) | | 用户可改的别名(默认取 catalog 名) |
| `auth_type` | String(20) | not null | `token / gateway_url / oauth` |
| `credentials_enc` | Text | not null | **加密** blob(对称加密;明文是 `{字段名: 值}`)。**绝不**进任何 API 响应/日志 |
| `config_json` | JSON | nullable | 非密配置(scopes、gateway base、选项) |
| `status` | String(20) | not null | `connected / needs_reauth / error / disconnected` |
| `last_used_at` | TS | nullable | 最近一次被 task runner 使用 |
| `created_at` | TS | default now | |

唯一约束 `(user_id, connector_id)`(一个用户一个 connector 一条)。索引 `(user_id, status)`。
`credentials_enc` 用服务端密钥对称加密(密钥走 env / KMS,**不**入库、**不**回客户端)。

---

## 4. Provenance（来源链）

每个 asset / event / contact 都可经 `source_input_turn_id` 回溯：

```
asset/event/contact.source_input_turn_id
   → input_turns.id (.session_id, .file_id, .text)
      → sessions.id (.session_type)
      → files.id (.storage_url, 录音)
```

可追到「哪句话、哪次输入、哪个录音」产生的。manual / chat 创建的实体此 FK 为 null。
时间流 ⚡「闪念捕捉」摘要（「待办×2 · 联系人×1」）正是按 input_turn 反查派生实体统计出来的。

---

## 5. render_spec DSL（卡片渲染契约）

存在 `user_skills.render_spec`（JSON）。前端据此**通用渲染** SkillCard，**无 if-type-equals**。
权威类型见前端 `frontend/src/lib/render-spec.ts`，详见 [§04](04-frontend.md)、[§05](05-design-system.md)。

### 5.1 字段
| key | 取值 | 说明 |
|---|---|---|
| `card_layout` | `horizontal / stacked / inline / compact` | 四种布局 |
| `icon` | emoji 字符串 | 图标 |
| `accent_color` | `blue/amber/green/red/purple/gray/neutral` | 7 槽强调色（CSS 另有 cyan）|
| `primary_field` | payload 字段名 | 主文本 |
| `primary_format` | 见下 | 主文本格式化 |
| `secondary_field` | payload 字段名 | 副文本 |
| `secondary_format` | 见下 | |
| `meta_fields` | `[{field, format?}]` | 元信息 pills（仅渲染真值）|
| `actions` | `["check","edit","delete","open","open_external"]` | 卡片动作 |
| `timeline_position` | `{time_field, fallback?}` | 时间流排序锚 |
| `calendar_render` | `{date_field}` | 日历落点 |

### 5.2 format 词汇（`applyFormat`）
`relative_date`（3天后 / 昨天）· `absolute_date`（5月29日）· `currency`（¥ 金额）·
`truncate_N`（截断到 N 字，如 `truncate_40`）· `badge`（徽章）。

> `check` 动作（复选框）**仅当** payload 真有 `status`/`done` 字段时才渲染
> （`buildCard` 守卫，避免幻影复选框）。

---

## 6. payload_schema（字段契约）

存在 `user_skills.payload_schema`（JSON）。描述某 skill 的 payload 字段、类型、required、enum、default。
agent 的 `create_asset` 必须严格按字典填字段名。

---

## 7. Seed 数据

### 7.1 `db.seed`（核心，幂等）—— 9 个 global_skills + 8 个 user_skills
`GLOBAL_SKILLS`（9）：`todo / event / idea / notes / misc / contact / expense / qa / external_ref`。

`USER_SKILL_CONFIGS`（8，**注意 event 不在内**——已提升为一级实体）。各 skill 完整
payload_schema + queryable_fields + render_spec 见 [§99 附录](99-prompts-appendix.md#seed-render-specs)，
摘要：

| skill | layout | icon | accent | primary | secondary | queryable | actions |
|---|---|---|---|---|---|---|---|
| `todo` | horizontal | ✅ | blue | content | due_date (relative_date) | due_date(date), status(enum) | check, edit |
| `idea` | stacked | 💡 | amber | title | content (truncate_40) | — | edit, open |
| `contact` | horizontal | 👤 | neutral | name | company | name(text), company(text) | edit, open |
| `expense` | horizontal | 💰 | green | amount (currency) | description | amount(numeric), category(enum), date(date), at(date), merchant(text) | edit |
| `notes` | stacked | 📝 | gray | title | content (truncate_40) | — | edit, open |
| `misc` | inline | 🗂 | gray | content | — (truncate_40) | — | edit, delete |
| `qa` | **null** | — | — | — | — | **null** | — |
| `external_ref` | horizontal | 🔗 | purple | title | external_system | external_system(enum), status(enum) | open_external, delete |

- `todo` 额外有 `timeline_position={time_field:due_date,fallback:created_at}` +
  `calendar_render={date_field:due_date}`。
- `qa` 是 system skill：`payload_schema=null` + `render_spec=null` + `queryable_fields=null`
  —— 这就是「系统能力、无资产产出」的契约。
- `external_ref` 有 `timeline_position={time_field:created_at}`。
- `expense.payload` 含 `at`（含时刻，timeline 优先用此）和 `date`（仅日期）两个字段。

### 7.2 `db.seed_demo`（可选演示数据）
seed_demo 在核心 seed 之上灌入演示资产：约 **17 个 assets + 4 个 events + 3 个 contacts**
（覆盖 todo/idea/notes/expense/misc + contact 引用 + 一批日程），用于「打开即有内容」。
非幂等，按需运行。详细行内容以 `backend/db/seed_demo.py` 为准。

---

## 8. 已知残留 bug（复刻时别照抄）

1. **`db/queries.py:158`** —— `query_assets_structured` 返回里引用
   `a.source_transcript_id`，但该列在 v1.3+ 已改名 `source_input_turn_id`。
   这条函数路径跑到会 `AttributeError`。正确字段名见 §3.6。
2. **`api/skills.py` 级联删除** —— 用了 Postgres 专有 SQL（`array_remove(...)` /
   `CAST(... AS uuid)`），在 MySQL 上跑不通。见 [§03](03-api-reference.md)。

> 这两处是从 Postgres 迁 MySQL 时漏掉的死角。复刻时按 MySQL 语义重写，不要照搬。
