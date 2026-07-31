# UReka Theme V2 — Today Coding Handoff

> 日期：2026-07-31
> 状态：**READY FOR IMPLEMENTATION · Today 单域产品真值**
> 设计源：`redesignureka.pen`
> 实现画布 Section：`PYuZt` —
> `Section / Theme V2 / 40 Today / Implementation Source`
> 基准设备：`411 × 960`

---

## 1. Coding Agent 读取规则

1. Today / Home 只读取本文件以及画布 Section `PYuZt`。
2. Goal 已完全退出当前产品和实现范围，不得实现、预留、注册或请求 Goal。
3. `N0ehb`、`SuznI`、`BNmyJ` 及其他 Goal 画板属于
   `ARCHIVE · DO NOT IMPLEMENT`，不得作为视觉或交互参考。
4. Light / Dark 使用同一组件树，仅通过 Theme V2 tokens 切换。
5. 当前 Home 只露出 Today。内部可以保留通用双层容器，但
   `secondaryLayer = null`，不可见、不可交互且不占布局空间。
6. 不得因为普通用户内容包含“目标”二字而删除内容。例如 Todo
   `更新个人目标` 是合法用户数据。
7. 本文件未定义的 Today 行为必须列为 gap，不得自行恢复旧 Goal 逻辑。

优先级：

1. `PYuZt` 内白名单节点
2. 本 handoff
3. Theme V2 shared tokens / components
4. 旧设计与历史文档

---

## 2. 实现范围与白名单

| 页面 / 状态 | Light | Dark |
|---|---:|---:|
| Today / Default | `WsOyv` | `PMCdg` |
| Today / Agenda / Fishbone | `vRy65` | `J5cpE` |
| Home interaction contract | `VvGFs` | shared spec |

本次实现包含：

- Today 默认态
- Agenda / Fishbone 展开态
- Today 数据加载、刷新、空态与错误态
- Reka Queue 中非 Goal 内容
- Asset bubble field / generated-asset chamber
- Agenda 展开与收起
- Theme V2 Home 与 Floating Dock 的集成
- Goal 入口、交互和数据依赖的彻底移除

本次不包含：

- Goal 列表、详情、创建、调整、结算或历史
- Home 第二层的新内容
- Calendar、Library、Asset、Session 的内部页面重构
- 新增 Goal feature flag、占位页或 Coming Soon

---

## 3. 当前 Home 架构

Home 保留一个通用层容器，但当前只有主层：

```dart
enum HomeSurface { today }

class HomeLayerState {
  const HomeLayerState({
    this.primary = HomeSurface.today,
    this.secondary,
  });

  final HomeSurface primary;
  final HomeSurface? secondary;
}

const currentHomeLayers = HomeLayerState(
  primary: HomeSurface.today,
  secondary: null,
);
```

当 `secondary == null`：

- 只渲染 Today。
- 不渲染背板、露出页头、数量、箭头、切换器或占位内容。
- 不保留第二层的可见空间。
- 不注册横向切层手势。
- 不保留透明 hit target。
- 不向无障碍树暴露第二层。
- 历史状态若请求第二层，直接归一为 Today。

未来恢复双层 Home 必须由新的产品决策定义第二层内容，不属于本 handoff。

---

## 4. 页面 Shell 与基准几何

### 4.1 411 × 960 基准

| 区域 | Bounds | 说明 |
|---|---|---|
| Status Bar | `x=0, y=0, w=411, h=44` | 系统区域 |
| Today Panel | `x=8, y=54, w=395, h=790` | Default 与 Agenda 共用 |
| Floating Dock | `x=121, y=865, w=169, h=60` | 固定，不参与滚动 |

Today Panel 底部为 `y=844`，与 Dock 之间保持 21 px 视觉间距。

Flutter shell 建议：

```dart
const ThemeV2PageScaffold(
  body: ThemeV2HomePage(),
  showTopNav: false,
)
```

- Home 不显示额外 Global Top Nav。
- Status Bar 与 Floating Dock 保留。
- Panel 在 SafeArea 顶部之后偏移 10 px，即全屏 `y=44+10=54`。
- Dock 固定在 viewport，不进入 Today Panel 的滚动树。

### 4.2 响应式约束

- `width >= 411`：Panel 使用 395 px 宽度并水平居中。
- `width < 411`：左右各保留 8 px，Panel 宽度为 `viewportWidth - 16`。
- Panel 顶部始终为 top safe area 后 10 px。
- 可用高度不足 790 px 时，Panel 高度收缩到 Dock 安全区以上。
- 不因更宽屏幕引入桌面双栏或重新露出第二层。

---

## 5. Theme V2 Tokens

使用语义 token，不在 Light / Dark 分叉组件结构。

| Token | Light | Dark | 用途 |
|---|---:|---:|---|
| `theme-v2/bg` | `#F7F9FC` | `#0B0D12` | 页面背景 |
| `theme-v2/surface` | `#FFFFFF` | `#121620` | Today Panel |
| `theme-v2/fg` | `#101319` | `#F3F5FA` | 主文字 |
| `theme-v2/muted` | `#6D7480` | `#8991A0` | 次级信息 |
| `theme-v2/border` | `#D9E0E8` | `#29303D` | 边框与分隔 |
| `theme-v2/accent` | `#25B6D6` | `#8A82FF` | 当前状态与主操作 |
| `theme-v2/accent-soft` | `#E9F8FC` | `#1A1D35` | 弱强调面 |

```text
font-primary: Geist
font-mono: Geist Mono
spacing: 4 / 8 / 12 / 16 / 24
panel-radius: 18
minimum-touch-target: 44 × 44
motion-fast: 160ms
motion-standard: 260ms
motion-fluid: 420ms
ease-fluid: cubic-bezier(0.22,1,0.36,1)
```

---

## 6. Today Default

### 6.1 内容顺序

Today Panel 内部从上到下：

1. 今日标题与本地化日期摘要
2. Next Moment
3. Reka Queue
4. Asset bubble field
5. Agenda 展开入口

Goal 头部移除后，Panel 从旧位置 `y=104, h=740` 提升为
`y=54, h=790`。内容随 Panel 上移，新增空间优先提供给 Asset bubble
field，不在顶部留下空槽。

### 6.2 Next Moment

- 使用现有 Today 数据中的下一个有效时间节点。
- 有内容时显示时间、标题与必要的类型信息。
- 无下一个节点时使用当前标准空态，不回退到 Goal 建议。
- 点击行为沿用对应 Calendar / Asset 的既有目的地。
- 长标题单行截断，使用省略号，不改变区域高度。

### 6.3 Reka Queue

仅展示当前仍受支持的队列项。

必须过滤：

- Goal progress
- Goal settlement
- Goal deadline
- Goal check-in
- Goal adjustment
- Goal suggestion
- Goal creation CTA

规则：

- 数量基于过滤后的队列重新计算。
- Goal 是唯一队列项时，展示普通非 Goal 空态。
- 不展示“目标功能已移除”等解释文案。
- 不保留 Goal 空槽或占位骨架。
- 普通 Todo 或 Asset 的用户文本即使包含“目标”也必须保留。

### 6.4 Asset bubble field

- 继续使用现有 Today Asset 数据与交互。
- Bubble 可以利用新增的 50 px 垂直空间。
- 不改变 Bubble 的业务目的地。
- 数据为空时保持区域结构稳定，并显示安静空态。
- 内容过多时仅在区域内部滚动或按现有聚合规则展示，不推动 Floating Dock。

---

## 7. Agenda / Fishbone

Agenda 与 Default 使用相同 Panel：

```text
x=8, y=54, w=395, h=790
```

内部结构：

1. Agenda 标题
2. 44 × 44 收起入口
3. 可伸展 Fishbone / Agenda viewport
4. 固定高度的 generated-asset chamber

规则：

- 回收的 50 px 全部增加到 Agenda viewport。
- generated-asset chamber 仍贴近 Panel 底部。
- 不把整个底部 chamber 随 Panel 顶部一起上移。
- Agenda 内容可以垂直滚动。
- Agenda 展开 / 收起保留。
- Home 跨层横向滑动被移除。
- Agenda 内部若存在横向内容手势，不得被误识别为 Home 层切换。

---

## 8. 状态与数据生命周期

Today 复用现有 `TodayData` / `loadToday(ApiClient)`，通过可测试 repository
适配器接入，不新增 Goal 数据源。

建议接口：

```dart
abstract interface class ThemeV2HomeRepository {
  Future<TodayData> load();
}
```

状态：

| 状态 | 展示 | 行为 |
|---|---|---|
| Initial loading | Theme V2 loading state | 不展示旧数据 |
| Loaded / Default | Today Default | 可展开 Agenda |
| Loaded / Agenda | Agenda / Fishbone | 可收起 |
| Refreshing | 保留旧数据 | 后台刷新，不闪回 skeleton |
| Initial error | Theme V2 error state | 提供重试 |
| Refresh error | 保留旧数据并轻量反馈 | 不清空页面 |
| Empty | 标准 Today 空态 | 不创建 Goal 替代内容 |

生命周期：

- 页面首次进入时加载 Today 数据。
- `dataRevision` 变化时重新加载。
- `IndexedStack` 切换 Calendar / Library 后返回 Home，保留当前
  Default / Agenda 状态和滚动位置。
- 页面销毁时，仅释放由页面自身创建的 controller / repository。
- 注入对象的生命周期由注入方负责。
- 不发起任何 Goal 请求。

---

## 9. 交互与 Motion

| 元素 | 触发 | 结果 | Motion |
|---|---|---|---|
| Agenda 展开入口 | Tap | Default → Agenda | 260 ms standard |
| Agenda 收起入口 | Tap | Agenda → Default | 260 ms standard |
| Today 内容项 | Tap | 进入既有详情目的地 | 160 ms pressed feedback |
| Asset bubble | Tap | 进入对应 Asset | 沿用 Asset 交互 |
| Home 横向拖动 | Drag | 不切换层 | 无响应 |
| 原 Goal header 区域 | Tap / Drag | 无动作 | 不存在 hit target |

Agenda 转场：

- Panel 外框位置与尺寸不变。
- 内部内容交叉淡化并轻微纵向位移。
- 不使用 3D 翻页、背板露出或 Goal 页推进效果。
- Reduce Motion 下取消位移，仅保留短淡化或立即切换。

---

## 10. Navigation 与 Goal 移除

当前实现不得注册或露出：

- Goal list / All Goals
- Goal history
- Goal creation / success
- Goal detail
- Goal adjustment
- Goal progress / guardrail
- Goal notification destination

移除 Goal 入口的范围：

- Home
- Library
- Asset detail
- Skill detail
- Session result
- Notification
- Global navigation

兼容行为：

- 历史 Goal deep link 统一返回 Home / Today。
- 不展示错误页、半成品 Goal 页或 Coming Soon。
- 本地缓存若记录 Home 第二层为选中态，启动时归一为 Today。
- 后端若意外返回 Goal-derived queue item，在渲染前过滤。

当前代码库没有正式 Goal model、repository、service、API、cache、job 或数据库迁移；
不要为了“移除”而创建兼容抽象。

---

## 11. 组件边界

建议文件结构：

```text
mobile/lib/theme_v2/home/
  home_layer_state.dart
  home_controller.dart
  home_repository.dart
  theme_v2_home_page.dart
  home_today_panel.dart
  home_agenda_panel.dart
```

建议组件：

| Component | 责任 |
|---|---|
| `ThemeV2HomePage` | 数据生命周期、Panel 定位、Default / Agenda 切换 |
| `HomeLayerState` | 通用 primary / nullable secondary 架构 |
| `ThemeV2HomeController` | Default / Agenda presentation |
| `HomeTodayPanel` | Today 默认内容 |
| `HomeAgendaPanel` | Agenda / Fishbone |
| `ThemeV2HomeRepository` | `TodayData` 可测试适配层 |

不要把 Theme V2 Home 改动混入 legacy
`mobile/lib/pages/today_page.dart`；旧 shell 继续使用 legacy 页面。

Theme V2 shell 的 tab 0 改为挂载 `ThemeV2HomePage`。

---

## 12. Content 约束与边界情况

- 日期必须走 locale formatter，不硬编码英文日期。
- 主标题单行展示，超长使用省略号。
- 次级摘要最多两行，超长使用省略号。
- 动态字体增大时允许内容区内部增高或滚动，不裁掉操作入口。
- 队列数量为 0 时显示标准空态，不隐藏整个 Panel。
- 100+ queue / asset items 不得一次性创建无限高度页面。
- 慢网络下保持 loading / refreshing 状态明确。
- 缺失可选字段时隐藏该字段，不显示 `null`、`--` 或空标签。
- 无下一事件、无队列、无 Asset 可以同时成立，页面仍需有稳定 Today 标题与结构。

---

## 13. Accessibility

- Today 是 Home 唯一可访问路由。
- Focus order 从 Today 标题开始，随后按视觉顺序遍历内容与 Agenda 入口。
- Agenda 展开入口使用 `打开日程` 或等价本地化 label。
- Agenda 收起入口使用 `收起日程`，并暴露 expanded / collapsed 状态。
- 最小触控面积 44 × 44。
- 不向语义树注册 Goal、第二层或透明切换区域。
- 过滤 Goal 队列项后，重新计算 `listPosition` / `listLength`。
- 动态字体与屏幕阅读器开启时，不依赖手势作为唯一操作方式。

---

## 14. 测试与验收

### 14.1 Widget tests

- Home 当前 `primary == today`。
- `secondary == null` 且 `hasSecondary == false`。
- Default 可以打开 Agenda，Agenda 可以收起。
- 切换不创建第二层。
- 411 × 960 下 Panel 为 `Offset(8,54)` 和 `Size(395,790)`。
- Home 不显示 Global Top Nav。
- Floating Dock 保留。
- 横向拖动不切换 Home。
- 原 Goal 区域没有可点击元素。
- Goal-derived queue item 被过滤。
- 普通用户内容 `更新个人目标` 保留。
- initial loading、refresh、empty、initial error、retry 均可达。
- Calendar → Home 返回后保留 Home 状态。

### 14.2 Golden tests

固定 411 × 960：

- Light Today Default
- Dark Today Default
- Light Today Agenda
- Dark Today Agenda

每张 Golden 验证：

- Panel 顶部 `y=54`
- Panel 高度 `790`
- Panel 底部 `y=844`
- Dock 位置不变
- 无 Goal header / count / arrow / switch
- Agenda generated-asset chamber 靠近 Panel 底部
- Light / Dark 几何完全一致

### 14.3 Domain absence

生产代码中不得新增：

```text
GoalRepository
GoalRoute
GoalService
GoalApi
GoalCache
GoalNotification
GoalAnalytics
```

---

## 15. 验收清单

- [ ] Theme V2 Home 仅展示 Today。
- [ ] 第二层为 `null`，不可见、不可交互且不占空间。
- [ ] Default 与 Agenda 使用 `x=8, y=54, w=395, h=790`。
- [ ] Floating Dock 保持 `x=121, y=865, w=169, h=60`。
- [ ] 不显示额外 Global Top Nav。
- [ ] Goal header、数量、箭头、切换器、手势与 edge reveal 全部移除。
- [ ] Reka Queue 不展示任何 Goal-derived item。
- [ ] 普通用户内容中包含“目标”的文本不受影响。
- [ ] Agenda 展开 / 收起正常。
- [ ] Agenda bottom chamber 保持底部对齐。
- [ ] Loading、refreshing、empty、error、retry 状态完整。
- [ ] 历史 Goal deep link 返回 Home / Today。
- [ ] Goal 画布和文档仅作为 Archive，不进入实现白名单。
- [ ] Light / Dark 使用同一组件树。
- [ ] Widget、Golden 与完整 Theme V2 regression tests 通过。

---

## 16. 关联文档

- 设计决策：
  `docs/superpowers/specs/2026-07-31-remove-goals-home-adjustment-design.md`
- 逐任务实施计划：
  `docs/superpowers/plans/2026-07-31-remove-goals-home-adjustment.md`
- 全局 Theme V2：
  `theme-v2-coding-handoff.md`
- Calendar：
  `theme-v2-calendar-handoff.md`
- Library + Assets：
  `theme-v2-library-assets-handoff.md`

若关联文档与本文件的 Today / Home 当前范围冲突，以本文件为准。
