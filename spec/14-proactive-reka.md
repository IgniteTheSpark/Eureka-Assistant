# 14 · 主动 REKA（陪伴层）

> **状态：Phase 2 核心 + Phase 3 晨间简报 + Phase 4 积累型 offer 已实现(2026-06)** —— heartbeat + 统计节律 +
> 缺口→Type A 提醒 + **积累→Type B offer(一键即做)** + peek/💡/展示回溯 + 傻瓜护栏 + 晨间简报(沉浸双皮,
> 详见各节 ✅);仅剩**会前调研型 offer**(event 扫描 → briefing 锚定到会议)待组装。
> 让 REKA 从「你来找它」变成「它陪着你」—— 在合适的时间主动提醒、主动帮你做点事。
> **目标人群 = 普通人**(宝妈 / 保姆 / 老人 / 学生党):有记录需求、但**不懂也不想配置**推送和定时任务。所以本层的第一性原则是 **零配置**:
> **不是「你设定提醒」,而是「REKA 看懂你的节律,替你记着」。** 全程 [§7.0](07-gamemode.md)/[§9.0](09-pet.md) 的**温柔护栏**:是邀请不是命令、不愧疚、不攀比、一键安静。

---

## 14.0 一句话架构：两类 nudge，复用两个既有系统

**整个陪伴层 = 在你已有的两个系统上加一个「定时大脑」。** 不造新输出机器:

| | 是什么 | **复用** | 真正新建的 |
|---|---|---|---|
| **Type A · 提醒** | 「该记 X 了 / 别忘了 Y」 | **通知系统**([§3](03-api-reference.md) / [§9](09-pet.md) 的 feed + 角标 + 回溯) | ① task-skill 完成通知(补缺)② **节律缺口**提醒(新,靠 §14.3 profile) |
| **Type B · 帮你做** | 「要我帮你产一份 X 吗」 → 产出**报告** | **报告引擎**([§6](06-synthesis-report.md))+ 报告容器 | 主动触发 + offer→报告流;**web-search 能力**(§14.9) |
| **晨间简报** | 每天第一次打开的沉浸式「早安」 | **§6 报告 genre** + 报告容器 | **定制沉浸式呈现**(design 主理,§14.8) |

新建的工程量其实很小:**定时器(cron/heartbeat)+ 节律 profile(统计)+ 晨间简报 genre + 沉浸式皮**。其余全是组合既有件。

---

## 14.1 引擎 ①：cron / heartbeat（✅ 已实现 2026-06）

> **落地**:`core/companion.py companion_loop` —— main.py lifespan 里与 reminder_loop 并列的 asyncio 循环,
> 30 分钟一跳;每个北京日的首跳顺带做离线日任务(节律重算 + 昨日未处理 nudge 标 `ignored`)。
> 全程确定性 SQL,**零 per-tick LLM**(文案纯模板)。

- **cron** = 排期的扫描(每 ~30 分钟一跳,或在「饭点 / 早 / 晚」锚点);**heartbeat** = 每用户「醒来 → 廉价检查 → 决定」的循环。
- **成本铁律(关键)**:「该不该提醒」的检查**必须确定性 + 廉价**(扫到期 todo/event、查节律缺口 —— **零 LLM**)。**只在真要发时**才生成文案(模板优先,或一次极小 LLM)。**绝不**每用户每跳跑一次 LLM —— 以本人群规模那会炸 [§12](12-business-model.md)。绝大多数 Type A 文案纯模板(「🐾 别忘了 {todo}」)。
- **是既有 daily-gen 的延伸**:[§1.8c](01-agent-architecture.md)/[§7.3](07-gamemode.md) 的 daily-gen 是「每天生成今日计划」;heartbeat 把它扩成「**日内也能醒来发提醒/给 offer**」。

---

## 14.2 引擎 ②：节律 profile（统计，非 LLM）（✅ 已实现 2026-06）

> **落地**:`core/rhythm.py` —— 28 天窗口、每技能 ≥5 条才建 profile;cadence=相邻间隔中位数、
> time-of-day=±1h 平滑 24 桶直方图取峰(typical_hours ≤3 个)、weekday=非零日集中时记子集、
> confidence=min(1, n/14)×峰窗占比;每日离线重算落 `rhythm_profiles`,heartbeat 只读。
> todo/event 不参与(它们有显式提醒);技能停记 → profile 自动删除(不催已放弃的习惯)。

> **如何提炼用户习惯。** 结论先行:**用统计,不用 LLM** —— 「用户一般几点记早餐」是个数学问题,`median()` 比 LLM 更准、更便宜、可审计;LLM 会幻觉出不存在的规律,且按用户计费。**老人的吃药时间不能交给会编的模型。**

**生成过程(每用户、每习惯技能):**
- 输入 = 该技能记录的**时间戳**序列。
- 算:
  - **节奏 cadence** = 相邻记录间隔的**中位数**(中位抗离群)→「约每 3 小时」/「约每天」。
  - **时段 time-of-day** = 记录小时的直方图 → 峰值窗口 →「早上 8 点前后」。
  - **星期 weekday** = 按周几的分布 → 集中则标(「周一三五」)。
  - **置信 confidence** = 样本量 + 方差;**低于阈值 → 不提醒**(数据不够别瞎猜)。
- **重算** = 每天一次离线 job,落一份紧凑 profile blob/用户;heartbeat 只**读**它(廉价)。
- **冷启动**:数据不足前**不发**节律提醒(可选:LLM/类目先验给个合理默认 —— 锦上添花,非必需)。

**LLM 的位置(可选,非核心)**:① 冷启动先验;② 更自然的提醒文案(但模板足够,v1 用模板)。**profile 本身 = 纯统计。**

---

## 14.3 触发规则：缺口 → Type A，积累 → Type B（复用 §7.3）（✅ 均已实现 2026-06）

> **落地(缺口→A)**:`core/companion.py scan_once` —— confidence ≥0.45 的 profile,在「峰值小时+1h ~ +3h」
> 窗口内若该技能今天还没记录 → fire(每习惯每天最多一条;weekday 型只在其集中日触发)。
> **落地(积累→B)**:同一 scan 先跑积累段(offer 更稀有、更贵重,与提醒共享每天 ≤2 上限)——两类来源:
> ① 专属技能(idea/记账类 machine/display 匹配,7 天 ≥5/≥8 条);② **灵感 domain**(§8,多数用户的灵感
> 是「随记 + 灵感域」而非独立技能,7 天 ≥5 条)→ `✨ 这周记了 N 条灵感,要我帮你理一理?` offer
> (kind=offer,cta=synthesize,ref=技能名或 `domain:灵感`,72h 过期)。防重:每习惯每周最多一条 offer;
> **刚综合过同 genre 报告 → 静默,除非那之后又攒满阈值条新记录**(新一批配得上新 offer)。

profile + 当前状态 → 喂一个触发引擎,两族规则(**正是 [§7.3](07-gamemode.md) 已设计的「缺口型 / 阈值型」**,这里靠 profile 定时、靠 heartbeat 推送):

| profile 信号 | → | nudge | 例 |
|---|---|---|---|
| **缺口**(你一般这点已记 X,还没记) | → | **Type A 提醒** | 「该记早餐了?」→ [记一笔] |
| **积累**(攒够 X、值得梳理了) | → | **Type B offer** | 「这周记了不少消费,要我帮你理一理?」→ 报告 |

心智模型:**缺口 → 「去做」(A);积累 → 「让我帮你理顺」(B)。** 一份 profile,两种产出。

> **积累→Type B 按内容类型分流到不同报告 genre**(都走 §6 管线,§14.5):消费积累 → `data-report`(理一理);**灵感**积累 → `idea-synthesis`(升华);**学习类知识**积累(单词/读书/学习笔记,§8「学习」域)→ **`quiz`/`flashcard`**(「这周记了 20 个新词,要考考你?」,[§6.14](06-synthesis-report.md))。**灵感不触发 quiz、代办不触发 B**(代办是 Type A 提醒)—— 见 §6.14 选材 gate。

---

## 14.4 Type A · 提醒（= 通知系统 + 两处增量）（✅ 已实现 2026-06）

- **显式 ahead-of-time(已具备)**:会前、todo 到期前的提醒,现有通知系统已能定时 fire。
- **增量 ①:task-skill 完成通知(✅ 早已存在)**:`agents/task_skill.py` 完成/失败均走 `create_notification`
  (M6 反应式族)—— 盘点后确认无缺口,无需新建。
- **增量 ②:节律缺口提醒(✅ 2026-06)**:由 §14.2 profile + §14.3 缺口规则驱动,「你一般这点记 X,还没记」→ [记一笔]。**有置信门槛**,不确定就不发。落地:nudge 落 `nudges` 表 + 走 `create_notification(type=nudge, link=nudge:<id>:<skill>)` 进 feed/SSE;移动端把 type=nudge 渲染成 REKA peek 气泡(不是普通 toast)。
- **文案**:模板为主(零 LLM);动作 = [记一笔](一键开快创对应技能)/[知道了]/[改时间]。
- **展示与回溯**:走既有通知 feed(§14.7)。

---

## 14.5 Type B · 帮你做（= 主动触发报告 + web-search）

> **统一:Type B 的产出永远是一份「报告」**(进报告容器),不是一段聊天。理由:报告是**可看、可存、可分享、带 REKA 署名**(§6.6.1)的实在产物;一句聊天会蒸发。用户的每个「接受」都换来一个**作品**。

**映射(都是 §6 的 genre):** 聚合想法 → `idea-synthesis`;消费分析 → `data-report`;weekly recap → `digest`;会前调研 → **briefing**(web-search 开,§14.9)。

> **✅ briefing genre 已实现(2026-06,手动路径)**:报告入口说「帮我做 X 的会前调研 / 调研一下 Y」→ dispatcher
> 判 `briefing` + 产 `search_queries` → 管线跑 §14.9 搜索步 → 内容 skill(`report-briefing`)产带出处简报
> (含 `:::actions` 会前准备动作 → §6.13 一键加待办)。
>
> **✅ 积累型 offer→报告流 已实现(2026-06)**:§14.3 积累触发产 Type B offer(peek 气泡 ✨)→ 点开
> **[✨ 帮我理一理] = 一键即做**:标 acted → 直接进 REKA 洞察气泡用内置 wish 生成(`RekaChat prefillWish`,
> 不用打字,显进度 → 出报告进容器);[知道了] = dismissed;忽略 → 72h 后自动 ignored(过期归档)。
> 实测全链路:6 条灵感攒满 → offer 触发 → 一键生成灵感综合报告。
> **会前调研型 offer**(heartbeat 扫到期 event → offer → 报告**锚定到 event**)仍待:差 event 扫描规则 +
> 锚定/会后过期;genre、搜索步、offer 壳都已就绪,纯组装。

**offer → 报告 流(以「会前调研」为例):**
1. **3 点** heartbeat 扫到 **4 点的会**(Type A 同款确定性检测)。
2. **生成 offer 文案**(模板,或为贴主题用一次轻 LLM)。
3. **REKA 旁 peek 气泡** + **落库进 feed**(回溯,§14.7)。
4. **接受(点)** → 跑 §6 报告管线(genre + scope 已内置;会前调研开 web-search)→ 产**简报报告** → 进**报告容器**,并**锚定到那个 event**(会议上下文里看得到)。**傻瓜版 = 一键即做**:点了 REKA 就开始(显进度 → 出结果),用户不用打字;想深入再在该报告的锚定 session 里追问。
5. **忽略** → feed 里留一条 one-liner + CTA [调研],会前一直可点。
6. **过期**(会已过)→ CTA 失效、显**已过期**、自动归档。

> 优雅处:这就是 [§6.13](06-synthesis-report.md)「报告 → 行动」环**反着跑**(REKA 发起);复用**锚定 session**([§1.5.1](01-agent-architecture.md))+ 开场 hint(此处**预置任务**)+ 回溯 outcome。

---

## 14.6 晨间简报（morning briefing）—— 专属的沉浸式产品时刻（✅ 已实现 2026-06）

> 它**本可归进 Type B**(每日主动报告),但要做成**有主观体验的专属 feature**。解法:**生成复用 §6(一个 genre),呈现专属(沉浸皮)。** 一个产物、两个面。

> **落地**:`agents/morning_briefing.py` —— 全确定性查询(今日日程 / 今日到期+逾期待办〔温柔「拖了 N 天」〕/
> 昨日回顾〔含自定义技能按 render_spec 配色的记录 feed〕/ 本周进度环)+ **模板**问候/格言(零 LLM,实测 gen_ms≈3ms,
> 「秒出」达标);`GET /api/briefing/today` 当日幂等(首调生成、再调同行);落 `reports`(genre=`morning-briefing`,
> 报告容器 🌅 回看)。**沉浸皮 = 设计包 morning-brief-a/b 两套逐字移植**(`report_styles.MORNING_CSS`):A 日出暖橙
> (hero+格言+日程卡+待办+昨日回顾),B 黎明冷蓝(居中 hero+今日聚焦卡+本周进度环+紧凑日程),按日交替;hero 与
> 署名都挂**真实用户 REKA**。前端 `morning_briefing_page.dart`:北京时间**中午前**首开(SharedPreferences 日期戳,
> 每天一次)→ 全屏沉浸页(✕ + 底部「开始今天」pill,绝不困住人;失败静默不挡启动)。天气 chip 仍 v1.5 后置;
> 换装(rerender)对此 genre 退化为通用版式(沉浸 html 由构建器持有,非 md 可重建)。

- **触发(三级优先,改自「仅按时间」)**:① **`!spawned`(全新用户)→ 让位给孵化 onboarding**([§9.2.2](09-pet.md)),**不**弹晨报;② 已孵化 + **中午前当天首开** + **有内容**(今日待办/日程/近期记录)→ 进沉浸式「早安」页;③ 已孵化但**数据太薄** → **跳过**(空晨报比没晨报糟),直接进 app。**每天一次、可滑走**(绝不困住人)。
- **内容骨架**(`morning-briefing` genre):REKA **早安**问候 + **今日待办**(daily-gen + 今日到期)+ **逾期**项(温柔,「这几件拖了几天」不愧疚)+ **今日日程** + (**天气**)+ (可选**昨日小结**)。
- **生成廉价**:绝大多数是**确定性数据**(待办/日程/逾期/天气 = 查询,非 LLM),只有问候/串场需要点模型(可模板)→ **首次打开时现生成、秒出、不卡**,无需重型预生成 cron。
- **两个面**:① **沉浸式**(首打开,design 主理皮);② **报告容器**里作「晨间简报」报告留存(**回溯**,可翻看过去的早安 —— 像日记)。复用 §6 md→HTML + WebView + GSAP + REKA 署名。
- **分工**:**内容/数据/genre = 工程**;**沉浸式呈现与装修 = design 主理**(这是个情绪化专属面,渲染为 HTML → 适配 `/design-shotgun` 探样 + `/design-html` 出生产皮,落进 §6 render catalog)。
- **天气 = 外部依赖**(定位权限 + 天气 API),**v1.5 加**;先上不带天气的简报。
- **别变负担**:每天一次、快、可跳过。天天一堵墙 = 用户怕开 app。一拍即过。

---

## 14.7 展示与回溯（nudge 的 UI + 历史）（✅ 已实现 2026-06）

> **落地**:`pet/reka_nudges.dart`(生命周期 store)+ `floating_mascot.dart`(轻 bob 单跳 + peek 气泡
> 8s 自动收起 → 点开可动作面板 [记一笔]/[知道了] → 忽略收成「...」chip,点 chip 再现)+ feed 行(🐾,
> 点击重开 peek)。outcome 走 `POST /api/nudges/{id}/outcome`;app 启动 `GET /api/nudges/pending` 恢复
> 安静态(不重复 bob);被抑制(REKA hero 页)时跳过 peek、回来时见「...」。
> [记一笔] = 标 acted + 打开 REKA 快创气泡(同 radial「快创」流)。

**显示(承 §9 的浮球 + 气泡 + 通知 feed,几乎全是组合既有件):**
- **到达 = 轻 bob + peek 气泡**:浮球**轻轻一弹**(**不是**掉落用的彩纸庆祝 —— nudge 是拍肩,不是开 party),旁边冒一个小气泡:**一句话 peek**(「🐾 该记早餐了?」)。「...」(复用 `_TypingDots`)= 收起后的安静态。
- **点 → 展开**:成完整**可动作**气泡(复用 `reka_chat`):Type A → [记一笔]/[知道了]/[改时间];Type B → [调研]/[看看] 等。
- **忽略 → 不消失、不唠叨**:收成浮球上一个安静的「...」点 + **进通知 feed**(可回看)。生命周期:**到达醒目 → 安静「...」→ 永远可在 feed 找回。**
- **辨识为「主动」**:它**自己冒出来**(对比快创/洞察是你点 REKA 才出),自动到达 + 轻 bob 就是「REKA 主动找你」的签名。
- **被抑制时**(REKA 在孵化/详情/我的岛 hero 页):跳过 peek,直接进 feed + 角标,REKA 回来时再现。

**回溯(必须持久,因为 heartbeat 在服务端、常在用户离线时 fire):**
- 每条 nudge = **服务端持久实体**,进**通知 feed**(时间序,「球球帮你记着的事」)。
- **outcome 状态**:`pending → delivered → seen → acted / dismissed / snoozed / ignored(过期未处理) / expired`。**一举两用**:① 用户端回溯(feed 显「✓ 已记」/「未处理」);② **自适应**(§14.8 靠它退避)。
- **双向溯源**:由 nudge 接受而建的记录带 `source_nudge_id`(同 §6.13 `source_report_id`)→ 记录知道「由球球提醒创建」,nudge 知道它促成了什么。对保姆 = 一份天然护理日志;对所有人 = REKA 显得可靠不掉链。
- **情绪定调**:这份历史读作**「球球一直帮你记着的事」**(陪伴),不是监控日志 —— 对老人/宝妈尤其重要,是他们愿意留着它的理由。

---

## 14.8 傻瓜护栏（这层真正难的地方）（✅ 服务端全套 2026-06）

> **落地(全部服务端、零配置)**:静默 22:00–08:00(北京)/ 硬上限 2 条·天 / 置信门槛 0.45 /
> 自适应退避(同一习惯连续 2 条未理 → 歇 72h;acted 即恢复)/ 总开关 `users.prefs.nudges_enabled`
> (默认 ON,UI 在 REKA 通知面板顶部「球球提醒」开关,`GET/PATCH /api/nudges/prefs`)。
> **注**:v1 投递为**应用内**(SSE + feed;打开 app 即见),系统推送(APNs)及其「温柔权限请求」随
> 推送基建后置 —— 正合「拒绝 → 退化为应用内提醒」的设计底线。

- **零配置**:不设日程表。Type A 显式提醒 day-one 就有;节律提醒攒几天数据后自动开;晨间简报开箱即用。
- **一次温柔的权限请求**:在**好时机**(他们已记了几条之后)、用 **REKA 口吻**问「让球球在你忘记时轻轻提醒你?」,**不是**首次启动那个吓人的系统弹窗。拒绝 → 退化为「打开 app 时的应用内提醒」。
- **静默时段自动**:默认夜里不打扰(或学其活跃时段),无需配置。
- **自适应 = 去掉设置页的关键**:**忽略 → REKA 退避(少提醒);采纳 → 继续。** 靠 outcome 状态(§14.7)自调,用户**永不**需要进设置页调频率。
- **硬上限 ~1–2 条/天**:通知疲劳是本人群卸载的头号原因。
- **温柔铁律(承 §7.0/§9.0)**:邀请非命令(「还没记哦,要记吗?」**绝不**「你又忘了!」)、不愧疚、不连胜攀比、一键「球球安静一会儿」。**对老人尤甚** —— 错时或愧疚的提醒会伤关系,温柔/易静音/自适应不是打磨而是安全。
- **默认 ON**(本人群不会自己去开),但配上面的强自适应 + 静默默认,确保不烦。一个总开关「球球提醒」给想关的人。

---

## 14.9 web-search 能力（✅ 已实现 2026-06）

> Type B 的报告常需外部资料 reference/investigate。给报告引擎加 web-search。**它触及整个 §6,不只主动层,故单列。**

- **架构落点 = 管线步骤,不是 content-skill 工具**:content skill **刻意无工具**(数据预注入,因 DeepSeek 工具调用不稳,§6 既有偏差)。所以**管线确定性地先 search → 把结果当「带出处的资料」注入** → content skill 引用它写报告。保持 content skill 无工具、搜索受控。
- **grounding 墙(关键)**:**用户的数据照旧 grounded**(他的数字/记录是真的,§6.3);**外部信息一律标外部 + 标出处**(「据公开资料…」),**绝不**和「用户数据的事实」混写。把铁律扩成:**每条外部主张都能追到来源**(如每个数据点能追到 asset)。
- **成本/门控**:search + 更多 token + 延迟 → **Pro 门控或配额**(同 AI 图);只给受益的 genre(briefing/research 必开,其余可选)。
- **provider**:Tavily/Serper/Brave/Bing 或带搜索的模型,择一接;结果存证、可引用。

**落地(✅ 2026-06)**:`core/web_search.py` —— key-driven provider(同 LLM 选型逻辑):`BOCHA_API_KEY` → 博查
(api.bochaai.com,国内 inbound 可靠,prod 首选);`TAVILY_API_KEY` → Tavily 兜底;都空 → 搜索关闭。
仅 `briefing` genre 触发:dispatcher 产 `search_queries`(1~3 条)→ 管线 `search` 阶段确定性检索(≤3 查询、
合并去重 ≤10 条、单查询超时 12s、单查询失败不连坐)→ 注入 `web:[{title,url,snippet,source,date}]` →
`report-briefing` 按 grounding 墙引用。**存证**:queries + sources + provider + status 落 `spec_json.web`。
**配额**:30 篇 briefing/用户/月(镜像 AI 图配额;只计数+硬上限,不接 billing,§12 pending)。**降级**:无 key /
超配额 / 零结果 → briefing 照常生成(仅用户数据 + 如实说明未联网),管线绝不因搜索步而失败。

---

## 14.10 数据模型（增量）（✅ 迁移 0019,2026-06）

- **`nudges`(主动提示,持久)**:`{id, user_id, type(A|B), kind(reminder|rhythm_gap|offer|briefing|…), text, body, ref?(todo/event/skill/domain), cta?, status(见 §14.7 outcome), source(scheduler|rhythm), created_at, delivered_at?, acted_at?, expires_at?}`。进通知 feed;outcome 驱动自适应。
- **`rhythm_profiles`(节律,每用户每技能)**:`{user_id, skill, cadence_minutes, typical_hours, weekdays, confidence, sample_n, computed_at}`。每日离线重算;heartbeat 只读。
- **`users.prefs`(JSON)**:v1 仅 `nudges_enabled`(§14.8 总开关,默认 ON)。
- **复用**:通知 feed(§3/§9)、`reports`(Type B/简报产物,§6.7)、`assets.source_nudge_id`(溯源)。
- **晨间简报** = `reports` 行(genre=`morning-briefing`),不另设表。

---

## 14.11 成本（系于 [§12](12-business-model.md)）

- **Type A + heartbeat + 节律**:模板 + 统计 + 确定性检查 = **近乎免费**(无 per-tick LLM)。
- **Type B 报告**:一篇报告成本(§12.1)+(若开)web-search 成本 → **Pro 门控/配额**。
- **晨间简报**:大半确定性数据 → 便宜。
- **配额**:Type B 主动报告 + web-search 计入 §12 的报告/搜索配额;别让 heartbeat 变成烧钱阀。

---

## 14.12 v1 范围与后置

- **v1 必做**:① task-skill 完成通知(✅ 盘点确认早已存在)② cron/heartbeat + **统计节律 profile** + 缺口触发(✅ 2026-06;积累→B 触发随 Phase 4)③ Type A 节律缺口提醒(✅ 模板、置信门槛、≤2/天、自适应、温柔)④ 展示(✅ 轻 bob + peek 气泡 + 「...」安静态 + feed 回溯 + outcome)⑤ **晨间简报**(✅ genre + 内容 + 沉浸双皮〔设计稿移植〕+ 报告容器留存)⑥ 傻瓜护栏(✅ 零配置 / 静默时段 / 自适应 / 默认 ON + 总开关;系统推送权限请求随 APNs 后置)。
- **紧随**:~~积累型 offer→报告流~~ ✅ 已实现(一键即做);~~web-search 能力(§14.9)~~ ✅ 已实现;
  剩**会前调研型 offer**(event 扫描 → briefing 锚定 event + 会后过期)与 `source_nudge_id` 溯源
  (`source_report_id` 已落,offer 生成的报告回链 nudge 待加)。
- **后置**:天气(晨间简报 v1.5)、LLM 富化文案/冷启动先验、跨技能相关性节律、傍晚 wrap-up、caregiver 护理日志视图。

> **实施 handoff(与 [§6.13](06-synthesis-report.md) 报告→待办合一,因同一闭环)= [`handoff-reka-companion.md`](handoff-reka-companion.md)**:Phase 1 报告→待办 · Phase 2 主动核心(提醒+引擎+展示+护栏)· Phase 3 晨间简报(design 主理皮)· Phase 4 Type B+web-search。含后端/前端/design 分工 + 验收 + 顺序。
