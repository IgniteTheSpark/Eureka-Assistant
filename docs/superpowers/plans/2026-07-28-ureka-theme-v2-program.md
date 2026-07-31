# UReka Theme V2 UI/UX Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在保留现有数据、设备、会话和资产能力的前提下，把 UReka Mobile 迁移到 `redesignureka.pen` 定义的 Theme V2，并让 Light/Dark、响应式、可访问性、加载/空/错状态和核心业务闭环达到可回归验证的标准。

**Architecture:** 采用“共享 Theme V2 foundation + 按业务域渐进替换”的方式，不复制 Light/Dark 组件树。现有 API、controller 和 schema-rendering 能力优先复用，旧的大型页面逐步退化为适配层。先替换 Calendar、Library、Asset Detail、Session、Inbox 和 Device 等已有成熟逻辑的 UI；Today/Home 与 Goal 涉及新业务逻辑，放在最后两个业务阶段。

**Tech Stack:** Flutter 3 / Dart、Material、Riverpod、现有 `ApiClient`、FastAPI、SQLAlchemy、Alembic、Flutter widget/golden tests、Python contract tests。

## Global Constraints

- UI 真值顺序：`spec/design/theme-v2-coding-handoff.md` 与 `spec/design/redesignureka.pen` 的 Theme V2 节点优先；`spec/design/design-goal-core.md` 继续作为 Goal 数据语义真值。
- 只实现节点名以 `UReka · Theme V2 /` 或 `Theme V2 /` 开头的设计。Pen 中 legacy 画板只用于迁移对照，不可抄回旧视觉。
- metadata 是交互/业务真值；`$theme-v2/*` 变量是视觉真值。
- Light/Dark 必须由同一组件树和主题变量驱动，禁止维护两套页面。
- 所有交互区域最小 `44 × 44`；视觉图标可以小于 44，但 hit box 与 semantics 不可小于 44。
- Dock 与固定输入区必须处理 SafeArea；键盘使用 `MediaQuery.viewInsets`；动画尊重 reduced motion。
- 先用单元/组件测试锁行为，再写实现；每个任务独立提交，避免跨域巨型提交。
- 不在本重构中改写已有 API/controller 的成熟业务规则，除非该规则与 Theme V2 明确冲突。
- 新页面放在 `mobile/lib/theme_v2/`，迁移稳定后再决定是否删除旧实现，避免继续扩张现有 1000–3600 行单文件。
- 所有 Asset Detail 默认以 Bottom Sheet 打开，并可展开为 Full Page；资产类型不决定 presentation。
- Today/Home 与 Goal 是最后两个业务模块；在它们之前不创建临时 Goal 后端。

---

## Pen 全量巡检结论

### 读取范围

- 文件：`spec/design/redesignureka.pen`
- 顶层节点：236
- Reusable components：94
- 主题轴：`mode = light | dark`
- 深度巡检范围：全部 Theme V2 业务矩阵、Theme V2 reusable components、Theme V2 variables、关键 metadata 和代表性布局快照。
- Legacy 节点已纳入文件盘点，但按 handoff 规则不作为实现真值。

### Foundation 变量

| Token | Light | Dark |
|---|---|---|
| `bg` | `#F7F9FC` | `#0B0D12` |
| `surface` | `#FFFFFF` | `#121620` |
| `fg` | `#101319` | `#F3F5FA` |
| `muted` | `#6D7480` | `#8991A0` |
| `border` | `#D9E0E8` | `#29303D` |
| `accent` | `#25B6D6` | `#8A82FF` |
| `accent-soft` | `#E9F8FC` | `#1A1D35` |
| `critical` | `#D23A57` | `#FF5F7B` |
| `watermark` | `#10131909` | `#FFFFFF09` |

- 字体：Geist / Geist Mono
- 间距：4 / 8 / 12 / 16 / 24
- 圆角：7 / 10 / 14 / 999
- Touch target：44
- Motion：160 / 260 / 420ms，配合 `ease-fluid`

Pen 同时保留 legacy 字体、暖色 palette 和旧 token。工程迁移时必须显式隔离，不能把 legacy token 合并进 Theme V2 命名空间。

### 业务矩阵

| 业务域 | 已巡检的关键节点 | 设计成熟度 | 实施结论 |
|---|---|---:|---|
| Home | `WsOyv`, `PMCdg`, `SuznI`, `BNmyJ`, `vRy65`, `J5cpE`, motion `VvGFs` | 高 | 可实施；Goals Layer 先使用可注入 view model |
| Calendar | `dWO0c`, `YAu8U`, `K1Z2iN`, `fHRmV`, `XbCxS`, `IugNo`, `V9LoFM`, `sc1bQ`, `J20Phd`, `sGk5M`, `zQK41`, `nMTbd`, `a6SVbz`, `M0i6f`, `BeBq4`, `J3XydT`, `vjW39`, `n0Eup4` | 高 | 可实施；先拆解现有 monolith |
| Library | `LTmYy`, `c5ejE`, `B70HCg`, `RTqWK`, `V0MnR`, `uSlon`, `rssuX`, `PnnTE`；Todo/Notes/Events/Contacts/Custom/Wizard 明暗矩阵 | 高 | IA 可实施；Detail 统一 Bottom Sheet → Full Page |
| Session | `UnTYH`, `b2SpwY`, `EHb9x`, `L1P3Sw`, `oQ4nv`, `u7yCE`, `NT9pT`, `b83gbZ`, `MBY4G`, `sO2M6`, `ezrjl`, `vurly` | 高 | 可直接围绕现有 controller 重做 view |
| Goals | `Mqv86`, `WB3fq`, `e6zmV3`, `Me6Bl`, `wpZIJ`, `Vcp3f`, `Es6w4` 及 dark variants | 高 | 当前 UI 方向已确认；作为最后功能模块之一接入 |
| Device | `wmIGW`, `Rf4KY`, `P8qgPL`, `CtBQS`, `b06Vn`, `B9OKu` | 中 | 主路径可实施；最后确认连接与异常态 |

### Reusable components

- 全局：Status Bar、Floating Dock、Global Top Nav。
- Calendar：Sticky Date Rail、Flash Count、Time Band、Time Row、Asset Row、AI Skill Banner、Compact Item、Untimed Divider。
- Session：Header、transcript row、analysis block、history drawer、composer、empty/error blocks。
- 多数组件已使用 `$theme-v2/*`；部分早期 Calendar、Library hub、Status Bar 和 Dock 仍有硬编码或手工重复。
- 工程实现不得逐画板照抄这些硬编码，应回收为 token 和共享组件。

### 已统一的产品口径与剩余缺口

1. Goal 按当前 Theme V2 UI 开发；Home Goals Layer、All Goals、创建、Detail、Adjust 和 History 共用 Goal Core 的确定性数据语义。
2. Todo、Notes、Events、Contacts、Custom 等全部 Asset Detail 默认使用 Bottom Sheet，并可展开为 Full Page；展开前后复用同一状态。
3. P1 Home 只依赖可注入 Goal view model，不要求先建设 Goal 后端；真实 Goal 接入放到最后功能阶段。
4. Goal History 复用 All Goals 组件，Progress/Guardrail Detail 复用 Check-in Detail 骨架，筛选与异步状态复用 P0 primitives。
5. Goal 完整业务与 Device 连接均放在主要页面完成后再进行最终确认。
6. Global Top Nav 的设备、主题、通知控件视觉尺寸多为 36px，代码需要 44px hit box。
7. Notification / Reka Inbox Theme V2 页面仍需完成。
8. Device 的 pairing failure、permission denied、lost connection 和 reconnecting 留到 Device 最终确认阶段。
9. 长中文、系统大字体、窄屏、横屏和 reduced motion 仍需完整验证。

---

## Recommended Delivery Order

1. P0 Truth lock + rollout baseline
2. P0 Foundation + App Shell
3. P2 Calendar
4. P3 Library + schema-driven Asset Detail
5. P4 Session
6. Notification / Reka Inbox
7. P6 Device final confirmation + connection states
8. P1 Today/Home UI + injectable Goal view model
9. P5 Goal final confirmation + full lifecycle
10. P7 Accessibility, responsive, visual regression, rollout cleanup

Calendar 与 Library 可以在 Foundation 稳定后并行开发。执行任务时使用 `0 → 1 → 2 → 3 → 6 → 7 → 8 → 9 → 10 → 11 → 13 → 4 → 5 → 12 → 14 → 15` 的顺序；Today/Home 与 Goal 最后处理。

---

## Task 0: Record the Unified Product Decisions

**Files:**

- Modify: `spec/design/theme-v2-coding-handoff.md`
- Modify: `spec/design/design-goal-core.md`
- Modify: `spec/design/design-goals-proactive-reka.md`
- Modify: `spec/design/redesignureka.pen` through Pencil only
- Modify: `docs/superpowers/plans/2026-07-28-ureka-theme-v2-program.md`

**Steps:**

- [x] 将 Goal Core 更新为 Theme V2 Home Goals Layer 方向。
- [x] 记录 Goal History、Progress/Guardrail Detail 和 All Goals 状态的组件复用规则。
- [x] 记录所有 Asset Detail 默认 Bottom Sheet，并统一支持展开为 Full Page。
- [x] 在 Pen 节点名中把 Todo 画板标记为 Expanded Full Page，把其他 detail 画板标记为 Bottom Sheet。
- [x] 将 Goal 完整业务与 Device 连接移动到最后功能阶段。
- [ ] Commit: `docs: align theme v2 goal asset and delivery decisions`

**Acceptance:**

- handoff、Goal Core、Proactive Goal 文档和实施计划不再对 Home Goal 入口给出相反指令。
- 所有 asset type 使用相同的 Bottom Sheet → Full Page presentation。
- Goal 与 Device 不阻塞 Foundation、Home、Calendar、Library 和 Session。

---

## Task 1: Add Theme V2 Rollout Baseline and Test Harness

**Files:**

- Modify: `mobile/lib/config.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/app_shell.dart`
- Create: `mobile/lib/theme_v2/theme_v2_rollout.dart`
- Create: `mobile/test/theme_v2/theme_v2_rollout_test.dart`
- Create: `mobile/test/theme_v2/theme_v2_test_app.dart`

**Steps:**

- [ ] 写失败测试：`THEME_V2=true` 选择 Theme V2 shell；默认仍可启动旧 shell。
- [ ] 在 `AppConfig` 增加 compile-time `themeV2` bool。
- [ ] 用单一分支在 app root 选择 shell，禁止在各页面散落 feature flag。
- [ ] 创建测试 app helper，固定 locale、screen size、theme 和 reduced-motion。
- [ ] 保留现有 `START_THEME`、`START_TAB`、`START_CAL_MODE`、`START_OVERLAY`、`START_SESSION` screenshot defines。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/theme_v2_rollout_test.dart`
- [ ] 运行：`cd mobile && flutter test test/widget_test.dart`
- [ ] Commit: `feat(theme-v2): add staged rollout baseline`

---

## Task 2: Implement Theme V2 Foundation

**Files:**

- Create: `mobile/lib/theme_v2/foundation/theme_v2_tokens.dart`
- Create: `mobile/lib/theme_v2/foundation/theme_v2_theme.dart`
- Create: `mobile/lib/theme_v2/foundation/theme_v2_typography.dart`
- Create: `mobile/lib/theme_v2/foundation/theme_v2_motion.dart`
- Create: `mobile/lib/theme_v2/foundation/theme_v2_semantics.dart`
- Modify: `mobile/lib/theme/app_theme.dart`
- Modify: `mobile/lib/theme/theme_controller.dart`
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/test/theme_v2/foundation/theme_v2_tokens_test.dart`
- Create: `mobile/test/theme_v2/foundation/theme_v2_theme_test.dart`
- Create: `mobile/test/theme_v2/foundation/theme_v2_motion_test.dart`

**Steps:**

- [ ] 写失败测试，逐项断言 Pen 的 9 组颜色、5 组 spacing、4 组 radius、44px touch target 和 160/260/420ms motion。
- [ ] 建立 `ThemeExtension`，同一结构承载 Light/Dark，不创建 `LightFoo` / `DarkFoo` 组件。
- [ ] 接入 Geist 和 Geist Mono；如果包内字体不可稳定离线解析，则把字体资源 vendored 到 `mobile/assets/fonts/` 并在 `pubspec.yaml` 声明。
- [ ] 实现 `ThemeV2Motion.duration(context, token)`：系统关闭动画时返回 zero duration。
- [ ] 实现 44px hit target wrapper 和统一 icon-button semantics。
- [ ] 让 `themeModeNotifier` 切换仅触发 theme 更新，不销毁 navigation/controller state。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/foundation`
- [ ] 运行：`cd mobile && flutter analyze`
- [ ] Commit: `feat(theme-v2): add tokenized light dark foundation`

---

## Task 3: Build Shared App Shell, Global Top Nav, Dock and Async States

**Files:**

- Create: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Create: `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- Create: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Create: `mobile/lib/theme_v2/shell/device_status_summary.dart`
- Create: `mobile/lib/theme_v2/shell/theme_v2_floating_dock.dart`
- Create: `mobile/lib/theme_v2/shell/theme_v2_async_state.dart`
- Modify: `mobile/lib/app_shell.dart`
- Reuse: `mobile/lib/widgets/global_header.dart`
- Reuse: `mobile/lib/widgets/floating_dock.dart`
- Reuse: `mobile/lib/widgets/skeleton_loader.dart`
- Create: `mobile/test/theme_v2/shell/theme_v2_shell_test.dart`
- Create: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Steps:**

- [ ] 写 widget tests：Global Top Nav 有 Logo、device state、theme toggle、notification；所有 actions hit box ≥44。
- [ ] 写 test：在 Today/Calendar/Library 间切换后页面状态与 controller state 保留。
- [ ] 写 test：Dock 的 bottom padding 包含 SafeArea，窄屏不 overflow。
- [ ] 实现共享 scaffold；页面只声明是否显示 nav、dock、keyboard inset。
- [ ] Global Top Nav 通过可注入的 `DeviceStatusSummary` 渲染状态槽，并复用 theme controller；本任务不修改 scan/pair/reconnect。
- [ ] Task 13 再把现有 device controller 映射到 `DeviceStatusSummary`；在此之前 Theme V2 rollout 保持关闭。
- [ ] 实现统一 loading/empty/error/retry primitives，复用现有 reduced-motion skeleton 行为。
- [ ] 视觉比较 Light/Dark、411px 与 360px。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/shell`
- [ ] Commit: `feat(theme-v2): add shared shell navigation and async states`

---

## Task 4: Define the Home Goals Layer View Contract

**Files:**

- Create: `mobile/lib/theme_v2/home/home_goal_snapshot.dart`
- Create: `mobile/lib/theme_v2/home/home_goal_source.dart`
- Create: `mobile/lib/theme_v2/home/home_goal_section.dart`
- Create: `mobile/test/theme_v2/home/home_goal_snapshot_test.dart`
- Create: `mobile/test/theme_v2/home/home_goal_section_test.dart`

**Interfaces:**

```dart
abstract interface class HomeGoalSource {
  Future<HomeGoalSnapshot> load(DateTime day);
}

class HomeGoalSnapshot {
  final int activeCount;
  final int scheduledCount;
  final List<HomeGoalNode> attentionNodes;
  final List<HomeGoalOverview> goals;
}
```

- P1 使用注入的 `HomeGoalSource` 完成视觉与交互测试，不创建临时 Goal API。
- Theme V2 rollout flag 在最终 Goal 接入前保持关闭，因此测试 fixture 不进入生产数据路径。
- Task 11 实现 `ApiHomeGoalSource`，把同一 contract 接到确定性 Goal 后端。

**Steps:**

- [ ] 写失败测试：摘要显示 active/scheduled 数量；attention nodes 可循环；Goal overview 与 history/+Goal actions 发出稳定 route intent。
- [ ] 实现 immutable view models，覆盖 loading/data/empty/error 四种状态。
- [ ] 实现 `HomeGoalSection`，只消费 `HomeGoalSnapshot`，不引用 API 或数据库类型。
- [ ] 为 Light/Dark golden 提供明确 fixture builder，fixture 仅存在于 `mobile/test/`。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/home/home_goal_snapshot_test.dart test/theme_v2/home/home_goal_section_test.dart`
- [ ] Commit: `feat(theme-v2): define injectable home goal view contract`

---

## Task 5: Implement Home Layer Switch, Agenda, Bubble Pool and Reka Queue

**Files:**

- Create: `mobile/lib/theme_v2/home/theme_v2_home_page.dart`
- Create: `mobile/lib/theme_v2/home/home_controller.dart`
- Create: `mobile/lib/theme_v2/home/home_layer_switch.dart`
- Create: `mobile/lib/theme_v2/home/home_agenda.dart`
- Create: `mobile/lib/theme_v2/home/home_asset_pool.dart`
- Create: `mobile/lib/theme_v2/home/home_reka_queue.dart`
- Reuse: `mobile/lib/theme_v2/home/home_goal_section.dart`
- Reuse/Modify: `mobile/lib/today/today_data.dart`
- Reuse/Modify: `mobile/lib/today/bubble_pool.dart`
- Reuse/Modify: `mobile/lib/today/bubble_physics.dart`
- Reuse: `mobile/lib/today/reka_offer.dart`
- Create: `mobile/test/theme_v2/home/home_layer_switch_test.dart`
- Create: `mobile/test/theme_v2/home/home_agenda_test.dart`
- Create: `mobile/test/theme_v2/home/home_asset_pool_test.dart`
- Create: `mobile/test/theme_v2/home/home_reka_queue_test.dart`
- Create: `mobile/test/theme_v2/home/theme_v2_home_golden_test.dart`

**Interaction truth:**

- Today 与 Goals 是 full-sheet swap；背层 header 露出约 50px。
- 抓取 160ms，稳定落位 420ms；reduced motion 下直接落位。
- 相同 effective time 共用一个时间节点，但展开后每个 item 必须独立可见。
- Reka queue 固定 188px 高，可滚动；placeholder 同高，避免布局跳动。
- Bubble 直径 30–80，位置由 `asset_id` 稳定 seed；最新 1–5 个使用 gradient；尺寸不随排名变化。

**Steps:**

- [ ] 先写 layer gesture tests：tap/drag/settle、快速反向拖动、reduced motion、state preservation。
- [ ] 扩展 Home model 组合 timeline、assets、offers/nudges 与注入的 `HomeGoalSource`；各 section 独立降级。
- [ ] 保留现有 timeline/assets/offer API，不复制 fetch 逻辑。
- [ ] 将现有 Forge2D pool 适配到 Theme V2 的 seed、尺寸和颜色规则；同一资产重载后位置序列稳定。
- [ ] 实现 agenda collapsed/expanded fishbone；验证同一时间的 3 个 item 不被压成 count。
- [ ] 实现固定高度 Reka queue、empty/loading/error/retry。
- [ ] 渲染 `HomeGoalSnapshot` 的 summary、attention stack、overview grid、history 和 +Goal route intent；生产代码不包含 hardcoded demo card。
- [ ] 生成 Light/Dark golden：411×891、360×800；覆盖 Today front、Goals front、agenda expanded。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/home`
- [ ] Commit: `feat(theme-v2): implement layered home experience`

---

## Task 6: Extract Calendar Domain from the Existing Monolith

**Files:**

- Modify: `mobile/lib/pages/calendar_page.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_models.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_controller.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_time_layout.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_mode_state.dart`
- Create: `mobile/test/theme_v2/calendar/calendar_time_layout_test.dart`
- Create: `mobile/test/theme_v2/calendar/calendar_mode_state_test.dart`
- Reuse: `mobile/lib/timeline/timeline.dart`

**Steps:**

- [ ] 写 pure tests 锁定 effective time 排序、event duration、untimed todo、overlap columns、15-minute todo band。
- [ ] 从 3600+ 行旧页面抽出 domain models 和布局算法，先保持旧 UI 行为不变。
- [ ] 定义 Flow / Month / Year 的单一 mode state，支持 horizontal switch 与 screenshot define。
- [ ] 明确 `effectiveAt` 来源：event start、todo due/occurred_at、asset period/occurred_at；禁止用 `createdAt` 代替业务时间。
- [ ] 为 inline draft 定义 ephemeral state；离开日期或取消时清理，确认后才调用现有 mutation。
- [ ] 运行现有 Calendar tests 与新增 pure tests。
- [ ] 运行：`cd mobile && flutter test test/calendar_stream_month_header_test.dart test/theme_v2/calendar`
- [ ] Commit: `refactor(calendar): extract theme v2 domain and layout state`

---

## Task 7: Implement Calendar Flow, Schedule Grid, Month and Year

**Files:**

- Create: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_sticky_date_rail.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_inline_draft.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_month_view.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_year_view.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_components.dart`
- Create: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`
- Create: `mobile/test/theme_v2/calendar/calendar_schedule_grid_test.dart`
- Create: `mobile/test/theme_v2/calendar/calendar_inline_draft_test.dart`
- Create: `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart`

**Interaction truth:**

- Flow 纵向无限滚动；日期首次点击选中，第二次点击打开 detail。
- Flow / Month / Year 横向切换；watermark 跟随 scroll。
- 重叠事件采用并行列。
- 同 due time todos 收进 15-minute band；点击展开并把后续 grid 向下推。
- 空白区域首次点击产生 inline 30-minute draft，确认后创建；再次编辑进入完整 editor。
- Sticky date rail 与 scroll content 是 siblings；下一日期 rail 推走上一 rail；untimed 使用 divider 而不是 rail。

**Steps:**

- [ ] 先写 interaction tests 覆盖上述六条 metadata 规则。
- [ ] 使用共享 Theme V2 components 重建 Flow、day records 和 schedule grid。
- [ ] 所有视觉小于 44 的 calendar controls 外包 44px hit box。
- [ ] Month/Year 不复制 Pen 的固定绝对尺寸，按 constraints 计算列宽和 cell height。
- [ ] 接入现有 asset/event detail routes。
- [ ] 覆盖 loading/empty/error/retry 和跨月边界。
- [ ] Golden 覆盖 handoff 的全部 18 个明暗状态中的代表性状态，并为 sticky transition 做 widget test。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/calendar`
- [ ] Commit: `feat(theme-v2): implement calendar flow and progressive time views`

---

## Task 8: Implement Library Hub, Container Index and Pinned Configuration

**Files:**

- Create: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Create: `mobile/lib/theme_v2/library/library_controller.dart`
- Create: `mobile/lib/theme_v2/library/library_hub.dart`
- Create: `mobile/lib/theme_v2/library/container_index.dart`
- Create: `mobile/lib/theme_v2/library/pinned_configuration.dart`
- Create: `mobile/lib/theme_v2/library/create_skill_action.dart`
- Reuse/Modify: `mobile/lib/pages/library_page.dart`
- Reuse/Modify: `mobile/lib/pages/category_detail_page.dart`
- Create: `mobile/test/theme_v2/library/library_controller_test.dart`
- Create: `mobile/test/theme_v2/library/library_navigation_test.dart`
- Create: `mobile/test/theme_v2/library/theme_v2_library_golden_test.dart`

**Steps:**

- [ ] 写 tests 锁定 Hub、All Containers、Pinned Configure、Create Skill 四类入口的 IA。
- [ ] 保留旧 Library 的 assets/skills/events/contacts/reports 聚合 adapter，删除 view 中的重复 fetch。
- [ ] 创建共享 container tile/list primitives；颜色只能来自 Theme V2 tokens。
- [ ] 把 Create Skill 作为独立 AI primary action，不混入普通 container。
- [ ] 明确 Hub pinned item 的排序持久化和无权限/失败回滚。
- [ ] 覆盖 zero-container、partial-fetch、offline 和 retry。
- [ ] Golden 覆盖 Hub、Container Index、All Containers、Pinned Configure 的 Light/Dark。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/library`
- [ ] Commit: `feat(theme-v2): implement library information architecture`

---

## Task 9: Build Schema-Driven Asset List, Detail and Editor Presentations

**Files:**

- Modify: `mobile/lib/render/render_spec.dart`
- Modify: `mobile/lib/render/asset_detail_sheet.dart`
- Modify: `mobile/lib/assets/assets.dart`
- Create: `mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart`
- Create: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Create: `mobile/lib/theme_v2/library/asset/asset_detail_page.dart`
- Create: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Create: `mobile/lib/theme_v2/library/asset/asset_editor.dart`
- Create: `mobile/lib/theme_v2/library/asset/set_goal_action.dart`
- Create: `mobile/test/theme_v2/library/asset/asset_detail_presentation_test.dart`
- Create: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`
- Create: `mobile/test/theme_v2/library/asset/asset_editor_test.dart`

**Contract:**

- Todo、Notes、Events、Contacts、Custom 和未知 custom skill 全部默认以 Bottom Sheet 打开。
- Bottom Sheet 支持上拉或点击 expand action 进入 Full Page；展开前后共享同一个 detail state、编辑草稿和异步请求。
- Global Top Nav / Dock 由打开上下文和共享页面壳决定，不由 `skillName` 决定。
- “设定目标”接收当前 `user_skill_id` 并预选 skill；无可绑定 skill 时禁用并解释原因。
- Asset model 暴露 `effectiveAt`，保留 `createdAt`；两者不可混用。

**Steps:**

- [ ] 先写 presentation tests，断言 Todo/Notes/Events/Contacts/Custom 和未知 custom skill 都从 Bottom Sheet 开始。
- [ ] 写 widget test：Bottom Sheet 展开为 Full Page 后保留 scroll position、编辑草稿和已加载 detail state。
- [ ] 扩展 `AssetItem` 解析 API 返回的 effective time/occurred_at/period 信息。
- [ ] 将旧 2400+ 行 detail renderer 拆成 field renderer、actions、共享 detail body、sheet/page chrome 和 editor。
- [ ] 所有字段仍由 `render_spec` 驱动；custom skill 不退化为硬编码通用文本页。
- [ ] 接入 edit/delete actions，并让 set-goal 只发出携带 `user_skill_id` 的稳定 route intent；Task 12 再接入真实 Goal route。
- [ ] Editor 处理 keyboard inset、长文本、required validation、动态字体与 unsaved changes。
- [ ] 测试 unknown field/type 的安全 fallback。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/library/asset`
- [ ] 运行现有 asset/todo/event contract tests。
- [ ] Commit: `refactor(theme-v2): add schema driven asset presentations`

---

## Task 10: Implement Session Loaded, Analyzing, History, Keyboard, Empty and Error

**Files:**

- Create: `mobile/lib/theme_v2/session/theme_v2_session_page.dart`
- Create: `mobile/lib/theme_v2/session/session_header.dart`
- Create: `mobile/lib/theme_v2/session/session_transcript.dart`
- Create: `mobile/lib/theme_v2/session/session_analysis_block.dart`
- Create: `mobile/lib/theme_v2/session/session_history_drawer.dart`
- Create: `mobile/lib/theme_v2/session/session_composer.dart`
- Reuse/Modify: `mobile/lib/pages/chat_page.dart`
- Reuse: `mobile/lib/chat/chat_controller.dart`
- Create: `mobile/test/theme_v2/session/session_state_test.dart`
- Create: `mobile/test/theme_v2/session/session_keyboard_test.dart`
- Create: `mobile/test/theme_v2/session/theme_v2_session_golden_test.dart`

**Steps:**

- [ ] 写 tests 把 controller state 映射到 loaded/analyzing/history/empty/error，避免 view 自行推断。
- [ ] Session 使用无 Dock scaffold。
- [ ] 历史 drawer 宽度最大 304px，但窄屏按可用宽度收缩。
- [ ] Composer 使用 `MediaQuery.viewInsets.bottom`，不复制 Pen 中固定 396px keyboard。
- [ ] 切换 history、主题或键盘时保留 transcript 与 streaming state。
- [ ] 分析失败显示 retry，已有 transcript 不消失。
- [ ] Golden 覆盖 12 个状态的 Light/Dark 代表集。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/session`
- [ ] 运行现有 chat/session 相关 tests。
- [ ] Commit: `feat(theme-v2): implement session state matrix`

---

## Task 11: Implement Notification / Reka Inbox Minimum Complete Route

**Files:**

- Create: `mobile/lib/theme_v2/inbox/reka_inbox_page.dart`
- Create: `mobile/lib/theme_v2/inbox/reka_inbox_controller.dart`
- Create: `mobile/lib/theme_v2/inbox/reka_inbox_item.dart`
- Reuse: `mobile/lib/today/reka_offer.dart`
- Reuse: `backend/api/nudges.py`
- Reuse: `backend/api/offers.py`
- Create: `mobile/test/theme_v2/inbox/reka_inbox_controller_test.dart`
- Create: `mobile/test/theme_v2/inbox/reka_inbox_page_test.dart`

**Steps:**

- [ ] 定义 Inbox item 对 pending/recent nudge 和 offer 的统一 read model。
- [ ] unread badge 来自数据状态，不用本地随机数或静态 badge。
- [ ] Inbox 覆盖 loading/empty/error/retry、seen/acted/dismissed。
- [ ] 与 Home Reka queue 共用 outcome mutation 和 cache invalidation。
- [ ] Global Top Nav notification action 打开 Inbox。
- [ ] 运行：`cd mobile && flutter test test/theme_v2/inbox`
- [ ] Commit: `feat(theme-v2): add reka inbox route`

---

## Task 12: Finalize and Implement the Complete Goal Module

**Execution gate:** 在 Foundation、Calendar、Library、Session、Inbox、Device 和 Today/Home 稳定后，先按当前 Theme V2 Goal UI 做一次最终范围确认，再开始本任务。

**Files:**

- Modify: `backend/db/models.py`
- Create: `backend/db/migrations/versions/0030_goal_core.py`
- Create: `backend/core/goals.py`
- Create: `backend/api/goals.py`
- Modify: `backend/main.py`
- Create: `backend/scripts/test_goal_model_contract.py`
- Create: `backend/scripts/test_goal_read_api.py`
- Create: `backend/scripts/test_goal_mutation_api.py`
- Create: `backend/scripts/test_goal_calculator.py`
- Create: `backend/scripts/test_goal_evidence_contract.py`
- Create: `mobile/lib/theme_v2/goals/goal_models.dart`
- Create: `mobile/lib/theme_v2/goals/goal_api.dart`
- Create: `mobile/lib/theme_v2/goals/goal_controller.dart`
- Create: `mobile/lib/theme_v2/goals/api_home_goal_source.dart`
- Create: `mobile/lib/theme_v2/goals/create_goal_flow.dart`
- Create: `mobile/lib/theme_v2/goals/all_goals_page.dart`
- Create: `mobile/lib/theme_v2/goals/goal_detail_page.dart`
- Create: `mobile/lib/theme_v2/goals/goal_progress.dart`
- Create: `mobile/lib/theme_v2/goals/goal_adjustment_sheet.dart`
- Create: `mobile/lib/theme_v2/goals/goal_history_page.dart`
- Create: `mobile/test/theme_v2/goals/create_goal_flow_test.dart`
- Create: `mobile/test/theme_v2/goals/goal_detail_test.dart`
- Create: `mobile/test/theme_v2/goals/goal_adjustment_test.dart`
- Create: `mobile/test/theme_v2/goals/goal_models_test.dart`
- Create: `mobile/test/theme_v2/goals/goal_controller_test.dart`
- Create: `mobile/test/theme_v2/goals/api_home_goal_source_test.dart`

**Contract:**

- Create flow：Select Skill → Describe → deterministic Confirm → Success。
- `GET /api/goals?status=active|scheduled|ended` 与 `GET /api/goals/summary?date=YYYY-MM-DD` 同时服务 My Goals、Home 和 Goal Detail。
- 同一 Skill + Type 最多一个 active/scheduled。
- Rule immutable；Adjust = 结束旧 Goal + 创建新 Goal，并保留 lineage。
- Evidence 是 Assets；manual check-in 必须创建 Asset。
- Progress 可提前达成；Guardrail 追踪到 `ends_at` 后最终结算。
- 本轮不加入 pause、LLM 判定、硬件 Goal 或自动 reminder。

**Steps:**

- [ ] 最终确认本任务仍按当前 Goal UI、Goal Core 和 Home Goals Layer contract 实施，不引入额外 Goal 类型或 Proactive Goal 建议。
- [ ] 先写 model/read API contract tests，覆盖三类 Goal、唯一性、时区边界和空列表。
- [ ] 先写 calculator tests 覆盖 Check-in、Progress、Guardrail、时区、删除/修正 Evidence、结束日边界。
- [ ] 新增 Goal、Goal lineage/adjustment 所需字段和索引；migration 遵循现有 idempotent 检查风格。
- [ ] 实现 deterministic calculator、read endpoints 和严格 Flutter JSON parsing。
- [ ] 实现 create/check-in/adjust/end mutations 和 transaction boundaries。
- [ ] 实现 lineage/history read contract。
- [ ] Create flow 不允许客户端把自然语言直接存为执行规则；确认页展示后端解析后的确定字段。
- [ ] All Goals 覆盖 filter/loading/empty/error。
- [ ] Detail 用同一卡片骨架渲染三种 deterministic progress 模块。
- [ ] Adjust sheet 显示结束旧 Goal 并创建新版本的影响。
- [ ] 用 `ApiHomeGoalSource` 接通 Task 4 的 Home contract；Home、My Goals 与 Detail 必须得到同一计算结果。
- [ ] 从 Asset/Skill detail 和 Home Goals Layer 接入同一 create/detail route。
- [ ] 运行全部 backend Goal scripts 和 mobile Goal tests。
- [ ] Commit: `feat(goals): complete deterministic goal lifecycle`

---

## Task 13: Finalize and Implement Device Connection

**Execution gate:** Calendar、Library、Session 和 Inbox 完成后，对 Device 的连接范围和四类异常态做最终确认；Device 完成后再进入 Today/Home 与 Goal。

**Files:**

- Create: `mobile/lib/theme_v2/device/theme_v2_device_center.dart`
- Create: `mobile/lib/theme_v2/device/device_view_state.dart`
- Create: `mobile/lib/theme_v2/device/device_pairing_flow.dart`
- Create: `mobile/lib/theme_v2/device/device_status_adapter.dart`
- Reuse/Modify: `mobile/lib/pages/device_pairing_page.dart`
- Reuse/Modify: `mobile/lib/pages/my_device_page.dart`
- Reuse: `mobile/lib/device/device_controller.dart`
- Create: `mobile/test/theme_v2/device/device_view_state_test.dart`
- Create: `mobile/test/theme_v2/device/device_pairing_flow_test.dart`
- Create: `mobile/test/theme_v2/device/theme_v2_device_golden_test.dart`

**States:**

- disconnected
- discovering
- discovered
- pairing
- connected
- permissionDenied
- pairingFailed
- reconnecting
- connectionLost

**Steps:**

- [ ] 先写 pure mapping tests：controller state 到上述 view state 必须穷尽。
- [ ] 用 `DeviceStatusAdapter` 把现有 device controller 接到 Task 3 的 `DeviceStatusSummary`。
- [ ] Global Top Nav device pill 打开 Device Center，并显示与 controller 一致的摘要。
- [ ] 复用现有 scan/pair/reconnect/silent reconnect 行为，只替换 view。
- [ ] 权限拒绝提供系统设置说明；pairing failure 提供 retry；connection lost 保留设备身份。
- [ ] 主题切换和 route 往返不重启 scan。
- [ ] 运行：`cd mobile && flutter test test/device_controller_test.dart test/device_silent_reconnect_test.dart test/theme_v2/device`
- [ ] Commit: `feat(theme-v2): implement complete device center states`

---

## Task 14: Accessibility, Responsive and Visual Regression Gate

**Files:**

- Create: `mobile/test/theme_v2/a11y/theme_v2_touch_targets_test.dart`
- Create: `mobile/test/theme_v2/a11y/theme_v2_semantics_test.dart`
- Create: `mobile/test/theme_v2/a11y/theme_v2_text_scale_test.dart`
- Create: `mobile/test/theme_v2/responsive/theme_v2_narrow_screen_test.dart`
- Create: `mobile/test/theme_v2/responsive/theme_v2_landscape_test.dart`
- Create: `mobile/test/theme_v2/goldens/`
- Modify: `mobile/pubspec.yaml`

**Matrix:**

- Light / Dark
- 411×891 reference
- 360×800 narrow
- landscape
- text scale 1.0 / 1.3 / 2.0
- animations enabled / reduced motion
- keyboard closed / open where applicable
- long Chinese titles, skill names and error messages

**Steps:**

- [ ] 自动遍历 tappable semantics rect，失败时输出小于 44px 的 label 与页面。
- [ ] 检查 icon-only actions 都有 semantic label。
- [ ] 检查 Dock、sheet、composer 和 modal 的 focus traversal。
- [ ] 检查 2.0 text scale 下无关键信息裁切；允许内容滚动，不允许固定高度吞字。
- [ ] 生成核心页面 goldens，并把 intentional glow clipping 单独记录为允许差异。
- [ ] 运行：`cd mobile && flutter test test/theme_v2`
- [ ] 运行：`cd mobile && flutter analyze`
- [ ] Commit: `test(theme-v2): add accessibility responsive and visual gates`

---

## Task 15: Switch Default, Remove Transitional Duplication and Release

**Files:**

- Modify: `mobile/lib/config.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/app_shell.dart`
- Modify/Delete after reference audit: old view-only sections in `mobile/lib/pages/today_page.dart`
- Modify/Delete after reference audit: old view-only sections in `mobile/lib/pages/calendar_page.dart`
- Modify/Delete after reference audit: old view-only sections in `mobile/lib/pages/library_page.dart`
- Modify/Delete after reference audit: old view-only sections in `mobile/lib/pages/chat_page.dart`
- Modify: `spec/design/theme-v2-coding-handoff.md`
- Create: `docs/theme-v2-release-checklist.md`

**Steps:**

- [ ] 用 `rg` 确认所有 Theme V2 routes 已覆盖旧主导航入口。
- [ ] 默认启用 Theme V2；保留一次 release 的显式 rollback define。
- [ ] 只删除已确认无引用的旧 view 代码；controller、API adapters 和 schema renderer 不因视觉迁移被误删。
- [ ] 运行完整 Flutter test suite、`flutter analyze` 和 backend Goal contract tests。
- [ ] 在真机验证登录后 Today→Goals→Calendar→Library→Session→Device→Inbox 主链。
- [ ] 按 411px 与窄屏分别截 Light/Dark 基线。
- [ ] 更新 handoff：实际文件映射、已实现状态、仍延期范围。
- [ ] 下一稳定版本移除 rollback define 和 legacy token imports。
- [ ] Commit: `refactor(theme-v2): make redesigned experience the default`

---

## Release Acceptance Gate

- [ ] Theme V2 全部页面使用单一 Light/Dark 组件树。
- [ ] 不存在业务页面直接硬编码 Pen 的 Light/Dark 色值。
- [ ] 所有交互 hit target ≥44×44。
- [ ] Home layer、Calendar sticky rail/inline draft、Library schema detail、Session keyboard、Goal deterministic progress、Device error states、Inbox outcome 都有自动化测试。
- [ ] 411px、360px、landscape、2.0 text scale 无关键 overflow。
- [ ] reduced motion 下不存在依赖动画才能完成的交互。
- [ ] 长中文、空、加载、错误、retry 状态闭环。
- [ ] Goal 首页摘要与 Goal Detail 使用同一后端计算结果。
- [ ] Asset 的 `effectiveAt` 与 `createdAt` 不再混用。
- [ ] Theme 切换不重置导航、输入、session stream、device scan 或 Home layer。
- [ ] 现有登录、timeline、assets、events、contacts、device、ring、chat regressions 全部通过。
