# 从想法到产品:UReka 的 vibe coding 实践

> 30 分钟 speaker-led 版本。  
> 目标:不是工具教程,也不是 UReka 产品路演,而是复盘一个 AI 产品如何从想法、架构、体验到工程实现被推进出来。

---

## Slide 1. 从想法到产品:UReka 的 vibe coding 实践

**画面建议:** 标题页。可以用 UReka 当前 App 截图或报告截图作为背景的局部裁切。

**页面文案:**

> 从一个闪念入口开始,把碎片记录变成可沉淀的个人资产。

**口播:**

大家好,今天我想分享的不是一个 AI 工具教程,也不是 UReka 的产品路演。  
我想讲的是:一个模糊的产品想法,如何在 AI Agent 的协作下,一步步变成一个真实可运行的 App。  
这里的 vibe coding 不是随便写 prompt 让 AI 写代码,而是一种结合产品判断、架构理解、审美输入和工程验证的开发方式。

---

## Slide 2. 我一开始以为:AI Coding = 更快写代码

**画面建议:** 简洁文字页,可以放一段被划掉的公式:Prompt → Code。

**页面文案:**

```text
Prompt → Code
```

> 后来发现:代码只是最后一步。

**口播:**

一开始我对 AI Coding 的理解也很直接:我描述需求,AI 帮我写 Flutter 页面、FastAPI 接口、测试和 bug fix。  
这些当然有用,但做 UReka 后我发现,代码其实是最后一步。  
如果产品方向、数据链路、状态边界没有想清楚,AI 写得越快,返工也越快。

---

## Slide 3. 起点:我想放大“闪念”

**画面建议:** 左侧放“硬件按钮 / 戒指 / App 输入入口”的图,右侧列碎片记录类型。

**页面文案:**

> 记录的痛点不是不会写,而是入口太重、后续太散。

- 记账
- 记事
- 灵感
- 运动
- 读书
- 工作想法

**口播:**

UReka 的起点不是“我要做一个 App”,而是我一直想放大“闪念”这个动作。  
普通人每天有很多琐碎内容想记录:记账、记事、灵感、运动、读书、工作想法。  
但这些内容现在要么散落在不同 App 里,要么最后都堆进备忘录,后续很难整理和利用。  
所以我的核心假设是:如果有一个统一输入入口,再配合一个统一的 AI 整理层,碎片记录就可能变成持续积累的个人资产。硬件闪念按钮就是这个想法的物理化。

---

## Slide 4. UReka 是什么:统一入口 + AI 整理层

**画面建议:** 放 UReka 当前 Today 页 / Reka / 报告页拼图。

**页面文案:**

```text
说一句 / 按一下
       ↓
AI 理解、归类、整理
       ↓
记录、提醒、报告、洞察
```

**口播:**

UReka 是一个面向普通人的 AI 记录伙伴。  
用户只管说,Reka 负责整理、提醒、总结,并逐渐把零散记录变成习惯和洞察。  
它不是一个简单 todo app,而是把闪念捕捉、技能模板、Today 页、Reka Offer、报告、硬件戒指这些能力串起来。

---

## Slide 5. UReka 的技术架构

**画面建议:** 一张分层架构图,从上到下:Flutter App / FastAPI Backend / Agent Pipelines / MCP & Tools / MySQL & Memory / External Apps & Hardware。

**页面文案:**

```text
Flutter App
  Today / Flash / Ring / Reports / Pet
        ↓
FastAPI Backend
  Auth / Assets / Chat / Reports / Notifications
        ↓
Google ADK Agents + Pipelines
  Flash / Chat / Report / Task
        ↓
FastMCP + External MCP
  Internal CRUD / DingTalk / Notion / Calendar
        ↓
MySQL + Files + Memory
  Assets / Events / Reports / Nudges / User Skills
```

**口播:**

技术上,UReka 的主客户端是 Flutter App,包括闪念捕捉、Today 页、戒指入口、报告 WebView 和 Reka 宠物层。  
后端是 FastAPI,负责认证、资产、事件、报告、通知和 connected apps。  
AI 部分不是一个单点 chat API,而是几条 pipeline:Flash pipeline 负责把输入结构化成资产,Chat agent 负责对话和工具调用,Report pipeline 负责把历史记录生成图文报告,Task skill 负责异步调用第三方 MCP。  
数据层是 MySQL,存 assets、events、reports、nudges、user skills。工具层用 FastMCP 暴露内部 CRUD,也可以接 DingTalk、Notion、Calendar 这些外部工具。

---

## Slide 6. 我的 Agent 开发工作流

**画面建议:** 放 Codex 对话记录截图,旁边叠一条流程线。

**页面文案:**

```text
Brainstorm / Office Hours
→ Writing Plans / Specs
→ Claude Design / Design Exploration
→ Coding Agents
→ Auto Review + Manual Review
→ Bug Agent Fix Loop
```

**口播:**

我后来发现,vibe coding 不是边想边让 AI 写。  
更稳定的方式是把 Agent 分配到不同阶段:先用 brainstorm 和 office-hours 梳理产品需求,再用 writing-plans 拆任务、写 spec,然后做设计探索,再让独立 coding agent 根据任务实现。  
实现后还要经过 auto review、manual review,最后不断和 bug agent 沟通修复。  
这里的重点不是用了多少工具,而是每一步都有边界、有产物、有验证。

---

## Slide 7. Case 1:Today 页如何被推翻

**画面建议:** Today 页演进截图。如果没有旧截图,可用当前 Today 页 + 简化演进箭头。

**页面文案:**

```text
日历里的今天
→ Dashboard
→ 泡泡池
→ 今日安排 + Reka Offer + 捕捉反馈
```

**口播:**

Today 页是一个很典型的例子。  
一开始我以为它就是“日历里的今天”,后来发现这只是历史回看,不是用户每天打开 App 的理由。  
然后尝试过 dashboard,但 dashboard 很容易变成填空式界面。  
最后逐渐收敛成今日安排、Reka Offer 和捕捉反馈。  
这个过程说明,AI 最有价值的地方不是一次给正确答案,而是陪你更快推翻不对的答案。

---

## Slide 8. 球球掉落:把记录变成资产感

**画面建议:** 放球球池 / bubble pool 截图或动效帧。

**页面文案:**

```text
闪念输入
→ AI 理解和归类
→ 生成一个可见资产
→ 球球掉落进入池子
→ 用户获得即时正反馈
```

**口播:**

我想用球球掉落来表现资产产生,不是为了好看。  
用户做的是一个很轻的动作:说一句话、按一下按钮、记一个闪念。  
如果系统只是把它存进列表里,用户很难感受到“我刚刚创造了什么”。  
但如果它变成一个球球掉落、进入资产池,用户会获得即时正反馈:我的碎片记录变成了一个可见的东西。  
所以球球掉落不是动效,而是把“记录成功”转译成“资产生成”的反馈机制。

---

## Slide 9. Agent Design:从 App 功能到 Agent 系统

**画面建议:** 一张循环图。中心写“Flash Pipeline / Agent Loop”,周围是 Input、Reason、Act、Verify、Memory、Trigger。

**页面文案:**

```text
Flash Pipeline = 用户输入后的一次局部 Agent loop
Cron Trigger = 系统按时间/条件主动醒来
Heartbeat Scan = 系统持续轻量检查状态缺口
Memory = 每次记录和反馈沉淀成下一次判断的上下文
```

**口播:**

这里有一个我觉得很重要的认知:UReka 不是“用户说一句,AI 回一句”。  
Flash pipeline 本身已经是一个局部 Agent loop:它要判断输入是什么类型,调用对应 skill 或 parser,把它结构化成 asset,检查结果是否可用,最后写入长期记录。  
Cron trigger 对应的是系统按时间或条件主动醒来,比如用户积累了足够多灵感后,提示他生成报告。  
Heartbeat scan 对应的是持续轻量检查状态缺口,比如每天检查用户有没有完成记账、运动或其他习惯记录。  
Memory 则是每次记录、反馈和报告都会沉淀成下一次判断的上下文。  
所以 UReka 逐渐从一个 App 功能集合,变成一个由 pipeline、trigger、heartbeat 和 memory 组成的个人记录 Agent。

---

## Slide 10. Case 2:硬件戒指接入

**画面建议:** 戒指实物 / 连接页 / 录音状态截图。

**页面文案:**

```text
按一下
→ 录音
→ 传输
→ ASR
→ Flash Pipeline
→ 资产 / 提醒 / 报告
```

**口播:**

硬件戒指接入是另一个关键 case。  
因为它把 UReka 从纯软件体验带到了真实世界:设备连接、录音、文件传输、ASR、状态恢复、异常处理都会出现。  
这时候 AI 不只是写 UI,而是帮我拆系统链路、设计状态、补测试、处理连接和调试入口这些真实工程问题。  
它也进一步强化了 UReka 的核心方向:记录入口要尽可能低摩擦。

---

## Slide 11. AI 改变的是迭代密度

**画面建议:** GitHub commit 记录截图。

**页面文案:**

> 不是一次生成,而是高频迭代。

```text
spec
→ design review
→ implementation
→ polish
→ verify
→ bug fix
```

**口播:**

这张 commit 记录很能说明问题。  
一天里不是只有“实现功能”,还有 spec、design review、UI polish、动效、验证和再调整。  
AI 带来的不是一次性生成,而是让迭代频率变高。  
以前一个人可能需要很久才能完成想清楚、写出来、验证完这个闭环,现在可以更快形成一个试验循环。

---

## Slide 12. 生成的不是内容,而是体验

**画面建议:** 生成报告截图,用手机 mockup 承载。

**页面文案:**

> 报告不是一段总结,而是一种可阅读的洞察体验。

**口播:**

这是 UReka 生成的报告。  
我不希望它只是 markdown 总结,而是一个有叙事、有重点、有视觉层级的阅读体验。  
Report pipeline 里会先判断报告类型和范围,再拉取真实用户数据,再生成内容,最后用确定性的渲染器输出 HTML,必要时再生成配图。  
这让我意识到,AI 让内容生成变便宜,但表达质量仍然需要被设计。

---

## Slide 13. 审美是 AI 时代的输入能力

**画面建议:** Variant 首页截图,可以拼 Craftwork / Hugeicons / Web to Design。

**页面文案:**

```text
看参考
→ 拆解为什么好
→ 转成设计语言
→ 让 Agent 实现
→ 再删掉模板味和炫技感
```

**口播:**

过去我们说审美,容易觉得它是主观感觉。  
但在 AI 工作流里,审美其实变成了一种输入能力。  
你看过什么、能不能拆解为什么好、能不能把它转成具体设计语言,会直接影响 AI 的产出质量。  
所以我会用 Variant、Craftwork、Hugeicons、Web to Design,再结合 taste skill 和 GSAP skill,把“好看一点”变成更明确的设计约束。

---

## Slide 14. 踩坑与总结:vibe coding 不只是写代码

**画面建议:** 简洁总结页,左侧“坑”,右侧“原则”。

**页面文案:**

```text
AI 会迎合你 → 反复问核心价值
AI 会过度实现 → 用 spec 收边界
上下文会漂 → 用文档和 handoff 稳住
代码能跑 ≠ 产品对 → review + QA
设计会 generic → 用参考和 taste 提高输入质量
```

**口播:**

这个过程里也有很多坑。  
AI 会迎合你,所以你要反复问这是不是核心价值。  
AI 会过度实现,所以必须用 spec 收边界。  
上下文会漂,所以要有文档、handoff 和 commit。  
代码能跑不等于产品对,Today 页就是例子。  
设计很容易 generic,如果没有审美参考,AI 会给你平均水平。  
所以最后我想总结一句:vibe coding 不只是让 AI 写代码,而是用 AI 把产品判断、Agent 架构、工程实现、质量验证和表达能力串起来。

---

## 30 分钟时间分配

| 部分 | 页 | 时间 |
|---|---:|---:|
| 开场与产品动机 | 1-4 | 7 min |
| 技术架构与开发工作流 | 5-6 | 5 min |
| 产品 case:Today + 球球反馈 | 7-8 | 5 min |
| Agent 架构 + 硬件接入 | 9-10 | 6 min |
| 迭代、报告、审美 | 11-13 | 5 min |
| 踩坑与总结 | 14 | 2 min |

---

## 第 9 页的关键边界

不要说:

> UReka 已经完整实现了通用 loop engineering。

更准确的说法:

> UReka 当前已经有 Flash pipeline、scheduler、heartbeat、后台任务和 memory 雏形;它们让我意识到,做 AI 产品需要理解 Agent loop、cron trigger、heartbeat scan 和 memory 的底层设计。

