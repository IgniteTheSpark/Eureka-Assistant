# Handoff · 日历（流 / 月 / DayDetail）时段分组 + 闪念移出流

> **⚠️ 范围更新（2026-06）**：本卡现在 = **日历侧**（流 / 月 / DayDetail 段视图 + 闪念移出流，大多**已落地**）。**「今日页」已重新定义**为首页 landing（Next Action + 气泡池），**实现卡见 [handoff-today-landing.md](handoff-today-landing.md)**；下文凡提"今日页 = 段视图"的均**作废**（段视图归日历，不归今日页）。
>
> 一句话（原）:日历的一天渲染从「按时间戳排一条流」改成「5 时段 + 闪念 chip」;原始闪念移出流 → `⚡N` pill。
> 规则真值见 [§4.5.0 / 4.5.0a / 4.5.0b](04-frontend.md) · [§2 §3.6 assets.period/occurred_at](02-data-model.md) · [§1.3 时段抽取](01-agent-architecture.md) · [§14.6 晨报并入今日页](14-proactive-reka.md)。
> **产品已拍板的决策**(2026-06):
> ① 今日页做 tab0、日历收进 📅、底部仍 3 tab、Reka 留在浮球+我的岛(不挂今日页);
> ② **没说时间 → 用捕捉(闪念)时刻落段**(默认即捕捉时刻);**`period` 只为"用户说了模糊时段"兜底**、`occurred_at` 只为"说了钟点"精确排序;**没有"无时间"大桶**;
> ③ 晨报并入今日页 hero;
> ④ 闪念移出流但**产出卡留时段**;
> ⑤ 空段**两处都折叠**(不画固定骨架)。

---

> ### 实施状态(✅ 2026-06,真值见 [§4.5 落地块](04-frontend.md))
> **已落地**:数据列 `period`/`occurred_at`([§2](02-data-model.md))+ agent 时段抽取([§1.3](01-agent-architecture.md));段视图(DayDetail 非日程 = `DayRender`、流/月 = stream-safe `_BandView`,同段逻辑);今日页骨架;闪念移出流 + pill;日历降级到 📅;月**单网格** + 选中日 footer;晨报并入今日页 hero([§14.6](14-proactive-reka.md))。
> **本轮设计迭代(覆盖本卡下面的旧描述):** 流改 **左日期/右内容 两栏**(左列 日期 + `⚡N` pill sticky 一起滚、右内容各时段 block 装进一个「day 容器」、**无固定 content header**);**闪念 pill = 「⚡N」(去「闪念」字),点 → 直接进「X月X日 闪念」session**(**去掉 `DayFlashView` 当日列表过渡页**);**没说时间** = 底部「**没有时间**」兜底段 +（说了时段没说钟点的）沉该段段尾、虚线、不显时刻;**月 footer = sticky 日头**(日期·周几 + `⚡N` 最右,**无时段、无「更多」**);**空日 = 更宽的斜纹空块 + 两段式引导语**(点空块露引导语、再点才弹 sheet);**领域 tag 进流/月卡片**(timeline item 加 `domain`)。
> **❌ 砍掉**:本卡「前端 · 纠错(时段选择器)」—— 经用户确认多余,asset 详情/编辑的时段 picker **已移除**(`asset_detail_sheet.dart` 不再有 `_pickPeriod`)。
> **⏳ 下一步(Part B,未做)**:DayDetail「日程」24h 网格放**待办**(有时刻小块 / 撞长事件 = 带标题瘦 chip / 同点 N 个 = 计数 chip 点开 / 无时刻 = 顶部「待安排」条)+ **重叠分列规则** + 结果记录收进顶部「记录·按类型」定高容器。设计见 [`handoff-calendar-design.md`](handoff-calendar-design.md) §B + 线框 `日历改版线框.dc.html`。

## 这条弧线（实现目标）

```
今日页(tab0) = [上午首开:晨报 hero] → header(日期 + 📅) → 今天的「一天渲染」
「一天渲染」= 凌晨/上午/中午/下午/晚上(空段折叠)，每段卡按"有效时刻"升序；
            没说时间的按捕捉时刻落到当下段；说了模糊时段的归该段；
            段末一条 ⚡N条闪念 chip → 当日闪念视图
日历(流/月/年) 经 📅 进入；流里每一天复用同一套「一天渲染」
```

## 落段判定（一处看全，前端核心逻辑）

```
对一条 item（按优先级）:
  day = 说了的日期(明天/周一/…) ?? 捕捉日
  if occurred_at || event.start_at:  段 = periodOf(时刻); 显时刻; 段内升序     // 事件只认 start_at,忽略 end_at
  elif period(只说了模糊时段):        段 = period; 进该段「没具体时间」组(不显时间、不按捕捉时刻排,即使此刻就在该段)
  elif day == 捕捉日:                 段 = periodOf(created_at); 显捕捉时刻       // 啥也没说→捕捉兜底
  else:                              该天**底部「没说时间」组**                  // 异日(昨天/前天/周一)、无钟点无时段
全天事件(全天开关): 该天**顶部「全天」条**。 空段折叠(两处都折叠)。
跨天: 产出落"那天"的流；捕捉日只闪念 chip +1(§4.5.0b)。 todo 无截止: due_at 留空。
```

时段区间:凌晨 00–05:59 / 上午 06–11:59 / 中午 12–12:59 / 下午 13–17:59 / 晚上 18–23:59。
`periodOf(t)` = t 的小时落哪个区间。**有效时刻 = `occurred_at` ?? event `start_at` ?? `created_at`**。

## 实施范围

| 面 | 做什么 | 验收 |
|---|---|---|
| **数据模型** | `assets` 加两列(迁移待定):`period`(String(8) nullable ∈ 凌晨/上午/中午/下午/晚上)、`occurred_at`(TS nullable,内容指向的精确时刻,**≠ created_at**)。v1 不加索引(按 date 取当天后内存分段)。 | 迁移跑通;两列可空、老数据 null 不报错 |
| **agent · 时段抽取** | flash + chat 的 sub-skill 落 asset 时,**只在用户明说时间时**抽:说钟点→`occurred_at`(+推 `period`);只说模糊时段→`period`;**没说→都 null、不臆造**(落段交给前端按 `created_at` 兜底)。`tool_create_asset` 增 `period?`/`occurred_at?` 参。一句话多意图各自抽。**todo 无截止 → `due_at` 留空**。 | 「下午3点开会」→occurred_at=15:00;「早上花了8块」→period=上午;「买了瓶水」→都 null(前端按捕捉时刻落段) |
| **前端 · 一天渲染 DayRender** | 新组件:5 时段(**无"其他"大桶**),**按优先级落位**:①说钟点(或 event `start_at`)→该段显时刻;②只说模糊时段→该段「没具体时间」组(不显时间、不按捕捉时刻排,**即使此刻就在该段**);③啥也没说→捕捉时刻 `created_at` 落当下段显时刻;④异日→那天的流。**event 只认 `start_at`、忽略 `end_at`**。全天事件→顶部「全天」条;异日(昨天/前天/明天)无时刻无时段→该天底部「没说时间」组。**空段折叠**。卡复用 `SkillCard`+领域 chip。 | 11点说「早上吃饭8块」→上午·没具体时间;「早上8点」→上午8:00;啥没说→上午11:00;「明天晚上8点」→明天·晚上、今天只闪念+1 |
| **前端 · 今日页 TodayPage** | tab0 落点改为 TodayPage(不再是 CalendarPage 流·今天)。结构:晨报 hero(上午首开,折叠)→ header(日期 + 📅→CalendarPage)→ 今天的 DayRender。**Reka 不挂这页**(仍浮球+我的岛)。 | 进 app tab0 = 今日页;📅 进日历;晨报上午首开在顶部 |
| **前端 · 闪念移出流 + DayFlashView** | 删 `FlashItemRow`(流内 ⚡ 行)。每天一颗 `⚡ N 条闪念` pill 挂在**日 header**(流 tile 头 / 今日页 header / DayDetail 顶部,**「日程」「非日程」两模式位置一致**;N=0 不显)→ `DayFlashView`(按 date 聚合当天 flash 捕捉,倒序列时刻+摘要+产出卡,点条进该捕捉 SessionDetailPage)。**产出的结构卡留在时段流**,只移走原始捕捉。纯随记(无产出)只在 DayFlashView。 | 流变干净;header 点 pill 看当天所有闪念;待办/名片仍在时段里 |
| **前端 · 日历降级** | CalendarPage(流/月/年)改从今日页 📅 进入(不再是 tab0)。流里每一天复用 DayRender(时段 + 闪念 chip),**空段折叠**。 | 日历可正常回看;每天都是时段视图 |
| **前端 · 「日程/非日程」toggle + 各面默认** | **一个 toggle、两模式(现有名称「日程/非日程」)**:**「非日程」= 上午/下午/晚上 分段**(事件只显开始,取代旧"按类型 tab 列表")⇄ **「日程」= 24h 网格**(事件 start–end 时长块、全天置顶、无时刻捕捉走顶部类型 tab,保留)。**默认**:今日页/流 = **「非日程」**;DayDetail = **「日程」**(钻进去看日程)。移除旧「列表(effective_at 排一条)」(并入非日程)。 | 今日页进来=非日程;3–5点的会:流=下午一条记录、DayDetail 日程=2h 块 |
| **前端 · 纠错** | 卡详情/编辑加轻量**时段选择器**(上午/中午/下午/晚上/凌晨/不指定)+ 可改钟点,跟 §8 domain 选择器同形。 | agent 放错段,用户一点就挪;改钟点自动重算段 |
| **晨报并入(§14.6)** | `morning_briefing_page.dart` 的独立沉浸页 → 改为今日页顶部 hero(上午首开折叠展开,✕/「开始今天」收起)。三级 gating 不变。沉浸皮迁为 hero 皮。 | 晨报作为今日页 hero 出现,不再是单独一屏 |
| **🎨 design** | ① 今日页整体(晨报 hero + 时段流的节奏/呼吸感)② 段头(🌅🌆🌃…)+ 段内卡 + 沉段底"没钟点"卡的视觉 ③ `⚡N条闪念` pill + DayFlashView + 顶部「全天」条 + 底部「没说时间」组 | 今日页"值得每天打开";时段读起来像一条温柔的时间线,不像表格 |

## 依赖 / 顺序

- **数据列 + agent 抽取** 是地基(先上);没抽到时间也能跑(全按捕捉时刻落段,降级不崩)。
- **DayRender** 是复用件,**今日页 / 日历流** 依赖它(DayDetail 是另一镜头 = 24h 网格、已实现保留)—— **先做 DayRender,再组今日页和改日历**。
- **闪念移出 + DayFlashView** 独立于时段分组,可并行。
- **晨报 hero** 依赖今日页骨架(hero 是它的第一段)。

## Out of scope（别做）

- 不给今日页堆 Reka 主动内容(nudge/offer/问候)—— 那些留在浮球雷达菜单 + 我的岛(经产品确认)。
- **不给 todo 的 `due_at` 写死捕捉时刻**(会被 §14.6 误判逾期)—— 落段用 `created_at`、`due_at` 留空;无期待办要不要催另在 §14 议。
- 不画固定 5 段骨架(经产品确认:两处都折叠空段,最轻)。
- 不动 flash 的数据模型(仍 session_type='flash' + date);DayFlashView 只是按 date 聚合渲染。
- DayDetailPage 的 24h 日程网格(精确排程视图)保留,与时段流并存(时段流=捕捉向,网格=排程向)。

## 读这些

[§4.5.0 今日页](04-frontend.md) · [§4.5.0a 一天渲染](04-frontend.md) · [§4.5.0b 当日闪念](04-frontend.md) · [§2 §3.6 assets](02-data-model.md) · [§1.3 时段抽取](01-agent-architecture.md) · [§14.6 晨报](14-proactive-reka.md) · §8 领域(段内卡的领域 chip)。

## 分工

- **后端 / agent(coding agent)**:assets 两列迁移 + `tool_create_asset` 新参 + sub-skill"只在明说时填、不臆造"的时段抽取 prompt;DayFlashView 的按-date 聚合接口(若需要)。
- **前端(coding agent)**:DayRender(有效时刻落段 + 捕捉兜底 + 沉段底 + 顶部 pinned)→ TodayPage(hero + DayRender)→ 闪念 chip + DayFlashView → 日历改 📅 入口 + 流复用 DayRender → 时段选择器纠错 → 晨报改 hero。
- **🎨 design(设计流程)**:今日页 + 时段流 + 段头/chip/DayFlashView 视觉(`/design-shotgun`→`/design-html`)。

## 护栏（承全局）

- **零配置**:时段是 agent 按"用户说的"归 + 捕捉时刻兜底,用户不用选(放错了能一点纠正,但不逼他填)。
- **不丢东西**:闪念移出流 ≠ 删掉 —— chip + DayFlashView 一定能找回;产出卡留在流里。
- **时间线总是活的**:默认捕捉时刻落段 → 不会出现"大半内容堆在无时间桶、时段全空"。
- **今日页不困人**:晨报 hero 可收、每天一次;不是一堵墙。
