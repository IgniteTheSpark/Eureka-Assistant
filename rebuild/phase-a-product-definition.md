# Phase A — Eureka 产品定义

> 版本：v3 | 2026-05-23
> 状态：定稿
> 用途：Eureka 从零重建的产品基线。决定「该做什么」与「怎么做对」,是 Phase B 架构设计的输入。
> 修订:v1→v3 经过讨论补入 calendar、名片、人群差异化、demo 约束的两层界定、agent 行为规则、知识沉淀机制、Transcript 一等实体、呈现模式。

---

## 一、背景：四阶段重建

本文档是 Eureka 从零重建的第一阶段。整体拆解：

```
Phase A — 产品定义    ← 本文档：锁定功能集与产品原则
Phase B — 架构蓝图    数据模型 / 模块边界 / Agent 编排 / API 契约 / 前端组件地图
Phase C — 后端重建    按蓝图重建 FastAPI + ADK + 数据层
Phase D — 前端重建    按蓝图与 API 契约重建 Next.js
```

技术栈保留:FastAPI + Google ADK + PostgreSQL + Next.js。重建的本质是
以「模块化 + 可维护」为原则,重做代码组织,并借机重新梳理产品。

---

## 二、产品定义

Eureka 是一个**个人 AI 助手**,硬件语音是它的线下输入入口。

用户通过硬件录下线下会议、对话、闪念指令;app 做 ASR 转录,
agent 把转录文本变成结构化资产;一个统一 AI 助手能跟你过去所有的记录对话。

---

## 三、底座 / 核心 / 差异化

| 层 | 内容 | 角色 |
|---|---|---|
| 底座 | 硬件语音输入(会议 / 对话 / 闪念) | 入口,产品的物理护城河 |
| **核心** | **统一 AI 助手**——看得到一切,意图明确时直接 CRUD,模糊时对话 | 不能碍的那件事 |
| 差异化 ① | 知识沉淀(学生 / 创作者 / 白领) | wing 1 |
| 差异化 ② | 日历为头牌 + 名片为支撑(商务 / 老板) | wing 2 |

判断标准:任何取舍,优先保障核心 AI 对话体验;两翼为它服务、为它呈现。

---

## 四、四条架构原则（移交 Phase B）

1. **生产级核心 + demo 级边缘,干净接缝**。可替换边缘(ASR / 硬件传输 / 鉴权)躲接口后;
   核心(pipeline / 数据模型 / 编排 / API)一次建对,上线不返工。
2. **AI 体验生产级**:流式、低延迟、自然。清掉现有代码里的 `nest_asyncio` / 守护线程 / 延迟 hack。
3. **资产类型由 skill 产出、可扩展**,非硬编码 enum。加/减能力 = 加/减 skill,核心编排不动。
4. **数据模型按生产级设计**:多用户-ready、Transcript 一等实体、会议留位、contact↔speaker 留缝。
   demo 跑单用户,但模型不为 demo 妥协。

---

## 五、AI 助手行为规则

统一 agent,一个对话面同时承担「捕捉」和「问答」。

| 情况 | 行为 |
|---|---|
| 用户意图明确指向资产(「帮我建个待办」「记一笔花了 50」) | agent **直接调工具创建**,资产卡片显示在对话里。无需用户额外操作 |
| 用户问的是没明确资产的问题(总结、分析、闲聊、建议) | agent 自然回答,**回答下方提供「沉淀为资产」交互** |

判定时机:一轮 agent 输出之后 —— 没有产生资产 tool call,展示沉淀入口;有的话不展示(避免重复)。

能力组成:
- 意图识别 → 选择 CRUD / 检索 / 对答
- 流式输出
- 多轮对话上下文
- 长期记忆**不靠塞 context**,靠 agent 用工具去资产库检索(production-grade pattern)

---

## 六、知识沉淀(wing 1 落地方式)

知识沉淀 = 让用户能把 AI 生成的内容沉淀成长期资产,之后 agent 还能调用。

| 路径 | 触发 |
|---|---|
| 自动沉淀 | 用户表达明确意图时,agent 直接创建对应资产 |
| 手动沉淀 | 无明确资产意图的 AI 输出,用户点「沉淀为资产」 |
| 沉淀后访问 | 资产对 agent 可见,作为长期知识库 |

沉淀的资产由 agent **通过 MCP 接口**调用(MCP 接口的具体形态—— 真 FastMCP server vs 内部 toolset —— 归 Phase B 决定)。

---

## 七、呈现模式(wing 2 落地方式)

两个人群,一套数据 + 一个 AI,**差异只在呈现层**。

| 模式 | 主屏 | 服务人群 |
|---|---|---|
| 日历为主 | 日历是 home | 商务 / 老板 |
| 资产为主 | 资产库 / 时间流是 home | 学生 / 创作者 / 白领 |

用户可随时切换。AI 对话面在任意模式下都常驻可达。

不存在「两个 app」「两种数据模型」「两套 AI」——只是首屏强调不同。

---

## 八、输入与管线

**硬件 = 纯录音工具,完全抽象**。真正的管线:

```
录音(File) → ASR → Transcript → agent 分析 → 资产
```

| transcript 形态 | 内容 | 状态 |
|---|---|---|
| 闪念 | 单说话人纯文本 | demo 实现 |
| 会议 | 带 speaker 1/2/3 标号 | 本轮不做,数据模型留位 |

**Transcript 是数据模型里的一等实体**(不是像现在那样把文本直接塞进 flash payload)。

**demo 的模拟**:浏览器麦克风 + Web Speech API,产出闪念 transcript(纯文本)。
不接专业云 ASR、不带 speaker 分离。文字输入直接作为 transcript。

---

## 九、功能集

### 输入
- 硬件语音闪念(demo:浏览器麦克风模拟)
- 文字输入

### Skills(可扩展集合,demo 装这几个)
| skill | 产出 | 必选 |
|---|---|---|
| `todo-skill` | `todo` | ✓ |
| `event-skill` | `event`(新增,用于日历) | ✓ |
| `idea-skill` | `idea`(note 已并入) | ✓ |
| `contact-skill` | `contact` | ✓ |
| `qa-skill` | 无资产,直接回答 | ✓ |
| `expense-skill` | `expense` | 可选(默认开) |

### 结构性类型
- `flash` —— 捕捉容器
- `contact` —— 名片,独立实体(非泛资产)

---

## 十、页面集（5 个,从 9 个砍下来）

| # | 页面 | 说明 |
|---|---|---|
| 1 | **AI 对话** | 核心。统一助手,看得到全部 |
| 2 | **时间流** | 含类型筛选 tab、点日期定位 |
| 3 | **日历** | 显性 feature,显示 event + todo |
| 4 | **资产库** | 按类型组织(待办按状态、记账有汇总) |
| 5 | **资产详情** | 单条查看 / 编辑 |

「呈现模式」决定打开 app 时落到哪一个 home,5 个页面集合不变。

---

## 十一、砍 / 留 / 改

### 砍掉
- Flash Session 闪念对话页 / Flash Overall 总资产页 → 并入 AI 对话
- Day View 单日页 → 并入时间流(点日期定位到当天)
- Workspace / Library 二选一 → 合成「资产库」
- Placeholder 页 → 删
- `agents/root_agent.py` LLM 路由 → 死代码,API 已绕过
- 遗留 `frontend/index.html`(146KB 单文件)→ 已被 Next.js 取代
- `/api/flash/audio`(UI 未接入)→ 暂缓

### 不砍,归 Phase B 决定
- `mcp/server.py` —— 文件现状是死的,但「要不要一个真 MCP server」由 Phase B 定
  (用户要求 agent 通过 MCP 访问资产)

### 留下
- 统一 AI 对话(核心)
- 闪念捕捉:硬件语音 + 文字输入
- 时间流 / 日历 / 资产库 / 资产详情
- Flash 提炼 pipeline(dispatcher → 并行 skills)

### 改
- 两个互不相通的对话入口(Flash Session / Agent Chat)→ 一个统一助手,共享全部上下文
- 闪念从「独立聊天世界」→ 退化成一种输入方式
- 资产类型 `note` 并入 `idea`
- 新增资产类型 `event`(日历的事件,与 todo 区分:event 有起止时间,todo 有截止时间)
- pipeline 输入从「raw text」→「Transcript」(一等实体)

---

## 十二、demo 边界(两层)

### 可以 demo 级(接口后面的东西,上线时替换)
- 硬件联调:不做,浏览器麦克风模拟
- ASR:用 Web Speech API 或简单云 API,不接专业云 ASR
- 多租户:不做,固定 `user_id="default"`
- 部署:不做,本地 docker-compose
- 真实硬件:不连

### 必须生产级(这次建对,上线不返工)
- pipeline 编排
- 数据模型
- API 契约
- agent 编排
- AI 体验质量(流式、低延迟、自然)

验收标准:**「PC 上能演示完整流程」+「核心架构上线不返工」**。

---

## 十三、非目标(本轮不做)

- Meeting Pipeline、会议专业 ASR、说话人分离
- 手动 speaker ↔ contact 匹配
- 音频文件上传 ASR
- 拍照 / 上传名片 OCR(名片只通过语音/文字录入)
- 多租户 / 账号系统
- 上云部署
- 真实硬件联调
- 重 CRM(跟进记录 / 上次联系时间等)—— 名片只做轻量容器

---

## 十四、数据模型留位(移交 Phase B)

设计时为以下场景留干净扩展点,demo 不用,但上线不返工:

- `File` / `Transcript` / `Session` 三表抽象能扩展到会议
- `contact` ↔ `transcript speaker` 链接(未来手动匹配)
- 多用户(`user_id` 不只是常量)
- 新 skill 接入(`GlobalSkill` / `UserSkill` 注册表的设计要遵循,不要再绕过)

---

## 十五、移交 Phase B 的明确决定项

Phase B 必须回答:

1. **单用户 vs 多用户**的数据模型设计(demo 跑单用户,模型按多用户准备)
2. **MCP 接口形态**:真 FastMCP server,还是内部 toolset(用户表述倾向真 MCP)
3. **对话上下文记忆深度**(近 N 轮窗口 / token 预算 / 摘要折叠)
4. **agent 编排怎么用 ADK 才不再写出 nest_asyncio / 守护线程 / 双实现**
5. **Transcript** 是独立表,还是 flash payload 里的字段升级
6. **流式输出**实现路径(SSE / WebSocket)
7. **呈现模式开关**的存储位置(本地偏好 / 用户设置 / URL state)
8. **资产类型动态渲染**:skill 可扩展意味着前端不能硬编码每种类型的卡片,需 schema-driven 渲染方案
