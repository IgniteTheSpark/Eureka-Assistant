# Eureka Assistant — 产品与工程 Spec（交付版）

> 版本：1.1 · 2026-06-04
> 状态：**Authoritative**。
> **真值源（2026-06 起翻转）：产品 = Flutter app `mobile/` + `backend/`；web `frontend/` 降为历史来源（出处参考）。**
> 当 spec 里的 web 行为描述与 Flutter 实现冲突，**以 `mobile/` 为准**。
>
> **本 spec 的分层与状态（读前必看）：**
> - **§1-3（agent / 数据 / API，后端）** —— 权威，基本与实现同步（后端未被重写）。
> - **§4（前端）** —— 正从「web demo 行为 + Flutter 注脚」**逐区 re-baseline 到 Flutter 规范**；
>   章内「Flutter 增量 / 实现注意」即规范。优化分支稳定后再做集中逆向。
> - **§6（合成·报告引擎）+ Connected Apps（§1.7.1 / §3.14 / §4.0.6）** —— **design-ahead 设计规格，
>   标注「待实现」**，不代表已构建。
>
> 与 `rebuild/` 的关系：`rebuild/` 是历史「分阶段重建」的规划文档（Phase A/B/D + 里程碑），
> 含大量 amendments / drift 标注，且部分内容已与代码脱节（见下方「与旧文档的偏差」）。
> **当二者冲突，以本 `spec/` 为准。**

---

## 阅读顺序

| # | 文档 | 内容 | 谁必读 |
|---|---|---|---|
| 0 | [00-product-overview.md](00-product-overview.md) | 产品定义、人群、核心概念、术语表、demo 边界 | 全员 |
| 1 | [01-agent-architecture.md](01-agent-architecture.md) | Agent 编排、Flash/Chat/Task 三条管线、MCP 边界、LLM 配置 | 后端 / AI |
| 2 | [02-data-model.md](02-data-model.md) | 数据库 17 张表、provenance 模型、render_spec / payload 契约、seed 数据 | 后端 / 全栈 |
| 3 | [03-api-reference.md](03-api-reference.md) | 每个 endpoint 的 method/path/请求/响应 JSON、SSE 事件格式 | 前端 / 后端 |
| 4 | [04-frontend.md](04-frontend.md) | 4 个主屏、交互/sheet/动画、render-spec 渲染、客户端数据流。**正逐区 re-baseline 到 Flutter 规范**（冲突以 `mobile/` 为准） | 前端 / Flutter |
| 5 | [05-design-system.md](05-design-system.md) | 精确 design tokens、7 个 accent 槽、字体、动效、组件视觉规范 | 前端 / 设计 |
| 6 | [06-synthesis-report.md](06-synthesis-report.md) | **合成·报告引擎**（设计中）：总结/升华/提案 dispatcher + 内容 skill + md→HTML 渲染 + GSAP/WebView + reports 实体 · §6.11 微点评(**已 pending**,需求转 §1.5.1 会话开场 hint) | 全栈 / AI / 前端 |
| 7 | [07-gamemode.md](07-gamemode.md) | **任务 & 周岛**（设计中 · 游戏化层之一）：dock 壳改动 · 任务体系(L1, daily-gen) · 周岛(成果物) · 统一 completion_event · 「我的岛」shell | 全栈 / AI / 前端 / 设计 |
| 8 | [08-domain-system.md](08-domain-system.md) | **领域(domain)系统**（设计中 · 横切章）：8 生活领域 · 存储真相链 · agent 赋值 · 卡片展示 · per-domain 任务日环 · 按领域总结/查询 + 技能名消歧 | 全栈 / AI / 前端 / 设计 |
| 9 | [09-pet.md](09-pet.md) | **宠物（球球）**（v1 已实现 · 游戏化层之二）：球球本体(无 exp) · 换装/背包 · 掉装饰 + 里程碑(奖励经济) · 浮动球球 · 只读消费 completion_event | 全栈 / AI / 前端 / 设计 |
| 10 | [10-game-config.md](10-game-config.md) | **游戏配置与 Live-Ops**（横切 §7+§9）：装饰目录/掉落池/里程碑/岛经济/调参旋钮的配置层 · 代码拥画法-配置拥经济 · 校验器 · Stage1 仓库内 config / Stage2 后台 admin | 后端 / 全栈 |
| 11 | [11-admin.md](11-admin.md) | **管理后台 / Live-Ops Console**（设计中 · 待讨论）：任务配置(规则+校验+奖励) · 组件库(增删/稀有度/概率) · 全用户总览(奖励发放可见) · 依赖 §10 Stage1 + §7 | 后端 / 全栈 |
| 12 | [12-business-model.md](12-business-model.md) | **商业模式**（pending · 先不做）：LLM 成本账(每请求/每用户) · Free+单 Pro 定价提案(捕捉 30/天·chat 300/月·报告/洞察) · 护栏 · **token 用量日志(唯一现在该做)** | 商业 / 后端 |
| 13 | [13-baizhi-integration.md](13-baizhi-integration.md) | **百智平台集成**（硬件供应商 + 未来收购方）：**B1 OAuth 登录 ✅ 已实现**(百智作 IdP)· B2 会议/日历 MCP 连接器 · B3 录音卡 SDK → Flutter 插件(手机直连) · B4 资产单向同步百智 KB（B2–B4 设计中）| 全栈 / 后端 / 移动 |
| 14 | [14-proactive-reka.md](14-proactive-reka.md) | **主动 REKA（陪伴层）**（设计中）：零配置主动提醒/帮做 · Type A=通知(+节律缺口) · Type B=主动报告(+web-search) · 晨间简报(沉浸式) · cron/heartbeat + 统计节律 profile · 傻瓜护栏 | 全栈 / AI / 前端 / 设计 |
| A | [99-prompts-appendix.md](99-prompts-appendix.md) | **逐字** LLM prompts（agent 行为的载体，必须 byte-for-byte 复刻） | AI / 后端 |

> 单一大文档版本：[`SPEC.md`](SPEC.md)（以上所有章节拼接，便于整体交付与检索）。

---

## 30 秒理解 Eureka

Eureka 是一个**个人 AI 助手**。用户用**语音（硬件/麦克风）或文字**记录闪念、待办、
开销、想法、联系人、日程；一个 **AI agent** 把这些非结构化输入归类成**带类型的卡片**
（typed cards），能**对你自己的全部数据问答**、生成 **HTML 图文报告**，并能把条目
**同步到第三方工具**（钉钉 / Notion / Google Calendar，经 MCP）。

```
语音/文字  →  Flash Pipeline（分类→并行 skill）  →  typed 卡片（todo/event/idea/...）
                              ↓
统一 Chat 助手  ←→  你的全部资产（CRUD + 问答 + 报告 + 外部同步）
```

两类入口、一个共享 agent 栈：
- **Flash**（`POST /api/flash`，**同步 JSON**）：捕捉。一句话可拆成多意图，并行处理后合并返回卡片。
- **Chat**（`POST /api/chat`，**SSE 流**）：对话。意图明确直接 CRUD，模糊则对答；可出报告、可外部同步。

---

## 技术栈（实际实现，非规划）

| 层 | 技术 | 备注 |
|---|---|---|
| 前端（产品） | **Flutter 3 / Dart**（`mobile/`，iOS-first） | **当前交付端，真值以此为准**；§4 正逐区对齐到它 |
| 前端（来源） | Vite 5 + React 18 + TS + Tailwind 3 + SWR（`frontend/`） | web demo，**历史来源 / 出处参考**，非交付端 |
| 后端 | FastAPI（Python，async） | title `Eureka API`，version `1.4.0`；**未被重写，§1-3 权威** |
| Agent | **Google ADK** + LiteLLM → **DeepSeek 直连**（`api.deepseek.com`，国内托管） | 见 §1 |
| 模型 | **`deepseek/deepseek-chat`**（所有角色；没 deepseek key 的 dev 回退 OpenRouter） | 国内 inbound 稳；见 §1.1 |
| 内部工具 | **FastMCP** server（stdio 子进程） | CRUD 工具 |
| 外部工具 | MCPToolset（stdio / streamable_http / sse） | 钉钉 / Notion / Google Cal |
| 数据库 | **MySQL**（aiomysql / pymysql） | ⚠️ **不是 Postgres，无 pgvector** |
| Dev runtime | Docker Compose（db + backend） | |

---

## ⚠️ 与旧文档（README / rebuild/）的关键偏差（移植者必看）

复刻时若沿用旧 `rebuild/` 或根 `README.md`，会踩到以下已确认的脱节点：

1. **数据库是 MySQL，不是 PostgreSQL + pgvector。** 全库无任何 vector / embedding 列
   （`db/database.py` 里只有一句「将来才加」的注释）。`UUID` 存为 `CHAR(36)`，应用层生成；
   布尔存为 `Integer` 0/1。
2. **`POST /api/flash` 是同步 JSON，不是 SSE。** 只有 `/api/chat` 和 `/api/notifications/stream` 是 SSE。
3. **LLM 模型是 `deepseek/deepseek-chat`**，经 **DeepSeek 直连 API**（`api.deepseek.com`，国内托管 →
   inbound 稳）。没配 `DEEPSEEK_API_KEY` 的 dev 机回退 `openrouter/deepseek/deepseek-chat`；prod compose
   硬要求 deepseek key（`core/llm.py`）。
4. **17 张表。** 原 14 + `users` / `reports` / `connected_apps`（后加；`models.py` 的 `__tablename__` 为准）。
5. **资产类型已是：** `todo / notes(随记) / expense / contact / qa / external_ref` + 自定义（`idea`/`misc` 已并入 `notes`/随记，迁移 0008），
   外加一级实体 `event`、`contact`。`event` 是**一级表、无 render_spec**；`contact` 真身在 `contacts` 表。
6. **前端导航是悬浮 dock（5 元素 capsule），不是底部 TabBar+FAB。** `/chat` 例外（不渲染 dock）。
7. **已知残留 bug（复刻时别照抄）：** `api/skills.py` 的级联删除用了 Postgres 专有 SQL
   （`array_remove` / `CAST(... AS uuid)`），在 MySQL 上跑不通；`db/queries.py` 的
   `query_assets_structured` 引用了已不存在的 `source_transcript_id` 列。详见 §2 / §3。

> 这些偏差正是 Flutter 移植「丢细节」的根因：旧 spec 描述的是*规划意图*，本 spec 描述的是*已构建事实*。
