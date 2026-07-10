# Handoff · 测验 / 记忆卡（quiz / flashcard genre · §6.14）

> 给 **coding agent + design** 的实施范围。把**学习类记录**(单词/读书/学习笔记)变成**可交互的测验/记忆卡** —— 补上「记得住」。
> 规则真值见 [§6.14](../06-synthesis-report.md)。**它是 §6 的新 genre + 第一个交互式渲染**;复用 §6 管线([§6.1](../06-synthesis-report.md))+ §6.6 的 WebView JS + §14 的 offer 流 —— **新肌肉只有「交互渲染」一处**,其余是组合。
> **可独立于其它 handoff 上线。**

---

## Phase 1 · quiz / flashcard v1（核心）—— ✅ 已实现（2026-06）

> 两模式同源:`flashcard`(正反翻卡、自评)/ `quiz`(题+答+计分、MC 自动判)。**接地铁律**:题/答只来自用户记录,绝不发明他没记过的(§6.14)。

| 面 | 做什么 | 验收 |
|---|---|---|
| **prompt(✅ 成稿照接)** | `report-flashcard` + `report-quiz` SKILL.md 按 [`handoff-report-prompts-v2.md`](handoff-report-prompts-v2.md) ⑤a/⑤b 原文落盘(加了既有的「写法铁律」防反引号围栏);⑤c gate 段已插入 dispatcher(七种体裁) | 学习类内容 → 出结构化 `:::quiz`/`:::flashcards` ✅(实测接地:只考记过的、干扰项同类);记账/待办被 gate 挡掉 ✅ |
| **后端(✅)** | genre 接进 §6 管线(REPORT_GENRES/_GENRES/渲染映射/标签);`:::quiz`/`:::flashcards` 随 `content_md` 持久化;**§14 钩子**:学习 domain 7d ≥8(排除 todo/event/expense/contact)→「📝 要不要考考你?」offer(复用积累 offer 流 + 一键即做,零新触发) | 「考考我」/「做成记忆卡」手动路径 ✅(实测两 genre);周测 offer fire ✅(合成用户验证);落容器可回看/重做 ✅ |
| **前端 / render(✅ 新肌肉)** | `report_render` 新增交互模板:`flashcard`=3D 翻卡 + 会了/还不熟自评 + 计数;`quiz`=选项→判定→计分→进度→结果页+「再来一遍」。vanilla JS(无 GSAP 依赖),**渐进增强**(无 JS 题/答静态可读;JSON 坏块降级 pre);重进 = 状态全新可重做 | 翻卡/答题/出分 ✅;JS 关可读 ✅;坏 JSON 降级 ✅ |
| **🎨 design(可选,未做)** | 测验/记忆卡的视觉再打磨(翻卡、选项态、结果页)→ `/design-shotgun`→`/design-html` 落 render catalog | 后续按真机观感决定 |

**v1**:flashcard 自评 + 简单 MC quiz;接地用户内容;手动 + 周测 offer;落容器。

---

## Phase 2 · 间隔重复 SRS（后置 · 大）

> 把「测过一次」升级成「真学会」—— 这才是最大上行,但是更重的活,**单独一轮**。

- 记每张卡/每题的**对错历史**;按遗忘曲线**重现没记住的**(Anki 式)。
- 天然接 [§14 主动 REKA](../14-proactive-reka.md):REKA 周期性「上次没记牢的 5 个,再过一遍?」(阈值/节律触发)。
- 需:per-card 成绩表 + 调度算法 + §14 复习 offer。**v1 不做。**

---

## 依赖 / 顺序

- Phase 1 自包含,**不依赖**其它 handoff;唯一前置是 §6 报告管线(已实现)+ §14 offer 流(已实现,Phase 1 的 offer 直接挂)。
- Phase 2(SRS)在 Phase 1 跑通、且有真实学习数据后再做。

## Out of scope（别做）

- **SRS / 成绩追踪**(Phase 2)。
- **外部增强**(标准释义/用法 → 接 [§14.9 web-search](../14-proactive-reka.md) + 接地墙)= 后置;v1 只测用户**自己记的**内容。
- 付费墙/计费(§12 pending)。

## 读这些

[§6.14](../06-synthesis-report.md)(genre 真值)· §6.1/§6.2/§6.3(报告管线 + 接地)· §6.6(WebView JS 渲染运行时,交互靠它)· [§14.3/§14.5](../14-proactive-reka.md)(阈值型 → Type B offer,周测复用)· §9(REKA 主持,可选)。

## 分工(prompt / 基建 / design)

- **prompt(spec 侧)**:`report-flashcard` + `report-quiz` content skill(生成 + 干扰项质量)+ dispatcher 学习类 gate。**这是质量本体,coding agent 拿成稿接线、不自拟。**
- **基建(coding agent)**:genre 接管线、`:::quiz`/`:::flashcards` 抽取与持久化、§14 阈值型挂 quiz offer。
- **🎨 design + 前端**:**交互渲染模板**(翻卡/答题/计分的 HTML+JS,§6.6 WebView)—— 本功能唯一的新肌肉。

## 数据模型

- 测验/记忆卡 = `reports` 行(genre=`quiz` / `flashcard`),`content_md` 存 `:::quiz`/`:::flashcards`,**不另设表**(v1)。
- Phase 2 SRS 才需新表(per-card 成绩 + 调度)。
