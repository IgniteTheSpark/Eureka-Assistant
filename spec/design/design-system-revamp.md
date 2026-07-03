# Design System Revamp Brief · UReka

> 目的：这不是页面清单，而是下一轮 **UReka 整体设计系统升级** 的工作底稿。
> 受众：design agent / coding agent / 产品决策。
> 目标：把当前 app 从“多个功能模块各自长出来”收敛成一个统一、精进、可持续扩展的产品体验。
>
> 相关真值：
> - 现有设计 token：[05-design-system.md](../05-design-system.md)
> - 前端结构：[04-frontend.md](../04-frontend.md)
> - 今日页新模型：[handoff-today-home-design.md](../handoffs/handoff-today-home-design.md)
> - Reka 表达层：[handoff-reka-emote-notif.md](../handoffs/handoff-reka-emote-notif.md)
> - 领域色：[08-domain-system.md](../08-domain-system.md)

---

## 1. Design North Star

UReka 的设计目标不是“可爱工具”，也不是“效率仪表盘”，而是：

> **一个普通人愿意每天打开的 AI 记录伙伴。**

它应该同时满足：

- **可信**：记录不会乱，信息结构清楚，用户知道东西放在哪里。
- **温暖**：每次记录都有被接住的感觉，尤其是闪念完成反馈、通知、Reka 对话。
- **轻松**：不用配置，不像填表；用户可以随口说，系统自己整理。
- **高级**：界面有品质，不像儿童游戏、不像粗糙 demo、不像后台管理系统。
- **有生命感**：Reka 是陪伴层，但不抢走内容主角。

设计判断标准：

```text
如果一个方案让用户更清楚、更愿意继续记录、更相信内容被妥善整理，它就是对的。
如果一个方案只是更炫、更满、更像展示 demo，但降低了记录和回看的清晰度，它就是错的。
```

---

## 2. Current Design Problems

当前 app 的问题不是缺页面，而是多个系统并行生长后，视觉和交互语言还没有完全统一。

### 2.1 页面层级混杂

今日、日历、资产库、宠物、报告、设备页的视觉密度和“高级感”不一致。有些地方像精致的 consumer app，有些地方像工程调试页，有些地方像功能原型。

### 2.2 内容 surface 不统一

同一条 asset 会以多种形态出现：

- bubble
- timeline item
- SkillCard
- AssetDetailSheet
- AssetEditPage
- Report source / action
- Notification target

这些形态之间需要有明确密度层级，而不是每个入口各画一套。

### 2.3 Reka 角色边界不清

Reka 同时是：

- 浮动宠物
- 通知入口
- 聊天入口
- 菜单入口
- 情绪反馈入口
- 游戏化入口

这不是问题，但它需要统一表达层：同一种气泡、同一种情绪符号、同一种温度，而不是在每个功能里单独设计一个“小助手 UI”。

### 2.4 系统态太多但缺统一表达

UReka 有大量异步和硬件状态：

- 闪念整理
- ASR
- BLE 传输
- 戒指录音
- 报告生成
- 通知 / offer
- 设备连接
- 离线同步

如果每个模块独立表达，会显得像多个工程模块拼接。设计系统必须给这些状态统一语言。

### 2.5 两种视觉倾向拉扯

UReka 一边需要高级、深色、结构化、数据感；另一边又有宠物、气泡、emote、陪伴感。

解决方式不是二选一，而是分层：

- **数据界面高级、克制、内容优先。**
- **Reka 表达层温暖、有生命感。**

---

## 3. Product Surface Model

不要按文件列表理解 UReka。应该按“产品表面”理解。

```text
L0 App Gate
登录 / 注册 / onboarding / 权限 / 设备初始化

L1 Main Shell
Today / Calendar / Library
+ Global Header
+ Floating Dock
+ Floating Reka

L2 Task Flows
闪念 / 快创 / 资产详情 / 编辑 / 聊天 / 通知 / 报告 / 设备连接

L3 System States
loading / empty / error / offline / BLE / ring recording / ASR / toast / confirm
```

设计系统 revamp 的任务，是让这四层的视觉和交互一致，而不是只重画几个页面。

---

## 4. Two Visual Layers

### 4.1 Data Layer

用于：

- Today
- Calendar
- Library
- Asset surfaces
- Report
- Detail / Edit
- Device information

关键词：

- premium
- structured
- calm
- readable
- content-first

表现：

- 深色 / 暖白主题都成立。
- 克制色彩，避免单一大面积高饱和。
- domain dot / domain color 是主要颜色来源。
- 卡片有层级但不花。
- 信息密度合理，不做玩具感。
- 动效服务理解，不只是装饰。

### 4.2 Reka Expression Layer

用于：

- Floating Reka
- Reka radial
- Reka chat bubble
- nudge / notification
- emote
- drop reveal
- onboarding hatch

关键词：

- warm
- alive
- soft
- companion-like

表现：

- Reka 气泡容器。
- Kenney emote / gentle expression。
- 小幅动效。
- 温柔文案。
- 可爱可以存在，但只属于表达层，不吞掉数据界面的高级感。

### 4.3 Layering Rule

```text
Data Layer = 用户的内容是主角。
Reka Expression Layer = REKA 在旁边接住用户。
```

Reka 不应该把所有页面都变成游戏界面。Today 可以有生命感，但 Calendar / Library / Report 仍要像可信赖的记录系统。

---

## 5. Global Shell

Global Shell 是所有页面的外壳，优先级最高。

### 5.1 Components

- `GlobalHeaderBar`
- `FloatingDock`
- `FloatingMascot`
- page background
- safe area
- app-level overlays

### 5.2 Responsibilities

Global Shell 需要回答：

- 当前在哪个主区域？
- 用户从哪里开始捕捉？
- Reka 在哪里？
- 设备状态在哪里看？
- 通知从哪里进？
- 页面内容和全局控件之间如何避让？

### 5.3 Header

Header 不是普通 toolbar，它承担：

- 品牌存在感
- 账号 / profile
- 设备入口
- 主题状态
- 调试入口隔离

原则：

- 常规用户只看到必要入口。
- debug-only 明确收纳，不污染正式体验。
- 设备状态要可读，但不要抢主内容。

### 5.4 Dock

底部 Dock 只承载三个主 tab：

- 今日
- 日历
- 资产

不再承载“我的岛”。我的岛归入 Reka 菜单。

Dock 设计要求：

- 固定、稳定、低认知。
- 与 bubble pool / bottom sheet / keyboard / safe area 不打架。
- tab icon + label 应清晰，避免为了造型牺牲可点性。

### 5.5 Floating Reka

Floating Reka 是全局 companion，不是第四个 tab。

它负责：

- Reka radial menu
- quick chat
- nudge peek
- notification signal
- pet / island entry
- subtle emotional response

它不负责：

- 承载完整页面导航树
- 替代系统 header
- 抢占核心内容阅读

---

## 6. Core Navigation Map

### 6.1 L0 Gate

| Surface | Role | Notes |
|---|---|---|
| `LoginPage` | 登录 / 注册 | 轻、可信，避免营销页感 |
| `PetSpawnPage` | 新用户孵化 + onboarding | UReka 的第一印象；展示“说一句 → 变卡片”的 aha |
| permission / device init | 设备或麦克风权限 | 只在必要时出现 |

### 6.2 L1 Main Tabs

| Tab | Role | User Question |
|---|---|---|
| Today | 今天的价值页 / app landing | 我现在该做什么？REKA 今天能帮我什么？ |
| Calendar | 时间回看与计划查看 | 我过去/未来记录了什么？ |
| Library | 长期沉淀与技能入口 | 我的东西和记录模板在哪里？ |

### 6.3 L2 Task Flows

| Flow | Entry | Output |
|---|---|---|
| Flash | Dock / Reka / hardware | warm reply + cards + session |
| Quick create | Dock / Reka / empty states | asset |
| Asset detail | any asset surface | detail sheet |
| Edit | detail / create | AssetEditPage |
| Chat | Reka / asset detail / session | conversation |
| Notification | Reka / notifications page | target action |
| Report | Library / offer / report actions | ReportViewer |
| Device | header / onboarding | connected device |

---

## 7. Core Tabs

### 7.1 Today

Role:

- app 的 landing
- 今天的价值表达
- 让用户知道下一步可以做什么
- 让用户感到今天记录的东西被接住

Should include:

- warm header
- 今日安排
- Reka Offer
- capture bubble pool
- lightweight progress / sense of motion

Should not:

- 不做历史流水账。
- 不塞完整日历。
- 不做纯 dashboard 填空。
- 不把 Reka 变成页面主角；Reka 仍是全局浮球和表达层。

Design focus:

- 一眼看到下一步。
- 有高级交互，但不是炫技。
- Bubble pool 是今日捕捉的整体感，不是详细列表。

### 7.2 Calendar

Role:

- 时间回看与计划查看
- 所有 asset 按 effective time 归位
- 日程 / 非日程两个镜头

Should include:

- stream / month / year
- DayDetail
- schedule / non-schedule mode
- flash pill
- period/no-time logic

Should not:

- 不把原始闪念混进流。
- 不把模糊时段造假时间。
- 不把 DayDetail 做成和流没有差异。

Design focus:

- 流 = 快速回看很多天。
- DayDetail = 精看某一天。
- 日程模式 = 24h 网格。
- 非日程模式 = 分段记录。

### 7.3 Library

Role:

- 长期沉淀
- 技能与资产的结构化入口
- 报告与管理入口

Should include:

- permanent entities
- active skills
- recent assets
- reports
- skill management
- connected apps where appropriate

Should not:

- 不做成杂乱文件夹。
- 不让每个 skill 自己长一套视觉。
- 不把技能管理暴露成工程后台。

Design focus:

- “我有什么”一眼清楚。
- 常驻实体和用户技能区分清楚。
- 自定义 skill 看起来像自然记录本，而不是数据库表。

---

## 8. Asset Surface System

同一条 asset 在不同场景中有不同密度。

### 8.1 Level 0 · Bubble

Used in:

- Today bubble pool

Purpose:

- 让用户感知“今天收了很多东西”。
- 不承载完整信息。
- 点按进入详情。

Display:

- domain color
- type glyph
- physics / cluster / drop-in

Do not:

- 不塞长文字。
- 不作为筛选 chip。
- 不承载完整操作。

### 8.2 Level 1 · Timeline Item

Used in:

- Calendar stream
- month compact view

Purpose:

- 快速回看。
- 一眼知道是什么。

Display:

- time or no-time state
- type emoji
- title 1
- title 2 optional
- domain dot

Do not:

- 不放完整 meta。
- 不把所有字段摊开。
- 不用大块彩色容器区分类型。

### 8.3 Level 2 · SkillCard

Used in:

- flash result
- session detail
- library recent assets
- category list
- report source previews

Purpose:

- 标准资产预览。
- 显示核心字段。

Display:

- icon tile
- title
- subtitle
- 1-2 meta
- domain dot / chip
- primary action if relevant

### 8.4 Level 3 · AssetDetailSheet

Used when:

- 用户想看完整内容
- 用户从 bubble / timeline / card 点入

Purpose:

- 展开所有字段。
- 显示溯源。
- 允许编辑 / 删除 / 聊天 / report action。

Rules:

- 详情是 bottom sheet，不是新页面，除非进入深编辑。
- 字段 label 要来自 render_spec，不显示机器名。
- 长文要有阅读节奏。
- source session / source report 可回溯。

### 8.5 Level 4 · AssetEditPage

Used when:

- 创建
- 编辑
- custom skill 表单

Purpose:

- 表单化，但尽量不重。
- 字段类型正确。
- 支持用户自定义 skill。

Rules:

- create 和 edit 同款。
- 控件按字段类型自动选择。
- 日期/时间、boolean、array、long text 要有对应控件。
- 保存只提交变化字段。

---

## 9. Capture & AI Flows

### 9.1 Flash Flow

```text
entry → FlashSheet → listening / typing → processing → warm reply → cards → session
```

Key surfaces:

- `FlashSheet`
- `FlashResult`
- `SkillCard`
- `SessionDetailPage`
- warm reply

Design requirements:

- 用户要知道系统正在听 / 正在整理。
- 完成后先给一句 warm reply，再展示 cards。
- cards 是事实，reply 是被接住的感觉。
- 失败时说明是否保留了原始输入。

### 9.2 Warm Reply

Warm reply 由 Flash Reply Agent 生成，不是模板。

Rules:

- 只基于本次输入和已生成 cards。
- 不编事实。
- 不暴露内部。
- 不写「已记录 N 项内容」。
- 短、具体、有温度。

### 9.3 Chat Flow

Chat 是深对话，不是 flash 的替代。

Entry:

- Reka
- asset detail
- session detail

Design requirements:

- 支持 bound context。
- tool result 和 card part 有清晰区别。
- query result 可折叠。
- 历史回看要稳定。

### 9.4 Notification / Offer Flow

Notification 不只是 push，也是 Reka 的可回溯建议。

Surfaces:

- Reka peek
- notification feed
- Today Reka Offer
- target detail / report / session

Rules:

- dismiss 不等于删除。
- 今天 dismiss 的 offer 当天不再 offer；第二天条件仍满足可再次出现。
- Push 是 PEEK，Today Offer 是 PULL。

---

## 10. Reka & Companion Layer

### 10.1 Reka's Role

Reka 是：

- 陪伴者
- 入口
- 反馈者
- 提醒者
- 轻量情绪层

Reka 不是：

- 页面主角
- 数据容器
- 所有导航的替代品
- 低龄化装饰

### 10.2 Reka Surfaces

| Surface | Role |
|---|---|
| FloatingMascot | 全局陪伴与入口 |
| RekaRadial | 快捷菜单 |
| RekaChat | 对话 / 通知 / peek |
| Reka bubble container | Reka 说话的统一容器 |
| Emote | 情绪符号 |
| PetPage | 我的岛 / 宠物系统 |
| Wardrobe | 换装 |
| DropReveal | 奖励反馈 |

### 10.3 Expression Rules

- Reka 可以温暖、轻、活。
- 不用负面脸，不训用户。
- 不把数据界面变成卡通玩具。
- Reka 气泡用于 Reka 说话，不用于普通数据 panel。

---

## 11. Reports

Reports 是 UReka 的闭环输出之一。

Surfaces:

- `ReportListPage`
- `ReportViewerPage`
- report actions
- source report links
- suggested todos

Design requirements:

- 报告要像可分享的内容，不像后台生成页。
- Reka Insights 品牌露出。
- report action 要清晰：生成 todo / 继续聊 / 回看来源。
- 报告 viewer 需要阅读节奏和加载态。

---

## 12. Devices & Hardware

Surfaces:

- `DevicePairingPage`
- `MyDevicePage`
- `MyRingPage`
- `RingDebugPage`
- `ConnectedAppsPage`
- BLE overlays
- listening overlays

### 12.1 User-Facing Hardware States

| Technical State | User Language |
|---|---|
| connecting | 正在连接 |
| connected | 已连接 |
| recording | 正在听 |
| transcribing | 正在听写 |
| filing | 正在整理 |
| syncing file | 正在同步录音 |
| failed ASR | 这段没听清 |
| no content | 这次好像没听到内容 |

### 12.2 Debug-Only

Debug surfaces must be clearly marked and hidden from normal users:

- `RingDebugPage`
- debug buttons in login/header
- raw diagnostic info

Design rule:

```text
正式体验里不出现工程词。
debug 入口存在可以，但要收纳、标记、可关闭。
```

---

## 13. Overlays & Sheets

UReka 大量核心操作不是 full page，而是 sheet / overlay。

### 13.1 Bottom Sheet

Use for:

- asset detail
- profile
- flash
- quick options
- picker
- lightweight confirmation

Rules:

- header 清楚。
- primary action 固定。
- 支持安全区。
- 可滚动内容不要和拖拽手势冲突。

### 13.2 Full Page

Use for:

- edit
- chat
- report viewer
- wardrobe
- device pairing
- deep settings

Rule:

```text
如果用户需要持续输入 / 阅读 / 多步操作，用 full page。
如果只是看一眼 / 选一下 / 确认，用 sheet。
```

### 13.3 Toast

Use for:

- 短成功反馈
- 非关键状态
- 不需要用户决策的信息

Do not:

- 不用 toast 承载关键错误。
- 不用 toast 替代 warm reply。
- 不连续刷 toast。

---

## 14. System States

UReka 的系统态必须统一表达。

### 14.1 Processing

Examples:

- 正在整理
- 正在听写
- 正在同步
- 正在生成报告
- 正在连接

Rules:

- 说明正在做什么。
- 如果可能超过 2 秒，给进度或阶段。
- 不使用技术词作为主文案。

### 14.2 Success

Success should include:

- visible result
- warm feedback
- optional Reka reaction

Do not rely only on toast.

### 14.3 Failure

Failure copy should answer:

1. 发生了什么？
2. 原始输入是否保留？
3. 用户能做什么？

Bad:

```text
ASR failed
```

Better:

```text
这段没听清，你可以再说一次。
```

If raw recording / text is saved:

```text
这段没听清，但原始录音还在。
```

### 14.4 Empty

Empty state should offer next action:

- 说一句试试
- 创建第一个技能
- 连接设备
- 查看示例
- 生成第一份报告

Do not show dead empty panels.

---

## 15. Interaction Grammar

### Tap

Open detail / select / execute light action.

### Long Press

Contextual reveal, especially bubble pool same-type overlay.

### Swipe

Use only when the mode is explicit:

- 今日安排 Tinder：previous / next
- Reka Offer：dismiss / execute

### Drag

Use for:

- bubble pool physics
- playful surfaces

Do not use drag for ordinary form organization unless necessary.

### Bottom Sheet

Lightweight detail / selection / confirmation.

### Full Page

Deep task / reading / editing.

### Reka Bubble

Only when Reka is speaking or nudging.

---

## 16. Visual Rules

### 16.1 Color

- Domain color is the primary semantic color system.
- Cards should not each invent accent colors.
- Data surfaces use restrained background, domain dot, subtle hierarchy.
- Reka expression can use warmer / softer accents, but stays layered.

### 16.2 Typography

- Compact surfaces use smaller, high-legibility text.
- Hero-scale type only for true landing / hero moments.
- Long content needs comfortable line height.
- Avoid overusing mono except timestamps / numeric counters.

### 16.3 Cards

- Cards are for repeated items, not every page section.
- Do not put cards inside cards.
- Repeated asset surfaces must map to the Asset Surface System levels.

### 16.4 Motion

Motion should clarify:

- item created
- state changed
- Reka reacted
- sheet opened
- bubble selected

Motion should not:

- delay recording
- make text hard to read
- turn utility surfaces into games

---

## 17. Redesign Priority

### P0 · Global Shell

- Header
- Dock
- Floating Reka
- page background
- safe area
- global overlay rules

### P1 · Asset Surface System

- Bubble
- timeline item
- SkillCard
- AssetDetailSheet
- AssetEditPage

### P2 · Core Tabs

- Today
- Calendar
- Library

### P3 · Capture & AI Flow

- FlashSheet
- warm reply
- session detail
- ChatPage
- Notifications / Reka Offer

### P4 · Companion / Pet / Device

- Reka radial
- Reka chat bubble
- PetPage
- Wardrobe
- Device / Ring states

### P5 · Reports

- ReportList
- ReportViewer
- report actions

Recommended design-agent sequence:

```text
Do P0 + P1 first.
Then redesign Today / Calendar / Library against those surfaces.
Do not shotgun Today in isolation.
```

---

## 18. Current App Map V0

This map is derived from the current Flutter app code. It is not the final information architecture; it is the raw surface inventory for redesign.

### 18.1 L0 / Gate

- `LoginPage`
- `PetSpawnPage`
- post-auth gate
- onboarding first capture
- permission / device entry

### 18.2 Main Shell

- `AppShell`
- `GlobalHeaderBar`
- `FloatingDock`
- `FloatingMascot`

### 18.3 Main Tabs

- `TodayPage`
- `CalendarPage`
- `LibraryPage`

### 18.4 Calendar / Time

- stream
- month
- year
- `DayDetailPage`
- `DayRender`
- `DayFlashView`

### 18.5 Asset / Skill

- `SkillCard`
- `AssetDetailSheet`
- `AssetEditPage`
- `CategoryDetailPage`
- `EntityListPage`
- `CreateAsset`
- `showCreateMenu`
- `AddSkill`
- `SkillConfigPage`
- `SkillManagePage`
- `AssetPicker`

### 18.6 Flash / Chat / Sessions

- `FlashSheet`
- `SessionDetailPage`
- `ChatPage`
- `RekaChat`
- `NotificationsPage`
- `RekaNotifications`
- `RekaNudges`

### 18.7 Reka / Pet

- `FloatingMascot`
- `RekaRadial`
- `PetPage`
- `_WardrobePage`
- `RekaDropReveal`
- `PetSpawnPage`

### 18.8 Reports

- `MorningBriefingPage`
- `ReportListPage`
- `ReportViewerPage`

### 18.9 Devices / Integrations

- `DevicePairingPage`
- `MyDevicePage`
- `MyRingPage`
- `RingDebugPage`
- `ConnectedAppsPage`
- BLE transfer overlays
- ring capture service

### 18.10 Global System Components

- toast
- confirm dialog
- date/time picker
- listening overlay
- BLE overlay
- flash file status bar
- notification routing

---

## 19. Deliverable Request For Design Agent

When handing this to a design agent, ask for:

1. **System audit** of current app surfaces against this brief.
2. **P0 + P1 redesign direction board**:
   - global shell
   - asset surfaces
   - overlays / sheets
   - Reka expression layer
3. **One unified component language**:
   - bubble
   - timeline item
   - card
   - detail sheet
   - edit page
4. **Then** redesign:
   - Today
   - Calendar
   - Library

Explicitly do not start with a standalone Today page mockup. Today must be designed after the shell and asset surface system are coherent.
