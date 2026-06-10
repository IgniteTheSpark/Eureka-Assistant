# Handoff · REKA 行动与陪伴（§6.13 报告→待办 + §14 主动 REKA）

> 给 **coding agent + design** 的实施范围。两块合一,因为它们是**同一个闭环**:
> **§14 Type B 给你一份报告 → §6.13 把报告里的下一步变成待办 → §14 Type A 在该做时提醒你。** REKA 把「洞察 → 行动 → 跟进」串起来。
> 规则真值见 [§6.13](06-synthesis-report.md) · [§14](14-proactive-reka.md)。**按 Phase 顺序做,前 Phase 不依赖后 Phase、可独立上线。**
> `:::actions` 的 prompt 成稿已在 [`handoff-report-prompts-v2.md`](handoff-report-prompts-v2.md)(idea-synthesis/data-report 已含,proposal 同理待加)。

---

## Phase 1 · 报告 → 待办（§6.13）—— ✅ 已实现（2026-06）

> 闭环的「行动」端。独立于 §14,最快见效(让报告的「方向/下一步」能真正被管理)。

| 面 | 做什么 | 验收 |
|---|---|---|
| **prompt(✅)** | content skill 在「方向/下一步/具体建议」后产 `:::actions`(每行一条可勾动作);idea-synthesis / proposal / briefing 均已落 | 报告 md 末尾带结构化 `:::actions` ✅ |
| **后端(✅)** | render `:::actions` → 「✦ 接下来」勾选样式(新旧两条 render 路径);pipeline `_extract_actions` → **`reports.suggested_actions`**(迁移 0018);**`GET/POST /api/reports/{id}/actions`**(GET 防重状态;POST 服务端幂等建 todo + `assets.source_report_id` 列) | 报告 HTML 有「✦ 接下来」段;`suggested_actions` 落库;幂等已验证 ✅ |
| **前端(✅)** | `report_viewer_page` **WebView 下方**原生「✦ 接下来」行动条:每条 `+ 待办` + 顶部 `全部加到待办`(走 `/api/reports/{id}/actions`,服务端建 todo+溯源)+ **防重**(已建转「已加 ✓」);`asset_detail_sheet` 待办详情显「来自报告《X》· 查看报告」(点开原报告) | 点 `+ 待办` 一键建 + toast;待办详情显来源、可点回报告;重复点不重复建 ✅ |

**v1**:todo 单类型、一键直建。**后置**:`+ 日程`(time-bound→event)、点 `+` 先开预填编辑表单、其它技能类型。
（= [§6.12](06-synthesis-report.md) 的「批 5」,**别重复建**;此处把它并进 REKA 闭环统一交付。）

---

## Phase 2 · 主动 REKA 核心（§14 v1)—— ✅ 已实现（2026-06）

> 陪伴层的地基:定时大脑 + 节律 + 显示 + 傻瓜护栏。**Type A 几乎全复用通知系统**,真正新建的是「定时 + 节律 + 推送」。

| 面 | 做什么 | 验收 |
|---|---|---|
| **后端 · 通知补缺(✅ 盘点无缺)** | **task-skill 完成通知**:`agents/task_skill.py` 完成/失败已走 `create_notification`(M6 反应式族) | task 完成有通知进 feed ✅ |
| **后端 · 引擎(✅)** | `core/companion.py companion_loop`(~30min,**确定性廉价检查、零 per-tick LLM**)+ `core/rhythm.py`(每日离线:cadence=间隔中位、time-of-day ±1h 平滑直方峰、weekday、confidence;落 `rhythm_profiles`,迁移 0019) | profile 每日重算落库 ✅;heartbeat 只读(统计单测:日常 8 点/一三五晚跑/散乱低置信 全过) |
| **后端 · 触发 + Type A(✅)** | 缺口→Type A(峰值+1h~+3h 窗、今天没记、模板文案、置信 ≥0.45、≤2/天)→ `nudges` 表 + `create_notification(type=nudge)`;`/api/nudges`(pending/outcome/prefs) | fire/防重/上限/总开关/退避/过期 全部在容器内验证通过 ✅ |
| **前端 · 展示+回溯(✅)** | `reka_nudges.dart` store + 浮球**轻 bob(单跳,非彩纸)+ peek 气泡(8s 自动收起)**→ 点展开**可动作**(`记一笔`=acted+开快创 / `知道了`=dismissed)→ 忽略收「...」chip(点击再现)+ 🐾 进**feed**(点击重开);启动拉 pending 恢复安静态;抑制页跳过 peek | 到达醒目→安静→feed 可找回 ✅ |
| **前端 · 傻瓜护栏(✅,权限请求后置)** | 零配置;静默 22-08 自动;**自适应**(同习惯连续 2 条未理→退避 72h、acted 恢复);默认 ON + 「球球提醒」总开关(REKA 通知面板顶部,`users.prefs`)。**系统推送的温柔权限请求随 APNs 基建后置**(v1 投递=应用内 SSE,正是「拒绝→应用内提醒」的底线形态) | 不配置即用;连续忽略后自动少提醒;夜里不打扰 ✅ |

**护栏铁律(承 §7.0/§9.0)**:邀请非命令、不愧疚、不攀比、一键「球球安静一会儿」。**对老人尤甚 —— 错时/愧疚提醒会伤关系。**

---

## Phase 3 · 晨间简报（§14.6）—— ✅ 已实现（2026-06）

| 面 | 做什么 | 验收 |
|---|---|---|
| **后端(✅)** | **`morning-briefing` genre**:`agents/morning_briefing.py` 全确定性内容(早安模板问候 + 今日日程 + 今日待办/逾期〔温柔〕+ 昨日回顾 + 本周进度);`GET /api/briefing/today` 当日幂等;落 `reports` | 首打开秒出(实测 gen_ms≈3ms)✅;报告容器 🌅 可回看 ✅ |
| **前端(✅)** | `morning_briefing_page.dart`:**每天中午前首次打开 → 沉浸式「早安」页**(SharedPreferences 日期戳一天一次;✕ + 「开始今天」pill 双出口;失败静默) | 一天一次、滑走进 app、不困住人 ✅ |
| **🎨 design(✅ 设计稿已有,直接移植)** | 设计包 `morning-brief-a/b.html` 两套沉浸皮逐字移植进 `report_styles.MORNING_CSS`(A 日出暖橙 / B 黎明冷蓝,按日交替);hero+署名挂真实 REKA | 一个「值得期待」的早安时刻 ✅ |

**后置**:天气 chip(定位+API,v1.5)、傍晚 wrap-up、沉浸页随真机反馈再打磨动效。

---

## Phase 4 · Type B 帮你做 + web-search（§14.5 + §14.9）—— 富、涉成本，最后

| 面 | 做什么 | 验收 |
|---|---|---|
| **后端 · offer→报告(✅ 积累型 2026-06;event 型待)** | **积累阈值触发 ✅**:§14.3 积累段(专属技能 + 灵感 domain 双路)→ offer nudge(peek ✨ + 落 feed);**接受 → 一键即做 ✅**(`RekaChat prefillWish` 直接跑 §6 管线);ignore → 72h 自动 ignored ✅。**到期 event 触发**(会前调研 offer + 报告锚定 event + 会后过期)待组装 —— genre/搜索步/offer 壳均已就绪 | 「这周记了 N 条灵感,要我帮你理一理?」→ 一键→出灵感综合报告 ✅(实测);会前调研 offer 待 |
| **后端 · web-search(✅ 2026-06)** | **管线步骤**(非 content-skill 工具):确定性 search → 注入**带出处**资料 → content skill 引用;**grounding 墙**(用户数据 grounded、外部标出处、绝不混写);配额(30/月,只计数不接 billing)。`core/web_search.py`(博查/Tavily key-driven)+ `briefing` genre(dispatcher `search_queries` + `report-briefing` skill + `spec_json.web` 存证 + 优雅降级) | briefing 引用外部且标源;用户数字仍只来自真实记录 ✅(已验证) |
| **前端** | Type B offer 气泡 + 接受流(锚定 session 预置任务)+ ignore/expire 态。**报告入口的手动路径已可用**(「帮我会前调研」→ briefing 报告,带 🔎 标签) | 一键即做、显进度→结果;忽略留 CTA |

**会前调研「调研」到底产什么(web vs 用户数据综合)**:已定 —— 外部画像(标出处)+ 最近动态 + 和你的关联(用户记录)+ 可聊的/注意的 + `:::actions` 准备动作 + 来源(见 `report-briefing/SKILL.md`)。

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

- **prompt(spec 侧)**:`:::actions`(✅ idea-synthesis + proposal 内容 skill 均已补:方向/下一步写成 `:::actions`,渲染为只读 ✦接下来 清单,后续被原生行动条抽成 +待办)+ 晨间简报 genre 内容 skill(若用 LLM 串场)+ web-search 引用纪律。**渲染器加固**:`_split_blocks` 容忍 flash 把 fence 写成反引号包裹(`` `:::rank` `` → 顶格 `:::rank`),避免整块当普通文字泄漏。Type A/offer **文案是模板字符串**(给 copy 规格即可,非 LLM prompt)。
- **基建(coding agent)**:`suggested_actions` 抽取+迁移、原生行动条、`source_report_id`/`source_nudge_id`;heartbeat、统计 profile、触发引擎、`nudges` 表、peek 气泡、feed 回溯、傻瓜护栏、Type B offer 流、web-search 管线步。
- **🎨 design(设计流程)**:**晨间简报沉浸式皮**(`/design-shotgun`→`/design-html`)+ nudge peek 气泡/「...」视觉打磨。

## 共享数据模型(一处看全)

- `reports.suggested_actions`(§6.13)· `assets.source_report_id` / `assets.source_nudge_id`(溯源)。
- `nudges`(§14.10:type/kind/text/ref/status/outcome/expires_at)· `rhythm_profiles`(§14.10:cadence/typical_times/weekdays/confidence)。
- 晨间简报 = `reports` 行(genre=`morning-briefing`),不另设表。
