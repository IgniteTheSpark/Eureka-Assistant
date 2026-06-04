# 00 · 产品定义与概览

## 1. 产品是什么

Eureka 是一个**个人 AI 助手**。硬件语音是它设想的线下输入入口（demo 用浏览器麦克风 / 文字模拟）。

核心循环：
- 用户**捕捉**（capture）一段输入 —— 一句语音转录、或一段文字。
- 一个 **AI agent** 把这段非结构化输入**归类**成一个或多个**带类型的资产**（todo / event /
  expense / idea / notes / contact / 自定义 skill …），渲染成卡片。
- 一个**统一 AI 助手**能看到用户**全部历史资产**，与之**对话**：意图明确时直接增删改查（CRUD），
  模糊时自然对答，要复盘时生成**图文 HTML 报告**，要落到外部产品时**异步同步**到第三方（钉钉 / Notion / Google Calendar）。

## 2. 底座 / 核心 / 差异化

| 层 | 内容 | 角色 |
|---|---|---|
| 底座 | 硬件语音输入（会议 / 对话 / 闪念） | 入口，物理护城河（demo 不接真硬件） |
| **核心** | **统一 AI 助手** —— 看得到一切；意图明确直接 CRUD，模糊时对话 | 不能让步的那件事 |
| 差异化 ① | 知识沉淀（学生 / 创作者 / 白领） | 资产为主的「呈现模式」 |
| 差异化 ② | 日历为头牌 + 名片为支撑（商务 / 老板） | 日历为主的「呈现模式」 |

取舍原则：任何取舍优先保障**核心 AI 对话体验**；两翼为它服务。

## 3. 四条架构原则（贯穿全 spec）

1. **生产级核心 + demo 级边缘，干净接缝。** 可替换边缘（ASR / 硬件传输 / 鉴权）躲在接口后；
   核心（pipeline / 数据模型 / agent 编排 / API 契约）一次建对。
2. **AI 体验生产级**：流式、低延迟、自然。
3. **资产类型由 skill 产出、可扩展**，非硬编码 enum。加/减能力 = 加/减 skill + render_spec，核心编排不动。
4. **数据模型按生产级设计**：多用户-ready（`user_id` 字段化）、InputTurn 一等实体、会议留位、provenance 不丢。

## 4. AI 助手行为规则（核心）

统一 agent，一个对话面同时承担「捕捉」和「问答」：

| 情况 | 行为 |
|---|---|
| 意图明确指向资产（「帮我建个待办」「记一笔花了 50」） | agent **直接调工具创建**，资产卡片显示在对话里 |
| 没有明确资产意图的问题（总结、分析、闲聊、建议） | agent 自然回答；回答下方提供「沉淀为资产」入口 |

判定时机：一轮 agent 输出之后 —— 没有产生资产 tool call → 展示「沉淀为资产」入口；有 → 不展示（避免重复）。

> agent 的完整行为表（CREATE / UPDATE / DELETE / QUERY / SUMMARY / CHAT-ANSWER / CREATE-FROM-REPLY / CHAT）
> 由 system prompt 强约束，逐字见 [§A 附录](99-prompts-appendix.md) 与 [§1 Agent 架构](01-agent-architecture.md)。

## 5. 输入与管线

**硬件 = 纯录音工具，完全抽象。** 真正的管线：

```
录音(File) → ASR → InputTurn(转录文本) → agent 分析 → 资产
```

| InputTurn 形态 | 内容 | 状态 |
|---|---|---|
| 闪念 | 单说话人纯文本 | demo 实现 |
| 会议 | 带 speaker 标号 | 数据模型留位，本轮不做 |

**demo 模拟**：浏览器麦克风 / 文字输入直接作为 InputTurn 文本，不接专业云 ASR、不带 speaker 分离。

## 6. 功能集（当前实现）

### 输入
- 语音闪念（demo：麦克风/文字模拟，`source=voice`）
- 文字输入（chat：`source=typed`）

### Skills（可扩展集合，demo 预置）

| skill（machine_name） | 产出 | 落库位置 | 备注 |
|---|---|---|---|
| `todo` | 待办 | `assets` | render_spec 渲染 |
| `idea` | 想法（短） | `assets` | |
| `notes` | 笔记（长文/纪要） | `assets` | v1.4 从 idea 拆回 |
| `misc` | 兜底零碎 | `assets` | 「沉淀为资产」默认目标 |
| `expense` | 记账 | `assets` | |
| `contact` | 名片 | **`contacts` 表**（一级实体） | asset 仅作 timeline 指针 |
| `event` | 日程 | **`events` 表**（一级实体） | **无 render_spec**，专用 EventCard |
| `qa` | 无资产，直接回答 | — | system skill，`render_spec=null` |
| `external_ref` | 外部系统引用 | `assets` | task-skill 创建的占位/结果卡 |
| 用户自定义 | 由 design agent 设计 | `assets` | 含 payload_schema + render_spec |

> 「skill 可扩展」是产品的核心承诺：新增一个 skill = 加 SKILL.md（或自定义 prompt）+ seed 一行
> （payload_schema + render_spec）+ dispatcher 表格一行，**零 pipeline / 前端代码改动**。详见 §1.4、§2.4。

## 7. 页面集（4 个主屏）

| # | 页面 | 路由 | 说明 |
|---|---|---|---|
| 1 | **AI 对话** Chat | `/chat` | 核心。统一助手，看得到全部；SSE 流式 |
| 2 | **日历** Calendar | `/calendar` | Schedule(流) / Month(月) / Year(年) / DayDetail / EventEditor 多视图；Schedule 吸收了「时间流」 |
| 3 | **资产库** Library | `/library` | 按类型组织（待办 / 事件 / 想法 / 笔记 / 名片 / 记账 / 文件 + 自定义） |
| 4 | **通知** Notifications | `/notifications` | Toast + 历史列表 + 时间驱动提醒 |

「呈现模式开关」（资产为主 ⇄ 日历为主）决定打开 app 落到哪个 home，页面集合不变。
详见 [§4 前端](04-frontend.md)。

## 8. demo 边界（两层）

### 可以 demo 级（接口后面，上线时替换）
- 硬件联调：不做，浏览器麦克风/文字模拟
- ASR：不接专业云 ASR，文字直接作 transcript
- 多租户：不做，固定 `user_id="default"`（`get_current_user_id()` 返回常量）
- 部署：本地 docker-compose
- 文件 pipeline（上传 + ASR + 分析）：留位不实现

### 必须生产级（建对，上线不返工）
- pipeline 编排、数据模型、API 契约、agent 编排、AI 体验质量（流式 / 低延迟 / 自然）

验收：**「PC 上能演示完整流程」+「核心架构上线不返工」**。

## 9. 术语表（Glossary）

| 术语 | 含义 |
|---|---|
| **Asset（资产）** | 一条通用 JSON-payload 内容行。**类型不存在 payload 里**，而是经 FK 链 `assets.user_skill_id → user_skills.skill_id → global_skills.name` 推导出 `skill_name`。 |
| **Skill** | 一种能力 = 一段 prompt（SKILL.md 或动态生成）+ 一行 UserSkill（payload_schema + render_spec + queryable_fields）。 |
| **render_spec** | 描述「一种 skill 的卡片怎么画」的受限 JSON DSL；前端据此通用渲染 SkillCard，**无 if-type-equals**。 |
| **payload_schema** | 描述「一种 skill 的 payload 有哪些字段」的 JSON。 |
| **Session（会话）** | 对话/捕捉容器，4 种类型：`flash / chat / meeting / manual`。 |
| **InputTurn** | session 内一次输入（一等实体，取代旧 Transcript 概念）。`source` = 模态 `voice / typed / imported`，与 session_type 正交。 |
| **provenance（来源链）** | 每个 asset/event/contact 都有 `source_input_turn_id` → input_turn → session → file，可追到「哪句话哪次输入产生的」。 |
| **effective_at** | 派生字段（不存库），entity 在时间线上的「有效时刻」，用于 timeline 跨类型混排。见 §2.6。 |
| **Flash Pipeline** | 捕捉管线：dispatcher（分意图）→ 并行 sub-skill agents → Python 聚合卡片。 |
| **Assistant** | 统一 chat 助手 agent（单 LlmAgent + MCPToolset）。 |
| **task-skill** | 异步包装第三方 MCP 调用：同步立刻返 placeholder 卡片，后台跑真活。 |
| **MCP** | Model Context Protocol。内部 MCP = 我们自己的 FastMCP CRUD server（stdio）；外部 MCP = 第三方托管 gateway（钉钉 AIHub 等）。 |
| **呈现模式（PresentationMode）** | 资产为主 ⇄ 日历为主，只决定 home，不分叉数据/AI。localStorage 持久化。 |
