# Runtime Flow — Phase B v1.4.x

> 这份文档是 Eureka 后端在**运行时**的端到端流程图谱。配套阅读:
> - `phase-b-architecture-blueprint.md` — 静态架构(数据模型 / 模块边界 / API 契约)
> - `phase-a-product-definition.md` — 产品意图与场景定义
>
> 看 Mermaid 图请用支持渲染的 viewer(GitHub、VS Code with Markdown Preview Mermaid Support、Typora 等)。

---

## 0. 一张图看全貌

两个用户入口(Flash / Chat)、一个共享的 ADK Runner、两类 MCP(我们自己的 + 第三方)、若干持久化表。

```mermaid
flowchart TB
    classDef user fill:#dbeafe,stroke:#3b82f6,color:#000
    classDef api fill:#fef3c7,stroke:#d97706,color:#000
    classDef agent fill:#e0f2fe,stroke:#0891b2,color:#000
    classDef mcp fill:#f3e8ff,stroke:#9333ea,color:#000
    classDef db fill:#ecfccb,stroke:#65a30d,color:#000
    classDef external fill:#fce7f3,stroke:#db2777,color:#000

    user1(["🎙 Voice / Hardware"]):::user
    user2(["⌨️ Chat UI"]):::user

    flashApi["POST /api/flash<br/>(sync JSON)"]:::api
    chatApi["POST /api/chat<br/>(SSE stream)"]:::api
    tasksApi["GET /api/tasks/:id<br/>(poll status)"]:::api

    fp["Flash Pipeline<br/>(dispatcher → parallel skills → aggregate)"]:::agent
    assistant["Unified Assistant<br/>(LlmAgent + history + assets hint)"]:::agent
    taskSkill["Task Skill<br/>(sync head + async tail)"]:::agent

    mcpInternal["Internal MCP Server<br/>(stdio subprocess)<br/>tool_create_asset / tool_create_event /<br/>tool_create_contact / tool_create_task / ..."]:::mcp
    mcpExt["External MCP Toolsets<br/>(streamable_http / stdio)"]:::mcp

    ext1[("Dingtalk Calendar<br/>mcp-gw.dingtalk.com")]:::external
    ext2[("Dingtalk Todo")]:::external
    ext3[("Notion / Google Cal /<br/>... (future)")]:::external

    db[("PostgreSQL<br/>sessions · input_turns · messages ·<br/>assets · events · contacts ·<br/>tasks · global_skills · user_skills")]:::db

    user1 --> flashApi
    user2 --> chatApi
    user2 -.poll.-> tasksApi

    flashApi --> fp
    chatApi  --> assistant

    fp -- "{type:task}" --> taskSkill
    assistant -- "tool_create_task" --> mcpInternal -.delegates.-> taskSkill

    fp -- "CRUD intents" --> mcpInternal
    assistant -- "tool_*" --> mcpInternal
    taskSkill --> mcpExt

    mcpInternal --> db
    mcpExt --> ext1
    mcpExt --> ext2
    mcpExt --> ext3

    taskSkill -- "placeholder + final state" --> db
    tasksApi --> db
```

---

## 1. Flash 流程(语音 / 闪念入口)

`POST /api/flash` 是**捕获**入口。一次输入可能拆成多个意图,并行处理后合并卡片返回。

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant API as api/flash.py
    participant DB as PostgreSQL
    participant Pipe as flash_pipeline
    participant Disp as dispatcher LLM
    participant Skill as skill agents<br/>(LlmAgent ephemeral)
    participant MCP as Internal MCP

    User->>API: POST /api/flash { text, source }
    API->>DB: create / get flash session (per day)
    API->>DB: insert input_turn (source=voice)
    API->>Pipe: run_flash_pipeline(user_text, ...)

    Pipe->>DB: SELECT user_skills + render_specs<br/>(pre-fetch once per request)
    Pipe->>Disp: classify → intents[]
    Disp-->>Pipe: [{type:todo, ...}, {type:expense, ...}, {type:event, ...}]

    par parallel skill agents
        Pipe->>Skill: _run_intent(intent_1, ...)
        Skill->>MCP: tool_create_asset(skill=todo, payload=...)
        MCP->>DB: INSERT assets
        MCP-->>Skill: {ok, asset_id, payload}
    and
        Pipe->>Skill: _run_intent(intent_2, ...)
        Skill->>MCP: tool_create_asset(skill=expense, ...)
        MCP->>DB: INSERT assets
        MCP-->>Skill: {ok, asset_id, payload}
    and
        Pipe->>Skill: _run_intent(intent_3, ...)
        Skill->>MCP: tool_create_event(...)
        MCP->>DB: INSERT events
        MCP-->>Skill: {ok, event_id, title, start_at}
    end

    Pipe->>Pipe: _aggregate(results, render_specs)<br/>render_spec → card (per skill)
    Pipe-->>API: { reply, summary, cards, derived_assets, derived_events }
    API->>DB: persist_chat_turn (messages row)
    API-->>User: FlashResponse JSON
```

**关键点**

- **render_specs 一次性 pre-fetch**:`run_flash_pipeline` 启动时查一次 `user_skills`,把 `render_spec` JSON 字典传到 `_aggregate` → `_make_card`,卡片生成无需 per-card DB 查询。
- **并行**:`asyncio.gather` 在意图之间并行;skill 之间不共享中间结果(无跨 skill 依赖)。
- **特殊路径**:
  - `qa` 意图 → 不出卡片,答案进 top-level `reply` 字段(对话气泡)
  - `task` 意图 → 走 task-skill 异步路径(见下面 §3)
  - `event` 意图 → 进 `events` 表(不是 `assets`),卡片用 `event_id` 而非 `asset_id`

---

## 2. Chat 流程(统一助手 + SSE 流)

`POST /api/chat` 是**对话**入口。SSE 流式返回 token / tool_call / tool_result / done 事件。

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant API as api/chat.py
    participant DB as PostgreSQL
    participant SS as core/session_service
    participant Ag as Assistant<br/>(LlmAgent + MCPToolset)
    participant MCP as Internal MCP

    User->>API: POST /api/chat { user_text, session_id?, event_id? }
    API->>SS: get_or_create_chat_session
    SS->>DB: SELECT / INSERT sessions
    API->>SS: create_input_turn_for_message (source=typed)
    SS->>DB: INSERT input_turns
    API->>SS: load_recent_messages (N=20)
    SS-->>API: messages[]
    API->>SS: load_session_assets_hint
    SS->>DB: SELECT assets + events for session
    SS-->>API: hint string

    Note over API: 构造 Assistant 系统提示<br/>(today_str + session_id +<br/>input_turn_id + assets hint)

    API->>Ag: Runner.run_async(user_msg + history)
    Ag-->>User: SSE event: meta { session_id, input_turn_id }

    loop ADK event stream
        Ag->>MCP: tool_call (e.g. tool_create_asset)
        Ag-->>User: SSE event: tool_call
        MCP->>DB: INSERT / UPDATE / SELECT
        MCP-->>Ag: tool_result
        Ag-->>User: SSE event: tool_result
        Ag-->>User: SSE event: token (text chunks)
    end

    Ag-->>API: final response
    API->>SS: persist_chat_turn (user + agent messages)
    SS->>DB: INSERT messages
    API-->>User: SSE event: done { elapsed_ms, message_id }
```

**关键点**

- **History 重放**:每次请求拉最近 20 条 message,格式化成 text 前缀给 Assistant — 解决「刚刚那个 X」的跨 turn 引用。
- **Session assets hint**:Flash 创建的 asset 不写 `messages` 表,会被 chat 历史漏掉 → 单独查一次本 session 内的 asset 注入到提示里。
- **today_str 注入**:防止模型从训练截止日期幻觉日期。
- **Event-anchored chat**:当请求带 `event_id` 时,系统提示里把当前会话锚定到那个 event。

---

## 3. Task-skill 异步流程(第三方 MCP)

用户说「同步到钉钉日历」「在 Notion 建一个页面」 → 一个 task-skill 实例,**同步立刻返 placeholder + 异步后台跑真活**。

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Pipe as flash_pipeline /<br/>Assistant
    participant Task as task_skill.run_task_intent
    participant DB as PostgreSQL
    participant Runner as Background asyncio.create_task
    participant TaskAgent as LlmAgent (ephemeral)<br/>with external MCPToolsets
    participant ExtMCP as External MCP<br/>(streamable_http)

    User->>Pipe: "在钉钉日历建一个明天3点的会"
    Pipe->>Task: run_task_intent(user_text, ...)

    rect rgb(220,240,255)
    Note over Task,DB: SYNC HEAD (<100ms)
    Task->>DB: INSERT tasks (status=pending)
    Task->>DB: INSERT assets (external_ref placeholder,<br/>status=pending)
    Task-->>Pipe: { task_id, asset_id, status:pending }
    Pipe-->>User: card "⏳ pending"<br/>(immediate response)
    end

    Task->>Runner: asyncio.create_task(_run_task_async)

    rect rgb(255,235,235)
    Note over Runner,ExtMCP: ASYNC TAIL (3–30s)
    Runner->>DB: UPDATE tasks (status=running)

    Runner->>TaskAgent: spawn with all external MCPToolsets<br/>+ today_str + MCP catalog (description)
    TaskAgent->>ExtMCP: pick + call MCP tool<br/>(e.g. create_calendar_event)
    ExtMCP->>ExtMCP: real action in 3rd-party<br/>(Dingtalk / Notion / Google ...)
    ExtMCP-->>TaskAgent: tool_result { external_id, url, ... }

    alt success
        Runner->>DB: UPDATE assets payload<br/>(status=done, external_id, url, ...)
        Runner->>DB: UPDATE tasks (status=done, mcp_target=...)
    else MCP returned ok:false
        TaskAgent->>ExtMCP: retry once with corrected args
        ExtMCP-->>TaskAgent: ok / final error
        opt still failed
            Runner->>DB: UPDATE tasks (status=failed, error_message)
        end
    end
    end

    User-->>+DB: GET /api/tasks/:id (poll)
    DB-->>-User: { status, result_asset_payload }
```

**为什么这么设计**

- **Flash 入口对延迟敏感**(用户对着硬件说话,期望 5s 内有回应)→ task 不能阻塞 dispatcher
- **第三方 MCP 自带延迟**(Dingtalk 通常 3-5s,Web 调用更长)→ 同步等会让 flash 阻塞
- **placeholder asset 已经能渲染卡片**(状态 ⏳ pending)→ 用户立刻看到「请求被理解了,正在跑」
- **失败也是个 done 状态**(status=failed + error_message),前端能展示给用户排错

---

## 4. MCP 边界与传输层

我们有**两类** MCPToolset,分别用不同的传输协议:

```mermaid
flowchart LR
    classDef our fill:#dbeafe,stroke:#3b82f6
    classDef ext fill:#fce7f3,stroke:#db2777
    classDef trans fill:#fef3c7,stroke:#d97706

    subgraph Backend["Backend Python process"]
        assistant["assistant.py"]:::our
        fp["flash_pipeline.py"]:::our
        skills["skill_factory<br/>(per-skill agents)"]:::our
        task["task_skill.py"]:::our
    end

    subgraph Internal["Internal MCP — our own tools"]
        toolset1["MCPToolset(stdio)<br/>singleton"]:::trans
        srv["mcp_server/server.py<br/>(Python subprocess)"]:::our
        tools["create_asset / query_asset /<br/>create_event / create_contact /<br/>create_task / ..."]:::our
    end

    subgraph External["External MCP — 3rd-party"]
        toolset2["MCPToolset(streamable_http)<br/>per-MCP"]:::trans
        ext1[("Dingtalk Calendar")]:::ext
        ext2[("Dingtalk Todo")]:::ext
        ext3[("...")]:::ext
    end

    assistant --> toolset1
    fp --> toolset1
    skills --> toolset1
    task --> toolset2

    toolset1 -.stdio pipe.-> srv --> tools --> DB[("PostgreSQL")]

    toolset2 -.HTTPS streaming.-> ext1
    toolset2 -.HTTPS streaming.-> ext2
    toolset2 -.HTTPS streaming.-> ext3
```

**传输协议在 `agents/mcp_config.py` 里**:

| transport | 用途 | 示例 |
|---|---|---|
| `stdio` | 我们自己的 mcp_server 子进程,或 npx-起的本地 MCP(将来) | Internal MCP, fake_external |
| `streamable_http` | 钉钉 AIHub 这种官方托管 MCP gateway | dingtalk_calendar, dingtalk_todo |
| `sse` | 老一些的远程 MCP(SSE 协议) | (尚未用) |

`get_external_toolset(name)` 根据 `cfg["transport"]` 路由到对应的 `ConnectionParams` 类(ADK 提供:`StdioServerParameters` / `StreamableHTTPConnectionParams` / `SseConnectionParams`)。

---

## 5. Card 渲染管线(render_spec-driven)

把 skill agent 的结果转成前端卡片 —— **新加 skill 默认走通用路径,不改代码**。

```mermaid
flowchart TB
    classDef src fill:#dbeafe,stroke:#3b82f6
    classDef proc fill:#fef3c7,stroke:#d97706
    classDef out fill:#ecfccb,stroke:#65a30d
    classDef special fill:#fce7f3,stroke:#db2777

    res["skill agent result<br/>{ok, skill, payload, asset_id, ...}"]:::src
    fail{"ok=false?"}:::proc
    special_check{"skill ∈ {event, task,<br/>contact pending, contact}?"}:::proc
    err["_error_card<br/>(card_type=error)"]:::special
    ev["_event_card<br/>(card_type=event)"]:::special
    tk["_task_card<br/>(card_type=task<br/>+ status icon)"]:::special
    pc["_pending_contact_card"]:::special
    ct["_contact_card"]:::special

    spec_lookup["look up render_specs[<br/>machine_name]"]:::proc
    spec["render_spec JSON:<br/>icon · accent_color ·<br/>primary_field + format ·<br/>secondary_field + format ·<br/>meta_fields · actions"]:::src
    builder["_build_card_from_render_spec"]:::proc
    fmt["_apply_format:<br/>currency / relative_date /<br/>absolute_date / truncate_X /<br/>badge"]:::proc

    card["card dict:<br/>{card_type, title, subtitle,<br/>icon, accent_color, meta_fields,<br/>asset_id, actions}"]:::out

    res --> fail
    fail -- yes --> err
    fail -- no --> special_check
    special_check -- event --> ev
    special_check -- task --> tk
    special_check -- "contact + pending" --> pc
    special_check -- contact --> ct
    special_check -- "anything else<br/>(todo/idea/notes/misc/<br/>expense/任何新 skill)" --> spec_lookup
    spec_lookup --> spec
    spec --> builder
    builder --> fmt
    fmt --> card

    err --> card
    ev --> card
    tk --> card
    pc --> card
    ct --> card
```

**新加一个 skill(比如 `habit`)只需要 3 处改动,零 Python 代码改动**:

1. `backend/skills/flash-habit-skill/SKILL.md` — 创建 prompt 文件(自动被 skill_factory 发现)
2. `backend/db/seed.py` — 加 `GLOBAL_SKILLS` + `USER_SKILL_CONFIGS` 条目(含 render_spec)
3. `backend/skills/flash-dispatcher/SKILL.md` — intent 表格加一行

之后 `_make_card` 通用路径会自动生成正确的卡片。

---

## 6. 数据沉淀路径(从输入到 timeline)

每次输入都留下可追溯的多层数据:

```mermaid
flowchart LR
    classDef input fill:#dbeafe,stroke:#3b82f6
    classDef session fill:#fef3c7,stroke:#d97706
    classDef asset fill:#ecfccb,stroke:#65a30d
    classDef view fill:#f3e8ff,stroke:#9333ea

    voice([🎙 Voice]):::input
    typed([⌨️ Typed]):::input

    sess["sessions<br/>(flash / chat / meeting / manual)"]:::session
    turn["input_turns<br/>(source=voice/typed/imported,<br/>index, text, file_id?)"]:::session
    msg["messages<br/>(user/agent/tool 三角,<br/>含 tool_call / tool_result / cards)"]:::session

    a["assets<br/>(payload JSONB,<br/>+ session_id + source_input_turn_id)"]:::asset
    e["events<br/>(start_at / end_at,<br/>+ source_input_turn_id)"]:::asset
    t["tasks<br/>(status, mcp_target,<br/>result_asset_id → assets)"]:::asset
    c["contacts"]:::asset

    timeline["/api/timeline<br/>(effective_at 排序的<br/>跨 kind 合并视图)"]:::view

    voice --> sess --> turn
    typed --> sess
    sess --> msg

    turn -.provenance.-> a
    turn -.provenance.-> e
    turn -.provenance.-> t
    turn -.provenance.-> c

    a --> timeline
    e --> timeline
    turn -.voice 才上 timeline.-> timeline
```

**核心关系**

- **sessions** ←→ **input_turns** ←→ **messages**:对话流(messages),原始捕获(input_turns)
- **assets / events / contacts** 都有 `source_input_turn_id` → 谁创建的可追溯
- **tasks** 有 `result_asset_id` → 异步任务的产物是 external_ref asset
- **timeline** 按 `effective_at` 排:对 asset 是 payload 里的 due_date/at/date,对 event 是 start_at,对 input_turn / file 是 created_at(语音 turn 才上,typed 不上)

详见 `phase-b-architecture-blueprint.md` §三.5(effective_at 规则)。

---

## 7. 一些设计原则的总结

| 原则 | 体现 |
|---|---|
| **意图形态分流** | capture(Flash) / question(qa-skill 短答) / task(异步 MCP) / chat(Assistant) —— 不同入口适配不同 latency 与 UX 预期 |
| **数据驱动卡片** | 卡片样式由 UserSkill.render_spec 决定,代码里不为单独 skill 写 if/else |
| **provenance 不丢** | 每个 asset / event 都指回 input_turn,turn 指回 session —— 任何资产都能追到「是哪一句话哪一次输入产生的」 |
| **异步外部动作** | 第三方 MCP 调用一律走 task-skill 异步,sync 立刻返 placeholder,后台跑 |
| **MCP 是边界** | Agent ↔ DB 必经 MCP server;Agent ↔ 外部系统必经外部 MCPToolset。没有第二条路 |
| **render_spec / payload_schema 是 skill 的合约** | 加 skill = 加 SKILL.md(prompt 行为)+ seed 一行(数据契约)+ dispatcher 表格(意图分类),不动 pipeline 代码 |
