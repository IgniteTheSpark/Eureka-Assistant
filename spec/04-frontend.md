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
| `/calendar` | `CalendarPage` | Segmented 流/月/年 |
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

### 4.0.6 设置 hub + 已连接应用（Connected Apps，设计规格 · 待实现）

header 的 `👤` 从「资料 sheet」升级成一个**设置 hub**(全屏页),容纳账号级配置:

```
设置
 ├ 账号        邮箱 · 退出登录
 ├ 已连接应用   ← Connected Apps(本节重点)
 ├ 设备连接     ← 硬件 BLE 配对(原 🔌,并入这里;header 可保留 🔌 做快捷)
 └ 偏好        昼夜等(昼夜仍可留 header 快捷切换)
```

**已连接应用页** = 两段:

1. **可连接(目录)**:拉 `GET /api/connectors`,列每个 connector(图标 + 名称 + 已连/未连)。点未连的
   → 一个**连接表单**:按 connector 声明的 `fields` 动态渲染输入框(密钥字段用密码框 + "你的密钥只存在服务端、
   加密保存"的说明文案),提交 `POST /api/connected-apps`。**beta 全是 token/网关-URL 粘贴**(见 [§1.7.1](01-agent-architecture.md))。
2. **已连接**:列本用户连接(`GET /api/connected-apps`)。每条:状态 chip(connected / needs_reauth / error)、
   `断开`(DELETE)、`重新连接/测试`(POST `/test`)。**绝不展示已存的密钥**(write-only,见 §3.14)。

要点:
- **密钥只进不出**:输入框提交后清空;页面任何地方都不回显已存凭据(后端也不返回)。
- 连接成功后,Agent 那边的「同步到钉钉 / 存到 Notion」才真正可用(运行时按 user 的连接构建 toolset,
  见 §1.7.1);未连时 agent 引导用户来这页连。
- **可深链(给外部资产用)**:本页接受一个目标参数(`connector_id` 或 `external_system`),从**外部资产详情/
  失败的同步**跳进来时(见 §4.4.2 / §4.4.3),**直接定位并高亮对应 connector 的卡片**(未连则直接展开其连接
  表单)。system 对多个 connector 时落到该 system 的分组/筛选。
- 完整后端契约见 [§3.14](03-api-reference.md) + [§2 `connected_apps`](02-data-model.md)。

## 4.1 核心交互：导航 dock（`FloatingDock`）

悬浮胶囊，**5 元素**，非底部 TabBar+FAB：

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
- **anchored 主语常驻「关联资产」**：`ChatPage._contextBar` 把 `subjectLabel` 渲染成一个**常驻 accent chip**
  (🔗,永不移除)，与用户后续「+ 添加资产」加进来的普通 context chip 并列。**`+ 添加资产` chip 放在 rail 最前**
  (不用滚过一长串 context 才够得着)。
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
| `text`（已落定） | `MarkdownText` 轻量渲染：`**粗体**`、`` `代码` ``、`*斜体*`、`-/*` 列表、`1.` 列表、`#` 标题（渲染成轻粗体行，非大标题）。**不用 dangerouslySetInnerHTML**，纯 React 节点拼装。 |
| `text`（看起来是 HTML 报告） | salvage：deepseek 偶尔把报告 HTML 当 text 吐出，识别 ` ```html ` / `<style>` / `<!doctype>` 开头 → 渲染成 `ReportReceiptCard`（流式中显「整理报告中…」占位） |
| `tool_call`（流式中且 isLast） | 琥珀色 chip「{中文名}中…」+ spinner。**落定后的 tool_call 不渲染**（其 tool_result 接续，重复 chip 冗余）。 |
| `tool_result`（report） | `ReportReceiptCard`（紧凑回执卡，点开全屏 `ReportSheet`，**chat 内不显原始 HTML**） |
| `tool_result`（query 类） | `CollapsibleQueryResult`：折叠成「↩ 查询资产 · 找到 N 项 ▸」，点开展开（避免中间查询结果刷屏，尤其喂给 SUMMARY 时） |
| `tool_result`（其它，有卡片） | 每张 `AssetCardInChat`（inline 布局，点开 `AssetDetailDrawer`） |
| `tool_result`（无卡片，如 delete） | 小字「↩ {中文名} 完成」 |
| `cards`（持久化的 flash 卡） | 每张 `AssetCardInChat` |
| `error` | 红色 chip + `AlertCircle` |

工具中文名映射见 `TOOL_LABEL`（`tool_create_asset`→「创建资产」… 全表见源码 / §A）。
`QUERY_TOOLS = {tool_query_asset, tool_query_event, tool_query_contact, tool_query_input_turn}`。

卡片类型标记 `tagByIdField()`：按 id 字段推 `card_type`——**`task_id` 优先于 `asset_id`**（create_task
结果同时带二者，task 路由到生命周期卡），其后 `event_id`→event、`contact_id`→contact、`input_turn_id`→input_turn。

### 4.2.4 「沉淀为资产」（`PrecipitateMenu`）

判定时机 = 一轮 agent 输出之后：
- **显示**条件：非流式 + 有 `onPrecipitate` + 纯文本长度 > 8 + **本轮未创建卡片**（`turnCreatedCards()` 为 false）
  + 文本不是 HTML 报告。
- `turnCreatedCards()`：有 `cards` part，或非 query/非 report 的 tool_result 产出了卡片 → 视为已创建 → 不显沉淀。
  （deepseek 偶尔在知识问答里误发一次 query，所以**不能**用「有任何工具活动」来 gate。）
- 4 个目标 skill：`todo`（待办）/ `notes`（笔记）/ `idea`（想法）/ `misc`（其它）。**无** expense/contact/event
  （那些需结构化输入）。
- 点选 → `handlePrecipitate(text, skill)` → POST `/api/assets`（`notes`/`idea` 额外从首行裁 ≤24 字做 title）→
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

> **文件实体已下线（Flutter）**：早期 web demo 有「文件(♪)」一级实体（闪念录音等）。产品上它对用户无意义，
> 已从 app 移除——`常驻` 不再有文件 tile、`最近` 不合并文件、日历/时间线 `fetchTimeline` 过滤掉 `kind=='file'`、
> SkillCard / detail sheet / render_spec 不再有 `file` 分支。后端 `/api/files`(供事件附件/音频基础设施)保留,
> 只是前端不再把它当可浏览实体。

三段式：
1. **常驻 · PERMANENT**（3-col grid）：一级实体 tile——事件(●紫)/名片(◯neutral)/外部(🔗blue)。
   每 tile = 图标块(辉光) + label + mono count，点进 `/library/:key`。
2. **启用的技能 · SKILLS**：`SkillsGrid`，每个注册 user skill 一 tile（按 `position` 排序）。**首格**是
   「新技能」(✨) tile → `AddSkillWizard`，用**虚线品牌色边框**(`_DashedBorder`) 表「添加」感，右下角显示
   **`当前数量/上限`**(如 `8/30`，满了转红)。隐藏 `external_ref`/`qa`/`contact`（系统 skill）。
   保护集 `{todo,idea,expense,notes,misc}` 不可删；用户自建可删。**`USER_SKILL_CAP=30`**(前端 `_skillCap`
   与后端 `api/skills.py` 常量同步；展示用 grid 可见技能数,后端 cap 计数另含 contact/external_ref，故 cap 远未到
   时二者可差 ~2，无实际影响)。
   - **活跃集（设计中，见 §4.4.5）**：格子**只显活跃技能**（`enabled=1`，上限 `ACTIVE_SKILL_CAP=9`）。
     末尾加一个「⚙ 查看全部技能 →」入口 → **技能管理页**（列全部含停用的，开关激活）。即「格子 = 活跃集，
     管理页 = 全量」。
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
- 点 skill tile → 该 skill 的 `SkillCreateForm`（不卸载本 sheet，表单作 sibling overlay）。
- **刻意不含 AI 入口**：跟 Agent 对话 / 闪念 已在 dock 的 Agent pill + 🎙——所以「+」语义纯粹是「造一个东西」。

### 4.4.2 CategoryDetail（drill-down）

- 由 `:skillName` 驱动。一级实体（event/file/contact）走各自专用 endpoint + **内联硬编码 fake render_spec**；
  其余 asset-backed skill 走 `useAssets({skillName})` + registry 的 render_spec。
- 列表每条 `SkillCard`，点开 `AssetDetailDrawer`。todo 类带 `onToggleCheck`（`useToggleTodo`）。
- **按天分隔（Flutter 增量）**：列表维持 `created_at` 倒序，只在**跨天处插一个轻分组头**（今天 / 昨天 /
  M月D日），复用「最近」「日历」已有的分组样式。数据一多时给个时间锚,**仅视觉分隔,不加排序菜单**(刻意从简)。
- **删除技能**（仅非保护 + 有 user_skill_id）：右上 🗑 → `DeleteSkillDialog` 两段确认。
  无资产 → 「确定删除」；有资产 → force-confirm「这会同时删除 N 条记录」，`DELETE /api/skills/:id?force=true`。
  > ⚠️ 已知 bug：`api/skills.py` 级联删除用了 Postgres 专有 SQL，MySQL 跑不通（见 §2/§3）。
- **外部(`external_ref`)容器 → 管理连接入口（设计中）**：这个容器装的是同步到第三方的引用。头部加一个
  「⚙ 管理连接 →」入口 → 设置 → 已连接应用（§4.0.6）。让用户从"看外部产物"的地方直接去"管外部连接"。

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
- **长内容展开（Flutter 增量,关键）**：详情 sheet **整体可滚动**;被判为长文的字段(按**字符数/换行数**的
  通用规则,**不写死字段名**,自定义 skill 的长正文同样适用)默认**折叠到 ~6 行 + 渐隐**,底部「展开/收起」
  **就地铺开**;展开后仍 > 一屏的,再给「**全屏阅读**」→ 推一个纯阅读页(标题 + 全文 + 复制)。这样短内容不被
  撑大、notes/灵感的长正文也能完整看。`MULTILINE_KEYS` 之外按内容长度兜底判定。
- **字段标签 + 格式 = skill 自定义驱动（关键，别按字段名瞎猜）**：
  - **标签**：优先用该 skill 的 `payload_schema[field].label`（design agent / 种子给每个字段写的 2-5 字中文短
    标签，例 喝水 skill 的 `amount`→「水量」）；缺失才回退「通用字段名表」（content→内容、due_date→截止时间…），
    再回退字段名本身。**绝不**把任意 `amount` 当「金额」——那是 expense 专属语义。
  - **格式**：以该 skill 的 `render_spec` 字段格式为准（`primary_format`/`secondary_format`/`meta_fields[].format`）——
    例如 expense 在自己的 render_spec 里把 `amount` 标成 `currency`，所以 ¥ 来自 render_spec 而**不是**字段名推断。
    render_spec 没声明的字段才做「按值兜底推断」（ISO 串 → 日期格式），**永不**按字段名推断货币。
  - 迁移注意:Flutter 把 RenderSpec 加了 `fieldLabels`(来自 payload_schema)+ `formatForField()`,detail sheet
    收 `spec` 参数据此渲染;`_inferFormat` 只剩日期类兜底。`MULTILINE_KEYS` 决定多行。
- **编辑分支**：`isEvent`→`EventForm`、`isContact`→`ContactForm`、其余→`SkillCreateForm`（`existing` 预填）。
  编辑表单是全屏模态，关闭后回到 drawer（SWR 已刷新 payload）。
- **删除 endpoint**：event→`/api/events/:id`、contact→`/api/contacts/:id`、其余→`/api/assets/:id`；
  成功失效 assets/events/contacts/timeline。
- **AgentTarget**：mount 时按 cardType 推 subjectType（contact/event/file/asset）`setAgentTarget`，unmount 清空。

### 4.4.4 报告容器 + 总结·升华入口（合成引擎前端）

资产库常驻多一个 **「报告」容器（📊）**;头部 + 一个显眼的 **「✨ 总结 · 升华」** 按钮 → 开一个
`session_type='report'` 的引导会话(复用 Chat 基建)。该会话里可一句话直给、可逐步引导、可走「手动选择资产」
全屏多选器(带类型筛选 tab)。报告点开 = 全屏 **WebView 查看器**。
**完整规格(dispatcher / 内容 skill / md→HTML 渲染 / GSAP / 实体生命周期 / 各前端表面)见
[§6 合成·报告引擎](06-synthesis-report.md)** —— 本节只是前端指针。

### 4.4.5 技能管理页（启用/停用 + 活跃集，设计规格 · 待实现）

资产库 SKILLS 格子的「⚙ 查看全部技能 →」入口打开。一页管全部技能(含停用的)：

- **列表**：`GET /api/skills`(返回**全部**含 `enabled`)。每条 = 图标 + 名称 + 记录数 + **激活开关**；
  支持**拖拽排序**(写 `position`)、**删除**(`DeleteSkillDialog`,同 §4.4.2)；末尾「✨ 新技能」→ `AddSkillWizard`。
- **活跃集 + 硬上限**：顶部显 **`活跃数/9`**(`ACTIVE_SKILL_CAP=9`)。开关切换是**暂存**;顶部「保存」
  → `PUT /api/skills/active {active_ids}`。**激活已满 9 再开 → 拦截 + 提示「先停用一个」**(开关回弹或置灰)。
- **保存即生效**：写完活跃集,**下一条 agent 消息**就按新集路由(dispatcher hint 每请求现拉,无需重启)。
  保存后 `bumpData()`,资产库格子立即只剩活跃的。
- **停用语义(给用户的话)**：停用 = 从首页格子收起、agent 不再自动往里记;**历史记录不删、仍可查**
  (点开停用技能仍能看旧记录,Agent 也答得出「我之前记的 X」)。
- 后端契约见 [§3.3 `/api/skills`](03-api-reference.md) + [§2 `user_skills.enabled`](02-data-model.md);
  路由按 enabled 过滤见 [§1.3](01-agent-architecture.md)。

---

## 4.5 日历（`/calendar`）

### 4.5.1 CalendarPage

顶部居中 `Segmented`（流/月/年，**默认月**），右侧 `HeaderControls`（🔔 + 昼夜切换）。

> Flutter 端把 🔔 + 昼夜切换收进了**全局 header bar**（见 §4.0.4），所以日历页头只剩居中
> segmented + 一个刷新按钮；资产库页头只剩标题/计数。全局控件不再各页重复。
三视图：`ScheduleView`（流）/ `MonthPane`（月）/ `YearPane`（年）。年→点月→切月视图并滚到该月。

`handleItemTap(item)` 分发：
- `input_turn`（闪念）→ set active session + `navigate("/chat")`。
- `event` → `EventDetailModal`（→ AssetDetailDrawer，cardType=event）。
- `contact` → `ContactDetailModal`。
- 其余 → `AssetDetailModal`。

**创建已收归全局**：日历内**无**任何内联「+ 添加事件」，统一走 dock 的 +。

### 4.5.2 ScheduleView（流 / Timepage 风格时间流）

学自用户分享的 Timepage 录屏，5 个行为（移植时是「日历手感」的关键）：
- **A** 滚动时右侧浮现「N 天/周/月/年 前/后」大字水印（`distanceLabel`：0→今天、±1→明天/昨天、<7→N天、
  <28→N周、<365→N月、否则 N年），滚动停 250ms 后淡出。
- **B** 每月首行左 rail 显「2026 / X月」锚点，当月 brand 蓝 + 辉光。
- **C** 所有日 tile **同一蓝色调**（`var(--eu-brand-faint)` 渐变），类型信号靠 tile 内每条的图标 halo（events 紫/todos 蓝/…）。
- **D** 空日 = 同色空间（不显「空闲」斜体）；`仅有事/全部` toggle（持久化 `eureka:schedule_show_empty`）控制空日是否折叠成
  `GapRow`（一条渐变细线）。
- **E** 「跳回今天」44px 浮钮（`⌄`），仅当今日离屏时显。
- 挂载自动滚到今日中心；近底部时 `fwdDays += 120`（≈无限前向滚动，cap ~10y）。
- tile 高随条目数：50/82/112/136+（0/1/2/3+）。
- **FlashItemRow**：闪念在流里渲染成 ⚡ + 产出 breakdown「✅ 待办×2 · 👤 联系人×1」（`derived` 字段，
  自建 skill 经 registry 取 icon/label），点开捕捉 session。

### 4.5.3 EventForm（事件创建/编辑）

全产品统一用这个 drawer-shape 表单（取代旧 Timepage 式 EventEditor）。`existing` prop 切创建/编辑。
字段：标题(必填) / 全天 toggle / 开始(datetime-local 或 date) / 结束(非全天才显) / 地点 / 描述。
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
  解读 → 当天晚些的时刻会整体跨天(用户选 6.4 → 存成 6.5)。`SkillCreateForm` 的 datetime/date 字段同此规则。

### 4.5.4 MonthPane / YearPane / DayDetailSheet（日视图）

- `MonthPane`（Flutter `_MonthView`）：连续月网格 + 底部「选中日」footer。**点一下选日**(footer 列当天条目)，
  **再点同一天 / 点 footer 头部的「日程 ›」→ 打开日视图**（mirrors web：tap-again → DayDetail）。
  footer 用**固定高度**(`screenHeight * 0.30`,内部滚动),不随选中日的条目多少伸缩——否则上面的月网格会跟着
  reflow/跳动。
- `YearPane`（`_YearView`）：12 宫格，点月回月视图。
- **日视图 `DayDetailPage`（Flutter，全屏；web 是 `DayDetailSheet`）**：
  - 顶部：返回 + 星期/距离/月日 + **日程⇄列表 toggle**。
  - **列表(默认)**：当天全部条目按 `effective_at` 时间升序，紧凑可点行（time/icon/标题/副标题）→ `_openTimelineItem`。
  - **日程(hour grid)**：24 行 × 56px 时刻轴。**网格只画「日程」= 事件**(非全天事件按 start/end 绝对定位成紫色块；
    全天事件走顶部 chip 行)。**待办和其它捕捉(todo/expense/idea/contact/notes/misc)不上网格**——它们进网格上方的
    **「今日捕捉」分区，按类型分 tab**(待办/记账/想法/名片/笔记/…,点 tab 切类型)。该分区**固定高度=3 行**
    (`60*3+4*2`,内部滚动),切 tab 时不伸缩,网格不跳动。今天画红色 now 线；挂载时自动滚到「最早事件前 1h / 否则 7 点」。
  - **统一小标题**：「今日捕捉」和网格的「日程安排」用同一个 `_sectionTitle`(mono caps + 可选 trailing,如 tab 行),
    两块读起来是一套系统。
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
3. **preview**：`buildCard(draft.render_spec + sample_payload)` **实时**预览大卡 + 日程行（`CalendarBulletPreview`）。
   - **字段配置**：每个 payload 字段一行，slot 选 `主/副/信息/隐藏`。主 1、副 1、信息 ≤3（满则禁用）。
     主标题**同时**出现在大卡和日历行（单一真值，`applySlotPick` 强制 primary/secondary 唯一）。
   - 可调 display_name / icon(≤2 字) / accent（7 色板）。
4. **register**：POST `/api/skills/confirm{name, display_name, payload_schema, render_spec, queryable_fields:[]}`
   → 失效 `/api/skills` → 关闭。409 显后端真实原因（重名 OR 容量满）。

`composeRenderSpec` strip 掉 legacy 装饰键（`field_units`/`*_label`/`*_unit`）——单位写进值里。

> **每个 payload 字段带 `label`**：design agent 为每个字段生成一个 2-5 字中文短标签（机器名可英文，但
> label 要贴合 skill 语义 —— 喝水的 `amount`→「水量」而非「金额」），随 `payload_schema` 落库。详情页
> 据此显示字段名（见 §4.4.3「字段标签 + 格式 = skill 自定义驱动」），而不是按字段名硬猜。

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
