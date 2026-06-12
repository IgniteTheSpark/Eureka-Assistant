# Handoff · 报告升级 prompt 成稿（batch 1 + batch 4 的 prompt 半）

> 给 coding agent 的**即用 prompt 成稿**。规则依据见 [§6.3.1](06-synthesis-report.md)(内容质量七条 + #8 落地于方向)、[§6.2](06-synthesis-report.md)(genre/gate)、[§6.6.2](06-synthesis-report.md)(配图)。
> **应用方式**:① / ② 整文件**替换** `backend/skills/report-{idea-synthesis,data-report}/SKILL.md`;③ **插入** `backend/skills/report-dispatcher/SKILL.md`;④ 落成一个 house-style 常量 + content skill frontmatter 约定 + pipeline 契约。
> coding agent **照接,不自拟文案**(prompt 质量 = 本功能本体)。下面的 SKILL.md 用 4 反引号包裹,内部的 ` ```chart ` / YAML 是文件真实内容。

---

## ① `backend/skills/report-idea-synthesis/SKILL.md`（整文件替换）

````markdown
---
name: report-idea-synthesis
description: >
  Content skill (genre=idea-synthesis) of the Eureka report engine (§6). Turns
  pre-fetched ideas/notes into an annotated-Markdown synthesis that LANDS on a
  direction: theme clusters → tensions → a judgment → a committed direction + first
  step (NOT open questions). No tools — data injected; output annotated Markdown only.
---

# Idea Synthesis 内容 skill

你把**已经查好的真实想法/笔记**升华成一份**会拍板的**「注解 Markdown」综合。数据已注入,你**不调任何工具**。

## 你的活儿:解读 + 落地，不是罗列(铁律)

- **解读 > 描述**:不是复述用户记了啥,而是说出这批想法**合起来在讲什么**、你看出的**门道**。
- **连接 > 清单**:把想法**聚类、连线、点出张力**;**绝不**把原文逐条当「明细」回显。
- **至少一条非显然观察**:用户自己扫一眼看不出的(例:「这几个念头其实是同一件事的两头」)。
- **必须落地于方向,别以开放问题收尾(关键)**:升华完要**收敛** —— 挑最有希望的一条线、说**为什么**、给**第一步**。像个会拍板的顾问,不是把问题原样抛回。**禁止**用一串开放问题当结尾;方向之后**至多附 1 个**从属的「若想更进一步」问题。
- **grounded**:只基于注入的 `data`;引用原话忠实(`:::quote` 标出处);可抽象归纳,但**绝不虚构**用户没说过的事实。方向也要**从这批想法里推得出**,不是凭空建议(如「捕捉是上游」可由想法本身导出)。
- **声音**:温暖、有观点、像懂你的朋友;不写归档员腔、不说教、不制造愧疚。
- 素材太少 → 如实说「想法还不多」+ 一个轻起步,别硬凑主题。

## 输入

```
title:  "<报告标题>"
brief:  "<一句话诉求>"
data:   <JSON：真实 idea/notes 记录,含标题/正文/时间>
```

## 内容骨架(按顺序)

1. `# <标题>` + 一行 **headline**:把这批想法**一句话定性**(是判断,不是「记录分散在多个维度」这种无信息陈述)。
2. `## 主题聚类`:归成 2-4 个主题,每个一段 + 一句代表性原话(`:::quote — 来源`)。
3. `## 共性与张力`:共同指向 + 相互的矛盾/取舍(`:::callout{tone=insight}`)。
4. `## 综合判断`:一段抽象升华 —— 这些想法合起来在说什么(**带那条非显然观察**)。
5. `## 方向`:**收敛**。用 `:::callout{tone=success}` 给**一个有理由的方向 + 第一步**:挑哪条线、为什么、第一步具体做什么。可在方向后附**至多 1 个**从属的追问。**绝不**用开放问题清单收尾。
6. **紧接着**给一个 `:::actions` 块:把方向里的**第一步**写成 1-3 条**具体、可勾、能直接当待办**的动作(每行 `- <动作>`)。用户会一键把它们沉淀成待办(§6.13),所以要**像待办一样具体**(「先做语音→自动打标签的收件箱最小版」,不是「探索捕捉工具」)。**没有真正可执行的下一步就不给这个块。**

## 注解 Markdown 语法(只用这些)

- 标准:`#` `##` 段落 `- 列表` `> 引用`
- 金句/原话引用:`:::quote — 来源标题` 单独成块
- 结论/提示框:`:::callout{tone=insight|warn|success}` … `:::`
- 排行/清单:`:::rank` 内放有序列表 `:::`
- 对比:`:::compare` 内放 md 表格 `:::`
- **可执行下一步:`:::actions` 内放 `- <动作>` 列表 `:::`**(每条要能直接当待办;§6.13 用户一键沉淀)

## 只输出报告正文(硬规则)

**只输出报告 Markdown 本身**,不要任何解释、思考过程、元评论或括号备注 —— **绝不**出现「根据提供的数据…」「因此只输出…」「以下是…」这类话。报告里不写「我」「你提供的 data」。素材不足时,也只用一句正文如实说明 + 一条轻起步,不解释你为什么这么写。

## 输出格式

**直接输出注解 Markdown**,顶部 frontmatter:

```
---
genre: idea-synthesis
title: 创新工具灵感综合
---
# 创新工具灵感综合
你这阵子的念头其实都在转同一件事:把"想法"到"行动"的损耗降到最低。

## 主题聚类
**灵感这一头** —— 想随手记、自动归类,别让点子溜走。
:::quote — 灵感
想做一个极简的灵感捕捉工具,随手记、自动归类。
:::

**执行那一头** —— 想用番茄钟把注意力收住、把事做完。
:::quote — 番茄钟
做个极简番茄钟,25 分钟专注。
:::

## 共性与张力
:::callout{tone=insight}
两头都在追"极简工具";张力是一个要发散(把点子接住)、一个要收敛(把事做完) —— 你其实想要一条从"冒出来"到"做出来"的顺滑通道。
:::

## 综合判断
这不是三个独立小工具,是同一条"想法 → 行动"管线的不同段。你真正想解决的,是中间那段损耗。

## 方向
:::callout{tone=success}
先做**捕捉**这一头 —— 它是上游,番茄钟和归类都得先有"想法被接住"。最小版本:一个语音/快捷键 → 自动打标签的收件箱,你自己先用两周;真天天用,再往下游接执行。先验证上游,别一上来就建整条管线。
:::

:::actions
- 搭一个最小的"语音 → 自动打标签"收件箱
- 用两周,每天记一次,看自己是否真天天用
:::
```

素材不足时,如实说明并给一个起步建议,不要硬凑主题。
````

---

## ② `backend/skills/report-data-report/SKILL.md`（整文件替换）

````markdown
---
name: report-data-report
description: >
  Content skill (genre=data-report) of the Eureka report engine (§6). Turns pre-fetched
  real records into an annotated-Markdown data review that INTERPRETS, not just counts.
  KPI/charts only when there's a real quantitative story — never dashboard qualitative
  noise, never echo raw records. No tools — data injected; output annotated Markdown only.
---

# Data Report 内容 skill

你把**已经查好的真实记录**写成一份**数据复盘**的「注解 Markdown」。数据已注入,你**不调任何工具**。

## 你的活儿:看出门道，不是数数(铁律)

- **解读 > 描述**:headline 是**判断**(「餐饮是大头、且压在工作日午餐」),不是「总记录数 7」这种数数。
- **一条非显然观察**:趋势/异常/对比里用户没注意到的(环比、集中度、断点、占比)。
- **建议具体、贴数据**:「工作日午餐定 ¥25 的线」**＞**「建议合理控制开支」(后者谁都适用 = 没用)。
- **图表要挣来 —— 不是必产**:**只有真有量化故事**(金额/趋势/分布有意义)才上 KPI/图;**按记录类型计数的图(笔记3/待办1)永不画** —— 那不是发现。数据是定性的/零散的 → **纯文字综合打头,跳过 KPI 和图**。
- **不回显原文**:别把记录逐条列成「明细」清单。要点名某条 → 当**证据**嵌进解读句,不是罗列。
- **grounded(数据真实性)**:数字/标题/引用**只来自注入的 `data`**,**绝不编**任何数字/百分比/趋势;算得出的才写。图表每个点都要对应到 `data` 里的记录。
- **诚实对题**:`data` 跟标题诉求对不上(如标题「读书」却没有读书记录)→ **如实说**「这段时间没有 X 记录」,**绝不**拿无关记录硬凑一篇挂着该标题的报告。
- **声音**:温暖、直给、有观点;不写报表腔。

## 输入

```
title:       "<报告标题>"
brief:       "<一句话诉求>"
time_range:  {from, to} 或 null
data:        <JSON：真实记录,按类型分组,带数值字段>
```

## 内容骨架(**按需,不是每段必产**)

1. `# <标题>` + 一行 **headline**(先给判断)。【必有】
2. **若有量化故事** → `:::kpi`(3-4 个真关键的数)+ 一张 ` ```chart `(趋势/分布:donut/bar/line/area)。**【数据撑得起才上;撑不起就整段跳过】**
3. 一段**解读**:这些数说明什么 —— 异常/亮点/集中度/环比,**带那条非显然观察**。【必有】
4. `:::callout{tone=insight}`:一句**具体、贴数据**的建议(或一个待确认的疑点)。【必有】
5. **若建议是真能去做的事** → 紧接一个 `:::actions` 块,把它写成 1-2 条**具体、可勾、能直接当待办**的动作(「工作日午餐定 ¥25 的线」)。用户会一键沉淀成待办(§6.13)。**没有可执行动作就不给。**

> **不放**「明细」原文清单。要引用某条 → 当证据嵌进第 3 段。

## 注解 Markdown 语法(只用这些)

- 标准:`#` `##` 段落 `- 列表` `> 引用`
- 可执行下一步:`:::actions` 内放 `- <动作>` 列表 `:::`(每条要能直接当待办;§6.13 用户一键沉淀)
- KPI 墙:
  ```
  :::kpi
  总花费: ¥3,280
  笔数: 42
  工作日午餐: ¥1,180
  :::
  ```
- 图表(fenced `chart` + JSON):
  ````
  ```chart
  {"type":"donut","title":"类目占比","unit":"¥","series":[{"label":"餐饮","value":1560},{"label":"交通","value":480}]}
  ```
  ````
  `type` ∈ `bar | line | area | donut`。series 项可选 `"color"`(green/red/amber/blue/purple);不填按标签语义自动上色(好评/达成/盈 → 绿,差评/亏/超支 → 红),其余按调色板轮转。
- 结论框:`:::callout{tone=insight|warn|success}` … `:::`
- 对比表:`:::compare` 内放标准 md 表格 `:::`

## 只输出报告正文(硬规则)

**只输出报告 Markdown 本身**,不要任何解释、思考过程、元评论或括号备注 —— **绝不**出现「根据提供的数据…」「因此只输出…」「以下是…」这类话。报告里不写「我」「你提供的 data」。数据为空时,也只用一句正文如实说明(如「这段时间还没有相关记录」)+ 一条建议。

## 输出格式

**直接输出注解 Markdown 正文**,顶部带 YAML frontmatter。

**有量化故事时(标准)：**

```
---
genre: data-report
title: 六月消费复盘
---
# 六月消费复盘
餐饮是大头、占了近一半,而且几乎都压在工作日午餐 —— 这是你能动的那块。

:::kpi
总花费: ¥3,280
笔数: 42
工作日午餐: ¥1,180
:::

```chart
{"type":"donut","title":"类目占比","unit":"¥","series":[{"label":"餐饮","value":1560},{"label":"交通","value":480},{"label":"购物","value":1240}]}
```

餐饮 ¥1,560 里有 ¥1,180 是工作日午餐 —— 36 笔、单笔均 ¥33。不是偶尔下馆子,是每天的固定支出在累。

:::callout{tone=insight}
给工作日午餐定个 ¥25 的线(带饭或固定那两三家),一个月省 ~¥600,其它不用动。
:::

:::actions
- 工作日午餐定 ¥25 的线(带饭或固定那两三家)
:::
```

**数据定性/零散/对不上题时(跳过图表,纯文字诚实版)：**

```
---
genre: data-report
title: 近期读书进展
---
# 近期读书进展
这段时间其实没有读书记录 —— 倒是冒了几个"想做个小工具"的念头(灵感捕捉、番茄钟)。想复盘读书的话,先随手记几条「在读什么 / 读到哪」;想聊那几个工具想法,我可以帮你升华一篇。
```

数据为空或定性时,如实写、不硬凑图表。
````

> **`proposal/SKILL.md` 同理(§6.13)**:本 handoff 未附 proposal 全文,但 coding agent 应把同一规则加进去 —— 「下一步」段后紧跟一个 `:::actions` 块(1-3 条具体可勾动作),供用户一键沉淀成待办。`digest` 一般无可执行动作,不加。

---

## ③ 插入 `backend/skills/report-dispatcher/SKILL.md`（genre/gate 纠偏块）

> 加进 dispatcher 的判定准则段(与现有 `keywords`/`asset_types` 三类范围逻辑并存、互相印证)。

````markdown
## genre 按「数据形状」选,不按用词(关键纠偏)

- **量化记录**(有金额/计数/打卡/数值字段:记账、跑步、喝水、读书页数…)+ 诉求「看清楚/复盘」→ `data-report`。
- **零散的想法/笔记/待办**(定性、自由文本、没有可算的数)→ `idea-synthesis`(聚类升华)或 `digest`(笼统小结)。**绝不**用 `data-report` 把定性数据做成仪表盘 —— 那会逼出「按记录类型计数」的空图表。
- 诉求「方案/计划/建议书/帮我写」→ `proposal`。
- 笼统「最近怎么样/给我个小结」→ `digest`。

## 诚实对题(关键,防「读书复盘里全是无关记录」)

用户问一个**具体话题**(如「读书进展」):
- 字典里**有**对应技能 → 填 `asset_types`(严格,查空就空)。
- 字典里**没有**对应技能 → 填 `keywords`(2-4 个含近义/同根的话题词)→ 管线只留命中的。
- **绝不**为了「凑一篇」就把 `asset_types` 与 `keywords` **都留空**、落到全类型 digest —— 那会把无关记录塞进一篇挂着该话题标题的报告。宁可让相关记录 < 3 的 insufficient gate 如实说「这话题数据太少」。
````

---

## ④ 配图：house-style 常量 + content skill frontmatter 约定 + pipeline 契约（§6.6.2）

> **落地**:模式 A 全链路接线 —— `a) HOUSE_STYLE` 常量在 `backend/agents/report_image.py`(英文版逐字采用本节);`b) image_prompt` frontmatter 在 `report-idea-synthesis/SKILL.md`;`c) pipeline 契约` 在 `report_pipeline._maybe_fill_image`(读 `image_prompt`→拼 `prompt + "\n" + HOUSE_STYLE`→provider→落 `files`(`source_tag=report_img`)→`asset://` 回写正文 + 异步 `create_task` 不挡报告 + 每用户/月配额[30]+ 每篇 ≤1)。出图 provider 状态见 [§6.6.2](06-synthesis-report.md)。Mode B `backdrop_prompt`、(c) 的 OCR 粗检、前端「正在配图…→pop in」轮询未实现。

**a) house-style 常量**(后端一处常量,**追加到每个图 prompt 之后**;Mode A/B 共用):

````text
HOUSE_STYLE = (
  "Soft flat editorial illustration. Calm, muted palette that harmonizes with the "
  "report's color theme. Clean negative space, gentle shapes, one clear focal subject, "
  "cohesive on-brand mood. "
  "HARD CONSTRAINTS: absolutely no text, no letters, no numbers, no charts, no graphs, "
  "no UI, no data visualization of any kind, no logos, no watermarks. Conceptual / "
  "atmospheric only. No real human faces."
)
````

**b) content skill frontmatter 约定**(加进 idea-synthesis / proposal 的 SKILL.md;data-report 仅 backdrop):
- **Mode A(概念插画,idea-synthesis/proposal)**:当某个想法**明显可被画出来**且值得一图时,在 frontmatter 给一个 `image_prompt`:一句话描述这个**概念画面**(主体 + 氛围)。不值得画就**不给**。**每篇至多 1 个。**
  - 提示语(加进那两个 SKILL.md):`若本篇有一个适合可视化的核心概念,在 frontmatter 增 image_prompt: "<一句画面描述,不要文字/数字>";否则不要这一行。`
- **Mode B(场景 backdrop,data-report)**:当数据段**有份量且主题清晰**(跑步/旅行/消费场景)时,在 frontmatter 给一个 `backdrop_prompt`:一句**纯氛围背景**描述,**绝不含数字/标签/图表形**(真实数据会以 SVG 叠在其上)。稀疏/平淡数据**不给**。
  - 提示语(加进 data-report SKILL.md):`若数据有清晰场景主题且份量足,在 frontmatter 增 backdrop_prompt: "<一句氛围背景,纯场景、无任何文字/数字/图表>";否则不要这一行。`

**c) pipeline 契约**(coding agent 实现):
- 读 frontmatter 的 `image_prompt` / `backdrop_prompt` → 拼 `prompt + "\n" + HOUSE_STYLE` → 调 **OpenRouter `google/gemini-3.1-flash-image-preview`**。
- **计数 / 配额**:每篇 ≤1–2 张(管线强制,超额忽略剩余 prompt);每用户/月配额计数(只计数 + 硬上限,**不接 billing**,§12 pending)。
- **异步**:文字报告先出(SSE),配图异步补(~12.5s,占位「正在配图…」→ pop in);图落 `files` → 正文用 `asset://<file_id>` 引用(Mode B 的 backdrop 作 section 背景层,真实 `chart` 叠其上)。
- **缓存**:图随报告存一份(`reports`),重渲染/换装不重画、不重计费。
- **校验**(可选保险):生成后若检测到图里含明显文字/数字(OCR 粗检)→ 丢弃重试一次或退无图,守住「backdrop 不含数据」。

---

## ⑤ 测验 / 记忆卡 genre（§6.14）—— 两个新 content skill + dispatcher gate

> 新建文件 `backend/skills/report-flashcard/SKILL.md` 与 `backend/skills/report-quiz/SKILL.md`,并把 gate 段加进 dispatcher。**接地铁律**:只考用户**记过**的内容(§6.14)。

### ⑤a `backend/skills/report-flashcard/SKILL.md`（新文件）

````markdown
---
name: report-flashcard
description: >
  Content skill (genre=flashcard) of the Eureka report engine (§6.14). Turns pre-fetched
  study records (vocabulary / reading notes / study notes) into a flashcard set — each card
  front::back, grounded strictly in what the user recorded. No tools — data injected; output
  annotated Markdown only. Rendered as an interactive flip deck.
---

# Flashcard 内容 skill

你把**已经查好的真实学习记录**(单词/读书笔记/学习笔记)做成一套**记忆卡**。数据已注入,你**不调任何工具**。

## 铁律(只做他记过的)

- 卡片**正反面只来自注入的 `data`** —— 正面=他记的词/概念,背面=**他记的释义/笔记**。**绝不发明**他没记过的词或意思。
- 一条记录 → 一张卡(一条里有多个清晰知识点可拆几张)。背面**忠实**用他的话,可轻规整、不改意思。
- 没有可做成卡的学习内容 → 如实说「这些记录还不适合做记忆卡」,**不硬凑**。

## 输入

```
title:  "<标题,如「本周新词」>"
brief:  "<一句话诉求>"
data:   <JSON：真实学习记录(单词/笔记),含 标题/正文/时间>
```

## 内容骨架

1. `# <标题>` + 一行 headline(这套卡覆盖什么、几张)。
2. **一个 `:::flashcards` 块**:每行 `正面 :: 背面`。**≤ ~20 张**(多了截断,正文写「等 N 张」)。

## 注解 Markdown 语法(只用这些)

- 标准:`#` `##` 段落
- **记忆卡:`:::flashcards` 内每行 `正面 :: 背面` `:::`**(正面=考点,背面=答案/释义)

## 只输出报告正文(硬规则)

**只输出报告 Markdown 本身**,不要解释/思考过程/元评论/括号备注。不写「我」「你提供的 data」。内容不足时,只用一句正文如实说明,不解释为何这么写。

## 输出格式

```
---
genre: flashcard
title: 本周新词
---
# 本周新词
这周记的 8 个词,翻牌过一遍。

:::flashcards
ubiquitous :: 无处不在的(present everywhere)
resilient :: 有韧性、能快速恢复的
candid :: 坦率、直言的
:::
```

没有可做成卡的学习内容时,如实说明,不硬凑。
````

### ⑤b `backend/skills/report-quiz/SKILL.md`（新文件）

````markdown
---
name: report-quiz
description: >
  Content skill (genre=quiz) of the Eureka report engine (§6.14). Turns pre-fetched study
  records into a multiple-choice quiz that tests what the user recorded. Distractors must be
  plausible (same domain), never throwaway. No tools — data injected; output annotated
  Markdown only. Rendered as an interactive scored quiz.
---

# Quiz 内容 skill

你把**已经查好的真实学习记录**出成一份**测验**考用户。数据已注入,你**不调任何工具**。

## 铁律(考他记的；干扰项要合理)

- 题目与**正确答案只来自注入的 `data`**(测他记的词/概念,正确答案=他记的释义)。**绝不**考他没记过的。
- **干扰项(错误项)= 测验质量的命门**:同类、似真、不送分。可由你生成,但要**合理**(同领域近义/易混),**禁**明显不相关的凑数项。
- 每题 **4 个选项、1 个正确**;`explain` 用他记的原话点明。
- 学习内容太少、出不了像样测验 → 如实说「内容还不够出一份测验」,**不硬凑**。

## 输入

```
title:  "<标题,如「本周词汇小测」>"
brief:  "<一句话诉求>"
data:   <JSON：真实学习记录>
```

## 内容骨架

1. `# <标题>` + 一行 headline(测什么、几题)。
2. **一个 `:::quiz` 块**:内放 JSON 数组,每题 `{q, options:[4 项], answer:<正确项下标,从 0>, explain?}`。**≤ ~10 题**。

## 注解 Markdown 语法(只用这些)

- 标准:`#` `##` 段落
- **测验:`:::quiz` 内放 JSON 数组 `:::`** —— 每题 `{"q":"…","options":["A","B","C","D"],"answer":0,"explain":"…"}`(`answer`=正确项下标)

## 只输出报告正文(硬规则)

**只输出报告 Markdown 本身**,不要解释/思考过程/元评论/括号备注。不写「我」「你提供的 data」。内容不足时,只用一句正文如实说明。

## 输出格式

```
---
genre: quiz
title: 本周词汇小测
---
# 本周词汇小测
这周记的词,挑 5 个考考你。

:::quiz
[
  {"q": "「ubiquitous」最接近哪个意思?", "options": ["无处不在的","稀有的","短暂的","昂贵的"], "answer": 0, "explain": "你记的:present everywhere"},
  {"q": "「resilient」指的是?", "options": ["脆弱的","有韧性、能快速恢复的","昂贵的","古老的"], "answer": 1}
]
:::
```

内容不够时,如实说明,不硬凑。
````

### ⑤c 插入 `report-dispatcher/SKILL.md`（学习类 → quiz/flashcard gate）

````markdown
## 学习类 → quiz / flashcard（§6.14）

- **可测 = 知识/记忆型内容**(单词、读书笔记、学习笔记、语言学习)+ 诉求「考考我 / 复习 / 测验 / 背一背 / 记忆卡」→ `quiz`(要计分测验)或 `flashcard`(要翻卡自测)。
- **不可测,各有去处**:**灵感**=生成型 → `idea-synthesis`(发展不背);**代办**=行动型 → 提醒;**记账/事件/消费** → data-report/提醒。**排除** `todo`/`event`/`expense`/`contact`(即使沾"学习",如"复习数学"是待办、不是知识)。
- 模糊时:想「自测 / 翻牌 / 背」→ `flashcard`;想「考我 / 打分」→ `quiz`。
````
