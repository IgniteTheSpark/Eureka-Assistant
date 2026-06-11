# 06 · 合成 / 报告引擎（Synthesis & Report Engine）

> 状态：**v1 已实现（2026-06-04）**。本章是该 feature 的**端到端唯一真值**：数据模型、agent 管线、
> md→HTML 渲染、运行时、前端表面都在这里收口；其它章节只放该层的契约 + 指回本章的指针。
>
> **实现与本设计的三处刻意偏差(为可靠性/落地):**
> 1. **② 内容层不调工具**:管线**先确定性地拉好真实数据再注入** content skill(见 §6.3 注),
>    content skill 是纯 data→md 转换器、无工具。原因:DeepSeek 工具调用在本仓库反复证明不稳,
>    预取保证「数字只来自真实记录」。
> 2. **③ render 是确定性 Python 模块** `backend/agents/report_render.py`(不是 LLM SKILL.md)——
>    与 §6.5「render 本质是确定性的」一致,直接走 catalog×palette×seed,零 LLM、零 slop。
> 3. **入场动效 = GSAP(本地打包)+ vanilla 兜底**:`gsap.min.js`(3.12.5,72KB)打进 app
>    (`mobile/assets/js/`),报告查看器在 `loadHtmlString` 前把它注入 HTML `<head>`(§6.6「渲染前注入」),
>    报告自带的增强脚本检测到 `window.gsap` 就用 **GSAP timeline + stagger**(块错峰淡入、柱状 `scaleY` 生长、
>    环形淡入);没有 gsap(如导出的 .html)则退到无依赖的 vanilla 淡入。**块默认全可见**,脚本不跑也完整
>    (静态优先),并尊重 `prefers-reduced-motion`。
>
> 落点见 §6.10。chat/flash 不产报告、只兜底指路(§6.8.0)。
>
> **视觉升级(2026-06,已实现)**:6 套 palette(ink/minimal/dashboard/neon/warm/forest,按 seed 选,连续两份不撞脸)、
> **语义图表配色**(series 可显式 `color`,否则按标签语义自动上色:好评/达成→绿、差评/亏→红)、masthead eyebrow。
> 全 4 genre 已在 393px headless 实测渲染通过(见各 directive:kpi/donut/bar/quote/callout/rank/timeline/compare)。
> **修过的坑**:`:::quote — 出处` 这类带行内尾注的 directive 曾让解析器死循环(行以 `:::` 开头但不匹配
> 旧 directive 正则 → 既不消费也不前进);已修正则 + 加「未消费的 block-start 行强制前进」兜底。

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

> **轻量近亲 = 单记录解读**:同样是「agent 解读你的数据」,但 scope 缩到**单条记录 + 近期上下文**、产出 1-2 句。**承载已改**:不再做卡片内「微点评」(§6.11 **已 pending**),而是作为**资产锚定会话的开场 hint**([§1.5.1](01-agent-architecture.md))—— 你主动就某条资产发起讨论时的开场白 + 起聊建议。报告 = 宏观合成(多资产、独立向导);hint = 微观开场(单记录、对话入口)。两者共享「先查真实数据再产出、绝不发明」的纪律,且**都不住在 skill 层**。

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
        │   → {genre, time_range?, asset_types?, keywords?, domain?, source_asset_ids?, brief}
        │     domain? = 按生活领域过滤(8 选 1,§8);技能名∩领域名冲突时澄清(见 §6.2 / §8.5.2)
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

> **独立入口(已实现 2026-06):** 这条管线走自己的端点 `/api/reports/intake` + `/api/reports/generate`(SSE),
> **不复用 chat、没有 `session_type='report'`**(早期设计已废弃);产物落 `reports` 表。取数仍复用同一套内部 MCP
> 查询工具(见 [§1](01-agent-architecture.md))。

---

## 6.2 ① report-dispatcher（体裁分类）

一次 LLM、**无工具**、纯分类。输入 = 用户意愿文本 + 选中资产的**类型分布与摘要**(不灌全文,只给
`{type, count, 标题样例}`)+ **用户真实拥有的资产类型字典**(`available_asset_types: machine_name = 显示名`)。

> **关键(踩过的坑)**:dispatcher 不知道用户的 skill machine_name(会把「读书」猜成 `reading`,而真名是
> `book_note`→ 查询拿不到数据、报告空)。所以**必须注入 `available_asset_types`**,并要求 `asset_types`
> **只能从字典里挑 machine_name**。管线侧 `_fetch_report_data` 再加一层**模糊解析**(machine_name 精确 →
> display_name → 子串)兜底。
>
> ⚠️ **不再「按类型查空就回退全类型 digest」(2026-06 修,曾把无关记录全塞进话题报告)**。根因:用户点
> 「读书进展」但字典里**没有**读书类技能 → 旧版 dispatcher 回 `asset_types:null` → `_fetch_report_data`
> 落到全类型 digest → 把待办/记账/跑步**全部**塞进一篇标题写着「读书复盘」的报告。**现在分三类范围**:
> ① 笼统/跨类型小结 → `asset_types` 与 `keywords` 都 null → 全类型 digest;② 具体话题 + 字典有对应类型 →
> 填 `asset_types`(**严格**,查空就查空、**不**回退全类型);③ **具体话题但字典没对应类型 → 填 `keywords`**
> (2~4 个含近义/同根的话题词)→ 管线对全类型记录做**关键词文本过滤**,只留命中的。三类都接 `_MIN_RECORDS`
> 门槛:**相关记录 < 3 → 如实「数据太少」**(而不是凑一篇无关内容的报告)。`keywords` 持久化进 `spec_json`。

输出 JSON:

```json
{
  "genre": "data-report | idea-synthesis | proposal | digest",
  "time_range": {"from": "2026-05-01", "to": "2026-05-31"} ,   // 可空(手动选时忽略)
  "asset_types": ["expense"],                                   // 可空 · 字典里有对应类型时填
  "keywords": ["读书","看书","阅读"],                            // 可空 · 话题但字典无对应类型时填(关键词过滤)
  "domain": "娱乐",                                              // 可空 · 按生活领域过滤(8 选 1,§8)
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

**按生活领域(domain)抽取(§8.5):** 用户说「总结我最近所有**娱乐**事项」「看看我最近**工作**整体情况」→ 填 `domain`(管线按 `assets.domain` 过滤,跨技能聚合该领域)。两条硬规则:
- **领域 ≠ 类型**:`domain` 是生活领域(8 选 1,跨技能);`asset_types` 是技能 machine_name。无修饰的领域词(工作/娱乐…)**默认解读为 `domain`**(贴合「整体情况」语感)。
- **技能名 ∩ 领域名冲突 → 澄清(关键,§8.5.2)**:一个词若**同时**命中某技能(`available_asset_types` 的 machine_name/显示名)**和**某 domain(如技能「工作记录」vs 领域「工作」)→ **不猜,反问一句**:「你是指『工作记录』这个技能,还是『工作』这个生活领域(涵盖所有工作相关记录)?」。这正是把领域级总结**收在报告向导**(而非 chat/flash)的理由——只有这里有澄清回合(§8.5.3)。

---

## 6.3 ② content skills（7 个 genre → 注解 Markdown）

每个 genre 一个 sub-skill,职责一致:**先 query 真实数据 → 按本体裁的结构产出注解 md**。结构骨架各异:

| genre | 内容骨架（content skill 必产的段落语义） |
|---|---|
| **data-report** | 概要 KPI → 分类/趋势(图表)→ 异常/亮点 → 一句话结论 + 建议 |
| **idea-synthesis** | 主题聚类 → 共性与张力 → 综合判断 → **方向/初步结论**(给一个有理由的方向 + 第一步,**不以开放问题收尾**,§6.3.1 #8) |
| **proposal** | 背景/问题 → 目标 → 方案要点(分点)→ 取舍/风险 → 下一步 |
| **digest** | 时间线近况 → 各类型亮点卡 → 一句话总览 |
| **briefing**(✅ 2026-06,§14.5 会前调研) | 是什么(外部画像,**每条标出处**)→ 最近动态(timeline)→ 和你的关联(用户记录)→ 可聊的/注意的 → `:::actions` 准备动作 → 来源。**唯一带 §14.9 web-search 管线步的 genre**;grounding 墙:外部主张可追溯、与用户数据绝不混写 |
| **quiz**(✅ 2026-06,§6.14) | 标题+headline → **一个 `:::quiz` 块**(JSON 题组:每题 4 选项+answer+explain,≤10 题)。**只考用户记过的**;干扰项同类不送分 |
| **flashcard**(✅ 2026-06,§6.14) | 标题+headline → **一个 `:::flashcards` 块**(每行 `正面 :: 背面`,≤20 张)。正反面**忠实**用户记录 |

**数据契约(硬规则,全 genre 通用):**
- 数字、标题、引用**只能来自查到的记录**;**绝不编**。查不到就在报告里如实写「这段时间没有 X」。
- 图表的每个数据点都要能追溯到 asset;render 不负责造数,造数在内容层就是 bug。

### 6.3.1 内容质量：洞察，不是流水账（产品决策 2026-06）

> **病灶(实测)**:`data-report` 骨架**强制** KPI 墙 + 图表 + 明细列表,套到「7 条零散笔记」上 →
> 把噪音做成仪表盘(按记录类型计数的 donut + 原文回显当「明细」)。**"洞察"之名、"摘要"之实、且枯燥。** 七条规则纠偏:

1. **解读 > 描述**:headline 必须是**判断/观点**,不是「记录分散在多个维度」这种无信息陈述。每段都要回答「所以呢」。
2. **连接 > 罗列**:把记录**聚类、连线、点出张力**(`idea-synthesis` 骨架已是对的形状);**禁止把记录原文当「明细」回显**。
3. **至少一条非显然观察**:用户自己扫一眼看不出的东西(例:「你这周反复回到'做个极简工具'——灵感捕捉、番茄钟在说同一件事」)。
4. **下一步要具体、贴内容**:「先把番茄钟想法写成一页」**＞**「建议单独建立读书笔记分类」(后者是通用归档建议,谁都适用 = 没用)。
5. **图表要挣来**:KPI/图表**仅当有真正量化故事**(金额/趋势/分布有意义)才出;**按记录类型计数的 donut(笔记3/待办1)永不渲染** —— 那不是发现。无量化故事 → 纯文字综合打头,骨架的 KPI/chart 步骤**可整段跳过**(不是必产)。
6. **诚实对题**:用户问「读书」却无读书数据 → **如实说 + 顺势聊真有的**,**绝不**拿无关记录凑一篇标题写「读书复盘」的报告。**insufficient 门槛按「命中主题的记录数」算,不是总记录数**(§6.2)。
7. **声音**:温暖、有观点的 REKA 口吻;不写归档员腔(「尚未形成系统读书笔记」→「这周你没真在读书,倒是冒了仨'想做个工具'的念头」)。

> **立体化(2026-06)**:在以上 7 条(尤其规则 5「图表要挣来」)前提下,各 genre skill **主动用渲染器的表现块**让报告更有层次 —— `:::rank` 排行、`:::compare` 对比表、多张 `chart`(分布 + 趋势)、`:::timeline`、多个 `:::callout`,各司其职;**每块承载真信息,不为用而用、不灌水**。各 genre 还加了深度层:**idea-synthesis**(主题排序 + 张力对比表 + 非显然观察)、**data-report**(分布 + 趋势双图 + 排行 + 环比对比)、**digest**(排行亮点 + **跨类联系**)、**proposal**(备选对比表 + 问题定性 + 风险缓解)。数据稀薄时照旧老实少放(规则 5)。
8. **落地于方向,别以开放问题收尾(尤其 `idea-synthesis`)**:升华/发散后必须**收敛到一个初步结论或方向** —— 挑最有希望的一条线、说**为什么**、给**第一步**。像个会拍板的顾问,不是把问题原样抛回。**禁止用 3 个开放问题当结尾**(那是 punt,不是洞察);结论后可附**至多 1 个**「若想更进一步」的问题,且从属于结论。立场要有、但谦逊:是**从真实想法里推出的**起步判断(如「捕捉工具是上游」可由想法本身导出),非凭空建议,用户可推翻。
   > 例:把「再发散:① 如何协同？② 要哪些分类维度？③ 哪个最迫切?」→「**方向**:先做灵感捕捉工具(它是番茄钟/归类的上游、你每天都会用),最小版本=语音→自动打标签的收件箱,两周后再决定要不要长成系统。」

**genre 选择纠偏(§6.2 dispatcher)**:**量化记录**(金额/计数/打卡)才 `data-report`;**零散 idea/notes/todo → `idea-synthesis`(聚类升华)或 `digest`**,别用 data-report 把定性数据仪表盘化。

> **落点 = 改 `skills/report-*/SKILL.md`**:① data-report 骨架的 KPI/chart/明细从「必产」改「有量化故事才产」+ 删原文回显;② 全 genre 加「解读>描述、非显然观察、具体下一步、REKA 声音」段;③ **`report-idea-synthesis` 把第 5 步「再发散:3 个追问」改成「方向/初步结论:有理由的方向 + 第一步,至多附 1 问」(#8)**;④ dispatcher 加「定性数据走 idea-synthesis」+ 主题命中数门槛。**(一次可选的更强写作模型只给 content 这一步:报告低频、质量即产品,见 §12 成本——这一步加钱划算。)**

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
| `:::actions` 多行 `- <可执行下一步>` `:::` | **可执行下一步清单**(渲染成「✦ 接下来」勾选样式;**每条可一键沉淀成待办**,见 §6.13) |

> 好处:报告**存 md + html 两份**。**重渲染 = 同一份 md 换 surface/palette/seed,瞬间换一套视觉**,
> 不重查、不重想 —— 多样性几乎零成本(见 §6.7)。

---

## 6.5 ③ render skill（注解 md → 单文件 HTML）

借鉴 `html-anything` 的 `SKILL.md` 协议:**surface(版式族) × palette(配色) × block 套件**,锁定组合 +
反 slop 硬约束。**「不千篇一律」全靠这一层。**

> **设计稿移植(✅ data-report / idea-synthesis / proposal / digest 四 genre 已落,2026-06)**:把外部设计
> handoff(6 palette × surface × block kit)移进渲染层。`agents/report_styles.py` = `report-base.css`(block
> 基元 + 6 个 `.pal-*` → `--rk-*` token 集) + `SURFACE_CSS`(每 surface 的专属版式/hero/glow)的逐字真值源,
> 现含 8 个 surface:`surface-dashboard`·`surface-neon`(data-report)、`surface-editorial`·`surface-note`
> (idea-synthesis)、`surface-deck`·`surface-forest2`(proposal)、`surface-mag`·`surface-wdash`(digest)。
> `agents/report_render_designed.py` = **新设计渲染路径**(emit 设计 markup:`.r-kpi-item`/div 柱/donut `data-arc`/
> `.r-callout.insight`/`:::actions`;每 surface 一套 masthead builder——dash/neon hero 大数、editorial 衬线+首字
> 下沉 lead、note 手帐贴纸、deck/forest 提案 cover、mag 4-up stat strip、wdash chip 行;donut 用**互异色**
> categorical 调色板、单序列柱用 accent 渐变;footer 仍挂**真实用户 pet**)。
> **加法、不破坏**:`render_report` 仅对 `_VARIANTS` 里的 genre 派发到它(每 genre 2 个变体,seed 选其一),其余
> genre 走旧渲染器零回归(morning-briefing 不在此列 —— 它有**专属沉浸构建器** `agents/morning_briefing.py`,见 §14.6)。`:::actions` 在所有 genre 都渲染为只读 ✦接下来 清单。

**surface 族（v1，按 genre 默认映射，render 可按内容覆盖）:**

| genre | 默认 surface | 气质 |
|---|---|---|
| data-report | `dashboard` | 数据仪表盘:KPI 墙 + 图表网格,冷静理性 |
| idea-synthesis | `editorial` | 杂志/手帐:大标题、留白、衬线,适合长文升华 |
| proposal | `deck-doc` | 提案文档/keynote:分节、要点块、结论强调 |
| digest | `magazine-lite` | 卡片流图文小结,轻 |
| briefing | `deck-doc` | 调研简报:严肃文档,无设计变体(走通用渲染),不配 AI 图 |

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

### 6.6.1 「Reka Insights」署名带（品牌 + 用户的 REKA，✅ 已实现 · §6.12 批 3）

> **目标**:每份报告有一块**固定的品牌署名带**(header 或 footer),放**该用户自己的 REKA**(可动)+ 「**Reka Insights**」字标。
> **分享时品牌必露出** —— 而且因为是用户**自己独一无二的 REKA**(自己的皮肤/徽记/光环),它是个**强分享钩子**(Wrapped / Duolingo 吉祥物式的传播),不是惩罚性水印。

- **放哪**:**footer 署名带为主**(签名/落款感、最适合分享图的「出品」位),可选 header 再放一个小 mark。**所有报告都带**(含免费用户 —— 这是免费营销);**不可由内容覆盖**(固定模板元素)。但**要克制**:一条精致署名带,不是占半屏的水印。
- **放什么**:用户的 REKA sprite(从 `pets` gene 渲染:`seed/skin/emblem/emblem_color/equipped/aura`)+ 「Reka Insights」字标 + 一行轻 tagline / `eureka.app`(分享图上引流)。
- **怎么实现(复用 §6.6 已有机制)**:
  1. **注入引擎**:像注入 `gsap.min.js` 一样,viewer 把 `assets/js/{pixel,mascot}.js` 注入报告 `<head>`(本地打包、不走网络,合 CSP 的 `script-src 'unsafe-inline'`)。
  2. **传入 gene**:pipeline 把该用户的 pet gene 写进报告 `spec_json`/frontmatter;模板里一个 `<div id="reka-sign">`,mascot.js 挂载并渲染**这只**REKA。
  3. **动效**:idle 循环 + 载入时一个轻 celebrate(REKA「呈上」这篇);尊重 `prefers-reduced-motion`;**渐进增强** —— JS 挂了就显一帧静态 REKA(sprite-factory PNG,`img-src data:`),署名带**绝不空白**。
- **分享/导出必须自包含(关键)**:导出 `.html` → 把 `pixel/mascot.js` + gene **内联**(同 §6.5「单文件自包含」),分享出去的文件独立就能动;导出**图片**(承 §7.4 岛分享卡「合成 岛+球球+stats」那套)→ 截取 REKA 一帧 pose,品牌稳进画面;链接分享(后置)→ 直接 live 动。
- **确定性 / 缓存**:pet gene **随报告快照存一份**(`reports` 行)→ 用户日后换了装,**老报告再分享仍是当时那只**(可复现、不回改历史)。
- **免费 vs Pro**:**建议署名在所有报告上保留**(增长 > 白标);Pro 去署名(白标)= 可选后置,但现阶段优先传播。

> **落点**:`report_render.py` 加 footer 署名带模板;`report_viewer_page.dart` 注入 `pixel/mascot.js`(同 GSAP 注入);pipeline 把 pet gene 进 `spec_json`;导出路径内联 JS+gene。与 [§9](09-pet.md) 的渲染引擎、[§7.4](07-gamemode.md) 的岛分享卡同源(都合成「用户的 REKA」)。

### 6.6.2 AI 配图（概念插画 + 场景 backdrop）

> **一条铁律压住一切**:**AI 永不画"数据"** —— 不画图表、不画数字、不画任何能被当成数据的东西(那是伪造,§6.3)。**真实数据永远是确定性 SVG**(从记录算出)。AI 只画**插画 / 氛围**。守住这条,下面两种用法都安全。

**模式 A — 概念插画(可视化的想法)**:idea-synthesis / proposal / 灵感里,把一个**能画出来的想法**配一张插画(「极简灵感捕捉工具」→ 一张概念图)。

**模式 B — 场景 backdrop + 表现力数据可视化(回答「图表类也能有意思」)**:数据段也能"有意思 + 有动效",两层叠:
- **底层(可选 AI)= 场景 backdrop**:Nano Banana 画一张**纯氛围**的背景**反映场景**(跑步报告→步道意境、消费报告→抽象金融质感)。**硬规则:backdrop 里绝不含数字 / 标签 / 图表形** —— house-style prompt 明令禁文字/数据。
- **上层(始终)= 真实数据的表现力 SVG**:真数据照旧渲成 SVG 图,但**画得有表现力 + GSAP 动效**(柱 `scaleY` 长出、环 `stroke-dashoffset` 扫出、线沿 path 画出、KPI 数字 0→值滚动、scroll-trigger 揭示)。**这层免费、即时、零伪造风险**,是「有意思的图表」的主力。
- **合体**:GSAP timeline 把两层串起 —— backdrop ken-burns / 淡入 → 其上真实 SVG 图 draw-on → 数字滚动。**既反映了"整个场景"、又一个数字都没编。**

- **gate(谁能配 AI 图)**:① **模式 A**:genre=idea-synthesis/proposal + content LLM 判"想法可视化";② **模式 B backdrop**:任意 genre 可,但**仅当内容有份量**(§6.3.1「fancy 随 substance」—— 7 条零散记录不配 backdrop);③ **配额闸**(下)。**表现力 SVG + GSAP(无 AI)不受配额限,默认就该好看。**
- **数量约束(服务端强制)**:**每篇 AI 图硬上限 ≤1–2 张**(content LLM 提议 `image_prompt` / `backdrop_prompt`,**管线计数强制**,超额跳过);**每用户/月配额**(Pro 门控,见 [§12](12-business-model.md))。
- **模型 / 接线(已定)**:**Nano Banana 2 = `google/gemini-3.1-flash-image-preview`,走 OpenRouter**(复用现有 key + LiteLLM,key 已申请)。**价**:输入 $0.50/M、输出 $3/M;**一张图 ≈ ~0.5–1.5¢**(图输出约 1–2k token,**以首次真实 `usage` 校准**)—— 比早先 ~2–4¢ 估值更便宜。**延迟 ~12.5s → 异步填充是硬要求**(下)。
- **统一画风(质量关键)**:每个 prompt 追加固定 **house style**(柔和扁平 / 跟报告 palette / **无文字无数字**)→ 全报告图风一致、贴品牌。
- **出图时机(实现:同步)**:原设计想异步补图(避 gemini ~12.5s 延迟);**实际改同步** —— 豆包 Seedream ~5s,且异步「事后 pop in」会让用户以为没生成(踩过)。现在在 persist 前就出图、hero 位内联进报告 html(`MEDIUMTEXT`),**报告一打开就有图**;一个 `image` 阶段(「正在配图…」)给进度反馈。图也落 `files` 表(`asset://` provenance,供换装复用);导出自包含时图本就内联 base64。
- **缓存 / 确定性**:AI 图**随报告存一份**(重渲染/换装不重画、不重计费)。表现力 SVG 本身确定性(seed)。
- **安全**:provider moderation;只画概念/氛围,**不画真人**(不从个人数据生成人脸);backdrop 不含数据。

**实现:**
- **配图(概念插画 + 场景海报)· 同步出图 · 双风格**:`agents/report_image.py`(`generate_image(prompt, house_style)` 全程 graceful + `quota_ok`/`monthly_image_count` 每用户/月配额 + `store_image_file`)。**`_IMAGE_GENRES` = `{idea-synthesis, proposal, data-report, digest}`**;**按 genre 选风格**(`_build_report_image`):
  - **idea-synthesis/proposal → `HOUSE_STYLE`(柔和扁平概念插画)** —— 单主体概念意象。
  - **data-report/digest → `POSTER_STYLE`(漫画/manga 海报)** —— 粗墨线 + 网点 halftone + cel-shading。**踩过的坑**:直接说「comic-book」模型会画成**杂志/漫画封面**(漏「Life Life」大标题、MOVIE 票、Supermerk logo、条码、人脸)。修法:prompt 明确「**this is NOT a cover/poster/page, just the objects**」+ 硬列 NO title/logo/barcode/cover-art/face、**every surface completely blank**。实测漫画感强且零文字。
  - 各 content skill 产 `image_prompt:`(场景实物,**只画无字实物**:咖啡杯/购物袋/跑鞋/书…,**禁**文字/数字/钞票/票据/logo/人脸 —— 数字交给图表)+ **可选 `image_prompt_2:`**(第二张不同场景;**每篇 ≤2 张**,配额逐张计)。
- **「✦ EUREKA MOMENT」段 + 1–2 图**:`run_report`(render 后、persist 前)发 `image` 阶段 → `_build_report_image`(≤2 张,逐张配额闸 → 生成 → 落 `files`)→ `_moment_section` 把图包进 **`<section class="r-moment">`(`✦ EUREKA MOMENT` 字标 + `.r-moment-imgs` grid:1 张全宽 / 2 张并排)** → `insert_report_image` 放**首个 `<h2 class="r-h2">` 之前**(intro/图表之后)→ 连图一起 persist。**同步**(报告一打开就有图);失败/超额 → 无图、报告完整。`asset://<id>` 回写 `content_md` 作 provenance;`rerender`(换装)抽**整个 `<section class="r-moment">`** 重新插入(不重生成)。render 含 `.r-moment`/`.r-ai-img` CSS。
- **高级动效层(GSAP · `_ENHANCE_JS`)**:图片有两层运动 —— **ken-burns**(缓慢电影感 zoom + drift,`scale 1.05→1.12` + xy 微移,11s 无限 yoyo,进视才启,`.r-ai-img` `overflow:hidden` 裁切在圆角内)+ **scroll 视差**(`ScrollTrigger` scrub,图随滚动上下漂移做景深)。`.r-ai-img` 加 `will-change:transform`。**ScrollTrigger 3.12.5** 随 gsap 一起 bundle(`mobile/assets/js/ScrollTrigger.min.js`,viewer `_withEngines` 在 gsap 后注入 + `gsap.registerPlugin`;导出 .html 也自带)。渐进增强:无 ScrollTrigger → 只 ken-burns;无 gsap / reduced-motion → 静态图,报告完整。
- **表现力 SVG + GSAP 动效层**:draw-on + count-up + scroll-trigger,无 AI 成本,见 §6.6 / `report_render._ENHANCE_JS`。
- **图片 provider 配置(与文字主 key 隔离)**:`.env` 的 `IMAGE_API_KEY` + `IMAGE_MODEL` → `docker-compose.yml` → `config.settings` → `report_image._image_api_key()/_image_model()`。`generate_image` 按 model/key **自动路由**:`doubao*` / `seedream` / `ark-…` → **Ark 适配器**(`_generate_ark`);其它 → gemini-via-litellm 路。未配可用 provider 时全路径退化为「无图、报告完整」。
  - ⚠️ **改 `.env` 后必须 `docker compose up -d backend`(重建容器)才生效;`docker restart` 只重启、**不重读 .env / 不重做 compose 插值**,env 仍是旧的。
- **出图 provider:豆包 Seedream(已接入并启用 · 默认)**:`_generate_ark` 直 POST `https://ark.cn-beijing.volces.com/api/v3/images/generations`(`response_format=b64_json` 避开 Ark url ~24h 过期 → 落**永久 data:URI**;**`size=2K`** —— Seedream-4-5 只收 `2K`/`4K` 预设,`1K`/显式小尺寸均 400;`watermark=false`;mime 按 base64 magic 嗅探,Seedream 返 JPEG ~0.5–0.9MB)。**已配置 + 实测出图,部署生效**。存储位宽:`files.storage_url`(迁移 `0015`)+ **`reports.html`(迁移 `0016`)** 均 `TEXT`→`MEDIUMTEXT`(报告 html **内联**那张 base64 图 → 否则 64KB 截断、figure 静默丢失)。**配置**:`IMAGE_API_KEY=ark-…` + `IMAGE_MODEL=doubao-seedream-4-5-251128`。
  - 备选(同一套配置槽,改 `IMAGE_MODEL`/key 即可):干净账号 OpenRouter key、直连 Google AI Studio(`IMAGE_MODEL=gemini/gemini-2.5-flash-image-preview`)。`OPENROUTER_API_KEY` 主账号被 Google 整账号 TOS 封(gemini-image/2.5、claude、gpt 全 403,见 `core/llm.py`),故默认走豆包。
- **模式 B(场景 backdrop)**:未实现(`backdrop_prompt` + 双层合体)。注:模式 A 改同步出图后,前端不再需要「正在配图…→ pop in」轮询(图随报告一起到);`spec.image_pending` 已废弃。

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
| `spec_json` | `{time_range, asset_types, keywords, domain, source_asset_ids, surface, palette, seed}`(可重跑) |
| `pet_gene`（✅ 已实现 · 迁移 0013 · §6.12 批 3） | 生成时的 REKA gene 快照(署名带用,§6.6.1;日后换装老报告仍是当时那只) |
| `tokens_used` / `gen_ms`（✅ 已实现 · 迁移 0012 · §6.12 批 0） | 本篇全管线累计 token(`run_agent.usage_tokens` 求和,dispatcher+content[+image])+ 生成耗时(`perf_counter` start→persist)。`_meta` 透出。**= §12.5 用量日志的一部分,一举两用(成本遥测 + 展示)** |
| `suggested_actions`（✅ 2026-06 · §6.13） | 从 `:::actions` 抽出的**可执行下一步**结构化列表 `[{title, kind?(todo\|event), due?}]`;前端据此显「✦ 接下来」+ 一键沉淀成待办 |
| `created_at` | |

> **展示口径(Q3 建议)**:`gen_ms` **可对用户露**(暖透明:「REKA 用了 8 秒为你整理」);`tokens_used` **留 admin/遥测**(用户不以 token 思考、配额下露 token 反增焦虑)。要露 token 就放一行不抢眼的可选 meta,别突出。

**生命周期:**
- **数据量门槛(已实现)**:**自动/一句话路径**(非手动选)取数后,若相关记录 `< _MIN_RECORDS`(=3)→
  **不生成**,经 SSE 发 `insufficient` 事件、前端提示「数据太少,先多记几条」。省掉一次内容 LLM + 一条空报告。
  **手动 hand-pick 路径不设门槛**(显式选择即尊重)。
- **生成**:管线产 md+html → `POST /api/reports`(SSE 进度:`status`→`report`→`done`)。
- **回看**:报告容器列表 → 点开 → WebView 看 `html`。
- **重渲染(换装)**:用 `content_md` + 改 seed/palette/surface → 重跑 render → 覆盖/另存 `html`。
  因为 substance 已固化在 md,**不重查数据、不重思考**。
- **分享(beta 先轻)**:导出 `.html` / 渲染成图 / 系统分享。核心先保证 存储 + 回看 + 重渲染。
- **删除**:`DELETE /api/reports/:id`。

---

## 6.8 前端表面（Flutter）

> 详细 UI 规范并入本节(本章是 feature 真值);[§4](04-frontend.md) 只放指针。

### 6.8.0 入口策略（**唯一入口,已拍板**）

报告是**重功能**,触发逻辑独立、引导逻辑独立 —— **跟 AddSkillWizard 一样,是一个自带向导的独立入口**。

- ✅ **唯一入口** = 资产库「报告」容器的「✨ 总结 · 升华」按钮 → 开 report 向导(`ReportCreatePage`,走独立的 `/api/reports/intake` + `/api/reports/generate`,**非 chat 会话**)。
- ❌ **Chat 不产报告**。用户在普通 chat 里说「帮我总结/复盘/出个报告」→ **不**在 chat 里生成,只回一句
  **兜底指路**:「想要一份图文报告的话,去资产库的『报告』点 ✨总结」。(简单的事实查询如「我这个月花了多少」
  仍是 QUERY,照常文字+卡片回答 —— 兜底只针对「要一份报告产物」的诉求。)
- ❌ **Flash 不产报告**。合成/报告类闪念 → 同样只给兜底指路,不生成。
- 🗑 **老的 chat SUMMARY 逻辑(LLM 手写 HTML → `tool_render_report`)完全弃用**:删除该意图、删除
  `tool_render_report` MCP 工具与 `render_report` 实现、删除 chat.py 的 report-pair 管线、删除 mobile 端
  已失效的 `_ReportReceipt`/`_ReportSheet`/HTML-salvage。报告 HTML 一律由本章 ③ render skill 确定性产出
  (catalog × seed,反 slop),不再由对话模型即兴写。

> 为什么不让 chat/flash 直接发起:报告是交互重、全屏、可重渲染的一级产物,塞进对话流/捕获 sheet 是错的
> modality;独立向导能专注做「选资产 → 定体裁 → 产报告」的引导,体验和职责都更干净。

### 6.8.1 入口与流程

1. **入口**:资产库「报告」容器头部 + 一个显眼的「✨ 总结 · 升华」按钮 → 开 `ReportCreatePage` 向导
   (**独立端点**:`/api/reports/intake` 逐步引导 + `/api/reports/generate` SSE 生成;**不是 chat 会话、无 `session_type='report'`**)。
2. **引导对话**:report 向导既能**一句话直给**(「帮我总结最近一个月消费」)也能**逐步引导**(问时间范围/
   资产类型/体裁,可交叉)。对话里始终提供一个 **「手动选择资产」** 的 affordance。
3. **资产选择器**(手动路径):全屏多选页,顶部**类型筛选 tab**(全部 / 待办 / 记账 / 灵感 / 笔记 / 事件 /
   名片 / 各自定义 skill),**外加一行「按生活领域」筛选 chip**(8 选 1,§8.3 配色;走 `GET /api/assets?domain=`),
   两层筛选可叠加。列表项带 checkbox;勾选 → 「用选中的 N 条总结」→ 选中 ids 回填进会话,
   管线从 `source_asset_ids` 直接进 ② content skill。这一行让「总结我所有娱乐事项」的手动路径与对话路径(§6.2 `domain`)对齐。
4. **报告容器**(📊,资产库常驻):报告列表(标题 + genre + 时间范围 + created_at),点开 → 查看器。
5. **查看器**:全屏 = 顶栏(标题 / 返回 / 分享 / 重渲染) + WebView(`html`)。重渲染 → 走 §6.7 换装。

---

## 6.9 v1 范围与里程碑

- **v1 必做(已实现)**:4 个 genre;md 注解语法;render 4 surface × 4 palette;reports CRUD + 容器 + 查看器;
  **引导对话**(`report-intake`,最多问 1-2 句澄清后放行)+ 资产选择器;**数据量门槛**(自动路径 < 3 条不生成)。
- **已补全(原 v1 可后置,现已实现)**:**分享导出**(WebView 顶栏「分享」→ 导出 `.html` 到系统分享,`share_plus`)、
  **重渲染换装**(顶栏「🎨 换装」→ `POST /api/reports/{id}/rerender` 用 `content_md` 换 seed/palette,瞬时重渲不重查)。
- **入场动效(已实现)**:**GSAP 本地打包 + 查看器注入**(timeline 错峰淡入 + 柱状生长 + 环形淡入),
  无 gsap 时 vanilla 兜底;静态优先、尊重 reduced-motion。
- **仍后置**:GSAP **ScrollTrigger** 级滚动揭示(已打包 GSAP core,加插件即可)、`asset://` 图文卡(用户图片资产少)。
- **质量门**:render 输出在 393px 实测视觉基线(数据复盘 = eyebrow + KPI 墙 + SVG donut/bar + 明细 + callout);
  反 slop 约束在 `report_render.py`。

---

## 6.10 落点（实现版）

| 文件 | 角色 |
|---|---|
| `backend/skills/report-dispatcher/SKILL.md` | ① 体裁分类(LLM,无工具) |
| `backend/skills/report-data-report/SKILL.md` 等 ×4 | ② 各 genre 内容 skill(LLM,**无工具**;data 由管线注入 → 产注解 md) |
| `backend/skills/report-intake/SKILL.md` | 引导对话 gate:够明确放行 / 太笼统问一句(§6.8.2) |
| `backend/agents/report_render.py` | ③ **确定性 Python** renderer:注解 md → 单文件 HTML;4 palette × 4 surface + SVG 图表 + block 套件 + 反 slop + GSAP 守卫脚本 + masthead eyebrow;支持 palette/surface/seed 覆盖(换装) |
| `backend/agents/report_pipeline.py` | 编排 ①→预取(注入 skill 字典 + 模糊解析)→数据量门槛→②→③→落库;`run_intake`(引导)、`on_phase`(进度) |
| `backend/agents/skill_factory.py` | `make_report_dispatcher_agent` / `make_report_content_agent` / `make_report_intake_agent` |
| `backend/api/reports.py` | `/api/reports` CRUD + `generate`(SSE,含 `insufficient`)+ `intake`(引导)+ `{id}/rerender`(换装) |
| `backend/db/models.py` `Report` + `0006_reports` 迁移 | `reports` 表(§6.7) |
| `mobile/lib/pages/report_list_page.dart` | 报告列表 + ✨总结 CTA;创建入口汇入 REKA 流(诉求输入 + 资产选择 + SSE 进度)。原向导页 `report_create_page.dart` 已删(create/edit 统一到 `AssetEditPage`) |
| `mobile/lib/pet/reka_chat.dart`(内联 `_AssetPickerModal`) | 报告资产选择器:REKA 洞察气泡内的多选器。原全屏 `report_asset_picker_page.dart` 已删 |
| `mobile/lib/pages/report_viewer_page.dart` | WebView 查看器(锁死导航;JS 开,**GSAP 已注入** —— rootBundle 取 `assets/js/gsap.min.js` splice 进 `<head>`) |
| `mobile/lib/pages/library_page.dart` | 资产库「报告」区:✨总结 CTA + 报告列表 |

> ① dispatcher 的逐字 prompt 与 ② 各 genre 的结构进 [§99 附录](99-prompts-appendix.md) 的范畴;
> ③ render 不是 prompt(确定性代码),catalog/约束在 `report_render.py` 内。

---

## 6.11 微点评（insight · 轻量解读层 · **已转 pending / 后置**）

> **状态(2026-06 改)**:**本节整体 pending,先不做。** 「agent 对单条记录的简要分析」这个需求,**改由「资产锚定会话的开场 hint」承载**(见 [§1.5.1](01-agent-architecture.md))——
> 点评不再写进卡片,而是在用户**主动就该资产发起讨论**时作为**开场白 + 起聊建议**出现。好处:捕捉零成本、只在用户想聊时才生成、且自然引向对话而非死批注。
> 本节以下设计**保留作参考**:其「通用 insight agent + grounded 纪律」正是 hint 的 **L2(LLM 富化)** 层(§1.5.1),将来富化 hint 时复用;「卡片内展示 / 异步填充」那套**不再采用**。
>
> **需求(原始)**:产品以记录为主、异步发生(硬件即时记、后续查看)。用户**后续查看**一条自定义记录时,可能想看到 agent 对它的**简要分析 / 点评**。
> 这是介于「捕捉」与「报告」之间的第三档 agent 输出。

### 6.11.0 三档高度（定位）

| 档 | 做什么 | 何时 | 重量 | 住哪 |
|---|---|---|---|---|
| **① 捕捉**（[§1](01-agent-architecture.md) flash/chat） | grounded 抽取 → 卡片 | 即时、同步 | 轻、**绝不发明** | 各 sub-skill |
| **② 微点评（本节）** | 对**单条记录 + 近期同类/同域上下文**产 **1-2 句** grounded 点评,**长在卡片里** | 开→异步补进卡片 / 关→pull(均不挡捕捉) | 一次短调用 | **独立 insight agent** |
| **③ 报告**（§6.1-6.8） | 多资产合成 → 体裁报告 | on-demand、引导 | 重 | report 管线 |

### 6.11.1 铁律一：不进 skill 层（回答「会不会加重 skill 负担」）

- **绝不放进捕捉 sub-skill 的 CREATE 路径**:① 会拖慢「录了就走」的唯一快路(加一次 LLM + 延迟 + 失败面);② 把「抽取(绝不发明)」和「解读(要推断)」两种高度塞进同一个 SKILL.md,prompt 变重、grounded 纪律被污染。**捕捉是捕捉,点评是点评,分两个时刻。**
- **一个通用 insight agent,不是 per-skill 分析 prompt**(`backend/agents/insight.py`,设计中):读 目标 asset 的 `payload` + `domain` + **该 skill 的 `render_spec`/schema**(理解字段语义)+ 一小片**近期同 skill / 同 domain 记录**(给趋势/连续/对比上下文)→ 产一句 grounded 点评。技能只贡献它**本就有的 schema**,**零新增 prompt 逻辑** → skill 负担不增。
- **grounded 纪律(继承 §6)**:只点评**查到的真实数据**(趋势、计数、连续、对比),**绝不发明**;**温柔**——不训诫、不制造愧疚、不冒充医疗/理财权威。**≤2 句**。

### 6.11.2 铁律二：开关控「自动/手动」，展示一律在卡片（回答「做一个开关」）

开关决定**要不要自动生成**;**展示位置始终是卡片**(§6.11.3),不随开关变。

- **开关 ON = 自动(push)**:记录落库后**异步**生成点评(在捕捉关键路径**之外**跑,不拖慢捕捉)→ 写 `assets.insight` → 卡片自更新出点评行。粒度:
  - **per-skill 开关**(记账/跑步/读书 值得点评、随手随记不必)—— **只是 skill 上一个布尔位,决定"要不要叫 insight agent",不是把分析逻辑塞进 skill** → 不加重 skill。
  - 加一个**全局总开关**(点评 on/off,一键全关)。
- **开关 OFF = 手动(pull 兜底)**:不自动生成;卡片/详情留一个轻「✨ 点评」入口,点一下才生成那一条。**不点不花钱**。
- **缓存**:点评存 `assets.insight`(命中即不重复计费);可手动刷新 / 数据显著变化时失效。
- **可选 REKA 口吻**:点评文案可由球球口吻写(「球球翻了翻你的记录,发现…」),把它接进 engagement 层而非冷冰冰的批注。**但仍只是卡片里那一行,不是 session 气泡。**

### 6.11.3 展示面：insight 长在「卡片」里（已定）

**决策:insight 不单独成一条 session 消息/气泡,而是作为卡片本身的一个槽。** 卡片 = 资产的渲染,资产带 `insight` → **卡片到哪,点评跟到哪**(闪念 session / 资产详情 / 分类列表 / 时间线),**一条渲染路径、零 per-surface 逻辑**。

- **卡片即时、点评异步补、卡片自更新**:
  1. flash 同步响应**只回卡片**(§3.2 同步 JSON,捕捉必须快;insight 不进同步响应)。
  2. 若该记录的 `insights` 为开 → flash **异步**起一个 insight job(复用已有 `has_pending`/通知机制),写 `assets.insight`。
  3. 客户端 `dataRevision`/轮询刷新 → **同一张卡**重渲染,底部多出一条 **点评行**(`SkillCard` 读 `asset.insight`,有则渲染)。从「✨ 思考中…」占位 → 落定为点评。
- **`insights` 开 → 卡片带点评行;关 → 不起 job、卡片就是纯卡片。** 这就是开关语义 —— 不在 session 里加任何东西,只让卡片多/少一行。
- **是卡片组件的通用槽,不是 per-skill render_spec**:`SkillCard` 统一加一个可选 insight 区(读 `asset.insight`)→ 不动各 skill 的 render_spec、不加重 skill。
- **gating(温柔、省钱)**:**per-skill 开关**决定哪类记录的卡片长点评(记账/跑步/读书 → 长;事件/随手随记 → 不长)。所以一条出 3 张卡的闪念,通常只有该长的那张带点评行,天然不炸屏。
- **详情页同理**:`AssetDetailDrawer` 也读同一个 `asset.insight` 显示;未生成且想要 → 一个「✨ 点评」按钮按需触发(pull 兜底,主要给开关关闭时的单条手动点评)。

> 一句话:**点评是卡片的一行,不是 session 的一条消息。卡片先到、点评异步补进卡片;开关只决定卡片有没有这一行。**

### 6.11.4 落点（设计中,实现时细化）

- **数据**([§2](02-data-model.md)):`assets.insight`(Text, nullable, 缓存)+ `assets.insight_at`。per-skill 开关 = `user_skills.insight_enabled`(0/1);全局开关 = 用户设置。点评是 `asset` 的字段 → **随 `GET /api/assets` / flash `cards` 一起出**,卡片直接读。
- **API**([§3](03-api-reference.md)):`POST /api/assets/{id}/insight`(手动生成或返缓存,`?refresh=` 强刷,供开关关闭时的 pull)。设置端点带全局/技能开关。
- **flash 管线**([§1](01-agent-architecture.md)/§3.2):建好 asset 后,若该 skill `insight_enabled` → **异步**起 insight job(复用 `has_pending`/通知,**不进同步响应**),完成写 `assets.insight`。
- **前端**([§4](04-frontend.md)):**`SkillCard` 加一个可选 insight 区**(读 `asset.insight`,有则渲染一行;生成中显「✨ 思考中…」占位)—— 这是**唯一展示点**,卡片在哪点评在哪。`AssetDetailDrawer` 同读该字段 + 开关关时的「✨ 点评」pull 按钮。设置页全局开关;技能管理页 per-skill 开关。
- **agent**([§1](01-agent-architecture.md)):`agents/insight.py` 单次结构化调用,复用 §6 的「先 query 真实数据」预取 + grounded 纪律。

### 6.11.5 v1 范围

- **v1**:**卡片内 insight 行**(`SkillCard` 槽,读 `assets.insight`)+ 开关 ON 时 flash 异步填充(复用 `has_pending`/通知)+ 开关 OFF 时详情 pull 兜底;通用 insight agent;grounded+温柔护栏;≤2 句;`assets.insight` 缓存。
- **后置**:全局/per-skill 开关 UI 全量打磨、REKA 口吻文案、点评进 REKA 通知 feed、跨记录的「近期观察」聚合点评、数据显著变化时自动失效重算。

---

## 6.12 报告升级 · 实现

报告升级(§6.3.1 内容质量 · §6.6.1 REKA 署名 · §6.6.2 AI 配图+动效图 · §6.7 token/time)分 5 批落地,前批不依赖后批、各自独立上线。

| 批 | 内容 | 状态 |
|---|---|---|
| **0 · 用量遥测** | 每次 LLM 调用记 `response.usage` + 计时;`reports.tokens_used`/`gen_ms` 落库(§6.7 / §12.5) | 已落地 |
| **1 · 内容质量** | 按 §6.3.1 七条 + #8「落地于方向」重写 `report-*/SKILL.md`;dispatcher genre 选择(定性→idea-synthesis)+ 主题命中数 insufficient gate(§6.2) | 已落地 |
| **2 · 表现力动效图(无 AI)** | `report_render.py` 的 SVG 图注入 GSAP draw-on(柱/环/线)+ KPI count-up + scroll-trigger;渐进增强 + reduced-motion | 已落地 |
| **3 · Reka Insights 署名带(§6.6.1)** | footer 模板 + 注入 `pixel/mascot.js` + pipeline 传 pet gene → `reports.pet_gene` 快照;导出自包含 | 已落地 |
| **4 · AI 配图(§6.6.2)** | content skill 产 `image_prompt`(模式A);**同步**出图 step → hero 位内联 + `files`/`asset://`;house-style 常量;每篇 ≤1 张 + 每用户/月配额;绝不画数据 | 模式 A 全链路落地;豆包 Seedream 已接入启用 |
| **5 · 报告 → 待办(§6.13)** | content skill 产 `:::actions`;pipeline 抽 `reports.suggested_actions`;查看器原生「✦ 接下来」行动条 + `+ 待办`/`全部` 一键建 + `source_report_id` 溯源 + 防重 | **✅ 已实现(2026-06,handoff Phase 1)** |

**各批实现要点:**
- **批 0**:`reports.tokens_used` / `gen_ms`(迁移 `0012`)+ `run_report` 用 `core.agent_runner.run_agent` 累加 `usage_tokens`、`time.perf_counter` 计 `gen_ms`,落库 + `_meta` 透出。
- **批 1**:`report-*/SKILL.md` 按 §6.3.1 重写 —— `idea-synthesis` 收敛到「方向」(有理由的方向 + 第一步,至多 1 问,#8,非 3 开放问);`data-report` KPI/图表「有量化故事才产」+ 去原文回显;digest/proposal 加「解读>描述 / 不回显 / REKA 声音」;dispatcher 加「定性数据→idea-synthesis」。主题命中数 insufficient gate(§6.2 `keywords`)。
- **批 2**:`report_render._ENHANCE_JS` —— 每个 `.r-block` 用 IntersectionObserver 滚动进视揭示;图表画上去(柱 `scaleY` 生长、环 `stroke-dasharray` 扫入、线 `stroke-dash` draw-on、KPI count-up)。`window.gsap` 在→GSAP 缓动,不在(导出 .html)→ vanilla 兜底。静态优先 + `try/catch` 恢复全可见 + 尊重 `prefers-reduced-motion`。GSAP 由查看器注入(`assets/js/gsap.min.js`→`<head>`)。
- **批 3**:`reports.pet_gene`(迁移 `0013`)+ `run_report._fetch_pet_gene`(mascot.js `opts` 形)嵌进 HTML + 落库快照。`report_render` footer 署名带(`<footer class="r-sign">` + `#reka-sign-pet` + 「Reka Insights」字标 + tagline);`_REKA_SIGN_JS` 在 `window.Mascot` 在时挂载 REKA。`report_viewer_page._withEngines` 注入 `pixel/mascot.js`,导出 .html 内联引擎+gene 自包含;rerender 复用 `pet_gene`。渐进增强:字标纯 CSS 常显,无 pet 也不空白。
- **批 4**:见 §6.6.2 —— 模式 A 全链路落地(`report_image.py` + `run_report` **同步** `_build_report_image` + `insert_report_image` hero 位 + 配额 + frontmatter + `.r-ai-img` CSS),成功/失败/超额三分支均验证、报告恒完整;出图豆包 Seedream 已接入启用。**KPI 卡片数字不换行**:`_split_kpi_value` 把括号后缀(「¥999(服装)」)拆到小字副行;`_kpi_font_px(max_len, n)` 按**整行最长值 + 列数**算一个**统一字号**(内联到 `.r-kpi-n`)+ `white-space:nowrap` —— 长值(如「¥1,445」4 列)整行一起缩到合适字号、**绝不**断成「¥1,44/5」(原 `clamp` + `overflow-wrap:anywhere` 反而允许数字中间断行,已废弃)。

**不在本轮**:Free/Pro 付费墙与计费([§12](12-business-model.md);批 4 只做配额计数 + 硬上限,不接 billing)、模式 B 场景 backdrop、[§10](10-game-config.md)/[§11](11-admin.md) admin·game-config、§6.11 卡片微点评。

**prompt 成稿**:idea-synthesis / data-report / dispatcher / house-style 的成稿在 [`handoff-report-prompts-v2.md`](handoff-report-prompts-v2.md);[§99 prompts](99-prompts-appendix.md) 为 spec 交付物。
- **基建 / 渲染 / 集成 = coding agent**(用量日志、GSAP 动效、署名带 render+注入+gene 管线、Nano Banana 集成、`files`/异步/配额/导出 plumbing)。

---

## 6.13 报告 → 待办：可执行下一步沉淀（✅ 已实现 2026-06）

> **缺口**:报告(尤其 idea-synthesis 的「方向」、proposal 的「下一步」、data-report 的具体「建议」)会给出**可执行的下一步**,但它们**烂在 WebView 里** —— 用户没法把「先做语音捕捉收件箱」一键变成自己能管理的待办。**洞察 → 行动**这条闭环没合上。本节合上它。

**1. 内容契约(content skill)**:产出可执行下一步的 genre,把它们**额外**写成一个 **`:::actions`** 指令块(§6.4),每行一条**具体、可勾**的动作:
- `idea-synthesis`:「方向」里的第一步 → `:::actions`;`proposal`:「下一步」→ `:::actions`;`data-report`:**具体**建议(「工作日午餐定 ¥25 的线」)→ `:::actions`;`digest` 通常无。
- 动作必须**grounded、具体**(承 §6.3.1 #4/#8) —— 不是「多记录」这种通用废话。

**2. 数据(pipeline)**:从 `content_md` 的 `:::actions` 抽出 → `reports.suggested_actions: [{title, kind?(todo|event), due?}]`(§6.7)。默认 `kind=todo`;含明确时间的可标 `event`。

**3. 展示 = HTML 里读 + 原生里做(两层,关键)**:
- **报告 HTML**:`:::actions` 渲染成「✦ 接下来」勾选样式段 —— **随报告一起读、一起分享**(分享出去也带着「该怎么做」)。
- **Flutter 查看器(`report_viewer_page`)**:读 `suggested_actions` → 在 WebView **下方**渲染一条**原生**「✦ 接下来」行动条:每条一个 **`+ 待办`** 按钮 + 顶部一个 **`全部加到待办`**。**走原生、不在 WebView 里塞按钮**(免 JS↔Flutter bridge,稳)。

**4. 沉淀 = 复用既有 create**:点 `+ 待办` → 调 `tool_create_todo` / `POST /api/assets`(skill=todo)建一条待办,`content=该 action title`。**v1 一键直建**(详情里可改);toast「已加到待办」。这与 chat 的「沉淀为资产」(§4.2.4)同族。

**5. 溯源(provenance)**:建出的待办带 `source_report_id`(+ 报告标题)→ 待办详情可显「来自报告《X》」、点回报告。让「洞察→行动」可追溯、不断链。

**6. 防重**:同一报告同一 action 已建过 → 按钮转「已加 ✓」(按 `source_report_id`+title 去重),不重复建。

- **v1 范围**:`:::actions` 抽取 + `suggested_actions` 字段 + 原生行动条 + `+ 待办`/`全部` 一键建 + 溯源 + 防重。**todo 单类型。**
- **后置**:`+ 日程`(time-bound → event)、点 `+` 先开预填编辑表单(`AssetEditPage`,改完再存)、沉淀成别的技能类型(读书感想→notes…)、「这条已完成」回写报告。

> **落地(✅ 2026-06)**:prompt — `report-{idea-synthesis,proposal,briefing}/SKILL.md` 产 `:::actions`;渲染 — 新旧两条
> render 路径都渲「✦ 接下来」勾选样式;pipeline — `_extract_actions` 抽 `reports.suggested_actions`(迁移 0018,
> POST `/api/reports` 外部写入路径同样抽取);API — `GET/POST /api/reports/{id}/actions`(GET 带 created 防重状态;
> POST 服务端幂等建 todo,写 `assets.source_report_id` 列 + payload `source_report_title`);前端 —
> `report_viewer_page` WebView 下方原生行动条(`+ 待办`/`全部加到待办`/`已加 ✓` + toast),`asset_detail_sheet`
> 待办详情显「来自报告《X》· 查看报告」(点开原报告)。**v1 todo 单类型**;`+ 日程`/预填表单仍后置。

---

## 6.14 测验 / 记忆卡（quiz / flashcard genre · ✅ v1 已实现 2026-06）

> **落地(v1)**:`report-quiz` / `report-flashcard` content skill(照 handoff-report-prompts-v2 ⑤ 成稿接线)+
> dispatcher 学习类 gate(⑤c,七种体裁);`report_render` 新增 **`:::quiz`/`:::flashcards` 交互模板**(§6 首个
> 交互渲染:翻卡+会了/还不熟自评+计数;选项→判定→计分→进度→结果页+「再来一遍」重做;vanilla JS 渐进增强,
> 无 JS 时题/答静态可读,JSON 坏块降级为可读 pre);genre 落 `reports`(🎯/🃏 进容器、可回看重做);
> **§14 周测 offer**:学习 domain 7 天 ≥8 条(排除 todo/event/expense/contact)→「📝 要不要考考你?」→
> 一键即做出 quiz(复用积累 offer 流,零新触发)。实测:真实单词笔记 → 测验接地(只考记过的、干扰项同类)。
> **选材稳定性(2026-06 补)**:没有专属单词技能时 dispatcher 只能猜话题词,猜偏 = 假「数据不足」(实测 1/3
> 成功率)。修复双保险:dispatcher gate 明示 quiz/flashcard **默认 `domain:"学习"`、禁猜 keywords**(§6.14
> 主信号);管线再加**确定性兜底** —— 选材不足时自动改按学习域重取(剔除 todo/event/expense/contact),
> 二者取多。复测同一 wish 3/3 稳定成功。
> **v1 后置**:SRS 间隔重复、外部增强、per-card 成绩(见 handoff-quiz.md Phase 2)。

> **定位**:把**学习类记录**(单词 / 读书笔记 / 学习笔记)变成**可交互的测验或记忆卡** —— 从「记下来」补上「记得住」。学生党(§14 目标人群)的核心场景:每天记新词 + 学习笔记,**一周出一份 quiz 考考自己**。
> **它是 §6 第一个「交互式」genre**(其余只读)。**靠 §6.6 已有的 WebView+JS** 实现交互 —— 这正是「render 开 JS」(§6.0 #2)那个决定为之准备的用途,**是 render 模板新增,不是新基建**。

**1. genre + 两模式(同源内容,两种呈现):**
- **`flashcard`**:正反面、自评翻卡(「会了 / 还不熟」)。最简,直接从记录派生(单词→他记的释义)。
- **`quiz`**:题目 + 答案 + **计分**(MC 自动判 / 填空)。更丰,需 content skill 生成**合理干扰项**(干扰项质量 = 测验质量的关键杠杆)。

**2. 内容契约(新 content skill,结构化指令块):**
- `:::flashcards` 块:每行 `正面 :: 背面`(`apple :: 苹果,水果`)。
- `:::quiz` 块:每题 fenced JSON `{q, options[], answer, explain?}`(MC),或填空/简答。
- **接地铁律(承 §6.3)**:题目/答案**只来自用户记录** —— 测他记的词、用他记的释义,**绝不发明**他没记过的内容。MC 干扰项可由 LLM 生成,但须**合理**(同类、不送分)。

**3. 选材 gate —— 可测 = 知识/记忆型,不是要做的/生成的(承 §6.2 + §8 domain)**:
- **可测**:**学习类知识内容**(单词 / 读书笔记 / 学习笔记 / 语言学习)。**主信号 = §8「学习」domain**(零新字段;可测内容天然落学习域);可选后置 per-skill `quizzable` flag(design-agent 打)。
- **不可测(各有去处)**:**灵感**=生成型 → `idea-synthesis`(你发展它、不背它);**代办**=行动型 → Type A 提醒;**记账/事件**=交易/日程 → data-report/提醒。即使沾「学习」也排除 `todo`/`event`/`expense`/`contact`(如"复习数学"是待办、不是知识)。
- **两段制**:gate 廉价触发(学习域知识积累)→ content skill 是最终质量闸(出不了像样 Q&A 就如实「内容还不够」)。手动「考考我」永远可用。

**4. 交互渲染(新 render surface)**:`flashcard` = 翻卡动画(GSAP);`quiz` = 选项 → 判定 → 计分 → 进度条 → 结果。复用 §6.6 受控 WebView 的 JS(渐进增强:无 JS 也能把题/答当静态读)。落 `reports` 容器 → **回溯**(过去的测验可重做)。渲染皮可走 design(`/design-shotgun`→`/design-html`)。

**5. §14 钩子(主动周测)**:**积累触发**([§14.3](14-proactive-reka.md) 阈值型)→ Type B offer「这周记了 20 个新词,要不要考考你?」→ 生成 quiz。用户那个「一周一考」正是此路,**复用 §14 已有的 offer 流,零新触发逻辑**。

**6. REKA 主持(可选,接 §9)**:REKA 出题、对错有反应、得分庆祝 —— 把测验做成 game-y 的陪伴体验,贴本人群。

- **v1**:`flashcard`(自评)+ 简单 MC `quiz`;**接地于用户内容**;手动(「考考我」)+ §14 周测 offer;落报告容器。
- **后置(大)**:**间隔重复 SRS**(记错题、按遗忘曲线让「上次没记住的再过一遍」,天然接 §14 主动 —— REKA 周期性复盘)、外部增强(标准释义/用法,接 [§14.9 web-search](14-proactive-reka.md) + 接地墙)、成绩追踪。

> **落点(✅ 全部已落,2026-06)**:`report-quiz` / `report-flashcard` content skill + dispatcher 学习类 gate + `report_render` 的 `:::quiz`/`:::flashcards` 交互模板(JS)+ genre 落 `reports` + §14 阈值型 quiz offer。**handoff(已 ✅)见 [`handoff-quiz.md`](handoff-quiz.md)。**
