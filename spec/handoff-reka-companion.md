# Handoff · REKA 行动与陪伴（§6.13 报告→待办 + §14 主动 REKA）

> 给 **coding agent + design** 的实施范围。两块合一,因为它们是**同一个闭环**:
> **§14 Type B 给你一份报告 → §6.13 把报告里的下一步变成待办 → §14 Type A 在该做时提醒你。** REKA 把「洞察 → 行动 → 跟进」串起来。
> 规则真值见 [§6.13](06-synthesis-report.md) · [§14](14-proactive-reka.md)。**按 Phase 顺序做,前 Phase 不依赖后 Phase、可独立上线。**
> `:::actions` 的 prompt 成稿已在 [`handoff-report-prompts-v2.md`](handoff-report-prompts-v2.md)(idea-synthesis/data-report 已含,proposal 同理待加)。

---

## Phase 1 · 报告 → 待办（§6.13）—— 小、自包含、先上

> 闭环的「行动」端。独立于 §14,最快见效(让报告的「方向/下一步」能真正被管理)。

| 面 | 做什么 | 验收 |
|---|---|---|
| **prompt(spec 侧,✅ 已出稿)** | content skill 在「方向/下一步/具体建议」后产 `:::actions`(每行一条可勾动作);见 handoff-report-prompts-v2.md | 报告 md 末尾带结构化 `:::actions` |
| **后端** | render `:::actions` → 「✦ 接下来」勾选样式;pipeline 抽 `:::actions` → **`reports.suggested_actions`**`[{title,kind?,due?}]`(迁移加列) | 报告 HTML 有「✦ 接下来」段;`suggested_actions` 落库 |
| **前端** | `report_viewer_page` **WebView 下方**原生「✦ 接下来」行动条:每条 `+ 待办` + 顶部 `全部加到待办` → 调 `tool_create_todo`/`POST /api/assets` 建待办(`content=action`)+ **`source_report_id` 溯源** + **防重**(已建转「已加 ✓」) | 点 `+ 待办` 一键建 + toast;待办详情显「来自报告《X》」;重复点不重复建 |

**v1**:todo 单类型、一键直建。**后置**:`+ 日程`(time-bound→event)、点 `+` 先开预填编辑表单、其它技能类型。
（= [§6.12](06-synthesis-report.md) 的「批 5」,**别重复建**;此处把它并进 REKA 闭环统一交付。）

---

## Phase 2 · 主动 REKA 核心（§14 v1)—— 提醒(Type A)+ 引擎 + 展示 + 护栏

> 陪伴层的地基:定时大脑 + 节律 + 显示 + 傻瓜护栏。**Type A 几乎全复用通知系统**,真正新建的是「定时 + 节律 + 推送」。

| 面 | 做什么 | 验收 |
|---|---|---|
| **后端 · 通知补缺** | **task-skill 完成通知**(异步完成→「已同步到X ✓」,归反应式族,§14.4) | task 完成有通知进 feed |
| **后端 · 引擎** | **cron/heartbeat**(ADK,~30min 扫;**确定性廉价检查、零 per-tick LLM**)+ **统计节律 profile**(每日离线 job:cadence=间隔中位、time-of-day 直方峰、weekday、confidence;落 `rhythm_profiles`)(§14.1/14.2) | profile 每日重算落库;heartbeat 只读 profile + 当前态 |
| **后端 · 触发 + Type A** | 触发引擎:**缺口→Type A 提醒**(模板文案、置信门槛、≤2/天)(§14.3/14.4);写 **`nudges`** 表(type/kind/text/ref/status/outcome,§14.10) | 「该记早餐了?」在缺口时 fire;不确定不发;每天 ≤2 |
| **前端 · 展示+回溯** | 浮球**轻 bob + peek 气泡**(到达)→ 点展开**可动作**(`记一笔`/`知道了`)→ 忽略收成「...」安静态 + 进**通知 feed**;outcome 状态(acted/dismissed/ignored…)(§14.7) | 到达醒目→安静→feed 可找回;feed 显「✓ 已记/未处理」 |
| **前端 · 傻瓜护栏** | 零配置;**温柔 REKA 口吻权限请求**(好时机、非首启系统弹窗);静默时段自动;**自适应**(忽略→退避、采纳→继续,靠 outcome);默认 ON + 一个总开关(§14.8) | 不配置即用;连续忽略后自动少提醒;夜里不打扰 |

**护栏铁律(承 §7.0/§9.0)**:邀请非命令、不愧疚、不攀比、一键「球球安静一会儿」。**对老人尤甚 —— 错时/愧疚提醒会伤关系。**

---

## Phase 3 · 晨间简报（§14.6）—— 工程产内容，design 主理皮

| 面 | 做什么 | 验收 |
|---|---|---|
| **后端** | **`morning-briefing` genre**(内容骨架:REKA 早安 + 今日待办 + 逾期 + 今日日程 +(天气后置)+ 可选昨日小结);**大半确定性数据 → 首次打开现生成、秒出**(只问候需点模型/可模板);落 `reports`(进报告容器,可回看) | 首打开秒出;过去简报在报告容器可翻看 |
| **前端** | **每天中午前首次打开 → 沉浸式「早安」页**(每天一次、可滑走);过后作普通报告卡 | 一天一次、滑走进 app、不困住人 |
| **🎨 design 主理** | **沉浸式呈现与装修**(布局/动效/情绪/REKA 角色)。渲染为 HTML → 走 `/design-shotgun` 探样 + `/design-html` 出生产皮,落进 §6 render catalog | 一个「值得期待」的早安时刻,非又一张报告卡 |

**后置**:天气(定位+API,v1.5)、傍晚 wrap-up。

---

## Phase 4 · Type B 帮你做 + web-search（§14.5 + §14.9）—— 富、涉成本，最后

| 面 | 做什么 | 验收 |
|---|---|---|
| **后端 · offer→报告** | offer 触发(到期 event / 积累阈值)→ peek 气泡 + 落 feed;**接受 → 跑 §6 报告管线**(genre+scope 内置)→ 报告进容器 + 锚定来源 event;ignore→feed CTA;**expire→已过期归档**;`source_nudge_id` 溯源(§14.5) | 「要我帮你会前调研吗」→ 一键→出简报报告;过期 CTA 失效 |
| **后端 · web-search** | **管线步骤**(非 content-skill 工具):确定性 search → 注入**带出处**资料 → content skill 引用;**grounding 墙**(用户数据 grounded、外部标出处、绝不混写);Pro 门控/配额(§14.9) | briefing 引用外部且标源;用户数字仍只来自真实记录 |
| **前端** | Type B offer 气泡 + 接受流(锚定 session 预置任务)+ ignore/expire 态 | 一键即做、显进度→结果;忽略留 CTA |

**会前调研「调研」到底产什么(web vs 用户数据综合)= 独立设计 pass**,Phase 4 接前定。

---

## 依赖 / 顺序

```
Phase 1(报告→待办,独立) ─┐
                          ├─ 闭环成立后体验最完整
Phase 2(主动核心)─ Phase 3(晨间简报)─ Phase 4(Type B + search)
```
- **建议顺序**:Phase 1 → 2 → 3 → 4。Phase 1 最小最快;Phase 2 是地基;Phase 4 最重(涉成本)放最后。
- Phase 4 的 Type B 报告会**用到 Phase 1 的 `:::actions`**(报告→待办)→ 闭环。

## Out of scope（别做）

- Free/Pro 付费墙与计费([§12](12-business-model.md) pending;Phase 4 只做配额计数+硬上限,**不接 billing**)。
- [§10](10-game-config.md)/[§11](11-admin.md) admin·game-config、§6.11 卡片微点评(已 pending)、[§1.5.1.1/.2/.3](01-agent-architecture.md) chat 健壮性(另一条线)。
- 把 nudge 决策做成 per-tick LLM(成本铁律:确定性 + 统计 + 模板)。

## 读这些

§6.13 · §14(全)· §6.2/§6.3(报告管线)· §7.3(缺口型/阈值型触发,§14 复用)· §3+§9(通知 feed)· §1.6(task-skill)· §1.5.1(锚定 session)· 成本 [§12](12-business-model.md)。

## 分工(prompt / 基建 / design)

- **prompt(spec 侧)**:`:::actions`(✅ 已出稿)+ proposal 同款补 + 晨间简报 genre 内容 skill(若用 LLM 串场)+ web-search 引用纪律。Type A/offer **文案是模板字符串**(给 copy 规格即可,非 LLM prompt)。
- **基建(coding agent)**:`suggested_actions` 抽取+迁移、原生行动条、`source_report_id`/`source_nudge_id`;heartbeat、统计 profile、触发引擎、`nudges` 表、peek 气泡、feed 回溯、傻瓜护栏、Type B offer 流、web-search 管线步。
- **🎨 design(设计流程)**:**晨间简报沉浸式皮**(`/design-shotgun`→`/design-html`)+ nudge peek 气泡/「...」视觉打磨。

## 共享数据模型(一处看全)

- `reports.suggested_actions`(§6.13)· `assets.source_report_id` / `assets.source_nudge_id`(溯源)。
- `nudges`(§14.10:type/kind/text/ref/status/outcome/expires_at)· `rhythm_profiles`(§14.10:cadence/typical_times/weekdays/confidence)。
- 晨间简报 = `reports` 行(genre=`morning-briefing`),不另设表。
