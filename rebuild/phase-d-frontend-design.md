# Phase D — Eureka 前端设计与实施 spec

> 版本:v1.2 | 2026-05-27
> 状态:实施中。v1.2 在 M3-redo 后回写 M2.x / M3.x / M3.5 的实际决策(避免 spec drift)
> 配套:[phase-a 产品定义](phase-a-product-definition.md) · [phase-b 架构蓝图](phase-b-architecture-blueprint.md) · [runtime-flow 调用图谱](runtime-flow.md) · [design-system](design-system.md) · [design-tokens.css](design-tokens.css) · [design-canvas](design-canvas/) ← **设计真相;phase-d 与之冲突时以 canvas 为准**

> ## v1.2 amendments (2026-05-27)
>
> M3 第一版偏离 design-canvas 较多(普通 form / list 而不是 colored 瓦片 / colored panel)。彻底 redo,见 §三.2 + §四. M3-redo 段落。其它持续性的 spec 变更同步如下:
>
> | 变更 | 出处 | 落地点 |
> |---|---|---|
> | session 模型统一为「subject + additive context」 | M2.3 + M3.5 brainstorm | §三.1 ChatPage 段落 + §配套后端 |
> | POST /api/sessions 收口(subject_type/subject_id 模式) | M3.5 brainstorm | 后端 §配套 |
> | /chat 隐藏 FloatingDock + ChatInput 沉底 + back-nav | M3.5 brainstorm | §0 AppShell amendment |
> | 所有 asset 都有 home session(不只一级实体) | M2.3 brainstorm | §三.4 AssetDetailDrawer |
> | SubjectBanner + ContextChipRail 加入 ChatPage | M2.2 + M2.3 + M3.5 | §三.1 ChatPage |
> | 整库 wipe 脚本 scripts/clear_data.py(--force) | M3.5 | 后端 §配套 |
>
> 以后每次 brainstorm 后立刻同步本 spec,不再 drift。

本文是 Phase D 前端实施的契约。Backend Phase C 已稳定运行(Flash / Chat / Task-skill / 4 个 MCP 接入 / render_spec-driven 卡片管线全部验证通过),Phase D 把前端从 `frontend-test/` 的单文件 QA 工具升级到生产级 SPA。

---

## 一、关键决策(brainstorm 锁定)

| # | 决策点 | 选择 | 备注 |
|---|---|---|---|
| 1 | MVP 切片形状 | 完整骨架 —— Shell + Chat + Library + Calendar + AssetDetail 同时起,每页先出最小可跳转的版本 | 不分批做单一页,要的是端到端可点 |
| 2 | 技术栈 | Vite 5 + React 18 + TypeScript strict + Tailwind 3 + SWR + React Router 6 | YAGNI:无 Redux / Zustand / Next.js / SSR |
| 3 | 代码位置 | 新建 `Eureka-BrandNew/frontend/`,保留 `frontend-test/` 作 backend 调试工具 | 两个面共存,各司其职 |
| 4 | 响应式 | Mobile-first,desktop 增强(`md:` 起 768px) | 跟硬件优先产品定位对齐 |
| 5 | 非一级实体「在 chat 里继续讨论」 | **回到创建它的那个 session**(用 `asset.session_id`) | 保持话题连续性 |
| 6 | Notification MVP 范围 | Toast(事件驱动)+ NotificationPage + 时间驱动提醒 | 文件相关随 file pipeline 后做 |
| 7 | AddSkillWizard MVP | 含 —— 端到端验证 design_agent backend | 这是 D2 核心愿景,必须跑通 |

---

## 二、技术栈与模块结构

### 栈选择

| 决策点 | 选择 | 理由 |
|---|---|---|
| Build / dev server | **Vite 5** | 启动毫秒级,HMR 干净 |
| 框架 | **React 18 + TypeScript strict** | 通用 |
| 样式 | **Tailwind 3** + `theme()` 桥接 design tokens | Tailwind config 把 `--eu-*` CSS vars 暴露为 `text-eu-purple` 等类 |
| 路由 | **React Router DOM 6** | 4 个顶层 page,移动 history 友好 |
| 服务端状态 | **SWR** | 轻量、hooks 原生 |
| 本地状态 | 组件 state + Context(只 3 个:PresentationMode / Toast / Drawer) | 无 Redux/Zustand |
| API 客户端 | `lib/api.ts` 手写 fetch 薄包装 | 后端 12 端点,生成 SDK 是过度工程 |
| SSE | 原生 EventSource + `lib/sse.ts` 重连封装 | chat / flash / notifications 三处用 |
| Icons | **lucide-react** | tree-shake 友好 |
| Lint / Format | ESLint + Prettier 默认 config | |
| 单测 | **Vitest + React Testing Library**,只测纯函数(render-spec / format) | 覆盖最有价值的部分 |
| E2E | **暂不做**,post-MVP | |

### 模块结构(`Eureka-BrandNew/frontend/src/`)

```
src/
├── main.tsx
├── App.tsx                       AppShell + 路由
├── styles/
│   ├── tokens.css                copy from docs/rebuild/design-tokens.css
│   └── globals.css               .theme-atmosphere class application
├── components/
│   ├── shell/
│   │   ├── AppShell.tsx
│   │   ├── TopBar.tsx            logo + 标题 + 3 icon (Device/Profile/Notification)
│   │   ├── TabBar.tsx            Chat / Calendar / Library 三 tab + 中间 FAB cutout
│   │   ├── DeviceMenu.tsx        MVP: 「未连接」placeholder
│   │   ├── ProfileMenu.tsx       含 PresentationMode 切换
│   │   ├── NotificationBell.tsx  红点 + popover 最近 5
│   │   ├── ModeSwitcher.tsx      Asset mode ⇄ Calendar mode
│   │   └── FlashFab.tsx          中间凸起 FAB → 全屏 sheet
│   ├── skill/
│   │   ├── SkillCard.tsx         render_spec 解释器
│   │   ├── GenericField.tsx
│   │   └── AddSkillWizard.tsx    4 步:描述 → 生成 → 预览 → 注册
│   ├── chat/
│   │   ├── MessageList.tsx
│   │   ├── MessageBubble.tsx
│   │   ├── AssetCardInChat.tsx   用 SkillCard,点开 AssetDetailDrawer
│   │   ├── SessionSidebar.tsx    desktop 持久 240px / mobile 抽屉
│   │   └── PrecipitateButton.tsx 沉淀为资产菜单
│   ├── calendar/
│   │   ├── ScheduleView.tsx
│   │   ├── MonthGrid.tsx
│   │   ├── DayDetailSheet.tsx
│   │   └── EventEditor.tsx
│   ├── library/
│   │   ├── CategoryList.tsx      一级:8 行类型 + count + +号
│   │   ├── CategoryDetail.tsx    二级:某类型下所有 asset 列表
│   │   └── CreateAssetMenu.tsx   一级页面右上 + 按钮
│   ├── notification/
│   │   ├── NotificationPage.tsx
│   │   ├── NotificationItem.tsx
│   │   └── Toast.tsx
│   ├── asset/
│   │   └── AssetDetailDrawer.tsx mobile 底抽屉 / desktop 右抽屉
│   └── ui/                       Button, Input, Tag, Pill, Drawer, Sheet …
├── pages/
│   ├── ChatPage.tsx
│   ├── CalendarPage.tsx
│   ├── LibraryPage.tsx
│   └── NotificationPage.tsx
├── hooks/
│   ├── useChat.ts                SSE EventSource 封装
│   ├── useFlashCapture.ts        /api/flash
│   ├── useSkillRegistry.ts       /api/skills + SWR
│   ├── useAssets.ts              /api/assets + SWR
│   ├── useTasks.ts               /api/tasks + polling
│   ├── useNotifications.ts       拉历史 + SSE 订阅新增
│   ├── useSessionForEntity.ts    get-or-create session per file/contact/event
│   ├── useSessions.ts
│   └── usePresentationMode.ts    localStorage hook
├── lib/
│   ├── api.ts                    fetch 客户端 + 错误处理
│   ├── sse.ts                    EventSource 工具
│   ├── render-spec.ts            RenderSpec type + interpreter
│   ├── notification.ts           toast queue 管理
│   ├── format.ts                 _apply_format JS 镜像
│   └── types.ts                  API 响应类型
└── context/
    ├── PresentationModeContext.tsx
    ├── ToastContext.tsx
    └── DrawerContext.tsx
```

### 配套后端改动(在对应 milestone 一起做)

| 改动 | Milestone | 状态 | 备注 |
|---|---|---|---|
| `sessions` 表加 `contact_id` / `file_id` / `subject_asset_id` / `context_asset_ids[]` 列 | **M2.3** | ✅ done | migration `0005_session_subject_fks.py`(原计划 M4,提前到 M2.3) |
| **统一** `POST /api/sessions` 接受 `{subject_type, subject_id, context_asset_ids[]}` get-or-create | **M3.5** | ✅ done | 吃掉了原计划的 `/for-entity`(短暂叫 `/for-subject`,M3.5 合并进 POST /sessions) |
| `PATCH /api/sessions/:id/context {add, remove}` | M2.2 | ✅ done | additive context 增删 |
| `core/session_service.load_session_subject_hint` + agent prompt 三 hint(subject 永久焦点 / context 附加 / assets 本 session 创建) | M2.3 | ✅ done | 三 hint 语义不重叠 |
| `backend/scripts/clear_data.py --force`(整库 wipe) | M3.5 | ✅ done | session_replication_role=replica 处理 FK 环 |
| 验证 / 修复 `agents/design_agent.py` 端到端 | M5 | pending | |
| `notifications` 表 + alembic migration | M6 | pending | |
| `api/notifications.py`(list / mark_read / dismiss / SSE stream) | M6 | pending | |
| Flash 完成 / Task 完成失败时 insert notification | M6 | pending | |
| `core/reminder_scheduler.py` (APScheduler 每分钟扫 todo/event) | M7 | pending | |

---

## 三、MVP scope by surface

### 0. AppShell

✅ TopBar(logo + 标题 + 3 icon:Device / Notification / Profile)
✅ ProfileMenu 内含 PresentationMode 切换(Asset mode ⇄ Calendar mode)
✅ **FloatingDock(悬浮 capsule,替代原 TabBar + FAB)**:
  - 今天(日历 icon 带当天日期)→ `/calendar`
  - 资产库(grid icon)→ `/library`
  - ── divider ──
  - 快创(+)→ CreateAssetMenu popover(M1 接入)
  - 闪念(mic)→ 全屏 sheet 输入 → /api/flash
  - ── divider ──
  - Agent(✨ 紫渐变 pill)→ `/chat`
  - **不带「当前页」高亮**(TopBar 已显示页名,dock 是纯快捷栏)
✅ React Router:`/chat` `/calendar` `/library` `/notifications`
❌ Settings 页(deferred,留 placeholder)
❌ DeviceMenu 真实连接逻辑(MVP 「未连接」placeholder)

> **v1.0 → v1.1 amendment(2026-05-26)**:原 spec 写的是「底部 TabBar(3 tab)+ 中间凸起 FAB」。M0 落地时发现 TabBar 形态视觉不够轻盈,且 grid 实现导致 tab 分布不均匀。用户决定改为**全局悬浮 dock**(5 元素 capsule),替换 TabBar + FAB,所有页面共享同一个 dock。Chat / Calendar / Library 不再是 tab,Chat 进入通过 Agent pill。
>
> **v1.1 → v1.2 amendment(2026-05-27)**:`/chat` 是 dock 的例外。session 页面里 ChatInput 沉底,user 需要的「上级返回」入口由 ChatPage 顶部 nav 提供(`← back + 🏠 home + 中间 session title + + 新对话`),不需要 dock 重复。AppShell 用 `useLocation()` 判断 `/chat` 时不渲染 dock + `pb-28 → pb-0`。其它路由 dock 保持。

### 1. ChatPage

✅ SessionSidebar(Claude 风,desktop 持久 / mobile 滑出)
✅ Session 点击切换 + replay 历史(`/api/sessions/:id/messages`)
✅ "新建对话" 按钮
✅ SSE 流:token / tool_call / tool_result / done
✅ 历史 cards 内联渲染(SkillCard / EventCard / TaskCard)
✅ cards 全可点 → AssetDetailDrawer
✅ "沉淀为资产" 按钮 hover 出现
✅ **(v1.2)** 顶部 nav:← back(智能优先级:router.state.from → /library)+ 🏠 home + 中间 session title + 「+ 新对话」 + (mobile)历史 toggle
✅ **(v1.2)** SubjectBanner(M2.3)— session 有 subject FK 时显示主语卡(contact / event / file / asset)
✅ **(v1.2)** ContextChipRail(M2.2)— 显示 + 编辑 `context_asset_ids[]`,「+ 添加资产」 picker
✅ **(v1.2)** ChatInput sticky bottom — AppShell 在 /chat 不渲染 dock + pb-0
❌ Multi-session 标签页式(deferred)
❌ 语音输入(硬件做)
❌ Chat 内 inline EventEditor(创建 event 走 agent tool_call)

### 2. CalendarPage **(M3-redo: 严格对齐 design-canvas/var-b-calendar.jsx)**

✅ **Schedule** 视图 = colored 瓦片时间流(替代独立时间流页面)
  - 顶部:大字 `5月` brand-glow + mono `2026` + 右上 ⌕ ⋮
  - **类型筛选 chips**:`全部 · 事件 · 待办 · 想法 · 记账 · 名片`(每个有 accent dot + mono count)
  - 左 64px **日期 rail**(weekday cap mono + 日期数字 Manrope;today 右侧 2px brand 竖线 + glow + 数字变 `#a4c2ff`)
  - 右 **「日色」瓦片**(背景按当日资产 dominant accent 推导:仅 event=紫渐变 / 仅 todo=蓝渐变 / 混合=紫蓝 / 仅 idea=琥珀 / 空=`#0e1426`)
  - 每瓦片项:mono 时间 + accent dot + 标题(白字)
  - **空闲瓦片** 50px + 「空闲」斜体(用户能看出哪天空)
  - 右上角 mono caps `TODAY` / `TOMORROW` 标签
  - **mount 时自动滚到 today**

✅ **Month** 视图 = 圆点格 + 选中日摘要
  - 顶部:3×3 brand pixel logo + 大字 `5月` Manrope 700 36px brand glow + mono `2026`
  - Weekday header `S/M/T/W/T/F/S` mono caps 0.16em
  - **32×32 圆点**(不是 cell)— event=紫 tint + ring / todo=蓝 tint + ring / mixed=深紫 / today=白实心+大 glow+反色 / selected=白 1.5px ring + 紫 tint
  - 跨月日期 opacity 调低,仍可点
  - **下半屏选中日摘要**:mono 日期 + caps brand「N 件事」+ event list(mono 时间 + dot + title)+ `+ 添加事件` mono
  - **右边缘 3px gesture strip**(6 种 accent 拼接)gesture affordance

✅ **DayDetail** sheet = 全屏 + dominant accent 渐变
  - 渐变背景按 day 主导 accent 推导(event=紫 / todo=蓝 / idea=琥珀 / 空=暗灰)
  - 右上 + 左下两团 radial 氛围光
  - 顶 bar:‹ 玻璃 back / 中间 `周X` 0.20em + 下方 mono caps `MAY 26` / + 添加
  - **4 分组**:`事件` / `待办` / `今日捕捉` / `来源`(SectionLabel caps mono)
  - **玻璃卡** `rgba(255,255,255,0.10) + backdrop-blur`,每张 header 用 mini-icon + caps mono kind 标签
  - 有 source_input_turn_id 的卡末尾带 `♪ 闪念 · 14:32 →` SourceChip

✅ **EventEditor** = 上 64% colored panel + 下 36% 工具栏 + 最近事件
  - 上半:紫渐变 panel + 右上光晕 + 右上 mono caps `EVENT` + 左上 ✕ close
  - 大字可编辑 title + 副位置(可编辑)
  - 居中日期块(`周三` + mono caps `MAY 27`)
  - **大字 mono 时间范围 `10:00 → 11:00`**(time picker inline)
  - **48 格 time scrub bar**(选中段高亮),配 15m/30m/1h/1.5h/2h 快捷 + ±15m/30m 步进
  - **Mode tabs**:`SET TIME / ALL DAY / MULTI-DAY` mono caps + 激活下划线
  - 下半:5 icon 工具栏(✕ ≡ ◎ ◯ + brand 高亮 ⌗→✓ save)+ 最近事件 quick-pick + 删除按钮

❌ Year 视图(deferred,见 design-system §5.4)
❌ 拖拽改时间(用 ±15/30m 步进 + 快捷代替)
❌ recurrence_rule UI(数据库字段在,UI 后做)
❌ FAB(per v1.1 amendment 全局 dock 取代)

### 3. LibraryPage

✅ CategoryList(一级:8 行类型 + count + icon + +号按钮)—— 类型: todo / event / idea / notes / contact / misc / expense / file
✅ + 按钮 → CreateAssetMenu(下拉选 skill type)
✅ 点类型 → CategoryDetail(二级:该类型所有 asset,SkillCard,按 created_at 倒序)
✅ 二级点 card → AssetDetailDrawer
✅ AddSkillWizard 入口(底部「+ 添加新技能」)
❌ 搜索 / 过滤 / 排序(deferred)
❌ 批量操作(deferred)

### 4. AssetDetailDrawer

✅ Mobile 底抽屉 / desktop 右抽屉
✅ payload 全字段(GenericField)
✅ SessionTurnCard(来源 session + input_turn)
✅ 编辑 / 删除(M4)
✅ **(v1.2)** 「在 chat 里讨论」按钮 → **所有** asset 都走 home session(M2.3 决策修订:
  最初设计是「非一级实体跳 asset.session_id」,实测会造成 session 碎片化 —— 多次点
  Kevin 会开多个 session。改为:每个 asset / entity 都有 ONE home session via
  sessions.{contact_id | event_id | file_id | subject_asset_id} FK,get-or-create
  通过 `POST /api/sessions {subject_type, subject_id}` 完成)。跳 chat 时 router state
  携带 `{from: pathname, fromLabel: card.title}` 给 ChatPage 的 back-nav 用。
❌ Revision history(deferred)

### 5. NotificationPage + Toast

✅ Toast(事件驱动):flash 完成 / task 完成 / task 失败
✅ NotificationPage 历史列表(`/notifications`)
✅ NotificationBell 红点 + popover
✅ 时间驱动提醒:todo 到期前 / event 开始前 1h/30m/15m
❌ 文件相关通知(随 file pipeline)
❌ Web Push API / 邮件 / 短信

### 横向

✅ Toast 队列(同时 3 条 FIFO)
✅ Task 卡片状态轮询(移植自 frontend-test)
✅ 错误降级:网络失败 toast / SSE 断线自动重连
❌ 离线缓存 / PWA
❌ 国际化(中文 only)

---

## 四、Milestones(M0–M7)

每个 milestone 结束 = 一次可演示 + 1 个 commit + tag `phase-d/mN`。

| M | 内容 | 估时 | 状态 | 备注 |
|---|---|---|---|---|
| **M0** Foundation | Vite + tokens 桥接 + 路由 + AppShell + dock + lib 骨架 | 1 d | ✅ done | tag `phase-d/m0` |
| **M0.1** Dock 替换 TabBar+FAB | per v1.1 amendment | 0.5 d | ✅ done | tag `phase-d/m0.1` |
| **M1** SkillCard + Library | render-spec interpreter + SkillCard + CategoryList + CategoryDetail + AssetDetailDrawer 只读 + CreateAssetMenu UI | 1.5–2 d | ✅ done | tag `phase-d/m1` |
| **M1.2** SkillCreateForm + ModalContext | schema-driven + dock backdrop fix | 0.5 d | ✅ done | tag `phase-d/m1.2` |
| **M2** Chat + Flash | useChat / useFlashCapture + MessageList + SessionSidebar + history replay + cards-in-chat + FAB 联通 | 2–2.5 d | ✅ done | tag `phase-d/m2` |
| **M2.1** Contact 存储修复 | SkillCreateForm 走 /api/contacts(非 orphan asset) | 0.25 d | ✅ done | tag `phase-d/m2.1` |
| **M2.2** session context + source trace | 在 chat 里讨论 + ContextChipRail + context_asset_ids | 0.5 d | ✅ done | tag `phase-d/m2.2` |
| **M2.3** home session per asset | migration 0005 subject FKs + SubjectBanner + AssetPickerSheet + agent prompt 三 hint | 1 d | ✅ done | tag `phase-d/m2.3`(吃掉了原 M4 后端) |
| **M3** Calendar + EventEditor(第一版) | ScheduleView + MonthGrid + DayDetailSheet + EventEditor + 联通 `/api/events` | 1.5 d | ⚠️ 偏离 canvas,后被 M3-redo 全部重写 | tag `phase-d/m3` |
| **M3.5** session / agent 逻辑统一 | POST /sessions 收口 + /chat 隐藏 dock + back-nav + 整库 wipe 脚本 | 0.5 d | ✅ done | tag `phase-d/m3.5` |
| **M3-redo** Calendar 对齐 canvas | Schedule colored 瓦片 + 类型 filter chips + 空闲 + rail / Month 圆点格 + 选中日摘要 + brand logo + gesture strip / DayDetail glass + dominant accent gradient + 4 分组 / EventEditor 64/36 + colored panel + scrub bar + mode tabs | 2 d | ✅ done | + spec 同步回写(本次 amendment v1.2) |
| **M4** AssetDetail 编辑 | drawer 加 edit / delete(per-entity session 已在 M2.3 提前做) | 0.5 d | pending | 大幅缩水 |
| **M5** AddSkillWizard | 验证 / 修 design_agent + Wizard 4 步 UI + 注册联通 | 1.5 d | pending | |
| **M6** Notification toast + page | migration notifications + API + SSE push + ToastContext + NotificationBell + NotificationPage | 1 d | pending | |
| **M7** 时间驱动提醒 | core/reminder_scheduler.py(APScheduler) + 扫 todo/event 触发 | 1.5–2 d | pending | |

**已用时**:~8 d(M0 → M3-redo,含 M3 redo 的 2 d「重做成本」)
**剩余估时**:~3–4 d(M4 + M5 + M6 + M7)

---

## 五、Git / 交付规则

- branch:新建 `phase-d`(从 main)
- 每个 milestone = 1 个 commit(可含若干小 commit,milestone 边界打 tag `phase-d/m0` … `phase-d/m7`)
- 每个 milestone 结束:push + demo notes(跑通什么 / 已知遗留 / 下一个起手)+ 用户 OK 再起下一个
- M7 完成 → merge phase-d → main

---

## 六、显式 out-of-scope(Phase D 之后)

- 多用户鉴权 / Sign-in flow(目前 `get_current_user_id()` 返回常量 'default')
- 文件 pipeline(上传 + ASR + AI 分析)
- 实时协作 / multi-device 同步
- 离线模式 / PWA
- 国际化
- 暗 / 亮主题切换(MVP 只 .theme-atmosphere 一套)
- 移动端原生 wrapper(Capacitor / React Native)
- 性能埋点 / Analytics
- A/B framework
- Settings 全部页面

---

## 七、变更管理

- Phase D 实施中如发现 spec 错(后端 API 跟前端假设不符 / 设计漏洞 / 估时严重偏差),**立刻停 milestone,在 chat 沟通,更新本 spec,重启**
- 用户随时可以加 / 删 / 换 milestone,我会重新算 timeline
- M7 完成后这份 spec 进入 archived 状态,后续 Phase D Polish 另起新 spec
