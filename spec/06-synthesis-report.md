# 06 · 合成 / 报告引擎（Synthesis & Report Engine）

> 状态：**设计规格（待实现）**。本章是该 feature 的**端到端唯一真值**：数据模型、agent 管线、
> md→HTML 渲染、运行时、前端表面都在这里收口；其它章节只放该层的契约 + 指回本章的指针。
> 实现归属另一个 session（本目录只负责需求与 spec）。

---

## 6.0 定位：这不是「总结」，是一个合成引擎

入口叫「总结」，但它真正要做的远不止概括。给定**一组资产 + 用户的主观意愿**,它要能产出不同**体裁
（genre）**的图文报告：

- **数据复盘**（把消费/指标/记录算成图表表格 + 结论）
- **灵感升华**（把多条灵感抽象成主题、张力、综合判断、再发散）
- **提案**（把选中的资产二次加工成方案/计划/建议书）
- **概览**（跨类型近况的轻量图文小结）

因为「产出什么」本身要随输入和意愿变化,所以它**不是一个单一 skill**,而是复刻 Flash Pipeline 的
**dispatcher → sub-skill** 模式:先判体裁,再产内容,最后渲染。

**两个底层决定（已拍板,贯穿全章）:**
1. **md 先行**:内容层只产**带轻量注解的 Markdown**(substance),渲染层再把 md → 单文件 HTML
   (presentation)。「不千篇一律」住在渲染层,跟内容彻底解耦。理念同 `nexu-io/html-anything`:
   *Markdown is the draft, HTML is what humans read.*
2. **渲染开 JS + 打包 GSAP + 渐进增强**:报告在 Flutter 的**受控 WebView**里渲染,允许 JS,
   本地打包 GSAP(`greensock/gsap-skills` 的运动模式),但**内容不依赖 JS 也能完整呈现**,GSAP 只在其上
   叠加动效。这推翻了早期「无脚本」的临时决定(那是 web demo 的 iframe sandbox 约束,Flutter WebView
   我们自己控)。

---

## 6.1 三段式管线

```
选中资产(ids) + 用户自然语言意愿
        │
        ▼  ① report-dispatcher        分类产出 genre + 抽取范围,不产内容(纯分类,无工具)
        │   → {genre, time_range?, asset_types?, source_asset_ids?, brief}
        │
        ▼  ② content skill (按 genre)  先 query 真实数据 → 产「注解 Markdown」(只管 substance)
        │   genres: data-report / idea-synthesis / proposal / digest
        │   → content.md  (+ 顶部 frontmatter)
        │
        ▼  ③ render skill              注解 md → 单文件 HTML
        │   选 surface(版式族) × palette(配色) + GSAP 动效;按 seed 决定组合
        │   → report.html
        │
        ▼  落 reports 表(md + html + spec) → 资产库「报告」容器 → WebView 查看
```

- ①②③ 都是 ADK `LlmAgent`(同 Flash 的 dispatcher/sub-skill 构造),共享 MCPToolset。
- ② 只用**只读** query 工具(`tool_query_asset` / `tool_query_digest` / `tool_query_event` / `tool_get_*`),
  **绝不**写库。
- ③ **不调 LLM 也行**:render 本质是确定性的 md→HTML 映射 + 模板填充;为了文案排版微调可以用一次轻量 LLM,
  但**布局/配色由 catalog + seed 决定**,不靠模型即兴(防 slop、防崩)。

> 复用既有基建:这条管线挂在 Chat 的 session/SSE 之上(见 §6.8),`session_type='report'`;查询工具与
> Flash/Chat 用的是同一套 MCP(见 [§1](01-agent-architecture.md))。

---

## 6.2 ① report-dispatcher（体裁分类）

一次 LLM、**无工具**、纯分类。输入 = 用户意愿文本 + 选中资产的**类型分布与摘要**(不灌全文,只给
`{type, count, 标题样例}`)。输出 JSON:

```json
{
  "genre": "data-report | idea-synthesis | proposal | digest",
  "time_range": {"from": "2026-05-01", "to": "2026-05-31"} ,   // 可空(手动选时忽略)
  "asset_types": ["expense"],                                   // 可空
  "source_asset_ids": ["..."],                                  // 手动选时必填
  "brief": "把五月消费按类目复盘,指出异常",                       // 归一化后的一句话诉求
  "title": "五月消费复盘"
}
```

判定准则(写进 dispatcher 的 SKILL.md):
- 选中/意愿里是**可量化记录**(消费/打卡/计数)且诉求是「看清楚/复盘」→ `data-report`。
- 选中多为 **idea/notes** 且诉求是「升华/综合/帮我想」→ `idea-synthesis`。
- 诉求出现「方案/计划/提案/建议书/帮我写」→ `proposal`。
- 笼统的「最近怎么样/给我个小结」→ `digest`。
- 交叉输入(灵感 + 记账一起)→ 按**主导诉求**选,内容层再融合两类数据。

---

## 6.3 ② content skills（4 个 genre → 注解 Markdown）

每个 genre 一个 sub-skill,职责一致:**先 query 真实数据 → 按本体裁的结构产出注解 md**。结构骨架各异:

| genre | 内容骨架（content skill 必产的段落语义） |
|---|---|
| **data-report** | 概要 KPI → 分类/趋势(图表)→ 异常/亮点 → 一句话结论 + 建议 |
| **idea-synthesis** | 主题聚类 → 共性与张力 → 综合判断/抽象升华 → 再发散的 3 个追问 |
| **proposal** | 背景/问题 → 目标 → 方案要点(分点)→ 取舍/风险 → 下一步 |
| **digest** | 时间线近况 → 各类型亮点卡 → 一句话总览 |

**数据契约(硬规则,全 genre 通用):**
- 数字、标题、引用**只能来自查到的记录**;**绝不编**。查不到就在报告里如实写「这段时间没有 X」。
- 图表的每个数据点都要能追溯到 asset;render 不负责造数,造数在内容层就是 bug。

---

## 6.4 注解 Markdown 语法（content ⇄ render 的契约）

正文是标准 Markdown;图表/KPI/时间线这类纯 md 表达不了的,用**指令块**(directive)或**带 JSON 的 fenced
块**。render skill 只认这套,未知指令降级成普通段落。

**顶部 frontmatter（YAML）:**
```yaml
---
genre: data-report
title: 五月消费复盘
time_range: {from: 2026-05-01, to: 2026-05-31}
source_asset_ids: [a1, a2, ...]     # 可追溯
surface_hint: dashboard             # 可空,render 可覆盖
---
```

**指令块清单(v1):**

| 写法 | 渲染成 |
|---|---|
| `# / ## / 段落 / - 列表 / > 引用` | 标准排版 |
| `:::kpi` 多行 `label: 值` `:::` | KPI 数字墙(每项 label/value/可选 delta) |
| ` ```chart ` + JSON `{type, title, unit, series:[{label,value}]}` | 图表(type ∈ bar/line/area/donut) |
| `:::timeline` 多行 `日期 — 事件` `:::` | 时间线 |
| `:::compare` 表格 md | 对比表 |
| `:::callout{tone=insight|warn|success}` … `:::` | 结论/提示框 |
| `:::quote — 出处` | 金句/重点引用 |
| `:::rank` 有序列表 `:::` | 排行榜 |
| `![alt](asset://<file_id>)` | 图文卡(资产里若有图) |

> 好处:报告**存 md + html 两份**。**重渲染 = 同一份 md 换 surface/palette/seed,瞬间换一套视觉**,
> 不重查、不重想 —— 多样性几乎零成本(见 §6.7)。

---

## 6.5 ③ render skill（注解 md → 单文件 HTML）

借鉴 `html-anything` 的 `SKILL.md` 协议:**surface(版式族) × palette(配色) × block 套件**,锁定组合 +
反 slop 硬约束。**「不千篇一律」全靠这一层。**

**surface 族（v1，按 genre 默认映射，render 可按内容覆盖）:**

| genre | 默认 surface | 气质 |
|---|---|---|
| data-report | `dashboard` | 数据仪表盘:KPI 墙 + 图表网格,冷静理性 |
| idea-synthesis | `editorial` | 杂志/手帐:大标题、留白、衬线,适合长文升华 |
| proposal | `deck-doc` | 提案文档/keynote:分节、要点块、结论强调 |
| digest | `magazine-lite` | 卡片流图文小结,轻 |

**palette（配色,起步 3-4 套）:** 极简数据 / 杂志墨 / 仪表盘暗 / 暗黑霓虹。每套 = 一组 design tokens
(配色、字阶、圆角、间距、动效曲线),复用 [§5 设计系统](05-design-system.md) 的 token 语汇。

**block 套件（无脚本即可渲染的 HTML/CSS 组件,render 从这里拼）:**
封面 hero · KPI 数字墙 · SVG 柱状/折线/面积 · CSS/SVG 环形占比 · 时间线 · 对比表 · 排行榜 ·
结论/提示框 · 金句 · 图文卡。每块自带响应式 + 8px 基线。

**变体 seed:** `seed = hash(report_id)`(或 `date+title`)→ 确定性地选 layout + palette。
→ **同一 report 重渲染稳定**;**不同 report 自然错开,连续两份不撞脸**。

**反 AI-slop 硬约束(写进 render 的 SKILL.md,源自 html-anything 的纪律):**
- CJK-first 字体栈;8px 基线网格;正文对比度 ≥ 4.5。
- **必须用真实数据**,禁止 lorem / 占位 / 凑字数的空段落。
- 单文件自包含:CSS 内联,字体/GSAP 走**本地打包**(见 §6.6),**不引 CDN、不发网络请求**。

---

## 6.6 渲染运行时（Flutter WebView + GSAP + 渐进增强）

报告 HTML 在 **Flutter WebView** 里渲染(`webview_flutter`):

- **JS 开启**,但 WebView **锁死**:禁用导航(不跟外链)、禁用文件/任意网络访问、只加载本地 `srcdoc`。
- **GSAP 本地打包**进 app(`assets/` 里放 `gsap.min.js`),渲染前注入,**不走 CDN**(离线 + 隐私:用户数据不出网)。
- **渐进增强(硬规则):** HTML+CSS 必须能**完整、静态地**呈现整篇报告;`<script>`(GSAP 入场/滚动揭示/数字滚动)
  只在其上叠动效,且:
  - 包在 `try/catch` + `typeof gsap` 存在性检查里 → JS 挂了 = 静态完整报告,**绝不空白**。
  - 尊重 `prefers-reduced-motion`。
- **安全:** 内容是「用户自己的 agent 用用户自己的数据」生成的单文件,渲染在每报告隔离的 WebView 里;
  叠加 CSP(`default-src 'none'; img-src data: asset:; style-src 'unsafe-inline'; script-src 'unsafe-inline'`)
  + 无外部 origin,把风险收口。
- 运动模式参考 `gsap-skills`:`gsap.timeline` 编排入场、`stagger` 批量、`ScrollTrigger` 滚动揭示。
  **教 agent 写正确 GSAP** 的知识可作为 render skill 的参考片段内置。

> 为什么不沿用 web demo 的无脚本 iframe:那是 demo 在桌面浏览器里的 sandbox 约束;Flutter 端报告本就是
> 我们自控的 WebView,开 JS 才能给到用户要的「图文/报表/动效综合」且「不千篇一律」的运动质感。

---

## 6.7 报告实体与生命周期

报告是**一级实体**(资产库有独立「报告」容器)。数据模型见 [§2](02-data-model.md) 的 `reports` 表,
API 见 [§3](03-api-reference.md) 的 `/api/reports`。核心字段:

| 字段 | 说明 |
|---|---|
| `id` / `user_id` | |
| `title` | dispatcher 给的标题 |
| `genre` | data-report / idea-synthesis / proposal / digest |
| `content_md` | 注解 Markdown(substance,可重渲染) |
| `html` | 渲染快照(用户当下看到的) |
| `spec_json` | `{time_range, asset_types, source_asset_ids, surface, palette, seed}`(可重跑) |
| `created_at` | |

**生命周期:**
- **生成**:管线产 md+html → `POST /api/reports`。
- **回看**:报告容器列表 → 点开 → WebView 看 `html`。
- **重渲染(换装)**:用 `content_md` + 改 seed/palette/surface → 重跑 render → 覆盖/另存 `html`。
  因为 substance 已固化在 md,**不重查数据、不重思考**。
- **分享(beta 先轻)**:导出 `.html` / 渲染成图 / 系统分享。核心先保证 存储 + 回看 + 重渲染。
- **删除**:`DELETE /api/reports/:id`。

---

## 6.8 前端表面（Flutter）

> 详细 UI 规范并入本节(本章是 feature 真值);[§4](04-frontend.md) 只放指针。

1. **入口**:资产库「报告」容器头部 + 一个显眼的「✨ 总结 · 升华」按钮 → 开一个 `session_type='report'`
   的会话(复用 Chat 的 SSE/会话基建,但用 report 管线 + 专属顶栏标题)。
2. **引导对话**:report 管线既能**一句话直给**(「帮我总结最近一个月消费」)也能**逐步引导**(问时间范围/
   资产类型/体裁,可交叉)。对话里始终提供一个 **「手动选择资产」** 的 affordance。
3. **资产选择器**(手动路径):全屏多选页,顶部**类型筛选 tab**(全部 / 待办 / 记账 / 灵感 / 笔记 / 事件 /
   名片 / 各自定义 skill),列表项带 checkbox;勾选 → 「用选中的 N 条总结」→ 选中 ids 回填进会话,
   管线从 `source_asset_ids` 直接进 ② content skill。
4. **报告容器**(📊,资产库常驻):报告列表(标题 + genre + 时间范围 + created_at),点开 → 查看器。
5. **查看器**:全屏 = 顶栏(标题 / 返回 / 分享 / 重渲染) + WebView(`html`)。重渲染 → 走 §6.7 换装。

---

## 6.9 v1 范围与里程碑

- **v1 必做**:4 个 genre(data-report / idea-synthesis / proposal / digest);md 注解语法全集;
  render 的 4 个 surface × 3-4 palette;WebView+GSAP 渐进增强;reports CRUD + 容器 + 查看器;
  引导对话 + 资产选择器。
- **v1 可后置**:分享导出(先只存+看)、重渲染换装 UI(后端 spec_json 先留好)、`asset://` 图文卡
  (用户图片资产少,先占位)。
- **质量门**:每个 surface 出 1 张 `example.html`(同 html-anything 的 example 约定)做视觉基线;
  反 slop 约束进 render SKILL.md。

---

## 6.10 skill 文件落点

| skill 文件 | 角色 |
|---|---|
| `backend/skills/report-dispatcher/SKILL.md` | ① 体裁分类(无工具) |
| `backend/skills/report-<genre>/SKILL.md` ×4 | ② 各 genre 的内容 skill(产注解 md;只读 query) |
| `backend/skills/report-render/SKILL.md` | ③ 注解 md → HTML;内含 surface×palette catalog + block 片段 + 反 slop 约束 + GSAP 片段 |
| `backend/agents/report_pipeline.py` | 编排 ①→②→③(复刻 `flash_pipeline.py` 结构) |

> 逐字 prompt 进 [§99 附录](99-prompts-appendix.md)(与 Flash/Chat 同等对待:agent 行为的载体)。
