# UReka Theme V2 — Calendar Coding Handoff

> 日期：2026-07-29  
> 状态：**READY FOR IMPLEMENTATION · Calendar 单域产品真值**  
> 设计源：`redesignureka.pen`  
> 实现画布 Section：`qIbQZ` — `Section / Theme V2 / 20 Calendar / Implementation Source`  
> 基准设备：`411 × 960`

---

## 1. Coding Agent 读取规则

1. Calendar 只读取本文件白名单以及画布 Section `qIbQZ`。
2. 旧 Flow `dWO0c` / `YAu8U`、`UReka · Screen / Calendar / ...`、探索稿和缓存截图不得实现。
3. Light / Dark 使用同一组件树，仅通过 Theme V2 tokens 切换。
4. 画布节点名称不渲染成 breadcrumbs；App 内没有 web 式路径导航。
5. 页面 `context` 与本文件描述业务行为；视觉值读取 Theme V2 tokens 和对应白名单画板。
6. 未在本文件定义的 Calendar 行为必须列为 gap，不得自行补产品规则。

---

## 2. 实现白名单

| Node ID | 页面 / 状态 |
|---|---|
| `BeBq4` / `J3XydT` | Flow / Sticky Date Rail / Resting |
| `vjW39` / `n0Eup4` | Flow / 下一日期进入 sticky threshold |
| `qeGVP` / `KesOZ` | Flow / 垂直滚动 / 距离 Today 超过一周 |
| `zQK41` / `nMTbd` | Month / Progressive Time |
| `a6SVbz` / `M0i6f` | Year / Progressive Time |
| `K1Z2iN` / `fHRmV` | Day Detail / populated |
| `OncEM` / `anKiT` | Day Detail / Asset empty |
| `XbCxS` / `IugNo` | Schedule Grid / default |
| `V9LoFM` / `sc1bQ` | Schedule Grid / same-time Todo expanded |
| `J20Phd` / `sGk5M` | Schedule Grid / inline draft |
| `LEtWx` / `T1IwgQ` | Manual Record Skill Picker / bottom sheet |

Section `qIbQZ` 直接收纳上述原始节点，不是交付副本。工程引用使用本表 Node ID；Section
内从上到下依次为 Flow、Month / Year、Day Detail、Schedule、Manual Record。

交互实现参考：

- `IYjMj`：Flow ↔ Month ↔ Year 横向视图切换契约。
- `xjEYu`：Flow 内纵向日期滚动、水印与“回到今天”契约。

---

## 3. Theme 与页面 Shell

### 3.1 Tokens

| Token | Light | Dark | 用途 |
|---|---:|---:|---|
| `theme-v2/bg` | `#F7F9FC` | `#0B0D12` | 页面背景 |
| `theme-v2/surface` | `#FFFFFF` | `#121620` | 容器、卡片 |
| `theme-v2/fg` | `#101319` | `#F3F5FA` | 主文字 |
| `theme-v2/muted` | `#6D7480` | `#8991A0` | 次级文字 |
| `theme-v2/border` | `#D9E0E8` | `#29303D` | 边框、分隔线 |
| `theme-v2/accent` | `#25B6D6` | `#8A82FF` | 主操作、选中态 |
| `theme-v2/accent-soft` | `#E9F8FC` | `#1A1D35` | 弱强调面 |
| `theme-v2/watermark` | `#10131909` | `#FFFFFF09` | 时间距离水印 |

```text
font-primary: Geist
font-mono: Geist Mono
space: 4 / 8 / 12 / 16 / 24
radius: 7 / 10 / 14 / pill
minimum-touch-target: 44 × 44
motion-fast: 160ms
motion-standard: 260ms
motion-fluid: 420ms
ease-fluid: cubic-bezier(0.22,1,0.36,1)
```

### 3.2 Floating Dock

- 固定于 viewport，基准尺寸 `169 × 60`，基准位置 `x=121, y=875`。
- 不参与页面滚动。
- Flow / Month / Year 一级表面保留 Dock，并为其预留视觉间距和 bottom safe area。
- Day Detail 与 Schedule 属于 Calendar 二级表面，隐藏 Dock，并在页面顶部提供明确返回。
- 全屏 Edit、modal、键盘态同样隐藏 Dock。

Calendar 一级页面标题使用共享 `ThemeV2PageTitle`，标题文字底部与 Flow / Month / Year
内容 viewport 顶部保持至少 `12px` 留白；三个尺度共享这一标题间距。

---

## 4. Flow / Sticky Date Rail

### 4.1 布局

411 基准：

| 区域 | Bounds |
|---|---|
| 当前 Sticky Date Rail | `x=14, y=62, w=54` |
| Rail Divider | `x=66, y=62, w=1` |
| 右侧滚动内容 | `x=84, y=56, w=309, h=760` |
| 下一日期 Rail | `x=14, y=642, w=54` |

- 左侧日期 rail 与右侧时间流是两个独立层级。
- 日期与 Flash count 必须一起 sticky，并被下一日期整体推走。
- 不允许把 Flash 数量做成独立悬浮层。

### 4.2 日期点击

- 点击有内容日期的日期标签：进入对应 Day Detail。
- 点击有内容日期内容区域的空白处：进入对应 Day Detail。
- 不显示“再次点击日期进入日详情”等 hint。

### 4.3 空日

空日必须出现在 Flow 中。

```text
点击空日日期或空白区域
→ 显示“手动记录”确认入口
→ 点击“手动记录”
→ 打开 Manual Record Skill Picker
→ 传入被点击日期 effective_date
```

- 确认入口本身不创建 Asset。
- 删除“点击空白处快速创建资产”等教学性 hint。

### 4.4 Asset rows

- 时间排序使用既有 `effective_time`：

```text
effective_time
= occurred_at
?? Skill timeline anchor
?? created_at
```

- 未指定时间的记录不另建“未安排”分组；使用安静分隔线维持顺序。

---

## 5. 自然语言时间水印

禁止 `+1 DAY`、`-1 DAY`、`+03` 等数学标记。

水印仅属于 **Flow 的纵向滚动反馈**：

- 只在用户拖动 Flow 或 Flow 惯性减速期间显示。
- Flow 停稳后隐藏；Resting、Month、Year、Day Detail 和 Schedule 均不显示。
- 计算基准 `center_date` 是当前 viewport 水平中线穿过的日期区块。
- 中线恰好位于两个日期区块边界时，选择中线两侧可见面积更大的日期；面积相同则选择当前滚动方向即将进入的日期。
- 水印与页面顶部 sticky 日期无关，也不使用列表第一条或最后一条日期。

按用户当地日历日期计算，不按持续小时数：

| 日期距离 | 水印 |
|---|---|
| 当天 | `TODAY` |
| 相邻 1–6 天 | `1 DAY AGO/LATER`、`N DAYS AGO/LATER` |
| 7–29 天 | `1 WEEK AGO/LATER`、`N WEEKS AGO/LATER` |
| 跨自然月 | `1 MONTH AGO/LATER`、`N MONTHS AGO/LATER` |
| 跨自然年 | `1 YEAR AGO/LATER`、`N YEARS AGO/LATER` |

- 使用最大稳定日历单位。
- 单复数必须正确。
- 当前画板使用英文大写；工程必须走 locale formatter。
- 水印是低对比背景信息，不抢夺日期和 Asset 的层级。

### 5.1 回到今天

- 只在 Flow 中出现。
- 当 `abs(calendarDayDiff(center_date, today)) >= 7` 时显示；小于 7 天立即隐藏。
- 采用 viewport 固定定位，411 基准为 `119 × 40`，水平居中并位于 Floating Dock 上方。
- 按钮不随 Flow 内容移动，也不占据日期列表布局空间。
- 点击后保持 Flow 尺度，将 Today 日期区块滚动到 viewport 中部。
- 回程滚动期间，水印继续依据实时 `center_date` 更新；到达 Today 后按钮消失。
- 回程进行中按钮不可重复触发；用户主动触摸 Flow 可中断回程并重新按当前位置计算状态。
- Reduce Motion 下使用短距离或无动画定位到 Today，不使用弹性过冲。

---

## 6. Month / Year Progressive Time

- Flow / Month / Year 是同一 Calendar 一级目的地的三个尺度。
- 横向手势跟手切换，完成后吸附到目标尺度。
- Month 和 Year 使用 Progressive Time 方案，不恢复旧版 Calendar Flow。
- 选中日期的 Progressive Day Summary 展示该日真实 Asset。
- 同一时间带中的项目仍按时间顺序排列。
- 点击选中日期进入 Day Detail，不显示重复点击 hint。

---

## 7. Day Detail

Day Detail 顶部先显示 `返回日历`，实际点击区域至少 `44 × 44`。这是返回 Calendar
overview 的主路径，不得只依赖 Android back 或 iOS 侧滑。日期标题和既有操作位于返回行
下方。

### 7.1 Populated layout

411 Light 基准：

| 区域 | Bounds |
|---|---|
| 日期标题 | `x=18, y=76` |
| 手动记录 | `x=211, y=78, w=98, h=34` |
| 日程 | `x=317, y=78, w=76, h=34` |
| Flash count entry | `x=18, y=129, w=375, h=44` |
| 日内时间轴 | `x=18, y=193, w=2, h=616` |
| 时间带内容 | `x=34, y=193, w=343` |

- 上午、下午、晚上、没说时间按真实数据出现。
- 手动记录与日程是独立操作，不互相替代。

### 7.2 Flash count

显示：

```text
闪念 N                                      >
```

行为：

- 点击进入当前日期 Flash Session。
- `create = false`。
- 不创建 Flash、Asset 或输入会话。
- 不显示“今天记一笔”。
- `N = 0` 时仍显示 `闪念 0` 并可进入空 Flash Session。

### 7.3 手动记录

```text
点击“手动记录”
→ 打开 Manual Record Skill Picker
→ 传入当前 Day Detail 日期
```

入口必须有至少 `44 × 44` 的实际点击区域；视觉按钮可保持画板尺寸，通过透明 hit slop
补足。

### 7.4 Asset empty

空态只判断 Asset：

```text
asset_count == 0
→ 显示 Asset empty
```

与 `flash_count` 独立。验收 fixture：

```yaml
asset_count: 0
flash_count: 5
```

仍保留：

- 日期头部。
- `日程`。
- `手动记录`。
- `闪念 5`。
- 顶部 `返回日历`。

内容区只显示：

```text
今天还没有记录
[手动记录]
```

不显示教程、解释或“从闪念开始”等 hint。

---

## 8. Manual Record Skill Picker

### 8.1 Presentation

- 移动端 bottom sheet，不使用居中 modal。
- 基准 sheet：`x=0, y=330, w=411, h=630`。
- scrim：从 status bar 下方覆盖至页面底部，带 `8px` backdrop blur。
- sheet 顶部圆角 `24px`，底部适配 safe area。
- Picker 阶段不自动打开键盘。
- 背景页面不可滚动、不可误触。

### 8.2 内容

```text
手动记录                                  [关闭]
选择要记录的 Skill

常用
[Skill] [Skill]
[Skill] [Skill]

全部 Skills
[内部纵向滚动的两列 Skill tiles]
```

- 同时读取系统默认 Skill 和用户自定义 Skill。
- 每个 tile 显示 Skill `display_name`。
- 两列结构；长名称单行省略，完整名称提供无障碍标签。
- Skill 数量增加时只滚动 `全部 Skills` 区域，sheet 高度不增长。
- `常用` 来源为产品既有排序；首版没有数据时可显示最近使用，不能由 LLM 临时排序。

### 8.3 选择行为

```text
输入：
effective_date
+ user_skill_id

点击 Skill
→ 关闭 Picker
→ 打开对应 Skill 的 Asset Edit
→ Edit 预填 effective_date
→ 用户保存后才创建 Asset
```

- Picker 本身绝不创建 Asset。
- 用户关闭 Picker 后不保留半成品。
- Skill 已 deprecated 时不展示。
- Skill 列表加载失败时保留 sheet，显示重试；不得进入空白页。

---

## 9. Schedule

Schedule 顶部先显示 `返回每日详情`，实际点击区域至少 `44 × 44`。点击后返回同一日期的
Day Detail；系统级返回遵循相同层级。Schedule 不显示 Floating Dock。

Schedule 的业务记录只接受 Event 与 Todo。其他定时 Asset 不进入 Hour Grid。每个已排期
Todo 在自己的 block 内显示 `HH:mm`，不依赖左侧时间轴推断；Todo 不展示独立 status 文案，
checkbox / 删除线就是完成状态。

### 9.1 统一头部

Default、Todo Expanded、Inline Draft 的 Light/Dark 使用完全相同的结构：

| 区域 | Bounds |
|---|---|
| 全天日程 | `x=18, y=130, w=375, h=54` |
| 未排期代办 | `x=18, y=192, w=375, h=92` |
| Hour Grid | `x=18, y=294, w=375, h=566` |

固定文案：

- `全天日程 · N`
- `未排期代办 · N`

标题和计数采用统一结构。

### 9.2 全天日程

- `N` 是当天全天事件总数，不是当前可见数。
- `N = 0` 时隐藏整个区域。
- `N > 0` 时标题和计数始终可见。

### 9.3 未排期代办

- 0 条：隐藏区域。
- 1–3 条：按真实数量展示。
- 超过 3 条：保持 `92px` 高度，内部纵向滚动。
- 内部滚动不得推动 Hour Grid。
- 内部滚动不得抢夺 Calendar scale 的横向手势。

### 9.4 同时间事项

同时间的不同事项必须是独立并列 block。

验收案例：

```text
小型讨论会
培训
3 个代办
```

必须显示为三个分割 block，不覆盖、不合并、不收敛成一张摘要卡。

### 9.5 Inline Draft

- 点击空白时间创建对应时段的 inline draft。
- Draft 显示明确起止时间，例如 `16:00–16:30`。
- 不显示“再次点击进入编辑”等 hint。
- Draft 不是已保存 Asset，确认前不得进入已保存记录状态。

---

## 10. Gesture 与 Motion

`IYjMj` 只定义 Calendar 尺度之间的横向切换；它不描述 Flow 内的日期浏览。
Flow 内纵向滚动由 `xjEYu` 单独定义。两个方向同时存在时，先根据手势意图锁定轴向：

- 明确纵向意图：Flow 日期列表滚动，不触发尺度切换。
- 明确横向意图：Flow ↔ Month ↔ Year 跟手切换。
- 轴向锁定后，本次手势结束前不得切换到另一轴。

| 元素 | 触发 | 动画 | 时长 |
|---|---|---|---:|
| Flow / Month / Year | 横向拖动 | 跟手位移并吸附 | `motion-fluid` |
| Flow 日期列表 | 纵向拖动 | 原生跟手滚动；滚动中显示中部日期距离水印 | 平台滚动物理 |
| Flow 水印 | 纵向拖动或惯性滚动 | 低对比淡入；停稳后淡出 | `motion-fast` |
| 回到今天 | `abs(day distance) >= 7` | 固定于 Dock 上方淡入 | `motion-fast` |
| 回到今天 | 点击 | Today 滚动至 viewport 中部 | `motion-fluid` |
| Sticky rail | 下一日期进入阈值 | 上一 rail 被整体推走 | `motion-standard` |
| Skill Picker | 打开 | scrim 渐入，sheet 自底部进入 | `motion-standard` |
| Skill Picker | 关闭 | sheet 下移，scrim 渐出 | `motion-fast` |
| Inline Draft | 点击空白时段 | 在目标时间格内展开 | `motion-standard` |

Reduce Motion：

- 禁止弹性过冲。
- scale swipe 可改为短距离淡入/淡出。
- “回到今天”使用短距离或无动画定位。
- sheet 仍需明确出现/消失，但使用简单位移与透明度。

---

## 11. Loading、Error 与边界

### 11.1 Calendar 数据

- Loading：保留日期 rail、页面标题和 Dock；内容区使用稳定 skeleton。
- Error：保留当前尺度和日期，显示重试，不自动跳到 Today。
- Refresh：不得丢失当前尺度、滚动位置或选中日期。

### 11.2 长文案

- Asset 主标题最多两行；Schedule block 空间不足时单行省略。
- Skill Picker tile 单行省略。
- 日期与数量不得因长标题被挤出。
- 中文、英文和混合数字必须使用同一布局规则。

### 11.3 时区与补录

- 自然日、月、年和水印都使用用户时区。
- 补录 Asset 按 `effective_time` 进入实际日期，不按创建时间进入今天。
- 夏令时变化不得造成同一 Asset 出现在两个自然日。

---

## 12. Accessibility

- 所有点击区域至少 `44 × 44`。
- Flash count 的无障碍名称：`7月3日，5 条闪念，查看闪念`。
- Skill tile 的无障碍名称：`手动记录：{Skill display_name}`。
- Schedule 同时间 block 按时间、从左到右进入焦点顺序。
- Picker 打开时焦点进入标题或关闭按钮；关闭后返回触发入口。
- Sheet 打开时背景内容对读屏隐藏。
- 内部滚动区域提供“全部 Skills”分区名称和可滚动状态。
- 颜色不是唯一状态表达；选中日期同时使用形态、描边或文字。

---

## 13. 路由与数据契约

```yaml
calendar_view_state:
  scale: flow | month | year | schedule
  selected_date: local_date
  timezone: iana_timezone

flow_scroll_state:
  center_date: local_date
  phase: idle | dragging | decelerating | returning_to_today
  day_distance_from_today: integer
  show_watermark: boolean
  show_return_today: boolean

day_detail:
  date: local_date
  asset_count: integer
  flash_count: integer
  assets: AssetSummary[]

manual_record_picker:
  effective_date: local_date
  system_skills: UserSkillSummary[]
  user_skills: UserSkillSummary[]

UserSkillSummary:
  user_skill_id: string
  display_name: string
  deprecated: boolean
```

路由：

```text
Flow populated day → Day Detail
Flow empty day → Manual Record confirmation → Skill Picker
Day Detail → Manual Record → Skill Picker
Skill Picker → Asset Edit(user_skill_id, effective_date)
Day Detail Flash count → Flash Session(date)
Day Detail Schedule → Schedule(date)
```

---

## 14. Acceptance Checklist

- [ ] 只实现白名单 Calendar 页面；旧 Flow 不存在于路由或代码。
- [ ] Light / Dark 使用同一组件树。
- [ ] Dock 固定且不遮挡内容。
- [ ] Flow 只有 Sticky Date Rail 方案。
- [ ] 日期与 Flash count 同步 sticky。
- [ ] 水印使用自然语言日历距离，不存在数学 `+N/-N` 标记。
- [ ] 水印只在 Flow 纵向拖动或惯性滚动时显示，停稳及其他视图不显示。
- [ ] 水印距离使用 viewport 中部日期计算，不使用 sticky 日期或列表首尾日期。
- [ ] 距离 Today 至少 7 个自然日时显示“回到今天”，小于 7 天隐藏。
- [ ] “回到今天”固定在 Dock 上方；点击后 Today 居中，按钮消失。
- [ ] 横向尺度切换与 Flow 纵向滚动完成轴向意图锁定，不互相误触。
- [ ] 空日保留，并走“手动记录 → Skill Picker”。
- [ ] Day Detail Flash 只显示数量并进入 Flash Session。
- [ ] 无 Asset、有 Flash 时仍显示 Asset empty。
- [ ] Manual Record Picker 同时包含系统与自定义 Skill，内部滚动。
- [ ] Picker 不创建 Asset，选择后进入对应 Asset Edit。
- [ ] 三种 Schedule 状态的顶部容器尺寸、位置和文案完全一致。
- [ ] 未排期代办最多可见 3 条，超出后只滚动内部。
- [ ] 小型讨论会、培训、3 个代办是三个独立 block。
- [ ] Calendar 中不存在“今天记一笔”“再次点击”“点击空白时间”等教学性 hint。
- [ ] 所有点击区域至少 `44 × 44`，并完成读屏焦点验收。
- [ ] 截图回归覆盖所有白名单状态的 `411px` Light / Dark。

---

## 15. Coding Agent Prompt

```text
请只实现 UReka Theme V2 Calendar。

设计源：
- redesignureka.pen
- Implementation Source Section：qIbQZ
- 单域 handoff：theme-v2-calendar-handoff.md

只实现 handoff §2 白名单。禁止实现旧 Flow dWO0c / YAu8U，也禁止读取
UReka · Screen、Exploration 或历史截图作为视觉真值。

优先完成：
1. Calendar shell、tokens 与 Floating Dock inset；
2. Sticky Date Rail Flow、滚动期自然语言水印与“回到今天”；
3. Progressive Month / Year；
4. Day Detail populated / Asset empty；
5. Schedule default / Todo Expanded / Inline Draft；
6. Manual Record Skill Picker 与路由。

所有业务规则、尺寸、状态、边界和验收以 theme-v2-calendar-handoff.md 为准。
横向视图切换参考 IYjMj；Flow 纵向滚动反馈参考 xjEYu。
设计未定义的行为请列为 gap，不要自行发明。
```
