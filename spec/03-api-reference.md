# 03 · API 参考

> FastAPI app `Eureka API` v1.4.0。所有路由前缀 `/api`（除 `/health`）。
> **鉴权（TestFlight beta 起）**：邮箱+密码 → HS256 token。`get_current_user_id()` 从
> `Authorization: Bearer <token>` 解析 user id，缺失/失效 → 401。**除 `/api/auth/*` 与 `/health`
> 外所有路由都要带 token**；数据全部按 `user_id` 隔离（注册时自动 provision 基线 skills）。多租户已上线
> （旧 `"default"` 数据仅为开发种子）。CORS 全开。落库契约见 [§2 数据模型](02-data-model.md)；
> agent 行为见 [§1](01-agent-architecture.md)。
> **百智 OAuth 登录(设计中,[§13.1](13-baizhi-integration.md))**:新增以百智作 IdP 的登录 —— bridge→换 token→映射到 Eureka `user_id`→**仍签发 Eureka 自己的 JWT**(每请求鉴权不变);百智真实 token 单独加密存,供调百智 MCP/API。

约定：除特殊说明外，响应体均含 `{"ok": true, ...}`；错误用 HTTP 4xx + `{"detail": "..."}`
（FastAPI HTTPException）或 `{"ok": false, "error": "..."}`（业务失败）。时间戳一律 ISO8601。

**路由注册顺序**（`main.py`，12 个 router）：chat, flash, skills, input-turns, files, assets,
sessions, contacts, events, timeline, tasks, notifications。

| 方法 | 路径 | 流式 | 用途 |
|---|---|---|---|
| POST/GET | `/api/auth/{register,login,me}` | 同步 | 邮箱+密码鉴权（register/login 免 token；me 需 token） |
| POST | `/api/chat` | **SSE** | 统一 Assistant 对话 |
| POST | `/api/flash` | 同步 JSON | 捕捉管线 |
| POST | `/api/flash/listening` | 同步 | 录音开关（ephemeral，发 SSE 信号） |
| GET/POST/PUT/DELETE | `/api/skills*` | 同步 | 自定义 skill 设计与管理 |
| GET | `/api/input-turns/{id}` | 同步 | 单条输入详情 |
| GET | `/api/files*` | 同步 | 文件列表（demo 常空） |
| GET/POST/PUT/DELETE | `/api/assets*` | 同步 | 资产 CRUD |
| GET/POST/PATCH/DELETE | `/api/sessions*` | 同步 | 会话容器 |
| GET/POST/PUT/DELETE | `/api/contacts*` | 同步 | 名片（一级表） |
| GET/POST/PUT/DELETE | `/api/events*` | 同步 | 日程（一级表） |
| GET | `/api/timeline` | 同步 | 跨类型时间线混排 |
| GET | `/api/tasks*` | 同步 | 异步任务只读面 |
| GET/POST/DELETE | `/api/notifications*` | 含 **SSE** | 通知 |
| GET | `/api/notifications/stream` | **SSE** | 实时通知推送 |
| GET | `/health` | 同步 | `{"status":"ok","version":"phase-b-v1.4"}` |

---

## 3.1 `POST /api/chat` — 统一 Assistant（SSE）

**请求** `ChatRequest`：
```json
{ "user_text": "帮我建个明天交报告的待办", "session_id": "<uuid|可空>", "event_id": "<uuid|可空>" }
```
- `session_id` 空 → 新建 chat session。
- `event_id` 给定 → agent 知道「当前在某个 event 的上下文里聊」（注入主题提示）。

**响应** `text/event-stream`，事件序列：

| event | data | 时机 |
|---|---|---|
| `meta` | `{session_id, input_turn_id}` | 流开始，先告知 id |
| `token` | `{text}` | 逐 token 增量文本 |
| `tool_call` | `{name, args}` | agent 调工具（如 create_asset） |
| `tool_result` | `{name, response}` | 工具返回（含可抽出的卡片） |
| `done` | `{elapsed_ms, message_id, total_tokens}` | 正常结束 |
| `error` | `{message}` | 异常 |

**机制**：
- `_looks_like_leaked_call` 检测 DeepSeek 把 function-call 当文本吐出 → 重试一次（`MAX_ATTEMPTS=2`）。
- `_cards_from_tool_result` 从工具结果抽资产卡片，持久化进 `messages`。
- 持久化 user + agent 两条 message；report 消息落库前剥掉笨重 html（只留指针/标题）。
- `_QUERY_TOOLS` 集合内的工具不算「产生资产」（用于判断是否展示「沉淀为资产」入口）。

> ⚠️ **持久性缺口(设计中,见 [§1.5.1.1](01-agent-architecture.md))**：现状把跑 agent + 落库**全放进 SSE 生成器、且只在跑完才落 user+agent**，离开 page→断流→**生成被取消 + 一条不落**。需求改为:**收到即落 user msg + 回合 `status`**、生成跑成**后台任务**(断流也跑完)、返回按回合 status **轮询对账**;并加一个「取 in-flight 回合 / 重连」查询。对齐 flash 的 `has_pending` 持久模型。

---

## 3.2 `POST /api/flash` — 捕捉管线（同步 JSON）

> ⚠️ flash 是**同步 JSON**，不是 SSE（旧文档常误标）。

**请求** `FlashRequest`：
```json
{ "text": "明天下午三点跟客户开会，午饭花了68", "session_id": "<uuid|可空>",
  "source": "voice", "file_id": "<uuid|可空>" }
```
- `source` ∈ `voice`（麦克风/语音模拟，默认）/ `typed` / `imported`，正交于 session_type。
- flash session **按自然日聚合**：同一天的闪念进同一个 `{月}月{日}日 闪念` session。

**响应** `FlashResponse`：
```json
{
  "ok": true,
  "session_id": "...",
  "input_turn_id": "...",
  "reply": "已记录 1 个日程、1 笔消费",
  "summary": "日程×1 · 记账×1",
  "cards": [ /* 渲染好的卡片，见 §2 render_spec */ ],
  "derived_assets": [ /* asset/event/contact 摘要 */ ],
  "has_pending": false,
  "elapsed_ms": 4213,
  "error": null
}
```
- `cards` 由 pipeline Step 3 纯 Python 聚合（event/task/contact/pending_contact 特殊分支 + 通用
  render_spec 路径）。
- `has_pending: true` 表示含异步 task placeholder（前端轮询 `/api/tasks/{id}`）。
- 产生一条 `flash_done` 通知（link=session_id）。**通知文案 = 纯标题「闪念已整理」,body 留空**(产品决策 2026-06,无多余文字)。
- **domain(§8):** flash dispatcher 在每个 intent 上判一个 `domain`,pipeline 建好 asset 后 `_apply_domain()` 覆盖到 `assets.domain`(覆盖技能 prior)—— 闪念产出的卡片**按内容打域**,不再只吃 notes/随记 prior。

> **硬件录入桥(dev 集成,代码在 `bizcard/Eureka-BrandNew/integrations/flash-card/`):** W1/W2 录音卡 → FlashType(macOS,BLE+Opus 解码)→ `external` ASR hook `eureka-bridge.py`(whisper.cpp 本地转写 → **带 JWT** `POST /api/flash`)→ 闪念入库 + `capture`/`flash_done` SSE → app。`/api/flash` 需鉴权,桥用 `docker exec create_token` 现取(无盘上 token)。stdout 只回纯转写(诊断写文件 —— FlashType 把 stdout+stderr 合并当转写)。
>
> **手机直连(设计中,[§13.3](13-baizhi-integration.md)):** W1/W2 就是百智录音卡 → 把百智 `RecordSDK`(Swift `BluetoothDeviceManager`)封成 **Flutter 插件**,**手机直接** BLE/WiFi 同步 + 闪念事件 → 剥 MARK → ASR → `POST /api/flash`,**去掉 macOS 桥**(桌面桥保留作 dev 路径)。这是「手机优先捕捉」的解锁。

### `POST /api/flash/listening`

```json
{ "state": "on" }   // 或 "off"
```
录音状态开关，**ephemeral**（不落库），通过通知 SSE 频道发 `listening` 信号给前端（驱动麦克风动画）。

> 硬件侧由 `listening-watcher.py`(tail FlashType 日志,见 started/finished → POST 此端点)驱动「正在聆听」浮层。**注意**:W1/W2 卡缓冲后传输,`started` 约在释放/传输时触发,浮层可能短暂/略延迟 —— 完美的「按住即录」指示需 FlashType 侧实时 press/release 信号。

---

## 3.3 `/api/skills` — 自定义 skill

| 方法 | 路径 | 请求 | 说明 |
|---|---|---|---|
| GET | `/api/skills` | — | 列用户 skill（**全部**，含停用）。**过滤掉 system skill**（render_spec 为 null 的，如 qa）。每条带 `enabled`（0/1，活跃集）+ `position` + `domain`（§8 prior：基线技能有值、自定义为 null）+ `chat_starters`（§1.5.1 会话开场 hint 用）+ 顶层 `active_cap` |
| POST | `/api/skills` | `DraftSkillRequest{description, answers?}` | 草拟。两段式：先 clarify，ready 则 design |
| POST | `/api/skills/confirm` | `ConfirmSkillRequest{name, display_name, payload_schema, render_spec, queryable_fields, chat_starters?}` | 落成 UserSkill。`USER_SKILL_CAP=30`（**创建**上限）。`chat_starters`（2-3 条起聊文案，§1.8）随 design 产出落库，喂会话开场 hint（§1.5.1） |
| DELETE | `/api/skills/{user_skill_id}?force=` | — | 删。有资产时 409（除非 `force=true`）；system skill 403 |
| PUT | `/api/skills/reorder` | `ReorderSkillsRequest{order: [user_skill_id...]}` | 重排资产库网格顺序 |
| PUT | `/api/skills/active` | `{active_ids:[user_skill_id...]}` | **设活跃集**（技能管理页「保存」）。原子写 `enabled`：列表内置 1、其余置 0。**超 `ACTIVE_SKILL_CAP=9` → 409**。下条 agent 消息即按新集路由。**`_CAP_EXCLUDED`(external_ref/qa/contact + 常驻 todo/notes)不参与 toggle、不计入 cap、永不被停用** |

**POST /api/skills 流程**：`description` + 可选 `answers`（clarifier 问题的回答）→ `clarify_skill`
返回 `{ready}` 或 `{questions}`；ready 则 `design_skill` 产 draft 供前端实时预览。

**活跃集（已实现，见 [§4.4.5](04-frontend.md) + [§2 `user_skills.enabled`](02-data-model.md)）**：`enabled=1` 的技能才进
资产库格子、才被 agent 路由（dispatcher hint / flash·chat 技能字典都 **WHERE enabled=1**）。停用的：隐藏 +
不路由（回退 misc），但**查询历史不过滤 enabled**（停用后仍能查它的旧记录）。新建技能默认 `enabled=1`
（若已满 9，则落为停用，提示去管理页激活）。**无需重启 agent**——每请求现拉，保存即下条生效。

> ⚠️ **已知 bug（复刻别照抄）**：`DELETE /api/skills/{id}` 的级联清理用了 Postgres 专有 SQL
> （`array_remove(context_asset_ids, CAST(:aid AS uuid))`，`skills.py:325-333`），**在 MySQL 上跑不通**。
> 复刻时改成应用层读出 JSON 数组、过滤、写回。

---

## 3.4 `/api/assets` — 资产 CRUD

| 方法 | 路径 | 请求 / 查询参数 | 说明 |
|---|---|---|---|
| GET | `/api/assets` | `user_skill_name, session_id, field, op, value, contains, limit, domain?` | 列表(`limit` 默认 50)。给了 `field/op/value` 走 `asset_fields` 结构化查询;`domain` 可选过滤(8 选 1) |
| GET | `/api/assets/counts` | — | **每技能全量计数**(all-time `GROUP BY`):`{counts:{<skill>:<n>}, total}`。资产库容器格子用它显**总数**(不是 `/api/assets` 那个 limit=50 窗口里碰巧有几条)。**路由上必须在 `/{id}` 之前声明** |
| GET | `/api/assets/{id}` | — | 单条 |
| POST | `/api/assets` | `CreateAssetRequest{user_skill_name, payload, session_id, source_input_turn_id, domain?}` | → `tool_create_asset`。`domain` 省略 → 服务端回落技能 prior 或 null（§7） |
| PUT | `/api/assets/{id}` | `UpdateAssetRequest{payload_patch?, domain?}` | patch 合并 + 重建 `asset_fields`;`domain` 与 payload 同一次提交(编辑表单改领域,§4.4.3a) |
| DELETE | `/api/assets/{id}` | — | 删 |

`_serialize_asset` 返回：`{id, user_skill_name, payload, domain, session_id, source_input_turn_id, created_at}`。
注意 `user_skill_name` 经 FK 链 `assets.user_skill_id → user_skills.skill_id → global_skills.name` 派生，
**类型不在 payload 里**。

> ⚠️ **已知 bug**：`db/queries.py:158` 的 `query_assets_structured` 仍引用已重命名的列
> `source_transcript_id`（现为 `source_input_turn_id`），会 AttributeError。复刻时用新列名。

---

## 3.5 `/api/sessions` — 会话容器

| 方法 | 路径 | 请求 / 参数 | 说明 |
|---|---|---|---|
| GET | `/api/sessions` | `date, session_type, limit` | 列表 |
| POST | `/api/sessions` | `CreateSessionRequest{session_type, title, date, context_asset_ids, subject_type, subject_id, peek_only}` | 3 种模式（见下） |
| GET | `/api/sessions/{id}` | — | 详情 + asset_count + turn_count + 4 个 subject FK + assets |
| GET | `/api/sessions/{id}/messages` | — | 消息（最旧在前，role_rank 平手时排序） |
| GET | `/api/sessions/{id}/input-turns` | — | 该 session 的输入 |
| PATCH | `/api/sessions/{id}/context` | `PatchContextRequest{add, remove}` | 增删 `context_asset_ids`。`add`/`remove` 是 asset id 列表，多选 picker 一次 PATCH 全加 |
| DELETE | `/api/sessions/{id}` | — | 删会话 + 转录（messages）。**产生的 asset/task 不删**，`session_id→NULL` detach 保留；`input_turns`（session_id NOT NULL）删除前先把引用它们的 `source_input_turn_id` 清空 |

**POST 三种模式**：
1. **subject get-or-create**：给 `subject_type` + `subject_id`（如某 event/contact/asset）→ 找到或新建
   讨论该主题的 session。
2. **fresh + context**：给 `context_asset_ids` → 新 session 预载一组资产上下文。
3. **blank**：都不给 → 空白新 session。

`peek_only=true` 只查不建。session 有 4 个 subject FK（`event_id`/`contact_id`/`file_id`/`subject_asset_id`，
chat-discussion 模式恰好置一个）+ `context_asset_ids`（JSON，additive）。

> ⚠️ **`context_asset_ids` 必须存字符串,不能存 `uuid.UUID` 对象**（曾导致「添加资产」500 → 前端「添加失败」）。
> 它是 **JSON 列**,`UUID` 不可 JSON 序列化;且若混存 UUID 对象,`uuid in current_strings` 去重永远不命中。
> POST 与 PATCH 都要：用 `uuid.UUID(s)` **校验**、`str(...)` **存储**;读出的现有值也先 `str()` 归一再比较。

---

## 3.6 `/api/events` — 日程（一级表）

委托 `mcp_server.tools` 的 event 工具。

| 方法 | 路径 | 请求 | 说明 |
|---|---|---|---|
| GET | `/api/events` | `from, to, contains, limit` | 列表 |
| GET | `/api/events/{id}` | — | 单条（含 attendees / files） |
| POST | `/api/events` | `EventCreate{title, start_at, end_at?, location?, description?, all_day?, recurrence_rule?, source_input_turn_id?}` | 硬校验：需 `end_at` 或 `all_day=1` |
| PUT | `/api/events/{id}` | `EventPatch`（仅非 None 字段生效） | 部分更新 |
| DELETE | `/api/events/{id}` | — | 删 |
| POST | `/api/events/{id}/attendees` | `AttendeeCreate{name, contact_id?, role?}` | 加参与人（`name_raw` 占位或绑 contact） |
| POST | `/api/events/{id}/files` | `EventFileLink{file_id, kind}` | 关联文件 |

> event **无 render_spec**：前端用专用 `EventCard`（不是通用 SkillCard）。前端用 `event_id` 而非 `id`。

---

## 3.7 `/api/contacts` — 名片（一级表）

`contacts` 表是 contact 数据的「真身」；asset 形态的 contact 只是 timeline 指针（payload 带 contact_id）。
**前端手动建名片 POST 到这里**（不是 /api/assets），这样 agent 查 contact 能在对的表里找到。

| 方法 | 路径 | 请求 | 说明 |
|---|---|---|---|
| GET | `/api/contacts` | `q`（名字搜）, `limit` | 列表，name ilike 模糊 |
| GET | `/api/contacts/{id}` | — | 单条 |
| POST | `/api/contacts` | `ContactCreateRequest{name(必), phone?, company?, title?, email?, notes?}` | 手动建（SkillCreateForm） |
| PUT | `/api/contacts/{id}` | `ContactUpdateRequest{同上全可选}` | 仅发来的字段生效（None=不动） |
| DELETE | `/api/contacts/{id}` | — | 删 |

序列化：`{id, name, phone, company, title, email, notes, created_at}`。`user_id` 此路由硬编码 `"default"`。

---

## 3.8 `GET /api/timeline` — 跨类型混排

**参数**：`from, to, kinds, skills, limit` → `core.timeline.assemble_timeline`。
**响应**：`{ok, items, count}`。

`TimelineItem.kind` ∈ `asset / event / contact / input_turn / file`。混排按 **`effective_at`**（派生字段，
不存库）排序，每 kind 规则：

| kind | effective_at |
|---|---|
| event | `start_at` |
| todo | `due_date` \|\| `created_at` |
| expense | `at` \|\| `date` \|\| `created_at` |
| idea / notes / misc / contact | `created_at` |
| input_turn | `created_at`（**`source="typed"` 的排除出 timeline**） |
| file | `created_at` |

`_derived_breakdown` 为 input_turn 生成 ⚡ 摘要（如「待办×2 · 联系人×1」，统计该次输入派生了什么）。
`_format_value` 把 ISO → 「M月D日 HH:MM」。

---

## 3.9 `/api/tasks` — 异步任务只读面

| 方法 | 路径 | 参数 | 说明 |
|---|---|---|---|
| GET | `/api/tasks` | `status?`（pending/running/done/failed）, `limit` | 列表 |
| GET | `/api/tasks/{id}` | — | 单条 + 关联 `external_ref` asset 的 payload |

任务由 flash dispatcher 的 `task` 意图或 Assistant 的 `tool_create_task` 创建（见 §1.6）。
`_task_to_dict` 返回：`{id, user_text, mcp_target, status, error_message, result_asset_id,
result_asset_payload, session_id, source_input_turn_id, started_at, completed_at, created_at}`。
前端轮询此端点（或重取 placeholder asset）发现 pending→done/failed。

---

## 3.10 `/api/notifications` — 通知

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/api/notifications?limit=30` | 最新 N 条（默认 30，`le=100`）+ `unread` 计数。**无分页**——前端只看最新一屏 |
| POST | `/api/notifications/{id}/read` | 标记单条已读 |
| POST | `/api/notifications/read-all` | 全部已读 |
| DELETE | `/api/notifications/{id}` | 删除单条。**前端已接：通知行左滑删除**（`Dismissible` → DELETE → 本地移除） |
| GET | `/api/notifications/stream` | **SSE**，每条新通知推一个 `notification` 事件 |

通知由完成钩子创建（`core.notifications.create_notification`）：flash 完成（`flash_done`）、
异步 task 完成/失败（`task_done`/`task_failed`）、M7 提醒调度器（reminder loop，`main.py` lifespan
启动）。

**保留策略（缓存管理）**：两层都有界，不会无限增长——
- **展示有界**：GET 上限 30、无分页，UI 永远只显示最新一屏，**不会列出全部历史**。
- **存储有界**：`create_notification` 每次插入后 `_prune`，**每用户只留最新 `_RETAIN_PER_USER=100` 条**
  （取第 101 新那条的 `created_at` 当 cutoff，`DELETE … created_at <= cutoff`；≤100 条时不删）。best-effort、
  独立 try，**剪枝失败绝不影响通知创建**。零后台任务。实测：连发 105 条 → 落库恰好 100（最旧 5 条被剪）。

**SSE 通用路由**：payload 带 `_event` 字段（如 `listening`）的当作非通知 app 信号发对应事件名；
普通通知行无 `_event` → 默认 `notification` 事件。带心跳（`with_heartbeats`）。

---

## 3.12.1 `/api/auth` — 邮箱+密码鉴权（TestFlight beta）

| 方法 | 路径 | 请求 | 说明 |
|---|---|---|---|
| POST | `/api/auth/register` | `{email, password}` | 建账号（密码 PBKDF2 哈希）→ 返回 `{token, user}`；**注册即 provision 基线 skills**（todo/idea/contact/expense/notes/misc/qa/external_ref）。重复邮箱 409，密码 <6 位 400。 |
| POST | `/api/auth/login` | `{email, password}` | 校验 → `{token, user}`；失败 401。 |
| GET | `/api/auth/me` | — (需 token) | 当前账号 `{id, email}`。 |

- **token**：HS256（`header.payload.signature`，`sub`=user_id，`exp`=`jwt_expire_hours` 默认 30d），
  签名密钥 `settings.jwt_secret`（**生产必须用 `JWT_SECRET` env 覆盖默认 dev 值**）。后端用 stdlib
  实现（`core/security.py`，PBKDF2 + HMAC，无新依赖）。
- **隔离**：`core/auth.get_current_user_id` 从 Bearer token 解析 user id；所有数据路由据此按 `user_id`
  过滤。迁移 `0004_users` 建 `users(id,email,password_hash,created_at)`。
- **前端**：token 存 `shared_preferences`，`ApiClient` + SSE 自动带 `Authorization`；401（token 失效）→
  自动登出回登录页。见 [§4 前端](04-frontend.md) 登录门。

---

## 3.11 `/api/input-turns` 与 `/api/files`

**`GET /api/input-turns/{id}`** → `{id, session_id, index, source, text, segments, file_id,
source_file_offset, asr_provider, language, created_at}`。供资产详情页的「原始输入」卡、日详情的
来源 chip 使用。

**`GET /api/files`**（`source_tag?=flash|meeting`, `limit`）→ 每个文件含 `turn_count` + `asset_count`
（资产库「文件」入口的「· N 资产」内联显示）。**demo 常空**（不真上传音频）。
**`GET /api/files/{id}`** 单条详情。文件**不走 SkillCard**，前端用专用 `FileList`。

> **注意**：「文件」一级实体已从 **Flutter app 下线**（前端不再展示为可浏览实体,`fetchTimeline` 过滤
> `kind=='file'`）。后端 `/api/files` 仍保留(事件附件/音频基础设施)。详见 [§4.4](04-frontend.md)。

---

## 3.13 `/api/reports` — 合成/报告引擎（**已实现**，见 [§6](06-synthesis-report.md)）

| Method | Path | 说明 |
|---|---|---|
| POST | `/api/reports` | 渲染管线产出后写入(body: `{title, genre, content_md, html, spec_json}`)→ 返回 `{id}` |
| GET | `/api/reports?limit=` | 列表(标题/genre/spec 摘要/created_at,倒序),供「报告」容器 |
| GET | `/api/reports/{id}` | 单条(含 `html` + `content_md` + `spec_json`),供查看器/重渲染 |
| DELETE | `/api/reports/{id}` | 删除 |
| POST | `/api/reports/generate` | **SSE**:跑整条 §6 管线(dispatch → 取数 → 内容 → render → 落库)。事件 `status`(分阶段)→ `report` → `done`;数据不足回 `insufficient`、出错回 `error`。body: `{user_wish, selected_summary?, source_asset_ids?}` |
| POST | `/api/reports/intake` | 引导对话判定:body `{messages}` → `{ready:true}` 或 `{ready:false, ask}`(一句澄清)。**无工具、不落库** |
| POST | `/api/reports/{id}/rerender` | 换装重渲染:body `{palette?, surface?}`,默认 bump seed |

- **报告是独立入口,不复用 chat**(2026-06,已实现):向导走 `/api/reports/intake`(逐步引导)+ `/api/reports/generate`(SSE 生成),
  产物持久化为 **`Report` 行**(非会话)。**没有 `session_type='report'` 这种会话类型**(早期设计已废弃)。完整管线见 [§6](06-synthesis-report.md)。
- **手动选资产**:前端把选中的 `source_asset_ids` 传给 `/api/reports/generate`,管线据此跳过分类的范围抽取、直接进内容层。
- **按领域**:`generate` 的 dispatch 会从 `user_wish` 抽 `domain?`(§8.5),pipeline 按域过滤取数。
- 全部 endpoint 受 `Depends(get_current_user_id)`,按 `user_id` 隔离(同其它资源)。

---

## 3.14 `/api/connectors` + `/api/connected-apps` — Connected Apps（**已实现**，见 [§1.7.1](01-agent-architecture.md)）

**目录(只读,开发者维护的 catalog):**

| Method | Path | 说明 |
|---|---|---|
| GET | `/api/connectors` | 支持的 connector 目录:`[{connector_id, name, icon, auth_type, fields:[{key,label,secret:bool,placeholder}], description}]`。**只描述要填什么,不含任何密钥** |

**用户连接(per-user):**

| Method | Path | 说明 |
|---|---|---|
| GET | `/api/connected-apps` | 本用户的连接:`[{id, connector_id, display_name, auth_type, status, last_used_at}]`。**绝不含 `credentials`** |
| POST | `/api/connected-apps` | 连接:body `{connector_id, credentials:{字段名:值}, display_name?}`。服务端**先 test-connect** → 加密存 → 返回 `{id, status}`(**不回显密钥**) |
| PATCH | `/api/connected-apps/{id}` | 改别名 / 更新凭据(同样只写不回显) |
| POST | `/api/connected-apps/{id}/test` | 健康检查 / 重新验证 → `{status}` |
| DELETE | `/api/connected-apps/{id}` | 断开(删行 + 弃凭据) |

- **密钥 write-only 铁律**:`credentials` 只在 POST/PATCH 进、**永不**在任何 GET 出;不进日志、不进错误信息。
- **OAuth(后补)**:再加 `GET /api/connected-apps/oauth/{connector}/start`(返回授权 URL)+ 回调 endpoint;
  token 进 `credentials_enc`,`auth_type='oauth'`,过期自动刷新或置 `needs_reauth`。
- 全部受 `Depends(get_current_user_id)`。`/api/connectors` 可不鉴权(纯静态目录)。

---

## 3.15 游戏化层 engagement 接口（③ 球球 ✅ 已实现 · ①② 岛/任务待实现）

只读为主的接口,喂「我的岛」板块。全部 `Depends(get_current_user_id)`、按 `user_id` 隔离。
**①② 任务/周岛属 [§7 任务&周岛](07-gamemode.md)(待实现);③ 球球属 [§9 宠物](09-pet.md)(已实现)** —— 经 `completion_event` 解耦,分别实现。

**① 今日任务(L1,§7.3):**

| Method | Path | 说明 |
|---|---|---|
| GET | `/api/daily-plan` | 今日待完成。缓存当天;**缺失/过期则现场生成**(一次真实 daily-gen agent 调用,可能数秒)。返回 `{day, items:[{id, title, reason, domain(8 生活领域之一,§8), tier(简单|中等|高难), cadence(daily|weekly), completion_predicate 摘要, status}]}` |
| POST | `/api/daily-plan/refresh` | 手动重生成今日清单 |
| POST | `/api/daily-plan/items/{id}/complete` | 直给项(todo/日程)勾选完成;推断项由其 `completion_predicate` 对数据求值自动判定(此端点供直给项)。完成 → 写一条 `completion_event` |

**② 周岛(§7.4):**

| Method | Path | 说明 |
|---|---|---|
| GET | `/api/island/current` | 本周岛渲染数据:`{week_start, seed, elements:[{domain, element, count, rare:bool}], stats:{完成数, 连续天, 解锁装饰数}}`。本周**实时算**(按 `completion_events` 当周聚合) |
| GET | `/api/island/history?limit=` | 历史周岛快照列表(供回看/对比) |
| GET | `/api/island/{week_start}` | 某周岛快照 |

> 渲染由前端 `worldgen`(同 seed → 同岛);分享卡 = 客户端把岛 + 球球 + stats 合成图片导出(beta);链接分享后置。

**③ 球球 + 背包(L2,✅ 已实现 —— [§9.6](09-pet.md)):**

实现收敛为单实体 `/api/pet`(GET/spawn/PATCH);设计稿的 `/api/mascot` `/api/cosmetics` `/api/milestones` 合并进这一组(里程碑随 pet 返回;装饰目录是代码内键空间,不设端点)。全部 `Depends(get_current_user_id)`。

| Method | Path | 说明 |
|---|---|---|
| GET | `/api/pet` | 球球状态(**缺失则懒建一颗未孵化的蛋**,skin 按 user_id 种子定):`{spawned, name, seed, skin, emblem, emblem_color, equipped{head,leftItem,rightItem,carrier,aura}, unlocked{skin,emblem,head,item,carrier,aura}, milestones{capture_count,streak_days,last_event_date,domains}}`。**无 exp/level**;旧宠物缺 carrier/aura 时回填 `none`/`soft` |
| POST | `/api/pet/spawn` | 孵化(蛋→球球):body `{name}`;保留种子皮肤、随机起 starter 徽记、写 starter 背包、**保底掉一件头部/手持并装备**(`starter_drop`)、置 `spawned=1`。**幂等**(已孵化只更新 name) |
| PATCH | `/api/pet` | 改名 / 换装:body `{name?, equip?{slot:value}}`;`slot ∈ skin·emblem·emblem_color·head·leftItem·rightItem·carrier·aura`,`value` 须在 `unlocked` 内(或 `none`;`aura` 额外放行 `soft`;`emblem_color` 不门控)。装饰**只换外观、不锁功能**。里程碑门控装饰(皇冠/蜜金身色/光环座/虹彩光环)由 completion 时 `check_unlocks` 自动入袋 |

> 多只宠物(后置):未来加 `active` 列 + `POST /api/pet/active`。

- **`completion_events` 是内部中心货币**(由记录创建 / 任务勾完成 / 机会型一级实体产生,见 [§2 §3.17](02-data-model.md)),不直接对外;球球的掉装饰 + 里程碑都在 `emit_completion_event` 里**只读派生**写回 `pets`。客户端通过轮询 `GET /api/pet`(任意写后 `dataRevision` 触发)发现新掉落 → 弹庆祝 toast。
- **里程碑端点(待实现):** 设计稿的 `GET /api/milestones`(独立的 `{key,label,counter,target,reward}` 目录)留待里程碑奖励目录化时再加;v1 的累计计数已在 `GET /api/pet` 的 `milestones` 里。
- **领域(domain)prior / 主题 tag**:不另设端点 —— **仅基线技能**有 `domain` prior(provisioning 时打,`GET /api/skills` 返回);**自定义技能 prior 恒 null**(不由 design agent 打,产品决策 2026-06);任务/记录的实际 `domain` 完全按内容定(见 [§8 领域系统](08-domain-system.md)),随记的 `tags` 在 `GET /api/assets` 的 payload 里(见 [§2 §3.2.1](02-data-model.md))。

---

## 3.12 SSE 实现约定

两个 SSE 端点：`POST /api/chat` 与 `GET /api/notifications/stream`（flash **不是** SSE）。
- 帧格式 `core.streaming`：`sse_event(name, payload)` / `sse_comment(text)` / `with_heartbeats(gen)`。
- 响应头：`Cache-Control: no-cache`、`X-Accel-Buffering: no`（关 nginx 缓冲）。
- 前端用两套解析：`lib/sse.ts:openSse`（GET EventSource 风格）vs `parsePostSseStream`（POST body 流），
  见 [§4 前端](04-frontend.md)。
