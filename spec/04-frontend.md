# 04 · 前端架构与交互细节

> **真值源（2026-06 翻转）：产品前端 = Flutter `mobile/`（iOS-first）。web `frontend/`
> （Vite + React + SWR）= 历史来源 / 出处参考，非交付端。** 本章描述的交互行为，**冲突一律以
> `mobile/` 为准**；章内「Flutter 增量 / 实现注意」即规范。
> **本章状态：正逐区 re-baseline。** 历史 React 描述（Provider 嵌套 / SWR / React Router / 组件名如
> `CategoryList` `AssetDetailDrawer`）保留作**意图与命名对照**，但当它与 Flutter 实现冲突时按 Flutter 来；
> 已对齐的 Flutter 行为见各处「Flutter 增量」段（header / 登录 / 设置 / 日视图 / 刷新模型 / 长内容 / 日期分隔…）。
> 渲染契约（render_spec → 卡片）见 §4.7；design tokens 见 [§5 设计系统](05-design-system.md)。

---

## 4.0 应用骨架（App shell / Provider / 路由）

### 4.0.1 Provider 嵌套（`App.tsx`）

由外到内**严格按此顺序**（内层依赖外层 context）：

```
ThemeProvider                  ← dark/light class 挂到 document
 └ PresentationModeProvider    ← 资产为主 / 日历为主（决定 home 落点）
   └ ModalProvider             ← 模态计数，控制 dock 显隐 + AgentTarget
     └ ListeningProvider       ← 闪念录音「聆听中」全局态
       └ PhoneFrame            ← 锁 393×852 视口
         └ ToastProvider       ← 顶部 toast 队列
           └ AppShell (Routes) ← StatusBar + main + FloatingDock
             └ NotificationsBridge  ← 挂 SSE，capture 事件触发 SWR revalidate
```

> Flutter 移植注意：`PhoneFrame` 不是业务需求，是 demo 在桌面浏览器里**模拟手机视口**的舞台道具。
> 移植到真机时整层去掉，但其「`transform: translateZ(0)` 造一个 containing block，让 `position:fixed`
> 的 sheet/dock 留在框内」的副作用要用原生 sheet 容器替代。

### 4.0.2 路由表（React Router 6）

| 路由 | 组件 | 说明 |
|---|---|---|
| `/` | redirect | 依 PresentationMode → `/library` 或 `/calendar` |
| `/chat` | `ChatPage` | 核心对话；**不渲染 dock**（`AppShell` 对 `/chat` 特判，`main` 用 `pb-0`） |
| `/calendar` | `CalendarPage` | Segmented 流/月/年；**默认「流 · 今天」**(产品决策 2026-06)。点 `今天` tab、从 pushed 页 pop 回、**或在 segmented 上选「流」** → 复位到 流·今天(`calendarHome` 信号 + 路由 `didPopNext`;选「流」走 `calendarHome++` 而非直接 `_switchMode`,因 PageView 保活、流页不会重建,只 bump 才会让它 `_jumpToToday`;`_jumpToToday` 先按估高 `animateTo` 再 **post-frame `_snapToday`**(`ensureVisible` 今日行)精确落到今天,避免估高累计误差导致定位偏几周)。data 刷新保留旧数据不闪 spinner(`_lastData`),PageController 不脱挂 → 流/月/年 与 segmented 不再错位。 |
| `/library` | `LibraryPage` → `CategoryList` | 资产库首页 |
| `/library/:skillName` | `CategoryDetail` | 单类型 drill-down（`/library/*` 委派给嵌套 `<Routes>`） |
| `/notifications` | `NotificationPage` | 通知历史 |

`AppShell` 结构：`StatusBar`（顶部假状态栏）+ `<main className="pb-28">`（`/chat` 时 `pb-0`）+
`<FloatingDock>`（`/chat` 时不渲染、任意模态打开时隐藏）。

### 4.0.3 客户端数据流（SWR + revalidate 协议）

- **读**：所有列表用 `useSWR(key, swrFetcher)`，key = API 路径字符串（如 `/api/assets?limit=500`）。
  SWR 跨组件去重——hub、drill-down、calendar 同时挂 `/api/assets` 只发一次。
- **写**：mutation 后用**前缀匹配** `mutate((key) => typeof key === "string" && key.startsWith("/api/assets"))`
  广播失效。各页据此自动刷新，无需手动传数据。
- **capture 联动（关键）**：`NotificationsBridge` 打开 `/api/notifications/stream` SSE；收到
  `flash_done` / `task_done` 时调用 `revalidatesOnCapture()`，批量失效
  `/api/assets`、`/api/timeline`、`/api/events`、`/api/sessions`。
  → 这是「闪念在后台整理完，前端无需刷新自动冒出卡片」的机制。Flutter 必须复刻这条 SSE→失效链路。
- **Flutter 失效模型**：全局 `dataRevision` ValueNotifier + `bumpData()`（= web 的前缀失效）。
- **列表订阅方式（关键，别用 initState listener）**：列表面（library / calendar / category / entity）在
  `build()` 里用 `ValueListenableBuilder<int>(valueListenable: dataRevision)` 包住，按 revision 取缓存的
  fetch future（`_futureFor(rev)`：`rev` 变了才重新 `_load()`，否则复用）。**为什么不用 `initState +
  dataRevision.addListener`**：那种写法热重载时不会重新注册（`initState` 不重跑），导致「改了刷新逻辑但
  开发时一直不刷新」的假象；`ValueListenableBuilder` 每帧在 build 里重新订阅，既能随数据变化重拉、又能
  在热重载后立即生效。category 详情页用 `addPostFrameCallback` 在 rev 变化时调度一次 `_reload()`（保留
  从 `widget.assets` 快照的即时首屏）。
- **通用刷新安全网（Flutter，关键）**：三层，互补、彼此不依赖，目标是「列表永不残留旧数据」：
  1. **路由 pop / sheet·dialog 关闭** → 根 navigator 挂 `DataRefreshObserver`，任何 pop 都 `bumpData()`。
     覆盖「在 session/快创/编辑里产生数据 → 退回来」。
  2. **SSE 事件** → `AppEvents` 收到 `capture` / `notification` 都 `bumpData()`。覆盖「闪念后台整理完 /
     硬件捕捉 / agent 异步写入」这类前端没主动操作就发生的变更。
  3. **App 回前台** → `AppShell` 挂 `WidgetsBindingObserver`，`AppLifecycleState.resumed` 时 `bumpData()`。
     覆盖「切后台期间数据变了（别的设备 / 推送 / 后台捕捉）→ 回来即刷新」。
  这三层都**不依赖**每个写入点记得手动 `bumpData`（防止新写入点漏刷新这类回归）。每个写入点仍可 `bumpData`
  做停留时的就地刷新。**新建技能**：AddSkillWizard confirm 成功后显式 `bumpData()`，library 的技能格立即
  出现新技能(无需重启/手动刷新)；GET `/api/skills` 返回含 `render_spec` 的全部用户技能，前端不做隐藏过滤
  (仅 external_ref/qa/contact 这三个系统/常驻技能不进技能格)。

### 4.0.4 全局 header bar（Flutter 增量，web demo 无）

Flutter 端在主壳（`AppShell`）顶部加了一条**常驻全局 bar**，承载真正全局的状态/入口，避免每页右上角
重复摆放。它在 Calendar / Library 上方常驻，**不**出现在 pushed 的 chat 路由（chat 有自己的返回/标题/历史栏）。

```
┌─────────────────────────────────────┐
│ Eureka            ☾  🔔  👤  🔌      │ ← 全局 bar（SafeArea top 之下）
├─────────────────────────────────────┤
│   流 [月] 年                    ↻    │ ← 页面头（仅页面专属内容 + 刷新）
```

- 左：**品牌 wordmark**（`assets/logo/eureka_wordmark.svg` = 官方「✦EUREKA」横排，经 `flutter_svg`
  渲染 + `ColorFilter(eu.brand, srcIn)` 染成品牌蓝，单色源 SVG 故同一资产在昼/夜都清晰）。曾是纯 `Text('Eureka')`。
- 右：`ThemeToggle`（昼夜，全局 `themeModeNotifier`）、`NotificationsBell`（未读红点 + 进通知页）、
  **设置**（`👤` → **设置 hub**，见 §4.0.6）、**设备连接**（`🔌` → 硬件配对，见 §4.11）。
- 设备连接：已绑定 → 我的设备；未绑定 → 首配流程。
- 页面头不再放昼夜/通知；日历页头 = 居中 segmented + 刷新，资产库页头 = 标题 + 计数 + 刷新。

> web demo 没有这条全局 bar（它把 🔔+昼夜放在各页 HeaderControls）。这是 Flutter 为「全局状态/设备
> 连接」预留的统一入口。

---

### 4.0.5 登录门（Flutter，TestFlight beta）

App 启动先解析持久化 token（`shared_preferences`，key `eureka_token`），再决定落点：

```
main() → AuthController.load()
  └ _AuthGate (AnimatedBuilder on AuthController)
      ├ !loaded            → 加载圈
      ├ !isAuthed          → LoginPage（邮箱/密码，登录⇄注册切换）
      └ isAuthed           → AppEvents.start() + AppShell（或 START_SESSION 回放）
```

- **token 注入**：`AuthStore.token`（零依赖持有者）被 `ApiClient._headers` 与 SSE client 自动读取，
  带上 `Authorization: Bearer`。`AuthController` 是唯一写入方。
- **401 自愈**：请求在「持有 token 时」收到 401 → `AuthStore.onUnauthorized` → 清 token + 登出 → 门回到
  LoginPage（token 过期/失效场景）。
- **登出**：全局 header 设置（`👤`）→ 设置 hub → 账号（邮箱 + 退出登录）→ `AuthController.logout()`（见 §4.0.6）。
- **provision**：注册成功后端即给新账号建基线 skills，所以首次登录资产库 SKILLS 网格非空（计数全 0）。
- **dev 旁路**：`--dart-define=DEV_TOKEN=<jwt>` 跳过登录页（仅供 headless/截图验证）。
- **登录页 hero = 品牌 lockup**：`SvgPicture.asset` 渲染**渐变全标**（mark + wordmark）—— 浅色
  `assets/logo/eureka_lockup.svg`（渐变深字）、深色 `eureka_lockup_white.svg`（纯白），按 `eu.brightness` 切。曾是 `Text('Eureka')`。

> **品牌 logo 资产体系（2026-06 接入）**：源文件来自设计交付的 `Eureka logo_所有文件`（渐变彩色版 +
> 纯白深底版 + 单色可染版）。app 内只用 3 个 SVG：`eureka_wordmark.svg`(header，单色染品牌蓝)、
> `eureka_lockup.svg`(登录·浅) / `eureka_lockup_white.svg`(登录·深)。依赖 `flutter_svg`。
> **iOS 应用图标**：从 lockup SVG 抠出渐变 mark（去掉文字 path）→ 居中铺在白底 1024 →
> `assets/icon/app_icon_1024.png` → `flutter_launcher_icons`（`remove_alpha_ios:true`，App Store 要求无 alpha）
> 生成全套 `AppIcon.appiconset`。改 logo 重跑 `dart run flutter_launcher_icons`。

### 4.0.6 设置 hub + 已连接应用（Connected Apps）

> **已连接应用 = 已实现**(`mobile/lib/pages/connected_apps_page.dart`):入口暂挂在 `👤` 个人中心 sheet 里的
> 「已连接应用」一项(全屏页);**全屏「设置 hub」整合(账号/偏好/设备并入)仍待做**。已连接应用页 = 两段:
> 「已连接」(状态点 · 测试 · 断开)+「可连接」(catalog 卡 → 连接表单,密钥字段密码框,提交即 `POST /api/connected-apps`)。
> 密钥 write-only(任何 GET 不回显)。完整后端契约见 [§1.7.1](01-agent-architecture.md) / [§3.14](03-api-reference.md)。

header 的 `👤`(目标:从「资料 sheet」升级成一个**全屏设置 hub**,容纳账号级配置)——目前是 sheet + 已连接应用入口:

```
设置
 ├ 账号        邮箱 · 退出登录
 ├ 已连接应用   ← Connected Apps(本节重点)
 ├ 设备连接     ← 硬件 BLE 配对(原 🔌,并入这里;header 可保留 🔌 做快捷)
 └ 偏好        昼夜等(昼夜仍可留 header 快捷切换)
```

**已连接应用页** = 两段:

1. **可连接(目录)**:拉 `GET /api/connectors`,列每个 connector(**品牌 logo** + 名称 + 已连/未连)。点未连的
   → 一个**连接表单**:按 connector 声明的 `fields` 动态渲染输入框(密钥字段用密码框 + "你的密钥只存在服务端、
   加密保存"的说明文案),提交 `POST /api/connected-apps`。**beta 全是 token/网关-URL 粘贴**(见 [§1.7.1](01-agent-architecture.md))。
2. **已连接**:列本用户连接(`GET /api/connected-apps`)。每条:状态 chip(connected / needs_reauth / error)、
   `断开`(DELETE)、`重新连接/测试`(POST `/test`)。**绝不展示已存的密钥**(write-only,见 §3.14)。

要点:
- **品牌 logo(已实现)**:三段(可连接 / 已连接 / 连接表单头)都用 `_connectorLogo()` 渲染真实产品标志,
  不再用 emoji —— `connector_id` 前缀 `dingtalk*` → `assets/logo/dingtalk.svg`(钉钉蓝)、`notion` →
  `assets/logo/notion.svg`(单色 N),白底圆角「应用图标」瓦片;SVG 用 `currentColor` + `colorFilter` 上品牌色。
  未知 connector 回退到 catalog 的 emoji。后端 catalog 的 `icon`(emoji)现在只是 fallback。
- **密钥只进不出**:输入框提交后清空;页面任何地方都不回显已存凭据(后端也不返回)。
- 连接成功后,Agent 那边的「同步到钉钉 / 存到 Notion」才真正可用(运行时按 user 的连接构建 toolset,
  见 §1.7.1);未连时 agent 引导用户来这页连。
- **可深链(给外部资产用)**:本页接受一个目标参数(`connector_id` 或 `external_system`),从**外部资产详情/
  失败的同步**跳进来时(见 §4.4.2 / §4.4.3),**直接定位并高亮对应 connector 的卡片**(未连则直接展开其连接
  表单)。system 对多个 connector 时落到该 system 的分组/筛选。
- 完整后端契约见 [§3.14](03-api-reference.md) + [§2 `connected_apps`](02-data-model.md)。

## 4.1 核心交互：导航 dock（`FloatingDock`）

> **dock = 3 tab(2026-06 今日页落地后改)。** dock = `[今日][日历][资产]` 三个纯导航 tab(**日历回归底栏**;**「我的岛」移出底栏 → 进 Reka 浮球雷达菜单**,见下);
> **全局浮动球球 REKA**(挂根 overlay 浮在**所有页面**之上、可拖、记忆位置,见 [§9.2](09-pet.md))。**短按 → 雷达功能菜单**(快创/洞察/通知/我的岛,corner-aware 扇形;**任务暂从菜单移除**,随岛屿任务 [§7](07-gamemode.md) 落地再加回);**长按 → 续上次对话**(ChatPage)。功能在**气泡**里解析:快创=列所有类型 chip〔带域色点〕→ 底部 sheet 编辑 → 回执气泡 + 庆祝 + 通知+1;洞察(原「总结」,改名去死板)=气泡打字/弹窗选资产→生成(REKA 小动画)→ 结果气泡 + 查看报告 CTA。**通知收敛到 REKA**(角标 + 气泡面板,**header 铃铛已移除**)。🎙 闪念移除(无软件语音)。「我的岛」(REKA 之家:hero + 里程碑 + 换装;周岛/任务占位,待 §7)**从雷达菜单进入,不再是底栏 tab**(2026-06 改)。
> **下文 5 元素 dock = web 参考实现(`frontend/`),Flutter 已不再沿用。** 仍待做:web 端对齐、周岛/任务板块(§7)、脉冲环动画。

web 参考实现(`frontend/`)—— 悬浮胶囊，**5 元素**，非底部 TabBar+FAB：

```
┌───────────────────────────────────────────────┐
│  [日历]  [资产库]  │  (+)  (🎙)  │  [ Agent ▸ ] │
└───────────────────────────────────────────────┘
   导航段（PresentationMode      创建段        Agent pill
   决定哪个在左）                              （紫渐变）
```

| 元素 | 行为 |
|---|---|
| 日历 / 资产库 | 路由切换。顺序随 PresentationMode（资产为主 → 资产库在前）。 |
| **+**（快创） | 打开 `CreateAssetMenu` 底部 sheet（见 §4.4.1）。**仅创建资产**，不含 AI 入口。 |
| **🎙**（闪念） | 打开 `FlashSheet` 底部 sheet（见 §4.3）。 |
| **Agent ▸** | 进入 `/chat`。若有 `AgentTarget`（来自某 detail drawer），peek 进入该 subject 的绑定 session。 |

实现要点：
- `z-[60]` 导航本体，`z-[55]` 辉光。
- 通过 `useIsAnyModalOpen()`（`ModalContext` 计数 > 0）隐藏——任何 sheet/drawer 打开时 dock 让位。
  例外：`AssetDetailDrawer` 用 `useModalMount({ keepDock: true })` **保留** dock，因为此时 dock 的
  Agent 按钮正是「进入这条资产的绑定会话」的入口（取代了旧的 drawer 内「在 chat 里讨论」按钮）。
- **doctrine（贯穿全产品）**：dock = 全局、上下文绑定的 Agent 入口。所有 detail/edit 表单（AssetDetailDrawer /
  EventForm / ContactForm）都**不内嵌**「讨论」按钮；它们 mount 时 `setAgentTarget({subject, label})`，
  unmount 时清空。

---

## 4.2 Chat 页（`/chat`）—— 产品核心

### 4.2.1 布局（`ChatPage.tsx`）

```
┌──────────────────────────────────────┐
│ ← 返回X    会话标题       History(☰)  │ ← 顶栏（shrink-0）
├──────────────────────────────────────┤
│ SessionTopicBar（subject + context）  │ ← 仅有 session/pendingSubject 时
├──────────────────────────────────────┤
│                                      │
│  MessageList（flex-1，自己滚动）       │
│                                      │
├──────────────────────────────────────┤
│ ChatInput（sticky 底，shrink-0）       │
└──────────────────────────────────────┘
```

桌面 `SessionSidebar` 常驻左侧；手机折叠为抽屉，由 History 图标开。抽屉里每条会话**向左滑可删除**
（confirm 弹窗 → `DELETE /api/sessions/{id}`，见 §3.5）；删的是会话+转录，其中产生的资产会保留。

### 4.2.2 会话状态机（移植最易丢的部分）

- `activeSessionId` 持久化在 `localStorage["eureka:active_chat_session"]`，reload 续上。
- 三个 SWR/hook 联动：`useSessionMessages(id)`（历史）+ `useSessionDetail(id)`（subject/context FK）→
  `dbToChatMessage()` 转成 `ChatMessage` → seed 进 `useChat`。
- **lazy session create**：新会话**不预先** POST `/api/sessions`。首条消息发出时，后端 SSE 的 `meta` 帧
  携带新 `session_id`，前端据此 `setActiveSessionId`。
- **re-seed 规则（issue #3 防线，务必照搬）**：
  - `chat.streaming` 时**绝不** re-seed（会抹掉乐观/流式气泡）。
  - 仅当 `chat.messages` 为空、或 `initialMessages.length > chat.messages.length`（服务器侧长出新消息，
    如同 session 内的硬件闪念写入）时才 `chat.reset(initialMessages)`。
  - 长度比较防循环：re-seed 后两者相等，`>` 守卫转 false。
- **返回时对账 in-flight 回合（✅ 已实现,`chat_controller._reconcilePending`,见 [§1.5.1.1/.3](01-agent-architecture.md)）**：离开再回到 session，加载线程后**按最新回合 `status` 渲染** —— `pending/running` → 显「分析中…」占位 + 轮询(或通知 SSE)直到落定;`done` → 直接显回复/资产。**用户消息收到即落库**(后端),所以**返回后输入一定在**;生成是后台任务(断流也跑完),不再「离开就丢」。配合上面的 re-seed:回合落定后服务器侧长出 agent 消息 → `initialMessages.length >` 触发 re-seed 显出来。
- **pendingSubject（lazy 绑定）**：dock 的 Agent 带 `pendingSubject` 进来时，ChatPage 起始留空（不让
  localStorage 旧 session 遮蔽新绑定意图），topic bar 先显示「你将要聊 Kevin」，**首条发送时**才
  `openSession({subject})` 真正建会话——避免误点 Agent 留下空会话。
- **空会话防线（适用于全部入口）**：「打开 chat（dock Agent）」「点 asset 卡片的『讨论』」「侧栏『新对话』」
  这三种动作**都不得直接建 session**。
  - 普通新对话：`session_id` 留空，靠 `/api/chat` 的 SSE `meta` 帧由后端 lazy-create。
  - 主题（讨论）线程：先用 `POST /api/sessions{subject_type,subject_id,peek_only:true}` **查不建**——
    命中既有线程就回放，未命中保持空白，**首条消息**才 get-or-create 绑定 subject 的 session
    （`/api/chat` 无 subject 参数，故 subject 会话必须在发送前存在；普通对话则交给 meta 帧）。
  - 只有用户**真的产生输入**（发消息，或「+ 添加资产」附加上下文）才落 session。
- **会话标题必须可读**：顶栏与侧栏都显示可读标题，后端按首条用户消息自动起名
  （如「我有什么代办」「讨论:交季度报告」）。前端取 `session.title`；缺失时回退「裁剪后的首条用户消息」，
  再回退「新对话」；讨论线程顶栏直接用 subject 标签（如「和张总吃饭」）。**绝不**把标题渲染成常量
  「Agent」之类的占位。
- **从某个 asset 进入 = 永远是该 asset 的同一个会话（已实现，验证过）**：asset 详情的「讨论」用
  `subjectType/subjectId/subjectLabel` 开 ChatPage → `bindSubject` 先 `peek_only` 查既有线程回放，首条发送
  `ensureSession` 走 `POST /api/sessions{subject_type,subject_id}` **get-or-create by subject FK** →
  同一 asset 反复进入**总是命中同一 session**(curl 三连 create/create/peek 返回同一 id)。
- **开场 hint（资产锚定会话的空态，设计中 [§1.5.1](01-agent-architecture.md)）**：当 `peek_only` 查到**空线程**(首次就该资产发起讨论)时,
  `ChatPage` 空态不是空输入框,而是渲染一个**开场白 + 2-3 个起聊建议 chip**(点 chip = 作为首条用户消息发出 → 进正常 chat)。
  内容由 §1.5.1 的三层逻辑生成(v1 = 模板起聊 + 计算填充,即时零 LLM;LLM 富化后置)。**有历史 → 无 hint**,直接回放线程。
- **anchored 主语常驻「关联资产」**：`ChatPage._contextBar` 把锚定主语渲染成一个**常驻 accent chip**
  (🔗,同一会话内不可手动移除)，与用户后续「+ 添加资产」加进来的普通 context chip 并列。**`+ 添加资产` chip 放在 rail 最前**
  (不用滚过一长串 context 才够得着)。**锚定主语用页内可变 `_anchorLabel`(initState 从 `widget.subjectLabel` 镜像)驱动 chip + 顶栏标题**,
  这样「新对话」能清掉它(widget 参数不可变,直接读会清不掉 —— 这是早期 context 泄漏的根因之一)。
- **「新对话」= 零上下文(✅ 已修)**:主动新建对话**必须不带任何上下文**。三处入口统一走「清空」:
  - `ChatController.reset()` 清 `messages/sessionId/sessionTitle/subjectType/subjectId/**contextAssets**/error` 并 `_persistActive(null)`(早先漏清 `contextAssets` → 附加资产泄漏到新对话)。
  - 侧栏「新对话」按钮 → 页面 `_newConversation()`(清 `_context` 列 + `_anchorLabel` + `reset()`),不再只调 `chat.reset()`。
  - REKA 气泡「新建对话」→ `ChatPage(startBlank:true)`:initState **跳过 `resumeLast()`**(早先 push `const ChatPage()` 会落进 resume 分支 → 「新建对话」实际是续上次、把旧 context 带过来)。浮球**长按**仍 `ChatPage()` = 续上次对话(resume),两者区分开。
- **重开历史会话时恢复 context chip(已修,codex r2)**：`loadSession` 额外拉 `GET /api/sessions/{id}` 的
  `context_assets`([{id,label}],后端按 `context_asset_ids` 解析),存进 `ChatController.contextAssets`;
  `chat_page._onChange` 在 `_context` 为空时**从中 seed 一次** → 之前重开会话 chip 栏空、用户误以为没附加上下文的问题修掉。
- **「+ 添加资产」picker（`_AssetPicker`）**：拉 assets + skills + render_specs。
  - **固定尺寸**：sheet 高度固定 = `screenHeight * 0.62`(1/2–2/3 区间),**不**随资产数量伸缩。
  - **多选 + 已选可取消**：点行 toggle 选中(右侧 ✓ 圈)；选中项另在底部确认条**上方**渲染成一排可点 chip
    (`标题 ×`,点即取消选择,不用回列表里找)；确认条显示「已选 N 项」+「添加 N 项」；确认后一次性
    `attachContexts([...ids])`(单个 PATCH 批量加)，把每条都加进 chat 上下文 chip。
  - **筛选**：顶部一排 chip = `全部` + 每个**出现过的** skill 类型(标签用 display_name)，点选过滤列表。
  - **可读标题(通用方案,非临时 patch)**：用 `readableTitle(payload, render_spec)` 统一解析每条的标题 ——
    优先 `render_spec.primary_field`(再 secondary)→ 常见文本字段(content/title/name/…)→ payload 里第一个
    非空字符串 → 兜底用 skill **display_name**。**绝不**回退到 machine_name(否则自定义 skill 的卡片标题会
    显示成 `book_note` 这种不可读机器名)。选中后用 `AssetItem.copyWithTitle()` 把解析出的标题带进 chat
    上下文标签。该 helper 放在 `render_spec.dart`，任何需要给 asset 起可读名的地方复用。

### 4.2.3 SSE 流渲染（`useChat` + `MessageBubble`）

`ChatPart` 联合类型：`text | tool_call | tool_result | cards | error`。一条 agent 消息是**有序 parts 序列**，
保留 SSE 到达顺序。`applyFrame()` 按帧类型 merge（text 帧累加进末个 text part）。

**PartRenderer 逐类型规则**（`MessageBubble.tsx`，移植对照重点）：

| part | 渲染 |
|---|---|
| `text`（流式中且 isLast） | 原文 + 闪烁 `Cursor`（不解析 markdown，避免半句 `**` 抖动） |
| `text`（已落定） | `MarkdownText` 轻量渲染：`**粗体**`、`` `代码` ``、`*斜体*`、`-/*` 列表、`1.` 列表、`#` 标题、`>` 引用、**`\| 表格 \|`**、**`:::callout{tone=insight\|warn\|success}`** 染色提示框（§6 注解 md 的一个子集）。其余报告指令 `:::rank/:::kpi/:::compare` **优雅降级**：剥掉 `:::` 外壳、内部 md 照常渲染（不显示生硬的 `:::` 文本）。完整富 DSL + 动效仍由**报告 WebView**（`report_viewer_page`,backend→HTML→WKWebView）承载。**不用 dangerouslySetInnerHTML**，纯节点拼装。 |
| `tool_call`（流式中且 isLast） | 琥珀色 chip「{中文名}中…」+ spinner。**落定后的 tool_call 不渲染**（其 tool_result 接续，重复 chip 冗余）。 |
| `tool_result`（query 类） | `CollapsibleQueryResult`：折叠成「↩ 查询资产 · 找到 N 项 ▸」，点开展开（避免中间查询结果刷屏）。**只在当下渲染、不持久化**——查询卡是临时视图（真值在资产库），退出 session 再回看时这些卡**不回放**，只剩 agent 的文字总览（故 QUERY 文字须点名查到了啥，见 [§1 QUERY](01-agent-architecture.md)）。对比下行 `cards`（create/update）才会进 `Message.cards` 回放 |
| `tool_result`（其它，有卡片） | 每张 `AssetCardInChat`（inline 布局，点开 `AssetDetailDrawer`） |
| `tool_result`（无卡片，如 delete） | 小字「↩ {中文名} 完成」 |
| `cards`（持久化的 flash 卡） | 每张 `AssetCardInChat` |
| `error` | 红色 chip + `AlertCircle` |

工具中文名映射见 `TOOL_LABEL`（`tool_create_asset`→「创建资产」… 全表见源码 / §A）。
`QUERY_TOOLS = {tool_query_asset, tool_query_event, tool_query_contact, tool_query_input_turn,
tool_query_digest, tool_get_event, tool_get_asset, tool_get_contact, tool_get_input_turn,
query_asset, query_event, query_contact, query_input_turn, query_digest, get_event,
get_asset, get_contact, get_input_turn}`。带/不带 `tool_` 前缀都按只读查询处理，避免
外部同步前的本地 reference 查询被误渲染成持久结果卡。

卡片类型标记 `tagByIdField()`：按 id 字段推 `card_type`——**`task_id` 优先于 `asset_id`**（create_task
结果同时带二者，task 路由到生命周期卡），其后 `event_id`→event、`contact_id`→contact、`input_turn_id`→input_turn。

### 4.2.4 「沉淀为资产」（`PrecipitateMenu`）

判定时机 = 一轮 agent 输出之后：
- **显示**条件：非流式 + 有 `onPrecipitate` + 纯文本长度 > 8 + **本轮未创建卡片**（`turnCreatedCards()` 为 false）。
- `turnCreatedCards()`：有 `cards` part，或非 query 的 tool_result 产出了卡片 → 视为已创建 → 不显沉淀。
  （deepseek 偶尔在知识问答里误发一次 query，所以**不能**用「有任何工具活动」来 gate。）
- 目标 skill（**随记合并后为 2 个**，Flutter `chat_page._types`）：`todo`（✅ 待办）/ `notes`（✍️ 随记）。
  老的 `idea`/`misc` 已并入随记（§3.2.1），不再单列；**无** expense/contact/event（那些需结构化输入）。
- 点选 → `handlePrecipitate(text, skill)` → POST `/api/assets`（`notes` 额外从首行裁 ≤24 字做 title）→
  失效 `/api/assets`。内联显示 saving/done(「已沉淀为待办」)/error 状态。

### 4.2.5 ChatInput

- 自增高 textarea，1 行起，封顶 232px（≈10 行）后内部滚动。
- `Enter` 发送、`Shift+Enter` 换行。**IME 守卫**：`e.nativeEvent.isComposing` 为真（中文输入法组字中）时
  不发送——CJK 必备，移植务必实现。
- streaming 时 send 按钮变 `StopCircle`（注：后端**暂不支持 abort**，按钮预留）。

### 4.2.6 TurnCostFooter

落定 agent 轮的尾部小字「用时 3.2s · 1.4k tokens」，来自 `message.meta`（SSE `done` 帧带 elapsed/tokens）。
tokens 缺失时省略。

---

## 4.3 闪念捕捉（`FlashSheet` + `useFlashCapture`）

- dock 🎙 → `FlashSheet` 底部 sheet。提示「约 15-30 秒」。`⌘/Ctrl+Enter` 提交。
- `useFlashCapture.capture(text)` → **POST `/api/flash`（同步 JSON，非 SSE）**，timeout 90s，`source:"voice"`。
- 返回 `FlashResponse{ session_id, cards[] }`。成功后失效 `/api/assets`、`/api/events`、`/api/sessions`、`/api/timeline`。
- demo 用文字模拟语音；浏览器麦克风/文字直接作 InputTurn 文本，不接云 ASR、无 speaker 分离。

> Flash 与 Chat 是**两类入口、共享 agent 栈**：Flash=同步整理捕捉，Chat=SSE 流式对话。前端处理完全不同
> （一个 await JSON，一个 read stream），移植别混。

---

## 4.4 资产库（`/library`）

### 4.4.0 CategoryList（首页 hub）

并行拉 3 个源（SWR 去重）：`/api/assets?limit=500`、`/api/events`、`/api/contacts`。

> **导出(✅ 新增 2026-06,`LibraryPage` header `ios_share` 按钮)**:**不是默认全量** —— 点 → `_ExportSheet`:
> **勾选要导的类型**(有数据的资产 skill + 事件 + 名片,各带条数,默认全选,带「全选/全不选」)+ **选格式 Markdown / CSV** →
> 「导出 N 类」→ `GET /api/export?format=md|csv&types=<逗号分隔>`(`backend/api/export.py`,只读、user-scoped;`types` 空=全部,
> 后端按 type key 过滤:资产按 skill machine_name、`event`/`contact` 控实体表)→ 写临时文件 → **原生分享面板**(`share_plus`)。
> **MD** = 选中类型按类型分组、人类可读(资产按 skill 分段,字段用 label 渲染;事件/名片各一段);
> **CSV** = 每条一行 `kind,type,title,domain,created_at,detail_json`,异构 payload 落到 `detail_json`(Python `csv` 正确转义)。
> 文件名 `eureka_export_YYYYMMDD.{md,csv}`。

> **文件实体已下线（Flutter）**：早期 web demo 有「文件(♪)」一级实体（闪念录音等）。产品上它对用户无意义，
> 已从 app 移除——`常驻` 不再有文件 tile、`最近` 不合并文件、日历/时间线 `fetchTimeline` 过滤掉 `kind=='file'`、
> SkillCard / detail sheet / render_spec 不再有 `file` 分支。后端 `/api/files`(供事件附件/音频基础设施)保留,
> 只是前端不再把它当可浏览实体。

三段式：
1. **常驻 · PERMANENT**（3-col grid，6 tile）：**系统级常驻** = `待办(todo) · 随记(notes) · 事件 · 名片 · 外部 · 报告`。
   每 tile = 图标块(辉光) + label + mono count;待办/随记/外部点进 `CategoryDetailPage`,事件/名片进各自实体列表,
   **报告(📊)→ `ReportListPage`(报告容器:✨洞察 CTA + 历史列表,§6.8.4 / §4.4.4)**。
   这些**始终在,不可删、不参与活跃集 toggle、不计入 9-cap**(系统能力)。
2. **活跃技能 · SKILLS**：`SkillsGrid`,**只显可选活跃技能**(`记账(expense)` + 自定义,`enabled=1`,按 `position`)。
   **首格**是「新技能」(✨) tile → `AddSkillWizard`,**虚线品牌色边框**(`_DashedBorder`),右下角显示
   **`活跃数/上限`**(如 `4/9`,满转红 —— `_activeCap=9` 同步后端 `ACTIVE_SKILL_CAP`)。**计数只算可选技能**
   (记账 + 自定义),**常驻 待办/随记 与系统 external_ref/qa/contact 都不计入**。保护集 `{todo, expense, 随记}` 不可删。
   - **活跃集（已实现）**：段头右侧「⚙ 全部技能」入口 → **技能管理页 §4.4.5**(列可切换的(记账+自定义),开关激活)。
     即「格子 = 可选活跃集（≤9，不含常驻），管理页 = 全量可切换技能（≤30 注册）」。新建技能默认活跃,活跃已满 9 → 落为停用。
3. **最近 · RECENT**：跨类型最新 N 条，**按天分组**（今天/昨天/M月D日）。合并 asset/event/contact，按
   `created_at` desc。事件走 `EventCard`、资产/名片走 `SkillCard`（**强制 `layoutOverride="horizontal"`**
   让每行等高）。
   - **Flutter 实现注意（曾漏 → 已修）**：`LibraryPage` 必须**拉实体的完整记录**(events/contacts 的 list,
     不只是 count) 再合并进「最近」——一级实体存在各自的表,**永远不在 `/api/assets`**,所以早期只把它们当
     count、最近列表只渲染 assets,导致「新建的事件/名片不出现在最近」。`_buildRecent` 把 assets + events +
     contacts 统一成 `_RecentEntry{createdAt, card}`(card 带 `card_type` 给 SkillCard 分流),按 `createdAt`
     desc。**比早期 web 多收了 contacts**(原 web buildRecent 只合并 asset/event/file)——产品上「最近」就该
     含新建的名片。

count/preview 规则：event→`/api/events`、contact→`/api/contacts`、其余→assets 按 `user_skill_name` 过滤。
preview = 首条 title-ish 字段（content/title/name），自建 skill 无匹配则空串（避免吐机器名）。

### 4.4.1 CreateAssetMenu（+ 快创 sheet）

- 底部 sheet，2-col tile grid。`creatable = skills.filter(有 render_spec && ≠qa && ≠external_ref)`。
- **硬编码「事件」tile**（event 是一级实体非 skill）→ 直接开 `EventForm`。
- 点 skill tile → **该 skill 的 `AssetEditPage`(create 模式)** —— **创建与编辑用同一个组件**(见 §4.4.3a),
  「create = 空数据的 edit」,不再有独立的 `SkillCreateForm`(已删)。contact tile → `ContactForm`;event tile → `EventForm`。
- **刻意不含 AI 入口**：跟 Agent 对话 / 闪念 已在 dock 的 Agent pill + 🎙——所以「+」语义纯粹是「造一个东西」。

### 4.4.2 CategoryDetail（drill-down）

- 由 `:skillName` 驱动。一级实体（event/file/contact）走各自专用 endpoint + **内联硬编码 fake render_spec**；
  其余 asset-backed skill 走 `useAssets({skillName})` + registry 的 render_spec。
- 列表每条 `SkillCard`，点开 `AssetDetailDrawer`。todo 类带 `onToggleCheck`（`useToggleTodo`）。
- **按天分隔（Flutter 增量,已实现 `CategoryDetailPage._withDayHeaders`）**：列表维持 `created_at` 倒序，
  只在**跨天处插一个轻分组头**（今天 / 昨天 / M月D日），复用「最近」「日历」的分组样式。**仅视觉分隔,不加排序菜单**(刻意从简)。
- **删除技能**（仅非保护 + 有 user_skill_id）：右上 🗑 → `DeleteSkillDialog` 两段确认。
  无资产 → 「确定删除」；有资产 → force-confirm「这会同时删除 N 条记录」，`DELETE /api/skills/:id?force=true`。
  > ⚠️ 已知 bug：`api/skills.py` 级联删除用了 Postgres 专有 SQL，MySQL 跑不通（见 §2/§3）。
- **外部(`external_ref`)容器 → 管理连接入口（已实现 `CategoryDetailPage._manageConnectionsCard`）**：这个容器装的是
  同步到第三方的引用。当 `skillName=='external_ref'` 时,列表**顶部**放一张「🔗 管理连接 →」品牌色卡片 → push
  `ConnectedAppsPage`（§4.0.6 / §1.7.1），**即使列表为空也显示**（空态文案「还没有同步到外部的内容」）。
  让用户从"看外部产物"的地方直接去"管外部连接"。

### 4.4.3 AssetDetailDrawer（通用详情）—— 全产品复用

手机底部 sheet（max-h 85vh），`eu-sheet-up` 入场。`keepDock:true` 保 dock。Esc 关闭。

结构：
- **Hero**：cardType caps + 关闭 ✕ → 54px 渐变图标块（或 `McpBrandMark` 若是 MCP 品牌图标）→ 大标题 → 副标题。
- **Action row**：`编辑`（可编辑时）/ `删除`（双击确认：首击变「确认删除」红，再击真删）/ `打开外部链接`（payload 有 `external_url` 时）。
- **管理连接入口（外部同步资产专属,设计中）**：当 cardType=`external_ref` 或 payload 带 `external_system` 时,
  Action row 多一个 **「管理连接 / 重新连接 <app>」** → 深链到 设置 → 已连接应用 的**对应 connector**
  (按 `payload.external_system` 映射到 catalog;一个 system 对多个 connector 时落到该 system 的分组/筛选)。
  **失败态优先**:当这条外部同步是 `pending` 卡住 / `failed`(常因该 app 未连接或需重新授权)时,把这个入口
  **提级成显眼的修复 CTA**(「该应用需要重新连接 →」),让 §1.7.1 的「同步失败 → 去连接 → 重试」闭环。
- **来源 · SOURCE**：三态——
  - `manual`（无 session）：✎「手动创建」，不可点。
  - `flash`（source session 是 flash）：⚡蓝色，点 → 打开该捕捉 session。
  - `agent`（chat）：●琥珀，点 → 打开创建会话。
  点击都 `localStorage` set active session + `navigate("/chat", {state:{from, fromLabel}})`。
- **Payload 字段**：遍历 `payload`，`shouldSkipField` 过滤内部 plumbing（`SKIP_KEYS` 一大串：ok/card_type/
  user_id/all_day/status/各种 id/render-spec 泄漏键…）。数组 → `ArrayField`（chip 列表，对象取 name(role)）。
- **通用详情重构(✅ Flutter `asset_detail_sheet.dart`,对齐设计稿「组件调整稿」)**:不再假设「内容=主体」—— 用户记录种类各异,**长内容只是某个命名字段**(随记叫 `content`、工作小结叫 `work_summary`),位置随类型变,且可与短字段共存。统一成一套 **general** 方案,渲染规则直接来自 `render_spec` 字段角色:
  - **一个 sheet 两态(`DraggableScrollableSheet`)**:**半屏 peek(0.62)→ 拖动 / 点「展开全文」拉满屏(0.95)** 专心读 —— 取代早先「预览 sheet + 另推全屏页」(用户定:一个 sheet 两态)。`onExpand` 把控制器 `animateTo(0.95)`。
  - **层级 + 去重(原主次调转)**:`hero`(accent 图标块 + 大标题 + 副标题 + 可点 domain chip)。**主→标题、副→副标题只在 hero 出现一次**,下方字段列表**不再重复抄一遍**(修了截图里 `¥25`/「金额 ¥25」、book_title 抄标题那种)。然后 **信息字段**(短字段 `label→value` 轻列表 `_infoList`)→ **长文字段**(md block)→ **来源一行**。标题字号按类型放大(`primary_format==currency` 或标题 ≤4 字 → 30px,如 ¥25)。
  - **长内容 = markdown doc block(`_DocBlock`)**:按**字符数/换行数**通用判定(不写死字段名),渲染成 **markdown**(`MarkdownText`,复用 chat 渲染器 + 新增 `baseStyle` 大阅读字号 + 新增 `>` 引用块);peek 态**折叠到 132px + 底部渐隐 + 居中「展开全文」pill**,展开同时把 sheet 拉满。
  - **来源收一行 + manual 隐藏(spec §四)**:有来源 session → 底部一行 `⚡ 由「闪念/对话」整理 · 查看原始记录 ›`(分隔线在上);**手动创建(无 session)→ 整行不显示**(不再有那块重蓝盒,也不显「手动创建」)。
  - **sticky 底部操作条**:`讨论 / 编辑 / 删除` 固定在 sheet 底部、上方渐隐过渡(不随内容滚走);删除走确认 dialog。
    **不透出内容(✅ 修 2026-06)**:操作条是「**短渐隐条(20px,内容溶入)+ 其下实心 `surfaceRaised` 条(放按钮)**」——
    早先整条用透明→实的渐变铺满,顶部透明区盖在按钮上 → 滚动内容从**ghost「讨论」按钮**里透出来。现按钮区背景实心,且 ghost 按钮(讨论/删除)给 `eu.surface` 实底,彻底不透。
- **字段标签 + 格式 = skill 自定义驱动（关键，别按字段名瞎猜）**：
  - **标签**：优先用该 skill 的 `payload_schema[field].label`（design agent / 种子给每个字段写的 2-5 字中文短
    标签，例 喝水 skill 的 `amount`→「水量」）；缺失才回退「通用字段名表」（content→内容、due_date→截止时间…），
    再回退字段名本身。**绝不**把任意 `amount` 当「金额」——那是 expense 专属语义。
  - **格式**：以该 skill 的 `render_spec` 字段格式为准（`primary_format`/`secondary_format`/`meta_fields[].format`）——
    例如 expense 在自己的 render_spec 里把 `amount` 标成 `currency`，所以 ¥ 来自 render_spec 而**不是**字段名推断。
    render_spec 没声明的字段才做「按值兜底推断」（ISO 串 → 日期格式），**永不**按字段名推断货币。
  - 迁移注意:Flutter 把 RenderSpec 加了 `fieldLabels`(来自 payload_schema)+ `formatForField()`,detail sheet
    收 `spec` 参数据此渲染;`_inferFormat` 只剩日期类兜底。`MULTILINE_KEYS` 决定多行。
  - **每个入口都必须传 `spec` + `domain`(✅ 已修,关键)**:detail/edit 的中文 label、完整字段(`schemaFields`)、长文判定(`longFields`)、hero 领域 chip **全靠 `showAssetDetail(spec:, data.domain)`**。`SkillCard`(chat/库/类目)从 `renderSpecsProvider` 传了;但**流(timeline)`calendar_page._openAssetDetail` 与 `notifications_page` 之前没传** → 详情显示英文机器名(feeling/activity…)、todo 只剩 content 一字段、领域 chip 空。修:这两条路径也 `await fetchRenderSpecs(api)[skill]` 取真 spec + `record['domain']` 带进 `data.copyWith(domain:)`。
  - **AI 设计「确认技能」弹窗也按此区分(✅ 已修)**:`add_skill._fieldRow` 原先直接显示**机器字段名**(distance/duration/
    pace/note),与设计稿不符。现读 `_draft['payload_schema'][f].label` → **中文 label 作主名(加粗)+ 英文机器键作下方
    dim 副行**(label 缺失才单显机器名)。机器键仍是 payload/查询用的真实 key,label 仅供人读 —— 一眼区分「给人看的名」
    与「存储用的键」。(label 由 design agent 强制产出,见 §1 design_agent「每个字段必须给 label」。)
- **编辑分支**：`isEvent`→`EventForm`、`isContact`→`ContactForm`、其余→`AssetEditPage`（`existing` 预填）。
  编辑表单是全屏模态，关闭后回到 drawer（SWR 已刷新 payload）。
- **创建 = 编辑(同一组件 `AssetEditPage`,✅ 修 2026-06「快创面板和编辑完全不一样」)**:`assetId==null` → CREATE
  (空/预填 payload → `POST /api/assets`,pop 一个回执 map);否则 EDIT(`PUT payload_patch`)。**两边像素级一致**,只是
  一个有数据一个空 —— 同一套实时卡片预览 + 文档标题 + 类型感知控件 + markdown + **领域选择器**(create/edit 都带,
  `RenderSpec.requiredFields` 在 CREATE 时校验必填)。**快创(库 `CreateAssetMenu` + REKA quick-create)与编辑不再各画一套**;
  asset-skill 的 `SkillCreateForm` 已删。create 的 spec 由 `renderSpecForSkill(SkillDef)`(`.withSchema(schema)`)
  现造,卡片预览仍走 provider 全 spec。event/contact 仍是各自专用表单(非 asset)。
- **编辑 = 全屏页 + markdown 编辑器(✅ Flutter `AssetEditPage`,对齐设计稿)**:原 Flutter 实现是「详情 sheet 上**再叠一个底部 sheet**」—— 输入大段内容时太憋。改为 **push 一个全屏编辑页**(appBar:取消 + 类型 caps + 保存):
  - **顶部实时卡片预览(✅)**:页首一张 `SkillCard`(`IgnorePointer` 非交互),`payload` 来自当前各字段控件值,**每次输入 setState 重渲染** —— 改字段「长什么样」一眼可见(对齐用户要的「卡片+字段 preview + 基本改动」)。
  - **标题升为文档标题输入**:textual 主字段(`render_spec.primary_field`,如 `book_title`,排除 currency/数字)或 `title`/`name` → 顶部**大号无边框文档标题输入** + 分隔线;其余字段在下。
  - **编辑按 skill 完整 schema 渲染(✅ 关键,修字段不一致)**:控件来自 **`RenderSpec.schemaFields`(payload_schema 全字段,声明序)∪ payload 里的 orphan 字段**(如 skill 重生成后遗留的旧 `note`)——不再只渲染「该 asset 恰好抓到的字段」。**同一 skill 的每条 asset 编辑结构一致**(空字段也显示、可补全);保存时**新空字段不入 patch**。(根因:同一 reading_notes skill 被重生成过,schema 从 `note` 漂成 `key_insights`,旧 asset 留 orphan;三条读书笔记字段集各异。)
  - **短字段 + 长文共存(Kevin #2)** + **`long` 字段声明驱动(✅)**:**长文判定从 schema 来,不再硬猜** —— 字段在 `payload_schema[f].long==true`(design agent 创建时按语义判定:感想/小结/正文/要点/评价/描述 → true;数字/日期/名称 → false)→ `RenderSpec.longFields` → 给 **大号 markdown 编辑器** `MdEditor`(min-height 220、`maxLines:null`、**编辑/预览**切换 → 预览即 `MarkdownText`)。**兜底**(旧 skill 无 `long`):key 名单(content/note/key_insights/summary/insights…)+ 当前值已长。短字段仍走紧凑输入。后端 confirm `_backfill_long`(按 key 名启发式补 `long`),新 skill 字段恒带此标志。
  - **类型感知控件(✅ Flutter `AssetEditPage`,修「todo 只有一个文本框」)**:控件由 **`RenderSpec.fieldTypes`(payload_schema 的 `type`)** 驱动,不再一律文本框 —— `datetime`/`date`→`_DateField`(点开 `showDatePicker`[+`showTimePicker`]、date-only 无时间段、X 可清空、显示 `YYYY年M月D日 [HH:mm]`);`boolean`→`_BoolField`(`Switch`,`all_day`/`done`/`completed` 自动归此);`array`→`_ChipsField`(可删 chip + 行内「+ 添加」提交);`long`/doc-key→大号 `MdEditor`;其余→紧凑短输入(`number` 走数字键盘)。**类型缺失兜底**:按 key 名推断(`*_at`/`*_date`/`due`/ISO 串→datetime;`all_day`/`done`/bool→boolean;`List`→array)。**序列化**:datetime → `YYYY-MM-DDTHH:mm:00+08:00`(date-only 出裸日期)。保存只把**变化字段**入 `payload_patch`。
  - **event/contact 走专用表单(✅ Flutter,对齐 §4.4.3 编辑分支 + 用户「event/contact 做专用表单」)**:`_AssetView._edit()` 按 `cardType` 分流 —— `event`→`EventForm(eventId,existing)`、`contact`→`ContactForm(contactId,existing)`(**真身实体,flat `PUT /api/events|contacts`**,不进 `/api/assets`),其余 asset → 上面的 type-aware `AssetEditPage`(`PUT /api/assets {payload_patch}`)。`EventForm` 有 start/end 双时间 picker + 全天开关 + `end>start` 校验;`ContactForm`(新增,姓名*/公司/职位/电话/邮箱/备注)。两者编辑成功 pop `true` → drawer `bumpData()` 关闭回刷。`AssetEditPage._save` 仍留 event/contact 兜底分支(`all_day`→0/1)以防分流遗漏。timeline 取记录时 `assetId` 已解析成真身 id(`event_id`/contact 的 `id`),专用表单可直接用。
  - **字段标签兜底**:`fieldLabels`(payload_schema 的 label)缺失 → 落 detail/edit 的**通用字段名表**(已补 `book_title→书名`、`key_insights→要点`、`time_spent→用时`…)→ 再落机器名。**后端 confirm 时也 `_backfill_labels`**:design agent 漏给 label 的常见字段在落库前补中文 label(`api/skills.py`),新 skill 不再存 null label;旧 skill 走前端兜底。(未做:旧 asset 的 schema 漂移迁移 —— 需按 skill 逐个改名,后置。)
  - **不做格式工具条**(用户定):无 B/I/列表/引用 按钮 —— 要效果就**直接敲 markdown 符号**(`# **  *  -  >`),hint 已提示。保存走原 `payload_patch`/event/contact PUT,`bumpData()` + pop 回刷新后的列表。
- **删除 endpoint**：event→`/api/events/:id`、contact→`/api/contacts/:id`、其余→`/api/assets/:id`；
  成功失效 assets/events/contacts/timeline。
- **AgentTarget**：mount 时按 cardType 推 subjectType（contact/event/file/asset）`setAgentTarget`，unmount 清空。

### 4.4.3a domain 展示 + 选择器（设计中 · 完整语义见 [§8 领域系统](08-domain-system.md)）

每条记录有一个**生活领域 `domain`**（8 选 1，见 [§2 §3.6](02-data-model.md) / [§8](08-domain-system.md)）。前端两件事:**显示** + **可编辑**。

**① 展示 domain chip（[§8.3](08-domain-system.md#83-展示让-domain-在-ui-露出来)）**:`SkillCard` / 事件卡 / timeline 条目的 meta 区显示一个**小色点 + 2 字领域名**（`domain==null` 不显示、不占位）;`AssetDetailDrawer` hero 副标题旁一个可点 chip（点 → 进编辑改领域）。8 领域配色复用 §5 accent 槽（映射表见 §8.3，终版图标走 design doc）。

**② domain 选择器（表单）**——规则:

- **范围 = asset-backed 表单**（`AssetEditPage`：todo / 随记 / expense / 自定义,**create 与 edit 同款**）。选择器在表单末尾，
  8 个 chip（工作/学习/健康/运动/社交/娱乐/生活/灵感）单选，**预填**该技能的 `domain` prior（`GET /api/skills` 返回；
  `随记` 预填「灵感」）。用户可改、可清空（→ null = 不归域、不长岛）。
- **事件 / 名片不在此列**：`event` 经一级表、靠**反应式任务**长岛（domain 由 daily-gen 的任务按内容带，§7.3.2），其本身 v1 不存 domain 列；
  `contact` 定义即「社交」（机会型创建直接以 `社交` 长岛，§8.4），故 `EventForm` / `ContactForm` **不加** domain 选择器。
- **AI/闪念创建**：agent 落库时已按内容打了 `domain`（§1 / §7.10），用户**无需**手填；想纠正就进编辑表单改。
  所以「手动 + 表单」是显式选，「对话/闪念」是 agent 猜 + 事后可改——两条路最终都写同一个 `assets.domain`。
- **编辑表单**（`AssetDetailDrawer` → 编辑分支，asset-backed 那支）同样带这个选择器，**预填当前 `assets.domain`**；
  改完 `PUT /api/assets/:id` 带 `domain`（与 payload 同一次提交）。改 domain **不追溯**已落的 `completion_events`
  （货币 append-only，§7.1）——只影响该记录此后的归属与展示。
- **视觉**：复用 §5 的 chip / 单选样式，不抢主字段焦点（放表单底部、副标题级权重）；空选有「未归类」灰态。

### 4.4.4 报告容器 + 洞察·升华入口（合成引擎前端，**已实现**）

> 命名:用户面文案统一为 **「洞察 · 升华」**(原「总结」太死板,2026-06 改名);内部 intent key 仍是 `summarize`,不动逻辑。

报告不是一个 asset skill,而是 **常驻格的一块 tile（📊 报告）**(见 §4.4.0 常驻 6-tile)。点它 →
`ReportListPage`(**报告容器**, `pages/report_list_page.dart`):

- 顶部一张显眼的 **「✨ 洞察 · 升华」** 渐变 CTA → **弹 REKA 洞察气泡(闭环,✅ 修 2026-06)**:`onTap` 调
  `openRekaInsight()`(`pet/floating_mascot.dart` 的全局 `rekaFunctionRequest` 触发器)→ 挂根 overlay 的浮球**就地开
  `RekaChat(intent:'summarize')` 单卡状态机**(锚定真·浮球,见 [§9.2](09-pet.md))。**不再 push 独立全屏页** —— 所有洞察
  入口(雷达菜单 + 报告列表 CTU)都汇到**同一个 REKA 流**,形成闭环。`ReportCreatePage`(`report_create_page.dart`)已删。
  生成走 `/api/reports/generate` SSE;手动选资产仍是气泡内的 `_AssetPickerModal`(类型 tab + **按领域筛选**,§8.5)。
- CTA 下方是**历史列表**(`GET /api/reports`,按 `dataRevision` 刷新):每行图标按 genre(`_genreMeta`)+ 标题 +
  「体裁 · M月D日」。**点开** → `GET /api/reports/{id}` → 全屏 **WebView 查看器** `ReportViewerPage`(锁定缩放、
  注入 GSAP、换装 rerender、分享导出);**向左滑** → `DELETE /api/reports/{id}`。空态指路 CTA。

> **这是报告的唯一入口**(像 AddSkillWizard 一样独立)。**chat / flash 不产报告**,用户在那里要洞察只会拿到
> 一句兜底指路。老的 chat SUMMARY(LLM 手写 HTML)已完全弃用。见 [§6.8.0 入口策略](06-synthesis-report.md)。

**完整规格(dispatcher / 内容 skill / md→HTML 渲染 / GSAP / 实体生命周期 / 各前端表面)见
[§6 合成·报告引擎](06-synthesis-report.md)** —— 本节只是前端指针。

### 4.4.5 技能管理页（启用/停用 + 活跃集，**已实现** `pages/skill_manage_page.dart`）

资产库 SKILLS 段头的「⚙ 全部技能」入口打开（Flutter `SkillManagePage`）。一页管全部技能(含停用的)：

- **列表**：`GET /api/skills`(返回**全部**含 `enabled`)。每条 = 图标 + 名称 + 记录数 + **激活开关**；
  支持**拖拽排序**(写 `position`)、**删除**(`DeleteSkillDialog`,同 §4.4.2)；末尾「✨ 新技能」→ `AddSkillWizard`。
  **只列可切换技能(记账 + 自定义)**;常驻 待办/随记 + 系统 external_ref/qa/contact **不在此页**(始终激活、不可 toggle)。
- **活跃集 + 硬上限**：顶部显 **`活跃数/9`**(`ACTIVE_SKILL_CAP=9`,**只算可选技能,常驻不计**)。开关切换是**暂存**;顶部「保存」
  → `PUT /api/skills/active {active_ids}`。**激活已满 9 再开 → 拦截 + 提示「先停用一个」**(开关回弹或置灰)。
- **保存即生效**：写完活跃集,**下一条 agent 消息**就按新集路由(dispatcher hint 每请求现拉,无需重启)。
  保存后 `bumpData()`,资产库格子立即只剩活跃的。
- **停用语义(给用户的话)**：停用 = 从首页格子收起、agent 不再自动往里记;**历史记录不删、仍可查**
  (点开停用技能仍能看旧记录,Agent 也答得出「我之前记的 X」)。
- 后端契约见 [§3.3 `/api/skills`](03-api-reference.md) + [§2 `user_skills.enabled`](02-data-model.md);
  路由按 enabled 过滤见 [§1.3](01-agent-architecture.md)。

---

## 4.5 今日 & 日历（今日页 = 首页 tab0；📅 → 流/月/年）

> ### ✅ 2026-06 本轮落地（流 / 月 改版 · KevinD 设计对齐 — 真值,下面历史小节按此读）
>
> 经多轮真机迭代后,**流 / 月** 的最终形态如下(代码:`mobile/lib/pages/calendar_page.dart` + `day_flash_view.dart`)。**与下面 §4.5.0a/b、§4.5.2、§4.5.4 的部分旧描述冲突处,以本块为准。**
>
> **流(ScheduleView,`_DayRow`)= 左日期/右内容 两栏:**
> - **左列 = 日期 + 闪念**:周缩写(mono)+ 大日号(今天蓝);`⚡N` pill **在日号下方**。左列作为**一个整体 sticky 跟随滚动**(钉在当天顶部、滚到当天底部停、被下一天推走);**钉住后用 live scroll offset 驱动 `Transform`(冻结 pin-anchor),不再每帧 `localToGlobal` → 0% jank、不抖**。**无「今天蓝点」**(被当 bug 去掉,今天靠日号蓝表示)。
> - **右内容 = 一个浅色「day 容器」**(`surfaceRaised` 圆角 16 + 描边 + 软阴影):各时段 block 仍分块,但**一起装进这一个容器**表达"同一天",不松散漂浮。**无固定 content header** —— 时段只由每个 block 自带的**段头(发光小球 + 段名 + 向右渐隐细线)** 标示。
> - **段色 = 色温**(凌晨蓝灰 `#6B75C0` → 上午暖金 `#F2B440` → 中午亮金 `#F3A034` → 下午琥珀 `#E89149` → 晚上冷蓝 `#5B69B2`;没有时间 = 灰 `#9AA0AD`),微洗在 base surface 上。
> - **卡片 = 悬浮卡**(2026-06 taste-pass:**去边框 + 暖色软阴影**浮在 day 容器上;无时刻的用更淡填充 + 无阴影。原"带边框小卡片"已改)。左侧时刻列 + 卡片:icon + 标题省略 + **领域小色点(右对齐)**。**领域进流了**(下面 §4.5.0a「领域 chip 退详情卡、不进流」已作废):接 §8 domain —— **timeline item 新增 `domain` 字段**(后端 `core/timeline.py` asset item + 移动端 `TimelineItem.domain`);**展示 = `Expanded` 标题把小色点推到卡片最右、各条对齐**(原色块 pill 已改成 7px 点,领域名仍在详情可读)。
> - **空日 = 更宽的斜纹空块**(`_HatchPainter` 对角斜纹 + 软阴影,不放文字);**两段式快记**:点空块 → 框内露出「**+ 在这天记一笔**」引导语;**再点引导语**才弹创建 sheet(不一点就弹)。
>
> **没有时间逻辑(最终,`_noTime` + `_bandGroupsOf`):**
> 1. 有钟点(`hasClockTime`/event)→ 段内按时刻、显 `HH:MM`、实线卡。
> 2. 说了时段没说钟点(`period` 有、无钟点)→ 落该段、**沉到段尾、不显时刻**;视觉 = **更淡填充 + 无阴影**(2026-06 taste-pass:原虚线边框 `_DashedRRect` 已删,靠"无时刻列 + 淡填充"表达"还没落定")。
> 3. 既无钟点也无时段 → 落**底部「没有时间」兜底段**(原名"没说时间",已统一为「没有时间」)。
>
> **闪念(`FlashPill` + 入口):**
> - pill 文案 = **「⚡N」**(去掉「闪念」二字,流/月/day detail 一致)。
> - 点 pill → **直接进「X月X日 闪念」session chat**(`SessionDetailPage`);**去掉了 `DayFlashView` 当日列表过渡页**(多条闪念 → 进最近一条有 session 的捕捉)。`DayFlashView` 类暂留但已不可达(死代码)。
>
> **月(`_SelectedDayFooter`):** 单月网格(只画当月)+ 底部选中日 footer。footer **sticky 日头**(固定顶):**左 = 日期·周几(收敛一行)**、**右最右 = `⚡N`**(`Expanded(date)+pill` 贴右、对称,无留白);**去掉时段、去掉「更多」**;内容可滚、点空白 → DayDetail。
>
> **DayDetail:** 「非日程」= `DayRender`(同段逻辑);**「日程」24h 网格 + 待办落格 = Part B(✅ 2026-06 已落地)**:事件 + 有时刻待办进网格、待办带 ○ 勾选、同点 N 个 = 计数 chip(点开手风琴)、结果记录 = 记录容器、默认镜头 =「日程」。**视觉精修(taste-pass)**:**记录段 / 日程段 = 两个对等 section**(记录的类型 tab 在容器内)、**全天 + 待安排 = 网格顶部左右并列的同款托盘**(全天**正常行、非 pill**)。详见 [`handoff-calendar-design.md`](handoffs/handoff-calendar-design.md) §B(含 taste-pass 块)/ 线框 `日历改版线框.dc.html`。

### 4.5.0 今日页（`TodayPage`，首页 tab0 = home）—— 重设计 · 方向 B「潮汐」2026-06

> **今日页 = app 的脸 / landing。** 一个常驻**气泡池**背景之上,前景是**两个可切换的屏**:**【今日安排】⇄【Reka Offer】**;顶部**暖顶**(早安 + 天气 + 今日一览);Reka 浮球在最上层。**不是「今天的段视图」**(段视图 = 回看,DayDetail / 流,§4.5.0a / §4.5.4)。
> **首页要答的不是「我今天记了啥」**(那是回看,交气泡池 / 日历),**而是「下一步做什么 + Reka 能帮我做什么」。**
> **真值**:逻辑 / 数据 / 决策 = 本节;**hifi 视觉 / 交互 = [redesign-home-B.md](design/redesign-home-B.md)(收录的用户设计真值,逐字)+ 给 design 的 brief [handoff-today-home-design.md](handoffs/handoff-today-home-design.md)**;Reka 声音 / 气泡 / emote = [§9.2 / §9.2.0](09-pet.md);域色 = [§8.3](08-domain-system.md);offer 逻辑 = [§14.5a](14-proactive-reka.md)。
> **nav(2026-06)**:底栏 = **今日 / 日历 / 资产**;**我的岛 → Reka 浮球雷达菜单**(§4.1)。

> **⚠️ 取代旧原型首页 + 复用(2026-06 重设计)**:旧 landing(branch `feat/today-page-landing`,完整落地记录见 [handoff-today-landing.md](handoffs/handoff-today-landing.md))的 **Dashboard(3 图表 / 类型 chips / summary 速览条)、Next Action 单屏卡叠、早报 merge 位置** —— **作废**。**保留并复用**:气泡池物理(forge2d,`bubble_physics.dart`)、nav 改、3 源池加载(assets / event / contacts 按 `created_at`)、记录详情 = 全局 `showAssetDetail`、域色气泡(现走 [§8.3](08-domain-system.md) B 域色板)、亮 / 暗两套 palette。

**层级(下→上)**
```
④ Reka 浮球(全局,不当主角)
③ 浮层 / bottom sheet(长按球的同类毛玻璃浮层、记录详情)
② 前景:【今日安排】⇄【Reka Offer】(全局二选一,各有 ▦墙/⚡Tinder 两模式)
① 气泡池(今天的捕捉,永远最底层背景)
   暖顶(早安 + 天气 + 今日一览 · 吸收晨报)挂前景顶部
```

**暖顶(吸收晨报)**
- 早安 + **天气**(☀️26°)+ **今日一览 chips**(N 日程 / N 待办 / ⚡N 闪念)。清晨 / 空池时撑场,白天可缩。
- **天气依赖**:**和风天气 QWeather**(server-side key,承安全铁律手机不持 key);**定位 = IP 粗定位到城市**(不弹定位权限,老人零摩擦),精确定位后置。
- **早报 merge 进暖顶**([§14.6](14-proactive-reka.md)):不再独立晨报页;上午首开可展开更完整早报。

**前景屏 ①【今日安排】(events + todos + 有时间的习惯)**
- 内容:今天的日程、待办、**有惯常时间的习惯**(喝水 11 点)。**没时间的提醒 / 逾期不在这屏 → 去 Reka Offer。**
- **▦ 墙模式** = 卡片墙,看全今天安排(滚动,按时间序)。
- **⚡ Tinder 模式(默认落点)** = 一张张卡,**左右滑 = 上一个 / 下一个(纯浏览,不 dismiss / execute)**;焦点卡 = 下一件,带**每秒倒计时 + 进度**;滑完 → **↻ 回到当前**。
- 卡:
  - **事件卡** = 倒计时 + 进度条 + **被动「🔔 到点自动提醒」一行(无提醒按钮 —— 提醒自动触发)** + 在日历看 ›。
  - **待办卡** = `完成 ✓` + `⏰ 延后` **两个独立按钮**(延后 = 卡上按钮、**不是滑**)。点延后 → popover:**1 小时 / 明天 / 后天 / 自定义时间**;长按 = 精确改期。**延到哪天就去哪天**(从今天消失,出现在那天的安排 / 日历)。

**前景屏 ②【Reka Offer】(Reka 能帮你做 / 你还没做)= [§14](14-proactive-reka.md) offer 的 PULL 落地面**
- 内容:**offer**(整理随记 / 消费总结 / 学习 quiz / 会前调研)+ **没固定时间的习惯提醒**(今天还没记单词)+ **逾期待办**。
- **打开即时现算**当前所有成立 offer(**不受 push 护栏限**,comprehensive;算法见 [§14.5a](14-proactive-reka.md))。
- **▦ 墙模式** = 看全今天所有 offer。
- **⚡ Tinder 模式**:**左滑 ✕ 跳过 / 右滑 ✓ 执行**;滑完 → **↻ 重新生成**(把刚跳过的重发一遍)。
  - **右滑执行**:offer → Reka 当场一键出报告([§6](06-synthesis-report.md));习惯 → 开该技能快记。
  - **左滑跳过 = 软「今天不想做」**:进通知 feed(留 14 天,可翻回做)+ **压一天**(当天不再 offer,**第二天**条件仍在则重新 offer)。详见 [§14.5a](14-proactive-reka.md)。
  - **底部 ✕ / ✓ 双按钮**镜像滑动。
- **watermark 增量**(§14.3 / §14.5a):总结过的旧批不重复,只有新攒满阈值才再 offer,且只总结新批。

**Tinder 拖拽 = 全局动作图标**
- 拖卡时屏幕中央淡入**大图标 + 标签**告诉你这一下会发生什么(Tinder 式),按动作配色:**蓝 = 浏览 / 绿 = 执行 / 红 = 跳过 / 琥珀 = 延后**。

**气泡池(永远最底层背景 = 今天的捕捉)**
- 一条记录 = 一颗气泡(**§8 域色填充 + 类型 emoji glyph**;域色 = [§8.3](08-domain-system.md) `domainColor()`,域 = 填充、类型 = glyph)。物理 = 复用旧 landing 的 forge2d(无壁盒 + 倾斜重力 + 拖抛 + 顶部 drop-in + 休眠去抖,参数见 prototype README)。
- **3 源**(承旧 landing):assets / event / contacts 按 `created_at` 在今天;event 无 domain → 中性球、contact → 社交。
- **点球 → bottom sheet(单条详情 = 全局 `showAssetDetail`)**。
- **长按球 → 首页毛玻璃浮层**:铺出**这个类型今天所有卡** + **同时高亮池里所有同类球**(其余暗)。**取代旧的类型 chips(chips 砍掉)**。
- **闪念不进池**(闪念 = pill,§4.5.0b)。
- **关键时刻区别**:池 / 今日页按 `created_at`(录入时刻)⊥ 日历按 effective time —— 今天建「明天 4 点上线」→ 今天池有、日历在明天(同一 asset 两镜头)。

**切换**
- **全局**【今日安排】⇄【Reka Offer】= **整屏左右 swipe** + 顶部段控指示。
- **模式**:每屏一个 **▦ / ⚡** 图标切 墙 / Tinder。
- **默认落点 = 今日安排 · Tinder**(打开就知道下一步,老人一眼懂)。

**⚡闪念 entry**:两屏都有 `⚡N` pill(N = 今日 flash session 计数)→ **打开当日闪念 session**(复用 `SessionDetailPage`)。

**卡片:按类型各长各样(反枯燥的关键)** —— 每张 = 一个小交互,域色单点 + 类型 emoji:

| 类型 | 卡的样子 + 一键 |
|---|---|
| 事件 | 倒计时滴答 + 进度条 + 被动「🔔 到点自动提醒」+ 在日历 › |
| 待办 | `完成 ✓` + `⏰ 延后`(两按钮);勾选那一下要爽 |
| 逾期 | 温柔「拖了 2 天」+ 改期 / 完成(**不愧疚**) |
| 习惯 / streak | 🔥 连续 3 天 + 「今天还没」+ 记一杯 |
| offer 整理 / 总结 | 💡✨「10 条随记」+ [帮我理一理] → 一键出报告 |
| 跟进 | 「给妈妈买礼物 → 设提醒?」+ [设] |

**4 个边态**:今日安排空(🌤️「今天没安排,随便记」)· Reka Offer 空(暖空态 +「记点啥都行」+ 一键切回安排,**别给白板**)· 气泡池空(🫧「今天还没记录」)· 全空·清晨(暖顶撑场)。

**质感铁律**:**高级**(克制、材质 / 光 / 深度,不卡通玩具感)· **直观**(默认屏老人一眼懂;墙 / Tinder / 长按 = 进阶发现,不挡基本使用)· **有交互**(Tinder 物理回弹 · 长按浮层铺开同类卡 + 球高亮 · 倒计时滴答 · 气泡 拖 / 倾斜 / drop-in · 右滑一键执行的爽感)。**Reka = 浮球不当主角;Reka 声音可爱、数据 UI 高级**([§9.2.0](09-pet.md))。

> **数据(无新模型)**:今日安排 = 今日及临近 events(`start_at`)+ 到期 todos + 有时间习惯,串 chain;Reka Offer = §14 offer PULL 现算([§14.5a](14-proactive-reka.md));气泡池 = `created_at` 今天的 3 源 asset(≠ 闪念原始捕捉;闪念 pill = 今日 flash session 计数 → §4.5.0b);点球 = 开 asset 详情;域色 = `domainColor()`([§8.3](08-domain-system.md))。
> **design's call(hifi 真值 = [redesign-home-B.md](design/redesign-home-B.md))**:全局切换形态(整屏 swipe vs 段控)、墙版式、长按浮层揭示动效、暖顶呈现、Tinder 滑动手感、卡片各类型美术、气泡材质 / 光。

### 4.5.0a 「一天渲染」DayRender —— 5 时段 + 闪念 chip（新增）

一天内容的渲染组件，**日历流（每一天）+ DayDetail 的「非日程」态 共用**（上午/下午/晚上 分段；「日程」= 24h 网格，§4.5.4），取代旧「按时间戳排成一条流」。**两处都折叠空段**（只画有内容的段，最轻；不画固定骨架）。**注**：今日页（tab0）**不用**本组件 —— 它是「扭蛋机」landing（§4.5.0），段视图是回看向、归 流 / DayDetail。

**5 个时段：** 凌晨 00:00–05:59 / 上午 06:00–11:59 / 中午 12:00–12:59 / 下午 13:00–17:59 / 晚上 18:00–23:59。

**核心规则（产品定 2026-06）：用户说什么就按什么，没说时间才用捕捉时刻兜底。** 一条记录按**优先级**落位：

1. **说了钟点**（`occurred_at`，或 event 的 `start_at`）→ 落该时刻的段、**段内按时刻升序、显 HH:MM**。
2. **只说了模糊时段**（`period`，没说钟点）→ 落该段的**「没具体时间」组**（排在段内有时刻的条目之后、**不显时间、不按捕捉时刻排**）。**即使此刻就在那个段也一样** —— 用户说「早上」就是在表达"没具体点"。
3. **啥时间都没说** → 按**捕捉时刻 `created_at`** 落到当下段、显捕捉 HH:MM（"闪念时刻就是记录时刻"）。
4. **说了是别的天**（昨天 / 前天 / 明天 / 周一 / 几号）→ 整条落**那一天**的流：在那天若说了钟点 / 时段按上面 1–2 排；**若那天既无钟点又无时段 → 落那天底部「没说时间」组**（捕捉时刻是今天、不能给那天兜底）。**今天的流里没有它，只闪念数 +1**（§4.5.0b）。

> 所以**没有"无时间"大桶**：没说时间的快记落当下段、说了模糊时段的进该段"没具体时间"组、说了钟点的精确排。

**落位例（设此刻 = 今天 11:00 捕捉）：**

| 用户说的 | 落在 | 段内位置 |
|---|---|---|
| 早上**8点**吃饭花了8块 | 今天·上午 | 8:00（显时间） |
| **早上**吃饭花了8块（没说点） | 今天·上午 | 「没具体时间」组（不显时间） |
| 吃饭花了8块（啥也没说） | 今天·上午 | 11:00（捕捉时刻兜底） |
| **下午**要开一个会（没说点） | 今天·下午 | 「没具体时间」组（不显时间；仍是 todo,不是 event） |
| **下午3点**要开会 | 今天·下午 | 15:00（显时间；单点仍是 todo,不是 event） |
| **明天晚上8点**和老板吃饭 | **明天**·晚上 | 20:00；今天流里无此条、只闪念 +1 |
| **昨天**花120买衣服（没说点） | **昨天**·「没说时间」组 | —；今天流里无此条、只闪念 +1 |
| 记得买 D3（啥也没说） | 今天·上午 | 11:00（捕捉兜底；**`due_at` 留空**，见下） |

**事件只认开始时刻**：流里 event 按 `start_at` 落段，**不管 `end_at`**（结束时刻不影响落位 / 展示）。

**两个"非时段"位置（边角）**：
- **顶部「全天」条** = 全天事件（开了「全天」开关的 event，只有日期没钟点，如"周五团建""国庆放假"，§4.5.3）—— 是这天的背景，不入任何时段。
- **底部「没说时间」组** = **归到这天、但既没说钟点也没说时段的记录**。典型 = **今天捕捉、内容指向别的天**："昨天花120买衣服"→落昨天、"前天打球180"→落前天，它们在那天无钟点无时段、捕捉时刻又是今天（不能给那天兜底）→ 收在那天「没说时间」组；"周一体检"（未来、没说点）同理。**措辞要软（design 定）—— 别叫"待安排"**，过去的消费不是待办。

**闪念产出的结构卡**（待办/名片/记录）照常按上面规则落段（§4.5.0b：只移走原始闪念）。

**展示**：每段轻段头（🌅上午 / ☀️中午 / 🌆下午 / 🌃晚上 / 🌙凌晨；**流/月 实现里段头 = 发光小球 + 段名 + 渐隐细线**,见 §4.5 落地块）；**每条 item = `[时间] [类型 emoji] 标题① · 标题②?`** —— 标题①② = 该技能 render_spec 的 ≤2 个标题行字段（wizard 里配，§4.8；记账 = 金额·用途、待办 = 任务 1 个）。**时间打头**；~~副标题 / meta / 领域 chip 退详情卡、不进流~~ **（✅ 本轮反转:流/月 卡片显领域;taste-pass 后 = 悬浮卡 + 领域**右对齐小色点**,见 §4.5 落地块；timeline item 已带 `domain`）**；**随记照记、不降权**。每段内：有时刻的按时刻排在上,**没说钟点的(说了时段)沉段尾、淡填充、不显时刻**(§4.5 落地块「没有时间逻辑」)。**闪念入口不在段里,挂在日 header / 流左列(§4.5.0b)。**

> **DayRender vs `_BandView`(实现注意)**:`day_render.dart` 的 `DayRender` 用在 **DayDetail「非日程」**(ListView 直接子,可测量);**流 / 月的 lazy 列表**用一个 stream-safe 的 **`_BandView`**(同段逻辑 + 段头/卡片,但用简单 primitives —— DayRender 的 stretch-Column 在 lazy SliverList 里测不出高度会白屏)。两者段分组规则一致(`_bandGroupsOf` / `_bandIndexOf`)。

> **待办 `due_at` / `period` 注意**：todo 没说具体截止钟点 → **别把 `due_at` 写成捕捉时刻**，否则 §14.6 立刻判它"逾期·拖了 N 天"。只说「下午/晚上」时,typed todo 必须写 `period=下午/晚上`、`occurred_at=null`、不写假 `due_at=15:00`；完全没说时间时才靠 `created_at` 兜底落段。
> **~~纠错:时段选择器~~（❌ 已砍 2026-06）**：原计划卡详情/编辑加轻量**时段选择器**,经用户确认多余 —— `asset_detail_sheet.dart` 的时段 picker(`_pickPeriod`/`_kPeriods`)**已移除**(domain 选择器 `_pickDomain` 保留)。放错段的纠正后续若需要,走改 `occurred_at`/`period` 字段即可。

### 4.5.0b 闪念入口 pill + 闪念移出流（新增）

> **✅ 本轮改(2026-06,见 §4.5 落地块):** ① pill 文案 = **「⚡N」**(去掉「闪念」字)。② 点 pill → **直接进「X月X日 闪念」session chat**(`SessionDetailPage`),**去掉了 `DayFlashView` 当日列表过渡页**(多条 → 进最近一条有 session 的捕捉);`DayFlashView` 类暂留但不可达。③ pill 位置:**流 = 左列日号下方**、**月 footer = 日头最右**、**day detail = 顶部**。下面的「当日闪念视图」段描述其历史形态(过渡页),已不在路径上。

**原始闪念（⚡ 捕捉本身）移出流** —— 它在流里堆叠让流显得乱（用户反馈）。改为：

- **每天一个闪念入口（挂在日 header，不在流 / 段里）**：一颗 `⚡ N 条闪念` pill 挂在那天的 **header 行**（流的每日 tile 头 / 今日页 header / DayDetail 顶部），**「日程」「非日程」两模式位置一致**（N = 按捕捉日算的当天 flash 数；0 不显）。点击 → **当日闪念视图**。**放 header 不放段尾**：闪念是"原始捕捉"的入口、不该埋在内容末尾、也不该随模式变位置。**跨天**：今天说「明天晚上和老板吃饭」→ 今天 pill +1（捕捉在今天）、产出待办落**明天**的流；两边不重复。
- **当日闪念视图 = 把那天的 flash 捕捉聚合到一处**（按 `date` 取，**与底层是 1 个还是 N 个 session 解耦**）：时间倒序列出每条捕捉（时刻 + transcript 摘要 + 它产出的卡作 provenance），点一条 → 进该捕捉的 session（`SessionDetailPage`，沿用现有回放）。这就是用户说的「进入那一日的闪念 session」。
- **产出的结构卡留在流里**（§4.5.0a）：一条闪念产出的待办/事件/名片/记录，**照常落各自时段**，不随原始闪念移走。
- **纯随记（无任何结构产出）只在当日闪念视图出现**，不进时段流（它本就没有"卡"）；这正好让流只剩"成形的东西"。

**改的是渲染，不动数据**：flash 仍 `sessions.session_type='flash'` + `date`（[§2 §3.3](02-data-model.md)），产出资产仍 `source_input_turn_id` 溯源。删去 §4.5.2 的 `FlashItemRow`（流内 ⚡ 行），换成 chip + `DayFlashView`。

### 4.5.1 CalendarPage（流/月/年 —— 底栏「日历」tab，2026-06 回归底栏）

顶部居中 `Segmented`（流/月/年，**默认月**），右侧 `HeaderControls`（🔔 + 昼夜切换）。

> Flutter 端把 🔔 + 昼夜切换收进了**全局 header bar**（见 §4.0.4），所以日历页头只剩居中
> segmented + 一个刷新按钮；资产库页头只剩标题/计数。全局控件不再各页重复。
三视图：`ScheduleView`（流）/ `MonthPane`（月）/ `YearPane`（年）。年→点月→切月视图并滚到该月。

`handleItemTap(item)` 分发：
- `input_turn`（闪念）→ **不再作为流内行**（§4.5.0b）；当日闪念走 DayRender 末尾 `⚡ N 条闪念` chip → `DayFlashView` → 点条目进该捕捉 session。
- `event` → `EventDetailModal`（→ AssetDetailDrawer，cardType=event）。
- `contact` → `ContactDetailModal`。
- 其余 → `AssetDetailModal`。

**创建已收归全局**：日历内**无**任何内联「+ 添加事件」，统一走 dock 的 +。

### 4.5.2 ScheduleView（流 / Timepage 风格时间流）

> **✅ 2026-06 本轮 = 左日期/右内容 两栏(真值见 §4.5 落地块):** 左列(日期 + `⚡N` pill 在日号下)整体 sticky 跟随滚动(pin-anchor,不抖);右内容各时段 block 装进一个浅色「day 容器」、无 content header。下面 A–E 是历史 Timepage 手感 —— **仍在:** A 距离水印 / B 月锚点 / E 跳回今天 / 自动滚到今日 / 无限前向滚;**已被两栏布局取代:** C「所有日同蓝 tile」→ 现为 day 容器 + 色温段块;D「tile 高随条数 50/82/112/136」→ 现为内容自然高 + day 容器。

学自用户分享的 Timepage 录屏，5 个行为（移植时是「日历手感」的关键）：
- **A** 滚动时右侧浮现「N 天/周/月/年 前/后」大字水印（`distanceLabel`：0→今天、±1→明天/昨天、<7→N天、
  <28→N周、<365→N月、否则 N年），滚动停 250ms 后淡出。
- **B** 每月首行左 rail 显「2026 / X月」锚点，当月 brand 蓝 + 辉光。
- **C** 所有日 tile **同一蓝色调**（`var(--eu-brand-faint)` 渐变），类型信号靠 tile 内每条的图标 halo（events 紫/todos 蓝/…）。
- **D** 空日 = 同色空间；`仅有事/全部` toggle（持久化 `eureka:schedule_show_empty`）控制空日是否折叠成
  `GapRow`（一条渐变细线）。**Flutter 流的点击模型(✅ 多轮收敛 2026-06)**:
  - **空日(`_EmptyDayRow`,✅ 2026-06 改)= 左日期 + 右「更宽的斜纹空块」**(`_HatchPainter` 对角斜纹 + 软阴影,不放文字)。**两段式快记**:**点空块 → 框内露出「+ 在这天记一笔」引导语**(`_EmptyDayRow` 内部 `_revealed`,旧 `_selectedDay` 已删)→ **再点引导语**才 `showCreateMenu(presetDate: day)`(不一点就弹 sheet,用户要求)。**空日不进日视图**(没内容可看)。
  - **有内容的日(`_DayRow`)→ 点条目 = 开该条详情;点 tile 的空白处 / 日期 = push 该天 `DayDetailPage`(日视图)** —— 从**段视图钻进 24h 日程网格**(§4.5.4)。手势保留、payoff 清晰:流 = 粗粒度捕捉流、点开 = 精确日程表(事件显 start–end 时长块)。
    关键:条目行用 `mainAxisSize.min + Flexible`(不是 `Expanded`)**只占文字宽度** —— 短标题右侧的空白**落到 tile(日视图)**而不是误开那条资产(修「点空白处反而打开那行资产」)。
  - **日视图自带 `FloatingActionButton.extended「+ 在这天记一笔」**→ `showCreateMenu(presetDate: day)`,字段预设到当天(event 默认 09:00)。
  - **走过的弯路**:① 早期「点 tile 空白就地展开快记」在**有内容的日**留白太少 → 点不出、也点不进日视图(已改:有内容的日点空白 → 日视图);② 中间一版让**空日**也常驻「+ 记一笔」按钮 → 用户嫌每个空日都挂按钮太吵 → 退回**点选式**(本条)。
- **E** 「跳回今天」44px 浮钮（`⌄`），仅当今日离屏时显。
- 挂载自动滚到今日中心；近底部时 `fwdDays += 120`（≈无限前向滚动，cap ~10y）。
- tile 高随条目数：50/82/112/136+（0/1/2/3+）。
- **~~FlashItemRow~~ → 闪念移出流（改，见 §4.5.0b）**：原始闪念**不再**作为流内 ⚡ 行；改为每天一颗 `⚡ N 条闪念` pill 挂在**日 header**（「日程」「非日程」两模式位置一致）→ `DayFlashView`。**它产出的结构卡（待办/名片/记录）仍按时段落在流里**（§4.5.0a），只移走原始捕捉本身。
- **时段分段（改，见 §4.5.0a）**：每个有内容的日 tile 不再是「按时间戳排一条」，而是 5 时段的 DayRender；没说时间的按捕捉时刻 `created_at` 落到当下段，说了模糊时段的归该段，空段折叠。

### 4.5.3 EventForm（事件创建/编辑）

全产品统一用这个 drawer-shape 表单（取代旧 Timepage 式 EventEditor）。`existing` prop 切创建/编辑。
字段：标题(必填) / 全天 toggle / 开始(datetime-local 或 date) / 结束(非全天才显) / 地点 / **描述(markdown)**。
- **描述 = markdown(✅ Flutter,修 2026-06)**:复用资产编辑器的 **`MdEditor`**(`asset_detail_sheet.dart` 公开导出,编辑/预览切换 + `MarkdownText` 预览),
  事件描述常带议程/纪要,要结构而非一行纯文本。**event 不加 domain 选择器**(沿用既定:事件靠反应式任务长岛,§7.3.2;经用户确认保持)。
- 全天开 → 提交 `all_day=1` + 开始用 date-only(`YYYY-MM-DD`)、省略 end_at；非全天 → 必须 end_at 且晚于开始
  （开始 ≥ 结束 → 结束自动 +60min，且保存时再校验一次）。
- 提交 `EventInput{title, start_at, end_at, all_day, location, description}`，时间用 `toIsoWithOffset`
  （带 +08:00 偏移）。
- 编辑模式有红色「删除」（双击确认）。
- 时间契约提醒：event **必须**有 end_at 或 all_day（见 §1 三道闸 + §3 create_event 校验）。
- **Flutter 实现注意（曾漏）**：`mobile/lib/pages/create_asset.dart` 的 `EventForm` 必须发 end_at(非全天)/
  all_day/description——早期只发 `title+start_at+location`，被后端「missing time span」400 拒掉。所有日期时间
  统一走 `isoBeijing(dt, dateOnly:)`：datetime 字段 → `YYYY-MM-DDTHH:MM:00+08:00`，date 字段 → 裸 `YYYY-MM-DD`。
  **不要**用 `DateTime.toIso8601String()`——它对本地 `DateTime` 会丢掉时区偏移(无 `+08:00`/`Z`)，后端按 UTC
  解读 → 当天晚些的时刻会整体跨天(用户选 6.4 → 存成 6.5)。`AssetEditPage` 的 datetime/date 字段同此规则。
- **Flutter 编辑模式(✅)**：`EventForm({eventId, existing})` —— `eventId` 非空即编辑(`initState` 预填
  title/location/desc/start/end/all_day,解析 ISO→local) → `PUT /api/events/{eventId}` 并 pop `true`;否则
  `POST` 并 pop 回执 Map。appBar 标题随模式切「📅 事件 / 📅 编辑事件」。从 `AssetDetailDrawer` 的编辑分支进入
  (见 §4.4.3),`existing` = timeline 拉到的 event 记录。

### 4.5.3a ContactForm（联系人创建/编辑，✅ Flutter `create_asset.dart`）

联系人是 **真身实体**（contacts 表,非 asset),故有自己的专用表单(不走 `AssetEditPage`)。`ContactForm({contactId, existing})`
—— `contactId` 非空即编辑 → `PUT /api/contacts/{contactId}`、pop `true`;否则 `POST /api/contacts`。字段:**姓名*** /
公司 / 职位 / 电话(phone 键盘) / 邮箱(email 键盘) / **社交媒体** / **备注**。从 `AssetDetailDrawer`
编辑分支(`cardType=='contact'`)进入,`existing` = `GET /api/contacts/{id}` 记录(`assetId` 已是真身 contact id)。
**创建与编辑都走此表单**:`CreateAssetMenu` 的 contact tile 已改开 `ContactForm()`(不再 `SkillCreateForm`),所以新建名片也能填社媒/邮箱/备注。

**① 社交媒体(从固定列表选,不自由填)**:支持平台 = **`x / telegram / linkedin / wechat / xiaohongshu / instagram`**(单一真源 `kSocialPlatforms`,
与后端 `core/contacts_meta.py` 同步;**改一处必须改两处**)。UI:已添加的平台逐行显示(emoji + 平台名 + handle 输入 + ✕ 移除);
「+ 添加社交媒体」→ 底部 sheet 列**尚未添加**的平台 → 选一个加一行。**只存账号/handle**,不存平台外的东西。保存时收集非空 handle →
`socials: {platform: handle}`(全量替换;后端 `clean_socials` 再过滤一次未支持平台)。详情页 `AssetDetailDrawer` 用 `_socialsBlock`
按 `kSocialPlatforms` 顺序渲染(emoji + 平台 + 可选中 handle)。
**② 备注 notes(批注,渲染为 md)**:`notes: List<String>`,每条是一句批注(在哪相遇 / 怎么认识…),表单里**一行一条**;
详情页按 `- 行` 拼成 markdown 走 `_DocBlock`(不再当 chips)。表单保存发**整组** `notes`(用户当面看着全部、显式管理 = 非盲改);
**agent / MCP 侧是 append**(`tool_update_contact(field="notes")` 追加一条,绝不覆盖,见 [§1 工具签名](01-agent-architecture.md)),API 另有 `notes_append` 支持只追加不全替。

### 4.5.4 MonthPane / YearPane / DayDetailSheet（日视图）

- `MonthPane`（Flutter `_MonthView`，✅ 2026-06 改）：**只画当月单网格**(`_displayMonth`,`‹ 2026 年 6 月 ›` 切月器,点标签回本月)+ 底部 `Expanded`「选中日」footer(内容区是较大那半)。**点一下选日**(footer 列当天条目)，**再点同一天 → 打开日视图**(mirrors web tap-again → DayDetail)。**footer = sticky 日头(固定顶) + 可滚内容**(§4.5 落地块):日头 **左 = 日期·周几(收敛一行)** / **右最右 = `⚡N`**(贴右对称、`Expanded(date)+pill`,无留白);**去掉时段、去掉旧「更多 / 日程 ›」入口**;点 footer 空白内容 → DayDetail。(旧「固定高度 0.30 + 头部 日程 ›」已作废。)
- `YearPane`（`_YearView`）：12 宫格，点月回月视图。
- **日视图 `DayDetailPage`（Flutter，全屏；web 是 `DayDetailSheet`）**：
  - **入口**:月视图点日(tap-again)**以及 `流` 里点某个有内容的日的日期/tile 空白处**(2026-06,见 §流 上;空日不进日视图、直接快创)。
  - **右下 `FloatingActionButton.extended「+ 在这天记一笔」**(2026-06 新增)→ `showCreateMenu(presetDate: 当天)`,新建字段预设到这天。**这是「往某天加一笔」的可靠入口**(不依赖流 tile 的留白)。**date 字段(due_date / start_at)预设到当天外,POST `/api/assets` 还带 `created_at=当天`**(否则随记等无日期字段的记录类资产 `effective_at=created_at` 会落到今天 —— 2026-06 修;todo/expense 仍由各自 due_date/date 定 effective_at,created_at 只是兜底锚点)。
  - **一个 toggle、两个模式（沿用现有名称「日程 / 非日程」）**：
    - **「非日程」= 上午/下午/晚上 分段**（`DayRender`，§4.5.0a；升级版），捕捉向：事件**只显开始**（3 点的会 = 段里一条记录、无时长）。取代旧「非日程 = 今日捕捉按类型分 tab」。"我今天记 / 发生了啥"。
    - **「日程」= 24h 网格**（保留），日程向：事件按 `start_at`–`end_at` 画**时长块**（3–5 点 = 一个 2h 块）；全天事件走顶部「全天」条；无时刻捕捉收在**顶部类型 tab / 列表区**（"顶部 tab 区分 assets"）。`end_at` / 时长是「日程」独有、「非日程」丢掉的信息。"把这天当日程表看"。
      - **✅ Part B（2026-06 已落地)**:网格里**只放事件 + 有时刻待办**,结果记录收进「**记录**」容器(类型 tab 在容器内)。**版面上→下 = 「记录」段 → 「日程」段(两个对等 section,各有标题,不分主次)**;日程段顶部 = **「全天」+「待安排」左右并列的同款轻托盘**(`_topTray`:全天**左**、待安排**右**,**全天 = 正常行非 pill**;只有一个时占满)→ 下接 24h 网格。**待办落格** = 有时刻小块(带 ○ 勾选框)/ 同点 N 个 →「**N 个待办 ▾**」计数 chip(**点开 = 手风琴**:撑开时间块、下推下方,不悬浮覆盖)/ 无时刻 → 「**待安排**」托盘(≤3 + 共 N + 展开其余);**○ 点击直接完成**(PUT `payload_patch.status` + bumpData)。**已完成待办在日程全程暴露**(绿勾 + 删除线,不隐藏)。重叠走 `_eventColumns` 等分列。**待补(下轮 polish)**:点状待办撞长事件的"左半瘦 chip"形态(当前等分列、功能正确)。完整设计 + 落地状态 + taste-pass = [`handoff-calendar-design.md` §B](handoffs/handoff-calendar-design.md)。
  - **差异由"默认进哪个模式"体现**（产品定 2026-06）：**今日页 / 流 默认 =「非日程」**（捕捉向，适合多数捕捉重的日子；toggle 可切今天的「日程」）；**DayDetail 默认 =「日程」（网格）**（从流钻进某天 = 想看精确日程）。所以**"点流空白进 DayDetail"=「非日程」→ 钻进「日程」**，差异明显。
  - 顶部：返回 + 星期 / 距离 / 月日 + **`⚡ N 条闪念` 入口**（§4.5.0b，两模式都在）+「日程 / 非日程」toggle；「日程」态今天画红 now 线、滚到「最早事件前 1h / 否则 7 点」。
  - **网格 app 已实现 → 保留**；本轮新增 =「非日程」分段视图（取代旧类型 tab 列表 + 作今日页 / 流默认），并移除旧「列表（`effective_at` 排一条）」（并入「非日程」）。
  - **列表卡片等高**：每行固定高度(60px),标题单独时垂直居中,有/无副标题的卡片大小一致。
  - **左滑删除**：列表/今日捕捉的行卡片支持左滑删除(确认弹窗 → DELETE → 本地过滤移除 + `bumpData`),与全局
    卡片一致;闪念捕捉不可删;网格里的事件块通过点开详情删除(块太小不适合滑)。
  - **stale-while-revalidate**：自身按 `dataRevision` 重新拉 timeline(过滤到当天),所以日视图里改/删即时反映;
    **重拉期间和出错时都保留上一份数据**(不闪空)——否则关掉某条的详情卡(关闭 sheet 会 bumpData)时,整页会瞬间
    转圈/清空,看着像「日程消失了」。文件实体已移除,timeline 过滤掉 `kind=='file'`。

---

## 4.6 通知（`/notifications`）

- `NotificationPage`：列全部通知（newest first），头部「{unread} UNREAD · {total} TOTAL」mono 副标 + 「全部已读」。
- `useNotifications`：`markRead/markAllRead/dismiss`。**点条 → 标已读 + 打开目标**：
  - `flash_done` → 跳转该捕捉 **session**（`link` 是裸 session_id）。
  - `task_done` / `task_failed` → 打开该 **asset** 详情弹层（`link` 是裸 asset_id）。
  - `reminder` → 打开提醒对象的详情弹层。**注意 `link` 不是裸 id**,是调度器的复合键
    `reminder:evt:<event_id>:<thr>` / `reminder:todo:<asset_id>:<thr>`(UUID 不含 `:`)。**必须 split(`:`) 取
    `parts[1]`=kind、`parts[2]`=id**,再按 evt→`/api/events/{id}`、todo→`/api/assets/{id}` 取数据开弹层。
    (曾经直接拿整个 `link` 当 event id 查 → 404 → 点了没反应。)
- GET `/api/events/{id}` 返回**扁平**、GET `/api/assets/{id}` 返回 `{asset:{}}` **包裹**——取数据用 `res['x'] ?? res` 兼容两种。
- 类型：`flash_done` / `task_done` / `task_failed` / `reminder`（后端 hook 产生）。
- **实时**：`NotificationsBridge`（挂在 AppShell）开 `/api/notifications/stream` SSE。payload 带 `_event` 字段路由：
  `"listening"` → 闪念聆听态；否则 → 普通 notification（推进 toast + 失效相关 SWR，见 §4.0.3）。

---

## 4.7 render_spec 渲染管线（通用卡片，**无 if-type-equals**）

这是「skill 可扩展」承诺的前端落点：前端**不硬编码任何类型分支**，全凭 render_spec DSL 通用渲染。

### 4.7.1 buildCard（`lib/render-spec.ts`）

镜像后端 `_build_card_from_render_spec`。输入 `{payload, spec, assetId, cardType, displayName}` →
输出 `CardData{title, subtitle, icon, accentColor, metaFields[], actions, checkDone?, cardType, assetId}`。
- `primary_field`/`secondary_field` + `*_format` 取值并格式化。
- `meta_fields[]` → pills。
- `checkDone` 仅当 payload 有 `status`/`done` 时定义（决定 todo 勾选）。
- `EXTERNAL_SYSTEM_LABEL`/`ICON` map 给 task/external_ref 卡。

### 4.7.2 FieldFormat（`lib/format.ts`，镜像后端 `_apply_format`）

| format | 输出示例 |
|---|---|
| `text` | 原样 |
| `relative_date` | `5月22日截止` / `5月22日 15:00`（有时间） |
| `absolute_date` | `5月22日`（无后缀） |
| `time` | `15:00` |
| `currency` | `¥85` |
| `duration` | `2 小时` |
| `truncate_30/40/60` | 截断加省略号 |
| `badge` | 徽标 |

ISO 检测守卫避免误格式化普通串。**单位已弃用**（embedded 进值里：`"5 km"`、`"150 毫升"`）——
render_spec 不再带 `field_units`/`primary_unit` 等（`AddSkillWizard.composeRenderSpec` 主动 strip）。

### 4.7.3 SkillCard（`components/skill/SkillCard.tsx`）

通用卡片，`switch(card_layout)`：`inline` / `compact` / `stacked` / `horizontal`。
- **固定卡片大小 = 3 行 DNA(✅ Flutter `_CardBody`,关键)**:卡片**不随内容高度变化** —— 严格 **3 行**:**① 标题行**(`_titleRow`:标题 `maxLines:1` 省略 + **领域 tag 放右上角**,不再混进 meta);**② 副标题单行**(多行 `\n` 折成一行 + 省略);**③ 信息行**(`_subAndMeta`:**最多 2 个 meta**,放在**一个 Row 里 `Flexible` 等比分宽 + 省略**,**永不换行到第二行** —— 这是之前「最后一行文字+tag 挤到下一行 → 一大一小」的根因)。完整内容在详情/全屏读;`_shell` `minHeight:60` 兜底。
- `CardShell` 过渡 240ms `cubic-bezier(.2,.7,.3,1)`。
- `IconTile`（勾选叠加层）。
- `MetaPill` + `LIFECYCLE_STATUS{pending:待处理, running:同步中, done:已同步, failed:失败}`（pending/running 脉冲动画）。
- **ACCENT class map 写死**：Tailwind purge 不能动态拼 class，故 `blue/purple/amber/green/red/gray/neutral`
  的 bg/edge/fg/solid 全部静态列出（`tailwind.config.ts` 同步映射）。
- **左滑删除（Flutter，通用）**：删除能力内建在 SkillCard 自身——**任何可删卡片**（asset / event / contact，
  按 cardType 选 endpoint：`/api/assets|events|contacts/:id`）在**任何位置**（资产库最近 / 类目列表 / 实体列表 /
  chat 内联卡）都支持向左滑触发删除（confirm 弹窗 → DELETE → `bumpData`）。file / task / 无 id 的 prebuilt 卡
  不可删。删后卡片自身渲染空 + `bumpData` 让所在列表重新拉取。`Dismissible(key: del_<path>)`。

### 4.7.4 EventCard（事件专用，**无 render_spec**）

event 是一级实体、**不走 render_spec**——有专用 `EventCard`（紫 accent，时间范围格式化）。
前端用 `event_id`（**非 `id`**）作 key。

---

## 4.8 自建 skill 向导（`AddSkillWizard`）—— skill 可扩展的前端入口

4 步（对应后端 design agent + clarifier，见 §1.8）：

1. **describe**：textarea + 示例 chips（跑步训练记录/读书笔记/每天喝水量/面试复盘）。`⌘/Ctrl+Enter` 提交。
   loading 文案「AI 正在设计你的卡片… 约 15-30 秒」。
2. **clarify**（仅当描述太模糊）：POST `/api/skills{description}` 返回 `questions[]`（1-3 个，`choice`/`text`）。
   choice 预选首项。全答完才能提交，POST `{description, answers[]}` 拿 draft。
3. **preview**：`buildCard(draft.render_spec + sample_payload)` **实时双预览** —— **大卡详情** + **流 item**（`CalendarBulletPreview`），两者随配置一起动态反馈（所见即所得，无需拖拽）。
   - **字段配置**：每个 payload 字段一行，slot 选 `标题①/标题②/信息/隐藏`（= 旧 `主/副` 相应重命名）。标题① 1 个、标题② ≤1 个、信息 ≤3（满则禁用）。
     **标题① + 标题②（≤2 格）= 标题行**，**同时**出现在 大卡标题行 和 **流 item**（`[时间][emoji] 标题① · 标题②`，§4.5.0a）—— 单一真值，`applySlotPick` 强制唯一。**信息(meta) 只进大卡详情、不进流**（保流干净）。
   - 可调 display_name / icon(≤2 字)。**(2026-06 颜色收敛:去掉 accent 7 色选色 —— 颜色 = 领域、自动,卡片本体单色,见 [§5.1](05-design-system.md))**
   - **重新生成（regenerate，新）**：preview 里一个 `↻ 重新生成` —— 快捷 `更简单`（精简字段）/ `内容更多`（多记几项）/ `调整…`（自由说，如「去掉地点、加心情」）→ 带当前 draft + 这句 hint 重调 design-agent（[§1.8](01-agent-architecture.md)）→ 出新 `payload_schema` + `render_spec` → **双预览实时刷新**；用户随后仍可手调 icon / 色 / 标题①②。**用自然语言把 schema 调到满意，不摊字段表单**（这就替代了"手动加字段 / 字段 CRUD"）。**创建时（未注册、无数据）随便重生成、零风险**；同一机制可复用到 §4.8.1 改**已有**技能 schema（加字段安全；删 / 改字段需提示老记录），**后置**。
4. **register**：POST `/api/skills/confirm{name, display_name, payload_schema, render_spec, queryable_fields:[]}`
   → 失效 `/api/skills` → 关闭。409 显后端真实原因（重名 OR 容量满）。

`composeRenderSpec` strip 掉 legacy 装饰键（`field_units`/`*_label`/`*_unit`）——单位写进值里。

### 4.8.1 改卡片配置(`SkillConfigPage` + `SkillConfigForm`,✅ 已实现)

向导生成的 config **创建后还能改**:技能的**类目页**(`CategoryDetailPage`)appBar 加 `⚙ 卡片配置` 入口(任意 `userSkillId != null` 的技能)→ push **`SkillConfigPage`**:拉 `GET /api/skills` 取该技能当前 `render_spec` + `payload_schema` + `display_name`,塞进 **`SkillConfigForm`**(从向导 preview 步抽出的**可复用**配置表:**实时卡片预览** `CardPreview` + icon(≤2) + 显示名 + 每字段 `标题①/标题②/信息/隐藏` 角色(**去 accent 选色 —— 色=领域,§5.1 颜色收敛**),逻辑与向导一致:标题①/② 唯一、信息 ≤3)。保存 → **`PATCH /api/skills/{user_skill_id}{render_spec, display_name}`**(后端 `update_skill`,只改**展示**,不动 `payload_schema`/字段 key 这条数据契约)→ `ref.invalidate(renderSpecsProvider)`(全局卡片按新 icon/色/字段位重渲)+ `bumpData()`。预览样例值由 schema 合成(`_sampleFor`)。**注**:向导当前仍保留各自一份配置 UI;后续可让向导也用 `SkillConfigForm` 去重(暂为降风险未重构)。

> **字段三件套:key · label · long**（每个 `payload_schema[<key>]`,design agent 创建时定,见 §1 design_agent）:
> - **key = 机器契约**:小写英文 `snake_case`(book_title / key_insights / pages_read),稳定不可变 —— 它是 payload 键 / 查询 / `asset_fields` 索引的契约;中文只进 label。
> - **label = 显示层**(2-5 字中文短标签,机器名可英文但 label 贴语义 —— 喝水 `amount`→「水量」非「金额」);**可翻译/易变**。i18n 后置:因 key⊥label,以后 `label` 从单串升成 `{zh,en}` + 取 locale 即可,不破坏 payload/查询。缺失走前端兜底 + 后端 `_backfill_labels`。
> - **long = 输入种类**:`true`=自由长文(→ markdown 编辑器 / 正文块),`false`=结构化短值。详情/编辑据此渲染(`RenderSpec.longFields`),不再按字段名硬猜;后端 `_backfill_long` 兜底。
> 详情/编辑据此渲染字段(见 §4.4.3),而不是按字段名硬猜。

---

## 4.9 ModalContext / PresentationMode / Theme（横切 context）

| context | 持久化 key | 作用 |
|---|---|---|
| `ModalContext` | — | 模态计数（register/unregister）控制 dock 显隐；`AgentTarget{subject:{type,id}, label}`；`useModalMount({keepDock})`；`useIsAnyModalOpen` |
| `PresentationModeContext` | `eureka:presentation_mode` | `asset` ⇄ `calendar`，**只**决定 `homeRoute`（`/library` vs `/calendar`），不分叉数据/AI |
| `ThemeContext` | `eureka:theme` | `dark`(class `theme-atmosphere`) / `light`(class `theme-light`)。`applyTheme` 先移除全部主题 class 再加目标 |

> 注：CSS 里还有 `theme-lab` / 默认 Slate，但 `ThemeContext` **只**在 dark(atmosphere)/light 之间切。详见 §5。

---

## 4.10 Flutter 移植清单（最易丢的细节）

1. **SSE 两条流**：`/api/chat`（POST SSE，`parsePostSseStream` 手切 `\n\n`）+ `/api/notifications/stream`
   （GET EventSource，重连退避）。`/api/flash` 是**同步 JSON**，别当 SSE。
2. **capture→revalidate 链**（§4.0.3）：闪念后台整理完，靠 notification SSE 触发列表失效自动冒卡片。
3. **chat re-seed 防线**（§4.2.2）：streaming 中绝不 reset，否则抹掉流式气泡。
4. **IME isComposing 守卫**（§4.2.5）：中文输入法组字中不发送。
5. **lazy session create**（§4.2.2）：首条消息的 SSE meta 帧才给 session_id。
6. **沉淀显示判定**（§4.2.4）：本轮创建过卡片就不显沉淀；query/report 不算创建。
7. **render_spec 通用渲染**（§4.7）：前端无类型分支；event 例外走专用 EventCard 且用 `event_id`。
8. **单位 embedded 进值**：render_spec 不带单位字段。
9. **dock 全局 Agent 入口 doctrine**（§4.1）：detail 表单不内嵌讨论按钮，靠 AgentTarget。
10. **来源三态**（§4.4.3）：manual/flash/agent 决定 SOURCE 区渲染与可点性。
11. **空会话防线 + 可读标题**（§4.2.2）：打开 chat / 点「讨论」/「新对话」都不建 session，subject 线程先
    `peek_only` 查不建、首条消息才落库；顶栏与侧栏标题必须可读（session.title → 首条用户消息 → 新对话 /
    subject 标签），不得显示常量「Agent」。

---

## 4.11 设备连接（硬件配对，Flutter 增量）

EurekaMind 录音卡（W1/W2 BLE）的**手机端配对**。由全局 header 的 设备连接（`🔌`）入口进入：已绑定 →
我的设备；未绑定 → 首配流程。

**硬件管线现状**：`integrations/flash-card/` 里，**FlashType（Swift / Mac app）做 BLE handshake + Opus
采集 + 解码成 WAV**；`eureka-bridge.py` 跑 whisper.cpp 转写 → `POST /api/flash`；`listen-watcher.py`
tail FlashType 日志 → `POST /api/flash/listening`。**手机上 FlashType 不在**，所以 iOS 直连必须让
Flutter 自己拥有 BLE。

**架构（seam）**：UI 只认 `DeviceController`（单例，持有绑定/连接态），`DeviceController` 只认
`DeviceTransport` 接口（`scan() / connect() / unbind(deleteData)`）。
- **现在**：`MockDeviceTransport`（模拟 搜索→发现→连接→信息），无硬件即可把配对/设备 UI 跑通 + web 验证。
- **以后**：把 FlashType 的 Swift BLE+Opus 代码做成 iOS 插件（MethodChannel/EventChannel），实现同一
  `DeviceTransport` 接口落进去，**UI 零改动**。ASR 需从「Mac 上 whisper.cpp」挪到服务端/云（手机没有
  whisper），方案待定。

**流程 / 界面**（对标官方 app 截图）：
1. **首配**（`DevicePairingPage`）：顶部「正在搜索你的 Eureka 设备…」pill + 2 步引导 pager（开启设备 →
   开始蓝牙配对）+ 页点 + 联系客服。挂载即 `startScan()`。
2. **发现设备** sheet：扫到设备后自动升起，列 `W2(BLE)` + `SN` + 连接。连接中转圈，`connected` → 关 sheet
   → `pushReplacement` 我的设备。
3. **我的设备**（`MyDevicePage`）：已连接绿标 + 设备信息（电量 / 存储）+ 设备管理「解除设备绑定」→ action
   sheet（仅解除绑定保留数据 / 解除绑定并删除数据 / 取消）。解绑后自动退出该页。

> BLE 是原生能力，**Flutter web 跑不了真连接**（mock 可跑）；真机插件落地后需真 iPhone + 卡验证。
> 设备连接未来也是「闪念硬件桥接状态」的自然归处（连接态 / 电量 / 聆听）。
