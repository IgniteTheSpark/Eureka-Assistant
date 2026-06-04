# 01 · Agent 架构与编排

> 本章描述 Eureka 后端的 AI 层：三条管线（Flash / Chat / Task）、统一 Assistant、
> 内/外 MCP 边界、LLM 配置、skill 工厂与 design agent。逐字 prompt 见
> [§A Prompts 附录](99-prompts-appendix.md)；数据落库契约见 [§2 数据模型](02-data-model.md)；
> HTTP 表层见 [§3 API](03-api-reference.md)。

---

## 1.0 全景

```
                         ┌─────────────── 用户输入 ───────────────┐
                         │                                        │
                  POST /api/flash (同步 JSON)          POST /api/chat (SSE 流)
                         │                                        │
                 ┌───────▼────────┐                      ┌────────▼─────────┐
                 │  Flash Pipeline │                      │  统一 Assistant   │
                 │  (多 agent)     │                      │  (单 LlmAgent)    │
                 └───────┬────────┘                      └────────┬─────────┘
                         │                                        │
            ┌────────────┼───────────┐                           │
       dispatcher   并行 sub-skills  Python 聚合                  │
       (1 次 LLM)   (N 次 LLM)      (_make_card)                 │
                         │                                        │
                         └──────────────┬─────────────────────────┘
                                        │
                              ┌─────────▼──────────┐
                              │  内部 MCP (FastMCP) │  stdio 子进程
                              │  CRUD 工具集         │  mcp_server/server.py
                              └─────────┬──────────┘
                                        │
                                  MySQL (14 表)

   task 意图 / tool_create_task ─────► task-skill ──► 外部 MCP (Notion/钉钉/GCal)
                                       (异步两段式)     stdio / streamable_http / sse
```

三条管线共享同一套 **ADK + LiteLLM → OpenRouter → DeepSeek** 栈与同一个**内部 MCP 工具集**。
区别只在编排形态：

| 管线 | 入口 | 形态 | agent 数 | 返回 |
|---|---|---|---|---|
| **Flash** | `POST /api/flash` | dispatcher → 并行 sub-skill → Python 聚合 | 1 + N | **同步 JSON**（卡片数组） |
| **Chat** | `POST /api/chat` | 单 Assistant + 工具循环 | 1 | **SSE 流**（token + tool 事件） |
| **Task** | flash `task` 意图 / Assistant `tool_create_task` | 同步占位 + 异步 MCP 路由 | 1（临时） | 同步 placeholder，后台补全 |

---

## 1.1 LLM 配置（`core/llm.py`）

**所有 5 个角色都用同一个模型** `openrouter/deepseek/deepseek-chat`，经 LiteLLM → OpenRouter：

```python
ASSISTANT_MODEL        = LiteLlm(model="openrouter/deepseek/deepseek-chat")
FLASH_DISPATCHER_MODEL = LiteLlm(model="openrouter/deepseek/deepseek-chat")
FLASH_SKILL_MODEL      = LiteLlm(model="openrouter/deepseek/deepseek-chat")
DESIGN_AGENT_MODEL     = LiteLlm(model="openrouter/deepseek/deepseek-chat")
TASK_MODEL             = LiteLlm(model="openrouter/deepseek/deepseek-chat")
```

> ⚠️ **复刻陷阱**：`core/llm.py` 顶部 docstring 仍写「Moonshot Kimi K2.5」——**那是过时注释**。
> 实际全用 DeepSeek（`core/llm.py:59-63`）。选 DeepSeek 的原因（写在代码注释里）：中文友好、
> 不触发 OpenRouter 对 Claude/GPT/Gemini 的区域 403、function-calling 纪律稳（能处理「payload 作为
> JSON 字符串」的双层 JSON 模式而不截断/转义错误，Kimi 在这点上挂过）、非推理、快（~2-5s/call）、便宜。

**为什么按角色命名而非按模型命名**：换模型只改这里 5 个字符串，agent 代码不动（「干净接缝」原则）。

`configure_llm_env()` 在 `main.py` 启动时调用一次（**在 import routers 之前**，因为 routers import agents
会实例化 model），把 `OPENROUTER_API_KEY` / `OPENAI_API_KEY` 写进 env 供 LiteLLM 读取。
`OPENAI_API_KEY` 仅给 Whisper ASR 留位（音频上传路径本轮不实现）。

无 prompt 缓存。

---

## 1.2 内部 MCP — 我们自己的 CRUD 工具集

内部工具是一个独立的 **FastMCP** server（`mcp_server/server.py`），以 **stdio 子进程**方式由
`MCPToolset` 拉起（`agents/mcp_toolset.py:get_mcp_toolset()`，懒加载单例）。Assistant、Flash sub-skill、
design agent 共用同一个内部 toolset。env 透传（DB / LLM 凭据进子进程）。

### 工具清单（`mcp_server/tools.py`）

所有工具统一返回 `_ok(**fields)`（带 `ok: true`）或 `_err(msg)`（`ok: false`）。

| 工具 | 签名（关键参数） | 落库 |
|---|---|---|
| `tool_render_report` | `(title, html)` | 不落库；返回 html 供 SSE 渲染。`_REPORT_HTML_MAX=120_000` |
| `tool_create_asset` | `(user_skill_name, payload, session_id, source_input_turn_id, user_id)` | `assets`（+ `asset_fields` 索引） |
| `tool_query_asset` | `(user_skill_name, contains, from_date, to_date, limit)` | 读 `assets` |
| `tool_query_digest` | `(from_date, to_date)` | 跨 skill 聚合计数 |
| `tool_update_asset` | `(asset_id, payload_patch)` | patch 合并 `assets.payload` |
| `tool_delete_asset` | `(asset_id)` | 删 `assets` |
| `tool_create_contact` / `query` / `update` / `delete` | 见 §3 | `contacts`（一级表） |
| `tool_create_event` | `(title, start_at, end_at, location, description, all_day, recurrence_rule, source_input_turn_id)` | `events`（一级表） |
| `tool_query_event` / `get_event` / `update_event` / `delete_event` | | `events` |
| `tool_add_event_attendee` | `(event_id, name, contact_id, role)` | `event_attendees` |
| `tool_link_event_file` | `(event_id, file_id, kind)` | `event_files` |
| `tool_query_input_turn` / `get_input_turn` | | 读 `input_turns` |
| `tool_create_task` | `(user_text, content, target_external_id, target_external_system, session_id, source_input_turn_id)` | 委托 task-skill（见 §1.6） |

### `payload` 是 JSON 字符串（关键约定）

`tool_create_asset` / `tool_update_asset` 的 `payload` / `payload_patch` 参数是 **JSON 字符串**，
不是对象。这是「双层 JSON」模式——选 DeepSeek 的关键原因就是它能稳定地把对象序列化成字符串再传，
不截断、不转义错。复刻时 sub-skill prompt 都按这个约定写（见各 SKILL.md「payload=JSON 字符串」）。

### `tool_create_event` 的硬校验

`create_event` 内部强制：**必须有 `end_at` 或 `all_day=1`**，否则返回
`_err("...should be todo...")`。这是「只有一个时刻 = todo，有完整时段 = event」铁律的**落库层兜底**
（dispatcher 是第一层，event-skill Step 0 是第二层）。

---

## 1.3 Flash Pipeline（捕捉管线）

入口 `agents/flash_pipeline.py:run_flash_pipeline(user_text, session_id, input_turn_id, today_str, user_id)`。
三步：

### Step 1 — Dispatch（`_dispatch`）

一次 LLM 调用、**无工具**（纯分类）。agent 由 `make_dispatcher_agent(custom_skills_hint)` 构造，
prompt 来自 `skills/flash-dispatcher/SKILL.md`。输出意图列表 JSON：

```json
{"intents": [{"type": "todo", "source_text": "..."}, {"type": "expense", "source_text": "..."}]}
```

意图 `type` ∈ `todo / event / expense / contact / idea / notes / misc / qa / task`（+ 用户自定义 skill 的
machine_name）。一句话可拆成多个意图并行处理。

**dispatcher 铁律（逐字见附录）**：
> **event 的唯一识别条件 = 有完整时段**（start+end / start+duration / 全天）。**只有一个时刻就是 todo。**

**task ≠ qa 的区分**：动作落在**外部产品**（钉钉/Notion/GCal）= `task`；问 Eureka 自己的数据或一般知识
= `qa`。

**自定义 skill 注入**：当用户注册过自定义 skill，`make_dispatcher_agent` 把 `custom_skills_hint` 追加进
dispatcher prompt，教它对关键名词命中时输出 `type=<machine_name>` 而不是倒进 misc。

> **活跃集过滤（设计中，见 [§3 skills API](03-api-reference.md) / [§4.4.5](04-frontend.md)）**：`custom_skills_hint`
> 与 chat 的技能字典都只取 **`enabled=1`** 的技能。**停用的技能不进 hint → dispatcher 不会路由到它**
> （该类输入回退 misc/notes）。因为 hint 每请求现拉，改活跃集**下一条消息即生效**，无需重启 agent。
> 查询工具**不**按 enabled 过滤（停用后仍能查其历史资产）。

**fallback 时建议建技能（设计中，见 [§99](99-prompts-appendix.md)）**：当一个**像「记录某类型」**的输入因
**没有匹配的活跃技能**被归到 **misc/notes 并建好资产**后，agent 在**回复正文里追加一句**自然语言建议，
点名识别到的类型：「我把它记到了『其它』。想长期、结构化记录『宝宝喝奶』的话，可以去资产库创建一个对应技能。」
**纯文字提示，无弹窗 / 无按钮 / 无深链 / 无节流**（本版）。chat（Assistant）与 flash（misc skill）都这么做。
**只在确实建了 misc/notes 资产时提示**；没识别出意图、没建资产的（如「123123 出」）维持现状不提示。

### Step 2 — 并行执行意图（`_run_intent` via `asyncio.gather`）

每个意图并发跑。路由规则：

| 意图情况 | 执行体 |
|---|---|
| `type == "task"` | `task_skill.run_task_intent`（异步外部 MCP，见 §1.6） |
| 自定义 skill（有 UserSkill 但无 SKILL.md） | `make_custom_skill_agent(name, display_name, payload_schema, render_spec)` |
| 其他（todo/event/expense/…） | `make_skill_agent(skill_name)`（从 `skills/flash-<name>-skill/SKILL.md` 加载） |

**event 自动降级**：event sub-skill 若发现 source_text 缺完整时段，返回错误；pipeline 检测到后
**自动以 todo 重跑**该意图（dispatcher 误路由的自愈）。

每个 sub-skill agent 都挂内部 MCP toolset，自行决定 create/update/delete 并调工具。

### Step 3 — Python 聚合（`_aggregate` → `_make_card`）

**纯 Python，不再调 LLM**。把每个意图的工具结果转成前端卡片。`_make_card` 有 4 个特殊分支
（event / task / contact / pending_contact），其余走通用 render_spec 路径
（`_build_card_from_render_spec` + `_apply_format` 镜像前端的格式化规则）。

**Fallback-success**（健壮性网）：DeepSeek 偶尔把 tool_call 结果输出成畸形 JSON 文本。
`_fallback_result_from_tool_events` 从捕获的 `tool_events`（真实工具调用记录）重建卡片，
所以即使模型最终输出坏了，只要工具真的调成功了，用户照样拿到卡片。

`note` → `notes` 的 machine_name 重命名在聚合层处理（v1.4 历史遗留）。

### 返回（同步 JSON）

`FlashResponse{ok, session_id, input_turn_id, reply, summary, cards, derived_assets, has_pending, elapsed_ms, error}`。
详见 [§3 API](03-api-reference.md)。

---

## 1.4 Flash sub-skills（`skills/flash-*-skill/SKILL.md`）

每个 sub-skill 是一段 SKILL.md prompt，由 `make_skill_agent` 加载成挂内部 MCP 的 LlmAgent。
**加 skill = 丢一个 SKILL.md + seed 一行 UserSkill + dispatcher 表加一行，零 pipeline 代码改动**
（`SKILL_FOLDER_MAP` 在 import 时从文件系统扫描，命名约定 `flash-<machine_name>-skill`）。

| sub-skill | 操作集 | 落库工具 | 关键行为（逐字 prompt 见附录） |
|---|---|---|---|
| **todo** | create/update/delete | `tool_create_asset(user_skill_name="todo")` | due_date：有时刻→ISO8601+08:00；只有日期→`"YYYY-MM-DD"`（**不猜时刻**）；无→null。update/delete 先 query keyword |
| **event** | create/update/delete | `tool_create_event`（**非** create_asset） | Step 0 时段硬检查（缺时段直接拒绝、不自降级）；create 后把所有「疑似参与人」字符串以 `name_raw` 占位为 attendee（**不查 contacts、不传 contact_id**） |
| **expense** | create/update/delete | `tool_create_asset(user_skill_name="expense")` | amount 必填；category 8 类推断；`date`(YYYY-MM-DD) + 可选 `at`(完整时间戳，按时段 canonical：早8/中12/下15/晚19/深夜23) |
| **contact** | create/update/delete | `tool_create_contact`（**非** create_asset） | name 必填；query 命中 0→create，1→update，2+→pending_confirmation（不乱改） |
| **idea** | create/update/delete | `tool_create_asset(user_skill_name="idea")` | title(≤10 词) + content(markdown，可扩 1-2 行，不编事实) |
| **notes** | create（only） | `tool_create_asset(user_skill_name="notes")` | 长文：title? + content(必) + tags?；忠于原文、可整理结构不可加事实 |
| **misc** | create（only） | `tool_create_asset(user_skill_name="misc")` | 兜底；content + tags?；可拒绝写入并报「dispatcher misroute」 |
| **qa** | 无写工具 | （只读 / 不落库） | Siri 式短答 1-3 句；问自己数据→`tool_query_asset` 再答；**绝不**说「这是未来功能」（report/外部同步都已上线） |

> qa 是 **system skill**：`payload_schema=None`、`render_spec=null`、`queryable_fields=None`，
> 不产生资产。它的输出 `answer` 由 pipeline 转成纯文本回复。

### 自定义 skill 的通用 sub-skill

`make_custom_skill_agent` 在调用时从 UserSkill 的 `payload_schema` + `render_spec` 即时拼出 prompt
（列字段、约束时间格式、要求只调 `tool_create_asset(user_skill_name=<machine_name>)`）。所以用户在
AddSkillWizard 注册的 skill 即便没写 SKILL.md 也能被 Flash 处理。

---

## 1.5 统一 Assistant（Chat 管线）

入口 `POST /api/chat`（SSE）。单个 `LlmAgent` + 内部 MCPToolset，由
`agents/assistant.py:make_assistant_agent(session_id, input_turn_id, event_id, today_str, user_skills_hint,
session_assets_hint, session_context_hint, session_subject_hint)` 构造。

`ASSISTANT_INSTRUCTION_BASE`（`assistant.py:25-203`，逐字见附录）定义统一意图表：

| 意图 | 行为 |
|---|---|
| **CREATE** | 意图明确建资产 → 直接调 `tool_create_*`，卡片显示在对话里 |
| **UPDATE** | query 定位 → `tool_update_*` |
| **DELETE** | query 定位 → `tool_delete_*` |
| **QUERY** | `tool_query_*` → 自然语言汇报 |
| **SUMMARY** | 对「用户记在 app 里的数据」复盘 → query → `tool_render_report` → 一句话 |
| **CHAT-ANSWER** | 一般知识/分析（对象**不是**用户的数据）→ 直接答 |
| **CREATE-FROM-REPLY** | 把刚才的回答沉淀成资产 |
| **CHAT** | 闲聊 |

**SUMMARY vs CHAT-ANSWER 的边界**：判据是「对象是不是用户记在 app 里的数据」。是→SUMMARY（出报告）；
否→CHAT-ANSWER（直接答）。

**CREATE 多条记录要抽全（关键，曾漏抽）**：chat Assistant 是**单次 LLM**做多意图抽取（不像 flash 有专门
dispatcher 先拆意图），narrative 长句容易**只抓最显眼的一条**、把其余当闲聊丢掉（实测：「看了 X；又看了 Y；
喝了 500ml」有时只记了喝水）。prompt 用三条规则补齐这层 dispatcher 纪律：① **陈述句也是 CREATE**（「我看了/
吃了/喝了 X」即记录，不是闲聊）；② 一条消息**先在脑内列全所有独立记录、再逐条 create、一条不漏**；③ 夹带的
主观评价（「很好看」「太文艺」）是该记录的**字段**，不是把整条变闲聊的理由。非确定性问题，规则降低漏抽率；
彻底兜底（整条空补全）见 [§1.5 Chat SSE](#chat-sse-与防漏调) 的空补全重试。

**SUMMARY 铁律**：先 query 拿真实数据 → 调 `tool_render_report` → 最后只回**一句话**。HTML 只能进
`html` 参数（不能漏进对话 token）；HTML 在 **393px sandbox iframe** 里渲染、**无 script**。

**外部同步**：`tool_create_task`，区分 `content`（要写入外部的正文）vs `user_text`（用户原话）；
更新已有外部对象时传 `target_external_id`。

`make_assistant_agent` 在 BASE 之上按需追加 7 个条件块（当前时刻、当前 session 的资产/上下文/主题
提示、用户 skill 清单等），让 agent 知道「此刻在聊什么」。

### 时间上下文（now-string，关键）

`today_str` **不是**只到天的日期，而是**完整的本地此刻**：`api/chat.py` 与 `api/flash.py`
都生成 `"<ISO 到分钟>+08:00(周X)"`（例 `2026-06-04T12:41+08:00(周四)`），通过
`make_assistant_agent` / flash 管线消息（`现在是 …`）注入 prompt。

解析分**三种情况，必须分开、别混**：

| 情况 | 例 | 解析为 |
|---|---|---|
| **明确时刻** | 下午五点 / 晚上8点半 / 14:30 | 用那个时刻 |
| **相对时刻** | 刚刚 / 刚才 / 现在 / 这会儿 / 几分钟前 / 一小时前 | 用 now 的**当前时分**，**严禁** 00:00 / 午夜 |
| **只有日期词 / 完全没提时间** | 今天 / 昨天 / 明天 / 下周三 ；「今天喝了水」 | 只确定**日期**；**不要编造一个具体时刻**——datetime/时间字段**留空(不传)**或只到日期；回复里也别提用户没讲过的钟点 |

> **为什么(两次踩坑)**：
> 1. 早期 `today_str` 只到日期，模型对「宝宝刚刚喝了 150ml」这类只有相对时刻的输入只能填 00:00 →
>    所以注入完整此刻、规定「刚刚 = 真实时钟时间」。
> 2. 但随后**过度修正**：「今天喝了 20ml 水」(没给钟点) 也被塞成当前时刻 15:02,回复还断言「15:02 喝了」——
>    用户没讲过的时间被凭空发明。所以补上第三种情况:**没给时刻就别造**。
>
> 三种情况在三处一致写明：统一 Assistant 的「时间上下文」块、`skill_factory` 自定义 skill prompt 的「流程」
> 步骤、以及内建 `flash-{event,expense,todo}-skill/SKILL.md`，覆盖**所有** skill（内建 + 自定义）。

### Chat SSE 与防漏调

`api/chat.py` 把 ADK 事件流转成 SSE：`meta → token → tool_call → tool_result → done`（异常时 `error`）。
两类「这一轮什么也没产出」都会**重试一次**（`MAX_ATTEMPTS=2`），别让用户只看到「用时 Xs」的空回复：
- **漏调**：`_looks_like_leaked_call` 检测 DeepSeek 把 function-call 当普通文本吐出来 → 重试(带「请直接调用工具」的 nudge)。
- **空补全**：`is_empty = 没调任何工具 且 没有正文`。DeepSeek **偶发返回空补全**(0 token、无工具、无文本) →
  同样重试。两次都空 → 回一句「我刚才没太理解,能换个说法再说一次吗?」**绝不静默**。
`_cards_from_tool_result` 抽卡片落库。report 的对话消息会剥掉笨重的 html 再持久化。详见 [§3 API](03-api-reference.md)。

---

## 1.6 Task-skill（异步外部 MCP）

`agents/task_skill.py`。把「落到第三方产品」的动作包装成**两段式**，永不阻塞用户：

### 同步头（<100ms）

`run_task_intent(user_text, session_id, source_input_turn_id, user_id, content, target_external_id,
target_external_system)`：
1. 建 `tasks` 行（status=pending）+ 占位 `external_ref` asset（payload status=pending、title=截断的 user_text）。
2. `asyncio.create_task` 触发异步尾。
3. **立刻**返回 placeholder 卡片 → Flash/Chat 当场显示「⏳ pending」。

> **正文恢复网**：当 `content` 为空、且 user_text 引用了「刚刚/上面/那段…」（`_PRIOR_REF_MARKERS`），
> 从 session 里**最近一条 agent 回复**捞正文（`_recover_prior_reply`），避免外部文档只有标题没正文。
> 只取最新一条（chat 场景引用的答案紧贴保存请求；flash session 是日级复用的，往回翻会捞到无关旧内容）。

### 异步尾（3-60s，`_run_task_async`）

1. `tasks.status=running`。
2. 拉**全部已启用的外部 toolset**（`get_all_external_toolsets()`）挂到一个**临时 LlmAgent**
   （prompt `_build_task_runner_prompt()` 在调用时构造，把 `MCP_SERVERS` 的能力目录列进去——新增 MCP
   无需改代码）。
3. 模型按 user_text 选**一个**最匹配的工具调用。`content` 非空时作为「要写入的正文」明确交给 agent；
   `target_external_id` 非空时走**更新**工具（不 create 新对象）。
4. `_extract_external_ref` 从工具结果里抽 `external_id`/`url`/`title`（兼容各家 MCP 的杂乱返回形状：
   下钻 `result`/`data`/`body`，union 一堆 id/url/title key 名）。成功 → asset payload status=done +
   `tasks.status=done`；失败 → status=failed + error_message + 失败 toast。
5. 两种结局都发通知（`task_done` / `task_failed`，link=asset_id）——异步任务往往在用户已经走开后
   才完成，所以通知系统在这里价值最高。

**失败处理显式**：broad-catch 是有意的（fire-and-forget worker 不能让异常静默吞掉协程）；
最多重试 1 次；无匹配工具返回 `{"ok": false, "error": "no matching MCP tool"}`。

前端轮询 `/api/tasks/{id}` 或重取 placeholder asset 来发现 pending→done/failed。

---

## 1.7 外部 MCP 注册表（`agents/mcp_config.py`）

外部 MCP 是第三方托管/社区 gateway，与内部 MCP 完全分开。`MCP_SERVER_CATALOG` 列全部已知 MCP；
`EUREKA_MCP_ENABLED`（env，逗号分隔，默认 `fake_external`）决定实际 spawn 哪些。

三种 transport（`agents/mcp_toolset.py:get_external_toolset`）：

| transport | 形态 | 例 |
|---|---|---|
| `stdio`（默认） | spawn 子进程（npx / python -m），`env_keys` 透传凭据 | `fake_external`、`google_calendar`（npx @cocal/google-calendar-mcp） |
| `streamable_http` | 远程 gateway，URL（带密钥）放 env，`url_env` 指 env 名 | `dingtalk_calendar` / `dingtalk_todo` / `dingtalk_notes`（钉钉 AIHub） |
| `sse` | 同 streamable_http 但用 `SseConnectionParams` | — |

每个 catalog 条目的 `description` 是给**路由 LLM**看的能力说明，**精确到参数名**（关键防错点）：

- **钉钉日历** create：`summary`（不是 title）、`startDateTime` / `endDateTime`（ISO8601+TZ，不是 start_at）。
- **钉钉待办** create：`create_personal_todo(PersonalTodoCreateVO={subject, dueTime, executorIds})`，
  `dueTime` 是 **Unix 毫秒时间戳**（不是 ISO 串、不是秒级）。
- **钉钉文档** create：`create_document(name, markdown)`（不是 title/content）；更新用
  `update_document(nodeId, ...)`，返回 `docUrl`/`nodeId`。

`fake_external`（`mcp_server/fake_external_mcp`）是测试替身：`create_notion_page` /
`create_calendar_event` / `send_dingtalk`，永远可用，保证 demo 不挂。

`get_all_external_toolsets()` 把所有启用的外部 toolset 一起挂给 task runner，由 LLM 自己挑工具。

### 1.7.1 Connected Apps（per-user 外部连接，设计规格 · 待实现）

现状是「开发者替所有人连好」:catalog 写死、`EUREKA_MCP_ENABLED` 全局开关、凭据塞共享 `mcp-credentials/`。
目标是把它拆成两层,做成**用户自管的「已连接应用」**:

- **Connector Catalog（开发者维护，= 现有 `MCP_SERVER_CATALOG`）**:"支持哪些 app"。每条声明
  `{connector_id, 名称, 图标, transport, auth_type, 需要用户填的字段(label/键名/是否密钥), 给路由 LLM 的能力说明}`。
  **beta 只开策展目录**(钉钉 / Notion / Google Cal / …),**不开任意自带 MCP**(BYO 作为后续 advanced tab)。
- **Connected Apps（per-user）**:"这个用户连了哪些 + 他自己的凭据"。落 `connected_apps` 表(见 [§2](02-data-model.md))。

**鉴权(beta):** **先做 token / 网关-URL 粘贴类** connector —— 用户把**自己的**密钥/网关 URL 粘进字段
→ **直存服务端加密**,不经过任何第三方、不回传客户端。覆盖钉钉 AIHub 网关(`streamable_http`,`url_env`)、
API key/header 型。**OAuth(Google/Notion 跳转)后补**(每家一套重定向 + 刷新)。

**运行时改造:** task runner 不再 `get_all_external_toolsets()`(全局),而是
`get_user_external_toolsets(user_id)`:读该用户的 connected_apps → **解密他的凭据** → 按连接构建 MCPToolset。
接上已做的 per-user `user_id` 线程化(同内部 MCP 的 `before_tool_callback` 注入)。**per-user 偏好
`streamable_http`/`sse` 网关型 transport**(不必为每用户 spawn 子进程,易扩容);`stdio` 仅自托管保留。

**agent 感知:** assistant / task-skill 只**提供并使用已连接**的 app。用户说「同步到钉钉」但没连
→ agent 回一句引导去「设置 → 已连接应用」连上,而不是硬调一个没凭据的 toolset。运行时把"已连接 connector
清单"作为 hint 注入 task agent(类似 skill 字典 hint)。

**「同步失败 → 去连接 → 重试」闭环:** task-skill 产出的 `external_ref` 资产 payload 已带 `external_system`
(目标 connector)+ 状态(pending/failed)。当某次同步因 **app 未连接 / 凭据失效** 失败,前端在该外部资产的
容器/详情里就**深链回对应 connector 的连接卡**(见 [§4.4.2 / §4.4.3](04-frontend.md));连好后重试即可。
让"发现问题的地方"和"修问题的地方"一键打通。

**安全(契合产品硬约束):** per-user 凭据**加密 at rest**、按 `user_id` 隔离、**绝不出现在任何 API 响应/日志**、
**绝不回传客户端、绝不给开发者**;catalog 条目声明"要哪些字段",用户自己填。

> 完整数据/接口/前端契约:[§2 `connected_apps`](02-data-model.md) · [§3 `/api/connectors` + `/api/connected-apps`](03-api-reference.md) · [§4 设置 hub](04-frontend.md)。

---

## 1.8 Design Agent（自定义 skill 设计器）

`agents/design_agent.py`，被 `POST /api/skills` 调用，**两段式**（先澄清后设计）：

### Clarifier（`clarify_skill`）

输入用户的自然语言描述，判断够不够具体。输出 `{"ready": true}`（够清楚直接设计）或
`{"questions": [...]}`（太笼统，问 1-3 个关键问题让前端渲染成卡片流）。判据：含动作+数值/隐含核心字段
→ ready；只给类目名（「宝宝喂养记录」「看书」）→ 追问。最多 3 问。用 ADK `output_schema`
（`CLARIFIER_SCHEMA`）保证结构化输出；解析失败保守 fallback 到 `{ready: true}`。

### Design（`design_skill`）

产出可直接装入系统的 skill 定义：
`{name, display_name, payload_schema, render_spec, sample_payload}`。用 `output_schema`
（`RESPONSE_SCHEMA`）强约束。设计规则（逐字见附录）关键点：

- 字段 3-6 个；payload 里**每个有意义字段都要能在卡片上看到**（进 primary/secondary/meta，否则用户以为内容丢了）。
- `accent_color` 必须从 7 槽选（blue/amber/green/red/purple/gray/neutral）；`icon` 1 个 emoji；
  `card_layout` ∈ horizontal/stacked/inline/compact。
- **单位塞进值里或用 string 字段**——不发明 `field_units`/`primary_unit` 等已废弃 key（卡片显示规则
  极简：就是字段原始值，无标签前缀、无单位后缀）。
- `actions: "check"` 纪律：只有真正状态化的 skill（todo/打卡/review）才加，measurement/log 类
  （跑步/读书/记账）不加。

产出经 `POST /api/skills/confirm` 落成一行 UserSkill（`USER_SKILL_CAP=30`）。详见 [§3 API](03-api-reference.md)。

---

## 1.8b Synthesis / Report Pipeline（合成·报告管线，设计中）

第四条管线(在 Flash / Chat / Task 之外):**report-dispatcher → content skill(按 genre)→ render skill**,
复刻 Flash 的 dispatcher→sub-skill 结构(`agents/report_pipeline.py`)。把「选中资产 + 用户意愿」合成成
**图文 HTML 报告**(数据复盘 / 灵感升华 / 提案 / 概览)。内容层只产**注解 Markdown**,渲染层 md→单文件 HTML
(surface×palette + 本地打包 GSAP,渐进增强)。内容层只用**只读** query 工具、绝不写库。
**完整规格见 [§6 合成·报告引擎](06-synthesis-report.md)**;逐字 prompt 进 [§99](99-prompts-appendix.md)。

---

## 1.9 编排不变量（复刻 checklist）

1. **三管线一栈**：Flash / Chat / Task 共享 ADK + DeepSeek + 内部 MCP。换模型只改 `core/llm.py`。
2. **dispatcher 无工具**（纯分类）；sub-skill 有工具；聚合纯 Python。
3. **event/contact 走一级表工具**（create_event / create_contact），不是 create_asset。
4. **event 时段三道闸**：dispatcher 铁律 → event-skill Step 0 → create_event 落库校验。
5. **payload 是 JSON 字符串**（双层 JSON）；DeepSeek 是为这个选的。
6. **Fallback-success**：模型输出坏但工具调成功 → 从 tool_events 重建卡片，不丢资产。
7. **task 永不阻塞**：同步占位 + 异步补全 + 完成通知。
8. **skill 可扩展零代码**：SKILL.md（或动态 prompt）+ seed 一行 + dispatcher 一行。
