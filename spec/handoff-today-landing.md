# Handoff（工程）· 今日页 landing 实现 — 给 coding agent

> **今日页 = 首页 tab0 landing**，两块：**① Next Action** + **② Recorded（Dashboard + 气泡池）**，浮在一个全屏物理气泡场之上，Reka 浮球在最上层。
> **三份真值**：逻辑 / 数据 / 决策 = [§4.5.0](04-frontend.md)；**hifi 视觉 / 动效 / 物理参数 = [prototype-today-page.md](prototype-today-page.md)**（用户原型 README，逐字）；设计意图 = [handoff-calendar-design §E](handoff-calendar-design.md)。
> 本卡 = **实施范围 + 对齐 + 复用 + 别做 + 顺序**。

---

## 0. 对齐（按 spec、别照原型 demo 的这几处）

- **域色 = §8 八色**（工作/学习/健康/运动/社交/娱乐/生活/灵感）—— 原型写的 6 色 /「财务」是 demo 样本，忽略；记账记录的域 = 生活（[§5.1](05-design-system.md) / §8）。
- **闪念 = `⚡N` pill → 当日 flash session，不进池、不是记录类型**（原型把 flash 当一种记录类型，去掉它的池气泡 + 类型 chip）。
- **早报 merge 进 Next Action**（不再独立晨报页，[§14.6](14-proactive-reka.md)）。
- **Reka = 全局悬浮球**（已存在，§9.2），不当首页主角、不做仪表盘。
- **不 port `support.js`**（原型运行时引擎）；**不建原型右侧 DEMO 面板**（重力按钮 / 晃一晃 / 记一条 / 场景切换 = 调试架）。
- **nav = 今日 / 日历 / 资产**（日历回底栏 tab）；**我的岛 → Reka 浮球雷达菜单**（[§4.1](04-frontend.md)）。

## 1. 实施范围

| 面 | 做什么 | 验收 |
|---|---|---|
| **nav 改** | 底栏 dock = `[今日][日历][资产]`；今日 tab0 落点 = `TodayPage`；「我的岛」从底栏移除 → 进 Reka 雷达菜单。 | 三 tab；岛从浮球菜单进；今日 tab 落 TodayPage |
| **Part 1 · Next Action** | 扇形卡叠（C-fan：2 虚化 peek 卡 + 焦点卡，**焦点卡固定高**事件/待办不变形）；左右滑切上/下一条、到点/完成前移；头部可折叠（`接下来`+`1/3`+caret）。**事件卡** = 每秒倒计时 + 进度条 + 🔔提醒 + 在日历看；**待办卡** = 备注 + 完成✓。下方 `🕒 无时间待办 N ▾` 展开虚线列表（域点+标题+圆勾选）。**早报 merge** 进来。空态 🌤️。 | 卡叠可滑、倒计时每秒走、完成/到点前移、无时间待办展开、空态 |
| **Part 2 · 气泡池** | 全屏后层（在面板之后、不与面板碰撞）。一条记录 = 一颗气泡（**域色填充 + 类型 emoji glyph**）。**点→详情 sheet；拖→抛；倾斜手机→重力跟随；新记录从顶 drop-in**。物理：无壁盒（地板在 nav 上方 / 天花近顶 / 左右壁）+ nav 胶囊作 AABB 碰撞体 + 圆-圆碰撞 + 多趟松弛(~14) + **休眠去抖**（g≈.44 / 弹性≈.22 / 阻尼≈.97 / 限速）。空态 🫧。 | 气泡正确落色/glyph、点开、拖抛、倾斜滚、新记录掉入、静止不抖 |
| **Part 2 · Dashboard** | 可折叠；**无记录整块隐藏**。头 `今天 N 颗` + `⚡N` 闪念 pill（→ 当日 session，**非筛选**）+ caret。**类型 chips**（`全部 N` + 出现的类型：📌待办 💰记账 👤名片 📝笔记 🎾运动 + 自定义；**无闪念 chip**）→ 点击**同时筛池 + 重算 summary + 重算图**。**summary 速览条**（见 §3）。**三图表**（玫瑰/柱状/树图，下方选择器 + 滑切；`全部`按类型 / 选某类按领域，**按条数**）。 | chips 筛池且重算；summary 随 chip 变；三图可切、drill 正确 |
| **记录详情 sheet** | 底部 sheet：域色圈 + 类型 glyph + 标题 + meta + 两 pill（类型、领域）。 | 点气泡/卡 → 开详情 |
| **4 边态** | 完整一天 / 只有日程·无记录（dashboard 隐、池空态）/ 只有记录·无日程（Next Action 空态）/ 全空·清晨。 | 四态都正确 |

## 2. summary 速览条（不强行 generalize —— 关键）

自定义字段无法判断哪个数字是关键，所以**只特化少数已知类型，其余只显"今天最新一条"**：
- **记账（特化）**：最新一笔（标题 + ¥）· 今天最大一笔（¥X）· **右侧大指标 = 今日总消费 `¥sum`**（¥ 从 payload 金额字段取/求和）。
- **其他所有类型（默认，含待办/名片/笔记/运动/自定义）**：**今天最新收录的那一条**（图标 + 标题 + 时间），不算聚合。
- **全部**：今天共 N 条 + 最新一条预览。
- 图表不受此限 —— 按**条数**分组（类型/领域），与自定义数值无关、照常通用。

## 3. 数据（无新模型，全用现有）

- **Part 1 chain** = 今日及临近 `events`（`start_at` > now）+ 到期 `todo`，按时间串；无时刻 todo → 「无时间待办」展开区。
- **Part 2 池** = `assets` where **`created_at` 在今天**（含闪念产出 + 手动建的）；**排除**原始闪念 `input_turn`（闪念走 pill）。球色 = `assets.domain`（§8 八色）；glyph = 类型。
- **闪念 pill 计数** = 今日 `session_type='flash'` 的 session 数 → 点击进当日 flash session（**复用 `SessionDetailPage`**）。
- **summary / 图表** 从这批今日 asset **现算**（记账 ¥sum、计数图按 type/domain）。
- **注**：池按 `created_at`（录入时刻）⊥ 日历按 effective time（发生时刻）—— 今天建「明天4点上线」→ 今天池有、日历在明天（同一 asset 两镜头）。

## 4. 复用 / 选型

- **Reka 浮球** = 现有全局 overlay（§9.2），不重做。
- **记录详情** = 复用现有 asset 详情（`asset_detail_sheet` 的域/类型/字段渲染）。
- **闪念 session** = 现有 `SessionDetailPage`。
- **物理**：用栈内引擎重写（**别 port 原型 JS**）。Flutter 建议：轻量自写 2D 解算（README 的方法够简单：圆-圆 + 位置松弛 + 休眠）或 `forge2d`；倾斜 = `sensors_plus`（accelerometer）。常量见 README。
- **图表**：用栈内图表库或自绘 SVG/Canvas（玫瑰/柱状/树图都不复杂，README 有画法）。

## 5. 别做

- 不 port `support.js`、不建 DEMO 调试面板。
- 不照 demo 的 6 域色 / 不把闪念当记录类型。
- **不把"段视图"放今日页** —— 段视图（5 时段）是**日历 流 / DayDetail** 的（[§4.5.0a](04-frontend.md) / §4.5.4），不是今日页。
- 物理别过度（休眠去抖是关键，避免常驻 RAF 烧电）。

## 6. 建议顺序

1. **nav 改**（小、先上）。
2. **Part 1 Next Action**（数据现成、最快见效）。
3. **Part 2 气泡池物理**（最重，单独啃；先静态落色 → 再加碰撞/休眠 → 再加拖/倾斜/drop-in）。
4. **Dashboard**（chips → summary → 三图表）。
5. **边态 + 详情 sheet + 闪念 pill 接线**。
6. **精修**（`/design-review` 对实现挑刺：高级质感 / 动效曲线 / 气泡材质）。

## 7. design's call（原型已有值可先照，后续 /design-review 精修）

气泡材质 / 光、三图表美术、两块整屏层级、空态暖度、卡叠 peek 角度 / 动效曲线 —— 原型 README 都有具体值，先照着搭；不要卡通玩具感（**高级 / 直观 / 有交互**三铁律）。

## 读这些

[§4.5.0 今日页](04-frontend.md)（逻辑真值）· [prototype-today-page.md](prototype-today-page.md)（hifi 视觉/动效/物理，逐字）· [handoff-calendar-design §E](handoff-calendar-design.md)（设计意图）· [§4.1 dock](04-frontend.md) · [§8 领域 + §5.1 颜色](08-domain-system.md) · [§14.6 早报](14-proactive-reka.md)。
