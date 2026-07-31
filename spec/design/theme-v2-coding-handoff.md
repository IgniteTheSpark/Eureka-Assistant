# UReka Theme V2 — Coding Handoff

状态：UI/UX 产品真值已基本成形；工程实施前需按本文件锁定范围。
设计源：`redesignureka.pen`
基准画板：`411 × 960`，包含 Light / Dark 两套主题。

> Revision 2026-07-29：旧 Calendar Flow 已从画布移除并由 Sticky Date Rail 原位替换；补充 Asset Emoji System、自然语言时间水印、日期/空日点击、Day Detail 空态、手动记录 Skill Picker，以及全部 Calendar 状态的 Asset 图标规则。已实现代码如与本 revision 冲突，应删除旧实现并按本稿回归。

## 1. 给 Coding Agent 的唯一读取规则

1. 只实现名称以 `UReka · Theme V2 /` 或 `Theme V2 /` 开头的页面和组件。
2. `UReka · Screen /`、`Exploration /`、`A ·`、`B ·` 等旧稿只用于历史参考，不得作为视觉真值。
3. 业务行为读取页面根节点的 `metadata` 与 `context`；两者冲突时以本 revision 新增的 `context` 为准。视觉值优先读取 `$theme-v2/*` variables。
4. Light / Dark 是同一组件树的主题变体，不允许复制两套业务代码。
5. 画板是手机基准，不代表固定宽度。实现时需适配 safe area、键盘、内容滚动和较长中文。
6. 任何设计中未覆盖的业务规则不得自行发明，先列为 gap。
7. 画布中的节点名、分区名和路径仅用于设计管理，绝不能渲染为 App 内 breadcrumbs。
8. 当本文件提供域内白名单时，白名单优先于节点名称前缀；同属 Theme V2 但被标记为 deprecated 的页面不得实现。

### Asset Emoji System

本节只定义 Asset，不定义 Goal、设备、通知或导航图标。Flash 不属于 Asset Emoji
映射，但 Theme V2 对 Flash 有独立的全局约束：所有“闪念”入口、数量、日期 rail
和 Flash Session 标识统一使用闪电 `zap`，不得使用 `sparkles`、星芒或 Skill Emoji。

- 日程、代办、名片、联系人、笔记及用户自定义 Skill 产生的对象全部属于 Asset。
- Agent 为 Skill 分配 Emoji；同一 Skill 的所有 Asset 始终复用同一个 Emoji。
- App 不直接渲染操作系统 Emoji 字体。前端必须把 Unicode Emoji 标准化后映射到随 App 固定版本发布的统一 Emoji SVG 资源。
- 标准化顺序固定为：完整 Emoji sequence → 去除 Variation Selector → 保留明确配置的肤色/性别组合 → 基础 Emoji alias → 通用 Asset fallback。
- Emoji 资源未命中时不得重新让 LLM 临时选择，也不得回退到平台原生 Emoji；使用固定的 `asset-generic` fallback。
- Skill 保存 Agent 原始 `emoji` 与稳定的 `emoji_asset_key`。已有 Skill 的 `emoji_asset_key` 一经确认，不因资源库升级自动变化。
- Emoji 本体保留统一资源库的标准颜色。Theme V2 统一尺寸、视觉重心、安全留白和可选低饱和容器；不对复杂 Emoji 强制单色染色。
- 尺寸档位固定为：Calendar dense row `16px`、普通 Asset row `20px`、卡片 `28px`、大容器与泡泡池 `40px`。
- Light / Dark 使用同一个 Emoji SVG，只切换外层容器、描边和背景 token。
- 页面标题、日期标题、分区标题不显示 Asset Emoji；Emoji 只属于真实 Asset item。

## 2. 实施顺序

实施节奏先完成 P0 Foundation，再依次替换 P2 Calendar、P3 Library / Assets、P4 Session、Notification / Reka Inbox 和 P6 Device 等已有成熟逻辑的 UI。P1 Today/Home 与 P5 Goal 涉及新业务逻辑，放在最后两个业务阶段；Home 先基于稳定 view model 和测试 fixture 完成，真实 Goal 数据、创建流程和生命周期在 P5 一次接通。

### P0 — Foundation

- Theme V2 tokens
- Global Top Nav
- Floating Dock
- 页面壳、safe area、Light / Dark 切换
- 通用 loading / empty / error / reduced-motion

核心组件：

| Node ID | Component |
|---|---|
| `E92l1` | Status Bar / Light |
| `lwbLt` | Status Bar / Dark |
| `ohIfN` | Dock / Light |
| `Y7EHo` | Dock / Dark |
| `Gcce8` | Global Top Nav / Device Disconnected |
| `t7nGi` | Global Top Nav / Device Connected |

#### Floating Dock Contract

- Dock 是固定在 viewport 底部上方的全局浮层，不随内容滚动。
- 411 基准画板使用 `169 × 60`，水平居中；Dock 下缘与 Home Indicator / bottom safe area 保持独立间距。
- 三个入口固定为：Today / Home、Calendar、Library。Goals 是 Home 的第二张页面，不增加第四个 Dock 入口。
- 只在一级浏览表面显示：Home Today / Goals、Calendar Flow / Month / Year / Schedule、Library Hub / Index。
- Session、Goal Setting、Asset Detail / Edit、Goal Detail、Device Connection、全屏 sheet、modal 和键盘打开状态隐藏 Dock。
- 页面可滚动内容必须预留 `dock height + visual gap + bottom safe area` 的底部 inset；最后一项不能被 Dock 覆盖，也不能通过把 Dock 放进滚动列表来解决。
- Dock 的选中态只表达当前一级目的地；App 不提供 hover，也不提供 web 式侧边高亮。
- Light 使用 `ohIfN`，Dark 使用 `Y7EHo`；业务代码必须共享同一 Dock 组件。

#### App Header Contract

- App 内禁止 breadcrumbs，不显示 `Home / Calendar / Flow`、`Library / Todo / Detail` 等路径。
- `UReka · Theme V2 / ...` 是画布节点名，不是用户可见文案。
- 一级表面使用 Global Top Nav；二级页面只使用“返回或关闭 + 当前页标题 + 必要动作”。
- 日期、月份、状态等业务 kicker 可以保留，但不得承担路径导航含义。

### P1 — Home

| Node ID | Screen / State |
|---|---|
| `WsOyv` | Light / Today Layer |
| `PMCdg` | Dark / Today Layer |
| `SuznI` | Light / Goals Layer |
| `BNmyJ` | Dark / Goals Layer |
| `vRy65` | Light / Today Agenda Fishbone |
| `J5cpE` | Dark / Today Agenda Fishbone |

必须实现：

- Today 与 Goals 是两张错位叠放的页面，不是底部 Tab。
- Today 在前、Goals 在后；滑动或点击露出的页头进行换页。
- 今日资产是内容下层的泡泡池。每个 Asset 独立成球；尺寸使用稳定伪随机，不按内容类型分类。
- 最新 1–5 个泡泡使用主题渐变强调，其余降为中性色。
- 展开 Agenda 使用毛玻璃层覆盖泡泡池。
- 同一时间点的多个事项放在同一个时间节点内，全部展开显示，不产生多分支，也不收敛成“2 个待办”。
- 多个同时需要关注的 Goal 使用可循环下翻的 stacked cards / carousel，不只展示最新一个。
- Goals Layer 按当前 Theme V2 画板实现：顶部摘要、下一 Goal 节点、全部 Goals 概览和历史入口使用同一份 Goal view model；P1 阶段完成组件与交互，P5 阶段接入真实 Goal 数据。

### P2 — Calendar

#### Calendar 实现白名单

| Node ID | Screen / State |
|---|---|
| `BeBq4` / `J3XydT` | **Flow / Sticky Date Rail / Resting** |
| `vjW39` / `n0Eup4` | **Flow / Sticky Date Rail / July 04 Entering** |
| `K1Z2iN` / `fHRmV` | Day Detail / Records；不是 Flow 路由 |
| `OncEM` / `anKiT` | Day Detail / Asset Empty；允许 `flash_count > 0` |
| `LEtWx` / `T1IwgQ` | Manual Record Skill Picker / Bottom Sheet |
| `XbCxS` / `IugNo` | Schedule Grid |
| `V9LoFM` / `sc1bQ` | Same-time Todo Expanded |
| `J20Phd` / `sGk5M` | Inline Draft |
| `zQK41` / `nMTbd` | Month / Progressive Time |
| `a6SVbz` / `M0i6f` | Year / Progressive Time |

#### Calendar 已移除稿

旧 Flow 节点 `dWO0c` / `YAu8U` 已从画布删除。原位置现由 `BeBq4` / `J3XydT`
的 Sticky Date Rail Resting 状态占据。Calendar Flow route 只能指向白名单中的
Sticky Date Rail 版本；历史截图、旧实现或缓存节点都不得重新引入。

业务真值：

- 时间水印使用自然语言距离，不使用 `+N DAY / -N DAY` 数学标记。当前语言画板使用大写英文，工程必须支持 locale。
- 水印计算使用当地日历日期而非持续小时数：当天 `TODAY`；相邻 1–6 天使用 `1 DAY AGO/LATER` 或 `N DAYS AGO/LATER`；7–29 天使用周；跨自然月后使用月；跨自然年后使用年。
- 周、月、年文案使用最大稳定日历单位和正确单复数，例如 `1 WEEK AGO`、`2 WEEKS LATER`、`1 MONTH AGO`。
- 日期与闪念数量位于侧边 sticky rail，右侧时间流独立滚动。
- Flash icon 与数量是日期 rail 的子元素，必须跟随日期一起 sticky / 被下一日期推走；点击进入该日 Flash Session。
- 所有 Flash icon 使用同一闪电 `zap` 语义；图标形态可随尺寸变化，但不得在不同页面混用星芒、灯泡或 Emoji。
- Day Detail 的 Flash 条只显示 `⚡ 闪念 N` 和 disclosure。它只打开当天 Flash Session，不创建 Flash、Asset 或输入会话；不得显示“今天记一笔”。
- Flow 与 Day Detail 中每条 Asset row 必须展示对应 Skill 的标准化 Emoji SVG；Emoji 只帮助识别 Skill，不改变时间排序。
- 点击有内容日期的日期标签或该日内容区域中的空白处，直接进入对应 Day View。
- 空日必须保留在 Flow 中。点击空日日期或空白区域先显示“手动记录”确认入口；点击确认入口打开 Manual Record Skill Picker，并携带被点击日期。
- Day Detail 提供独立的“手动记录”入口，同样打开 Manual Record Skill Picker，并携带当前日期。
- Manual Record Skill Picker 同时展示系统默认和用户自定义 Skill。选择 Skill 后进入该 Skill 的 Asset Edit 页；Picker 本身不创建 Asset，也不自动打开键盘。
- Day Detail 的空态只由 `asset_count = 0` 决定。即使 `flash_count > 0`，仍显示“今天还没有记录”与手动记录动作，同时保留 `⚡ 闪念 N`。
- Calendar 不显示“再次点击日期”“点击空白时间”“今天记一笔”等教学性 hint；交互通过按钮、卡片和 disclosure 表达。
- 未指定时间的记录不作为一组展示，只用安静分隔线保持时间顺序。
- Flow / Month / Year 横向切换；Month / Year 使用 Progressive Time 方案。
- 日程网格、同时间待办展开、空白时段快速创建分别按对应状态画板实现。
- Schedule 页标题、全天日程和未安排代办标题都不加 icon。全天事件、未安排代办和时间网格中的每一个真实 Asset item 分别显示所属 Skill Emoji。
- Schedule Grid、Same-time Todo Expanded 和 Inline Draft 的顶部容器统一使用 `全天日程 · N` 与 `未排期代办 · N`，尺寸、间距和计数位置一致。
- Schedule Grid、Same-time Todo Expanded 和 Inline Draft 等全部状态共用同一 Asset Emoji row / block renderer；不得只修改默认 Schedule Grid。
- 日程、培训和代办在时间上重叠时必须使用并列的独立 block。示例中的“小型讨论会”“培训”“3 个代办”是三个 block，不得覆盖、合并或压成一个摘要。
- 未安排代办区域最多同时展示 3 条；0 条时隐藏该区域，1–3 条按真实数量展示，超过 3 条时保持区域高度不再增长，并在区域内部纵向滚动。
- 未安排代办的内部滚动不得推动 Schedule Grid，也不得与整页滚动抢夺横向手势。
- 全天日程区域左上角显示 `全天日程 · N`；`N` 是当天全天事件总数，不是当前可见数。
- 全天日程为 0 时隐藏；有内容时标题和计数始终可见，事件内容位于标题下方。

### P3 — Library / Assets

入口画板：

| Node ID | Screen |
|---|---|
| `LTmYy` / `c5ejE` | Library Hub |
| `B70HCg` / `RTqWK` | Container Index |
| `V0MnR` / `uSlon` | All Containers |
| `rssuX` / `PnnTE` | Configure Pinned |

资产页面采用同一状态矩阵：

```text
List / Detail / Edit / Empty
×
Light / Dark
```

已覆盖 Todo、Notes、Events、Contacts 和 Custom Skill 示例。实现时抽象为 schema-driven Asset UI，不为每类资产复制页面。

关键规则：

- 每个 icon/asset 都保留时间。
- 首页容器与“全部容器”是管理入口；“创建技能”是独立的 AI 主动作，不与全部容器同级并排。
- 容器长按配置必须与主界面当前结构一致。
- Skill/Asset Detail 提供“设定目标”的上下文入口，并预选该 Skill。
- Todo、Notes、Events、Contacts、Custom Skill 等所有 Asset Detail 默认使用 Bottom Sheet，不按资产类型分叉。
- Bottom Sheet 支持上拉或点击展开动作进入 Full Page；展开前后复用同一 detail state，滚动位置、编辑草稿和异步状态不得丢失。
- Full Page 是统一 Detail 的展开形态，不是 Todo 专属页面；是否显示 Global Top Nav / Dock 由打开上下文和共享页面壳决定，不由资产类型决定。

### P4 — Session

| Node ID | State |
|---|---|
| `UnTYH` / `b2SpwY` | Loaded |
| `EHb9x` / `L1P3Sw` | Analyzing |
| `oQ4nv` / `u7yCE` | History Open |
| `NT9pT` / `b83gbZ` | Keyboard Open |
| `MBY4G` / `sO2M6` | Empty |
| `ezrjl` / `vurly` | Error |

优先复用 Theme V2 Session components：`T3kZvN`、`d75dT`、`sqQRI`、`jAu2q`、`JjkFU`、`G5gSN9`、`hXDge`。

### P5 — Goal Core（最后确认阶段）

| Node ID | Screen |
|---|---|
| `Mqv86` / `s7cFJ` | Select Skill |
| `WB3fq` / `GfkUr` | Describe |
| `e6zmV3` / `xJtQw` | Confirm Draft |
| `Me6Bl` / `a7r1m` | Success |
| `wpZIJ` / `ZbWba` | All Goals |
| `Vcp3f` / `oRqjp` | Goal Detail / Check-in |
| `Es6w4` / `BlVcp` | Adjust Goal Confirmation |

不可破坏的规则：

- Goal 必须关联已有 Skill。
- 首页 `+ Goal` 先选择 Skill；从 Skill/Asset 详情进入时预选 Skill 并跳过选择页。
- Draft 可修改，离开流程即丢弃；确认后计算规则不可编辑。
- 调整目标不是修改原 Goal：先弹窗说明“将创建新 Goal，当前 Goal 与记录保留”，确认新 Draft 时原子结束旧 Goal并创建新 Goal。
- Goal Detail Evidence 是按 `effective_time DESC` 排序的扁平 Asset 列表。
- All Goals 分 active / scheduled；组内 `created_at DESC`；历史目标进入独立页面。
- 同 Skill + 同 Goal Type 最多一个 scheduled/active Goal，服务端确认时再次校验。
- 当前 Goal UI 方向已确认可实施。Goal History 复用 All Goals 的卡片骨架和筛选结构；Progress / Guardrail Detail 复用 Check-in Detail 的页面骨架，仅替换确定性进度模块；loading / empty / error 使用 P0 通用状态。
- P5 开始时进行一次最终范围确认，然后统一完成 Goal read contract、Home 数据接入、创建、详情、调整和历史，不在 P1–P4 中拆出临时 Goal 后端。

### P6 — Device / Global Entry（最后确认阶段）

| Node ID | Screen |
|---|---|
| `wmIGW` / `Rf4KY` | Device Center / Disconnected |
| `P8qgPL` / `CtBQS` | Discovery / Discovered |
| `b06Vn` / `B9OKu` | Device Center / Connected |

Global Top Nav 包含 Logo、设备连接状态、Light/Dark 切换和 Notification 快速入口。Notification 打开 Reka Inbox；设备状态打开对应 Device Center。

P6 在 Calendar、Library、Session 和 Inbox 稳定后进行范围确认，再接入发现、配对、连接和异常恢复。P0 的 Global Top Nav 只需要先保留稳定的 Device Center 入口与可替换状态接口；Device 完成后再进入 Today/Home 与 Goal。

## 3. Theme V2 Tokens

工程 token 名应保持语义一致，不要把 Light / Dark 色值散落在组件内。

| Token | Light | Dark |
|---|---:|---:|
| `theme-v2/bg` | `#F7F9FC` | `#0B0D12` |
| `theme-v2/surface` | `#FFFFFF` | `#121620` |
| `theme-v2/fg` | `#101319` | `#F3F5FA` |
| `theme-v2/muted` | `#6D7480` | `#8991A0` |
| `theme-v2/border` | `#D9E0E8` | `#29303D` |
| `theme-v2/accent` | `#25B6D6` | `#8A82FF` |
| `theme-v2/accent-soft` | `#E9F8FC` | `#1A1D35` |
| `theme-v2/critical` | `#D23A57` | `#FF5F7B` |
| `theme-v2/watermark` | `#10131909` | `#FFFFFF09` |

```text
font-primary: Geist
font-mono: Geist Mono
space: 4 / 8 / 12 / 16 / 24
radius: 7 / 10 / 14 / pill
touch-target: 44
motion-fast: 160ms
motion-standard: 260ms
motion-fluid: 420ms
ease-fluid: cubic-bezier(0.22,1,0.36,1)
```

注意：少数较早创建的 Theme V2 Library / Calendar 画板仍含等价硬编码颜色。工程实现以本表 token 为准，不复制硬编码值。

## 4. Interaction Contract

| Interaction | Required behavior |
|---|---|
| Home layer switch | 两张纸错位叠放，手势跟手；完成后切换前后层级 |
| Goal attention stack | 可循环下翻；手动交互优先；自动轮播需在用户触摸、读屏或 reduced-motion 时停止 |
| Asset bubble pool | 泡泡位于内容下层；新资产出现时使用短促落入/浮入反馈；点击打开 Asset Detail |
| Agenda expand | 毛玻璃 sheet 展开；背景泡泡仍可感知但不可误触 |
| Calendar scale swipe | Flow / Month / Year 横向跟手切换 |
| Sticky date rail | 日期 + Flash count 始终可见；下一日到阈值时推走上一日 |
| Flow day open | 点击日期或有内容日期的空白区域进入 Day View |
| Empty Flow day | 空日保持可见；第一次点击显示“手动记录”确认，点击后打开 Manual Record Skill Picker |
| Flow Asset row | 每条记录显示所属 Skill 的标准化 Emoji，保持 effective time 排序 |
| Flash identity | 所有“闪念”入口、计数与 Session 标识统一使用闪电 `zap` |
| Day Detail Flash | 只显示数量并打开对应 Flash Session；不得触发创建 |
| Manual record | Day Detail 或 Flow 空日 → Skill Picker → Skill-specific Asset Edit；Picker 不创建 Asset |
| Day Detail empty | `asset_count = 0` 即为空态；与 `flash_count` 独立 |
| Schedule overlap | 同时间事项按独立并列 block 展示，不覆盖、不合并成数量摘要 |
| Unscheduled Todo Tray | 最多可见 3 条；超出后区域内部纵向滚动，外部布局高度保持不变 |
| All-day Events | 左上角固定显示“全天日程 · N”；0 条时隐藏整个区域 |
| Floating Dock | 固定于 viewport，不参与页面滚动；只显示在规定的一级浏览表面 |
| Goal adjust | 先解释 replacement 语义，再进入带旧规则预填的新 Draft |
| Theme toggle | 无页面重建闪烁；状态、滚动位置和输入内容保持 |

## 5. Missing / Must Not Guess

以下项目尚未在画布中完整闭环，coding agent 应创建 gap list，而不是自行定产品规则：

- Notification / Reka Inbox 的 Theme V2 完整页面。
- 所有页面在极端长文本、动态字体和横屏下的最终布局。
- Device 配对失败、权限拒绝、断线重连等异常态。

Goal 的缺失画板不再阻塞实现：History、Progress / Guardrail Detail、All Goals 筛选和异步状态按 P5 中已经确认的组件复用规则实现，不另行发明一套视觉语言。

## 6. Acceptance Checklist

- [ ] 代码中只有一套组件树，通过 theme tokens 切换 Light / Dark。
- [ ] 所有交互区域最小 `44 × 44`。
- [ ] Dock 不遮挡最后一项；滚动容器包含 bottom safe-area padding。
- [ ] Dock 仅出现在规定的一级浏览表面，Session / Detail / Edit / modal / keyboard 状态不显示。
- [ ] 所有页面均未渲染画布节点路径或 breadcrumbs。
- [ ] Calendar Flow 只实现 Sticky Date Rail；已删除的 `dWO0c` / `YAu8U` 不得从历史实现或缓存重新引入。
- [ ] Flow 与 Day Detail 的每条真实 Asset row 均带所属 Skill Emoji；标题、日期和分区标题不带 Asset Emoji。
- [ ] 空日保持可见，并严格执行“显示手动记录确认入口 → 打开 Manual Record Skill Picker”的两步流程。
- [ ] Flash icon / count 与日期 rail 同步 sticky，不成为独立浮层；所有 Flash 表面统一使用闪电 `zap`，不存在 `sparkles`。
- [ ] Day Detail Flash 条只显示数量且只能打开 Flash Session；不存在“今天记一笔”。
- [ ] Day Detail 空态按 `asset_count` 判定；无 Asset、有 Flash 时仍显示空态并保留 Flash 数量。
- [ ] Manual Record Skill Picker 同时包含系统与自定义 Skill，内部滚动，选择后进入对应 Asset Edit，并正确携带日期。
- [ ] Schedule 的日程、培训、代办重叠时显示为独立并列 block；Light / Dark 头部结构一致。
- [ ] App 不直接渲染平台原生 Emoji；Skill Emoji 全部经固定版本资源映射，未命中时使用 `asset-generic`。
- [ ] 未安排代办最多可见 3 条，超过 3 条只滚动内部容器。
- [ ] 全天日程左上角显示准确总数，0 条时隐藏。
- [ ] 键盘打开时输入区可见，当前 Session 内容不丢失。
- [ ] 动画支持 Reduce Motion；自动轮播可暂停。
- [ ] 中文长文案不会覆盖图标或 CTA。
- [ ] loading / empty / error 不改变页面主要结构。
- [ ] Home、Calendar、Library、Session、Goals、Device 的入口和返回路径可闭环。
- [ ] Goal 规则和 Evidence 计算由确定性数据驱动，不由 UI 或 LLM 临时判断。
- [ ] 截图回归至少覆盖 411px Light / Dark 与一档更窄设备。

## 7. 可直接交给 Coding Agent 的 Prompt

```text
请实现 UReka Theme V2。

设计源为 redesignureka.pen。只读取名称以 “UReka · Theme V2 /” 或
“Theme V2 /” 开头的节点；忽略所有旧版 Screen、Exploration、A/B 风格稿。
节点名前缀只是第一层过滤，仍必须遵循 handoff 中各域的显式白名单和
deprecated 列表。任何画布节点名或路径都不得作为 breadcrumbs 渲染。

先读取 spec/design/theme-v2-coding-handoff.md，把其中的业务规则和
acceptance checklist 视为实现约束。视觉值从 $theme-v2/* variables 获取；
Light / Dark 必须共用组件树。页面根节点 metadata 是交互真值。

按 P0 → P2 → P3 → P4 → Inbox → P6 → P1 → P5 的工程顺序实施；章节编号仍表示设计域，不表示执行先后。每阶段先给出：
1. 将实现的 route / state；
2. 复用的组件和 token；
3. 设计未覆盖的 gap。

不要自行补产品规则。完成每阶段后运行测试、截图回归和可访问性检查，并逐项
对照 acceptance checklist 报告结果。
```
