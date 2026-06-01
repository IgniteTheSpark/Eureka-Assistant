# Eureka · Design System

> ⚠️ **ADDENDUM (Phase B v1.3, 2026-05-24)**:§7.1 `source` 字段语义已更新。
> 原文写 `source = flash | chat | meeting`(等同 session_type);新模型把
> `source` 重定义为**输入模态** `voice | typed | imported`,跟 session_type
> 正交。这让混合模态会话成为可能(flash session 内可以有 typed turn 做
> CRUD 跟进,例:语音建完待办后打字「改成 4 点」)。SessionTurnCard、
> Schedule 视图等视觉语言不受影响。
> 详见 [phase-b-architecture-blueprint.md §三.4](phase-b-architecture-blueprint.md)。

> Version 0.2 — 2026-05-24
> Selected direction: **B · Atmosphere**
> Configuration: [`tokens/eureka-tokens-b.json`](tokens/eureka-tokens-b.json) · [`tokens/tokens.css`](tokens/tokens.css) · [`index.html`](index.html) (design canvas)
> Archived alternatives: [`tokens/eureka-tokens-a.json`](tokens/eureka-tokens-a.json) (Slate), [`tokens/eureka-tokens-c.json`](tokens/eureka-tokens-c.json) (Lab)

---

## 一、品牌定位

Eureka 是个人 AI 助手。视觉气质：

> 「一个私人 AI 正在为我工作 — 沉静、有秩序、值得信任。」

落点是 **Quiet Tech with depth and pulse**。
不喧闹，但有大气层；克制，但有脉搏。AI 像在房间里跟你呼吸。

**通吃两个人群 — 一套视觉**
- 知识沉淀型（学生 / 创作者 / 白领）
- 商务型（商务 / 老板）
- 差异只在「呈现模式开关」（资产为主 / 日历为主），视觉系统不分叉

---

## 二、视觉语言（B · Atmosphere）

| 维度 | 决策 |
|---|---|
| **背景** | `#0b1220` + 两层径向渐变（蓝紫光晕，左上和右下） |
| **表面** | 半透明白色叠加：2.5% / 4.5% / 7% 三层 |
| **品牌色** | `#6f9eff` 深海蓝 + glow（box-shadow: `0 0 24px rgba(111,158,255,0.35)`） |
| **字体** | Manrope（body）+ JetBrains Mono（数字 / 时间 / 标签）+ Noto Sans SC（中文） |
| **圆角** | 8 / 12 / 16 / 24（softer than Slate） |
| **密度** | Airy — 多呼吸 |
| **运动** | fast 150ms · normal 280ms · slow 420ms · stagger card 60ms / token 30ms |

### 2.1 关键视觉惯例

- **辉光** — 品牌色和强调色配 box-shadow 形成 glow，但**不滥用**：只用在 user 气泡、品牌 dot、FAB、选中态
- **径向渐变背景** — 整页底层有渐变，让纯黑界面有"大气层"
- **mono 一切数字** — 时间、货币、id、caps 标签都走 JetBrains Mono + 0.16-0.22em 字距
- **glass 表面** — 卡片半透明白叠加，配 backdrop-blur，让层次有空气

---

## 三、Design Tokens

详细数值见 [`tokens/eureka-tokens-b.json`](tokens/eureka-tokens-b.json)。要点：

### 3.1 中性

| Token | 值 |
|---|---|
| `bg` | `#0b1220` (+ 径向渐变层) |
| `surface` / `raised` / `hover` | rgba(255,255,255, 0.025 / 0.045 / 0.07) |
| `border` / `border.strong` | rgba(255,255,255, 0.07 / 0.14) |
| `text.hi` | `#f4f7fb` |
| `text` | `#d4dbe6` |
| `text.mid` | `#9aa6b8` |
| `text.lo` | `#6c7689` |
| `text.muted` | `#4a5364` |

### 3.2 7 个 accent 语义槽

| Token | 角色 | solid | bg (10% tint) | glow |
|---|---|---|---|---|
| `accent.blue` | 默认 · todo | `#6f9eff` | `rgba(138,180,255,0.10)` | `rgba(111,158,255,0.35)` |
| `accent.amber` | idea · reminder | `#e5b35a` | `rgba(245,201,119,0.10)` | `rgba(245,201,119,0.30)` |
| `accent.green` | expense · positive | `#5fc685` | `rgba(134,224,165,0.10)` | `rgba(134,224,165,0.30)` |
| `accent.red` | urgent · overdue | `#ec6a83` | `rgba(255,141,161,0.10)` | `rgba(255,141,161,0.30)` |
| `accent.purple` | event · calendar | `#9c80f0` | `rgba(196,168,255,0.10)` | `rgba(196,168,255,0.30)` |
| `accent.gray` | secondary | `#7c8898` | `rgba(154,166,184,0.08)` | — |
| `accent.neutral` | no semantic · contact | `#9aa6b8` | `rgba(212,219,230,0.05)` | — |

**每个 accent 有 5 个变体**：`fg` / `bg` (tint) / `edge` (ring) / `solid` (实色) / `glow` (用于 box-shadow)。

> Phase B 的 `render_spec.accent_color` enum 直接用这 7 个 key。

### 3.3 字体

```
Manrope          400 / 500 / 600 / 700  · body / heading
JetBrains Mono   400 / 500 / 600 / 700  · numerals / labels / time
Noto Sans SC     300 / 400 / 500 / 600 / 700  · 中文兜底
```

**Scale**: 11 / 12 / 14 / 15 / 17 / 22 / 26 / 34 / 52

**Mono 使用约定** — 全套通用：
- 所有 **数字 / 时间 / 货币 / hash / id** 用 mono
- 所有 **caps 标签**（TODAY / OVERDUE / TOOL_CALL / SCHEDULE / EVENT）用 mono + 0.16-0.22em 字距 + 600 weight

### 3.4 间距 / 圆角 / 阴影

```
spacing  4 · 8 · 12 · 16 · 24 · 32 · 48 · 64
radius   sm 8 · md 12 · lg 16 · xl 24 · full 9999
shadow   sm soft drop · md atmospheric · lg deep · glow brand-aura
```

### 3.5 运动

```
duration  fast 150ms · normal 280ms · slow 420ms
easing    in-out cubic-bezier(.2,.7,.3,1)
stagger   card 60ms · token 30ms
```

**节奏要点**
- 一轮 agent 输出的资产卡片以 60ms 间隔 stagger 浮入（fade + 8px y）
- 流式 token 每 30ms 出现一个，光标 1s blink
- 模式切换（资产为主 ↔ 日历为主）用 280ms slide + crossfade
- 日历视图切换（schedule → month → year）用 280ms slide + scale 0.96→1.0

---

## 四、组件视觉规范

### 4.1 SkillCard — 最重要

**统一渲染器** — 所有 skill 走同一个 `<SkillCard spec={render_spec} payload={asset.payload} />`。

**4 种 layout**

| Layout | 用途 | 视觉 |
|---|---|---|
| `horizontal` | todo / event / expense / contact | accent.bg (10%) + accent.edge + icon block 带 inset glow |
| `stacked` | idea / note | 同上，标题在顶 + 多行内容 |
| `inline` | 时间流密集场景 | 单行紧凑，accent.bg + 极小 padding |
| `compact` | 日历格子内 chip | accent.bg + accent.edge + 圆点 dot + glow |

**固定结构**（render_spec 控制，不能改）
- `icon`（emoji 或预定义符号集 `☑ ● ◇ ¥ ◯ ! ·`）
- `accent` 应用（fg / bg / edge / solid / glow）
- `primary_field`、`secondary_field`、`meta_fields[]`、`actions[]`

**状态**
- default · hover（box-shadow 6-8px glow 浮起，280ms） · selected（边线变 solid + 弱 glow） · overdue（primary 文字变 red.fg）

### 4.2 Chat 消息

| 元素 | 处理 |
|---|---|
| User 气泡 | linear-gradient brand → 偏冷 → 白字 + box-shadow glow + 18px radius |
| Agent 文字 | 无气泡，纯文本，正文色 |
| 流式光标 | 7×14 圆角矩形 + brand box-shadow + 1s blink |
| Tool call 指示 | pill 胶囊：`绿点 + create_asset · event`，绿点带 glow |
| 内嵌 SkillCard | horizontal 紧凑变体，max-width 380 |
| 沉淀按钮 | amber.bg + amber.edge + 全圆 pill + 「＋ 沉淀为想法」 |

### 4.3 闪念捕捉

- 录音中：呼吸 dot（brand 实心 + 周围 pulse ring 2s 周期）
- 转录文本：跟 user 气泡区分 — 半透明 + 虚线 dashed border，标 `TRANSCRIPT`
- 转录完成：资产卡片以 60ms stagger 飘入（fade + 8px y + scale 0.96→1）

### 4.4 时间流（已并入日历 Schedule）

时间流不再是独立页面 —— 它的功能被 **Calendar Schedule 视图**吸收：

- 同样的「类型筛选 tab」（全部 / 事件 / 待办 / 想法 / 记账 / 名片）放在 Schedule 顶部
- Schedule 默认按日期纵向滚动，相当于带颜色的时间流
- 切换筛选时，瓦片内只显示对应类型的资产；空日仍保留，但瓦片只渲染该类型的项
- 「呈现模式开关」（资产为主 / 日历为主）只决定 home 落到哪个 tab，不再切换页面架构

### 4.5 输入区（composer）

- 单行框 16px padding + 14px radius + surface.raised + 微 inner highlight
- 麦克风按钮 34×34 + 10 radius + surface 表面
- 发送按钮 34×34 + 10 radius + brand 填充 + glow

### 4.6 FAB（全局闪念入口）

- 56×56 圆形 + `linear-gradient(135deg, brand, accent.purple.solid)`
- box-shadow: `0 8px 28px rgba(111,158,255,0.45), 0 0 0 1px rgba(255,255,255,0.08)`
- 持续微 pulse glow 2s 周期
- 位置：底部 tab bar 上方右侧 18px

### 4.7 Add Skill Wizard（魔法时刻）

- 多步流程：描述 → AI 流式产出 → 用户微调 → 确认
- design agent 流式输出时，左侧字段一条条出现（stagger 80ms），右侧 preview 实时刷新
- accent 选择器固定 7 个槽位，每个一颗带 glow 的圆点
- 确认时整张卡片 fade + scale 飞向资产库（280ms）

---

## 五、日历交互规范（Timepage-inspired）

日历是 5 个状态之间的滑动 — **颜色和滑动方向是唯一的导航**。

### 5.1 状态机

```
SCHEDULE (默认)
   ├─ swipe → MONTH ─ swipe → YEAR
   │            │              │
   │            └─ tap month ──┘
   │
   ├─ tap day → DAY DETAIL
   │              │
   │              └─ tap + or event → EVENT EDITOR
   │
   └─ tap + (FAB) → EVENT EDITOR
```

过渡：所有 280ms slide（水平为右滑，垂直为下滑 + 缩放 0.96→1.0），用 `--eu-ease-in-out`。

### 5.2 SCHEDULE — 默认 · 纵向时间流（合并版）

**核心隐喻**：一天 = 一块**有颜色**的瓦片。颜色即信号 —— 用户一眼能扫到「哪天忙、哪天空」。
这是 Eureka 的 home —— 它同时承担了**日历**和**时间流**两个角色。

- **顶栏**：左侧月份大字 + 年份 mono；右侧搜索 / 更多。
- **类型筛选 tab**（关键 — 不再是独立时间流页面）：
  `全部 · 事件 · 待办 · 想法 · 记账 · 名片`
  - 横向可滚 pill tabs
  - 每个 tab 前有该类型的 accent 圆点 + glow
  - 计数用 mono 后缀
  - 切「全部」= 完整 Schedule；切某类型 = 该类型在时间轴上的呈现
- **布局**：左侧 64px 日期 rail + 右侧瓦片流。纵向无限滚动（虚拟列表）。
- **日期 rail**：
  - 每天：上方 weekday cap (mono) + 下方 date number（Manrope 500/700）
  - **今天**：右侧 2px brand 竖线 + glow，日期数字变 `#a4c2ff` 带 text-shadow
- **瓦片高度** = 该日资产数：
  - 0 项：50px（仅显示「空闲」斜体小字）
  - 1 项：82px
  - 2 项：~112px
  - 3+ 项：~136px+
- **瓦片背景** — 根据当日资产计算"日色"：
  - 仅 event：紫色渐变 `linear-gradient(135deg, rgba(156,128,240,0.42), rgba(120,98,200,0.22)) over #18143a`
  - 仅 todo/expense：蓝色渐变 `linear-gradient(135deg, rgba(111,158,255,0.34), rgba(82,128,200,0.18)) over #131a35`
  - event + todo 混合：紫蓝混合
  - 仅 idea：琥珀色渐变（低强度）
  - 空：纯 `#0e1426`
- **瓦片内每项**：mono 时间 + 带 glow 的圆点（颜色 = accent） + 标题（白字）
- **特殊标签**：TODAY / TOMORROW 在右上角 mono caps
- **FAB**：右下角 56×56 圆，brand → purple 渐变 + 持续 pulse

### 5.3 MONTH — 月视图 · 圆点格 + 选中日摘要

- **顶部**：左侧 3×3 brand 像素 logo + 大字 `5月`（Manrope 700, 36px, brand 色 + text-shadow glow），下方 mono `2026`
- **Weekday header**：S/M/T/W/T/F/S mono caps + 0.16em 字距
- **日格**：每天一颗圆点（32×32），无事件日仅显示数字
  - 有 event：紫色 tint 圆 + 紫色 ring 边
  - 有 todo（但无 event）：蓝色 tint 圆 + 蓝色 ring 边
  - mixed：稍深的紫色 tint
  - **今天**：白色实心圆 + 大 glow，数字反色 `#1a1735`
  - **选中**：白色 1.5px 边 ring + 紫色 tint 内填
- **右边缘**：3px 宽彩色条带 —— 由 6 种 accent 拼接（gesture affordance：暗示可右滑出月份）
- **选中日摘要**（屏幕下半）：
  - mono 日期（`5月 26 日 · 周一`）
  - caps brand 标 `2 件事`
  - 事件列表（mono 时间 + 圆点 + 标题）
  - 末尾 mono `+ 添加事件`

### 5.4 YEAR — 年视图 · 12 个迷你日历

- **顶部**：`2026` 极大字（56px, Manrope 700, brand glow）+ 下方 mono caps `YEAR · 47 EVENTS`
- **12 月**：3 列 × 4 行排布，每月一块
  - 月名 caps Manrope 700
  - 6 行 × 7 列日期网格（mono, 8.5px）
  - 有事件日：紫色 + 加粗
  - **今日所在月**：紫色 tint 背景 + 紫色 ring，月名变 `#a4c2ff` + glow
  - **今天**：白色实心圆 + 数字反色
- **点击一个月** → 切到 month 视图，月份名 + 高亮日期联动

### 5.5 DAY DETAIL — 当日详情 · 全屏铺色

- **背景**：渐变铺色 `linear-gradient(180deg, #3d2f7a 0%, #2a1f5a 100%)`（紫色为 event 主导色；其它日按主导 accent 推导）
- **氛围光**：右上 + 左下两团径向 glow
- **顶部 bar**：左 `‹` 返回（圆形玻璃按钮）+ 中间日期块（大字 `周一` 0.20em 字距 + 下方 mono caps `MAY 26`）+ 右 `+` 添加
- **内容分组**（按 Eureka 资产模型，非 Timepage 原样）：
  - `事件` — 有时间的 event-skill 资产
  - `待办` — 当日截止的 todo-skill 资产
  - `今日捕捉` — 没有时间锚点但当天创建的资产（idea / expense / contact）。这是 Eureka 区别于 Timepage 的关键 —— 我们的资产类型比单纯的日程多。后续可扩展更多 skill。
  - `来源` — 当日的闪念录音文件
- **资产卡**：玻璃 (rgba(255,255,255,0.10) + backdrop-blur)；header 用左上角 mini-icon + caps mono 标签（EVENT / TODO / IDEA / EXPENSE …）；主体按 SkillCard render_spec。有来源的卡在末尾带一个极小的 source chip：`♪ 闪念 · 14:32 →`。点入才打开资产详情看完整来源。

### 5.6 EVENT EDITOR — 事件编辑器

- **上半**（64% 高度）：colored panel
  - 渐变背景：`linear-gradient(155deg, #4a3a8f, #2a1f6a)` + 右上角光晕
  - 右上 mono caps EVENT（类别标签，紫色 = event）
  - 标题大字 + 闪烁光标
  - 副位置（"会议室 B"）
  - 中部居中：日期块（`周一` + mono `MAY 26`）
  - 时间范围：`10:00 → 11:00` 大字 mono
  - 时间 scrub bar：48 格刻度 + 选中段高亮（可拖拽改时长）
  - 模式 tabs：`SET TIME / ALL DAY / MULTI-DAY` mono caps + 激活下划线
- **下半**：工具栏（5 个图标按钮，包括关闭 / 备注 / 位置 / 联系人 / **link to skill**）+ 最近事件列表（用作 quick-pick）
- **键盘**起来时，下半被遮挡只剩工具栏

### 5.7 模式切换（PresentationMode）

「呈现模式开关」位于设置/侧边栏：
- **资产为主**：home → 时间流；日历仍可达
- **日历为主**：home → Schedule view
- 切换时整页 280ms slide + crossfade，不硬切

---

## 六、资产库子系统

资产库是「资产为主」模式的 home。不是一个扣扣筛选的平顺列表，而是**主视图 + 各类型入口**的架构。

### 6.1 资产库 Hub（主视图）

- 顶部：「资产库」大字 + 总计数 caps mono
- **类型碑 grid**（3 × 2）：每个类型一块磁贴
  - 上行：accent 色图标方块（带 glow）+ 该类型总数（大字 mono）
  - 下行：类型名 + 最近一个项目预览
  - 点击 → 该类型的完整列表页
- **必须包含 6 个类型**：待办 / 事件 / 想法 / 记账 / 名片 / **文件**。后二者在之前被遗漏了 —— contact 只在筛选里，file 完全没有入口。
- 下方：**最近**分区 — 跨类型的最新 4-6 个资产

### 6.2 资产类型列表（类型入口点入后的页）

以**想法**为代表设计了一张；其它类型同样模式。

- 顶部：返回 · 当前路径面包屑 (mono)
- Hero：该类型的 accent icon 方块 + 大字名称 + 总数
- 排序按钮（默认按时间）
- 列表：sticky 日期分组 + accent.bg 卡片，有来源带右上角 `♪` 小图标

### 6.3 文件视图（重要）

文件不是严格意义上的 SkillCard，但在资产库里作为一个类型出现 —— 需要可浏览来回追「这个闪念是哪天那个录音里说的」。

- 列表项：flash / meeting 两种颜色（青色 / 紫色）
- 每项显示：kind caps + duration mono + ASR 状态（ `· N 资产` 或 `· ASR 转录中`）
- 主行：filename mono
- 右侧：创建时间 mono

---

## 七、来源模型 — Session as the unit of provenance

资产的来源**一定是一个 session 里的某个 input turn**，不是裸文件。这是 Eureka 独特的数据模型。

### 7.1 Session 的四种类型

| Session 类型 | input | output | 是否有关联 file |
|---|---|---|---|
| `flash` | 语音 → 转录 turn | assets | 是 — .m4a |
| `chat` | 用户文字 / 语音 输入 turn | agent 回复 + assets | 可选 |
| `meeting` | 会议录音 → 转录 segment | assets | 是 — .m4a |
| `manual` | 无（用户直接创建） | asset | 否 |

会议录音也是一种 `session` —— 只是它的 input 是 transcript（不是用户输入的对话），output 是 assets。这让「从资产追溯」的路径在所有产生方式上均一。

### 7.2 Asset Detail 里的「来源」块 = SessionTurnCard

不是 FileCard。包含：

- **顶部**：session 图标 + `SESSION · FLASH` caps + 时间 + session 标题 + 跳入箭头
- **Input Turn**（中部 — 重点）：
  - 左侧 2px 蓝色竖线 strip（表示"这句"）
  - mono caps `INPUT TURN · 产生当前资产`
  - 斜体引用 transcript中产生该资产的那句话。 可以高亮精确到句子级别。
- **Sibling assets**：同一 session 还创建了其它什么资产（小同胞列表）
- **Indirect file pointer**（底部极小）：文件名 mono + 时长 + 外链箭头。如果没有文件（手动创建或 pure chat）则不显示这一行。

### 7.3 资产列表里的来源表示

- 列表中**不**显示完整来源。只在有来源的卡上加一个 `♪` 11px 小图标作为指示。
- 哪里看完整来源：点入卡片详情页（§5.5 Day Detail 中某项 → Asset Detail）

### 7.4 数据模型

```typescript
type Session = {
  id: SessionId
  type: 'flash' | 'chat' | 'meeting' | 'manual'
  created_at: timestamp
  title?: string                  // 可由 agent 推导
  input_turns: InputTurn[]
  output_asset_ids: AssetId[]
  file_id?: FileId                // flash / meeting 有，chat / manual 可能没有
}

type InputTurn = {
  id: TurnId
  session_id: SessionId
  index: number                   // 第几轮
  text: string                    // 转录文本或用户输入
  timestamp: timestamp
  source_file_id?: FileId
  source_file_offset?: number     // ms in audio
}

// Asset 代取原有的 source_transcript_id 字段：
type Asset = {
  // ...
  source: {
    session_id: SessionId
    input_turn_id?: TurnId        // 不存在 = 手动创建
  }
}
```

### 7.5 为什么这么设

- **统一来源描述语义**：闪念 / chat / 会议 都是 session，不需要在 UI 上为每种资产生产方式写单独逻辑
- **可追到语义精确位置**：input_turn 是句子级错记，不是「这是录音里某个时间点」粗糙的表达
- **同伴资产**：Session 是 assets 的容器 — 从一个 asset 能看到同样从这个 session 里出来的其它资产（闪念里说了三件事，看其中一件可以跟踪到另两件）
- **文件仍可达**：file_id 在 Session 上，资产详情在 SessionTurnCard 底部间接闪过，点入 session 详情可以看到完整文件和所有 turns

---

## 八、Render Spec 与设计的对应

```typescript
type RenderSpec = {
  card_layout: 'horizontal' | 'stacked' | 'inline' | 'compact'
  icon: string
  accent_color: 'blue' | 'amber' | 'green' | 'red' | 'purple' | 'gray' | 'neutral'
  primary_field: string
  primary_format?: 'text' | 'relative_date' | 'absolute_date' | 'time' | 'currency' | 'duration' | 'badge' | 'truncate_40'
  secondary_field?: string
  secondary_format?: FieldFormat
  meta_fields?: Array<{field: string, format?: FieldFormat, label?: string}>
  actions?: Array<'check' | 'edit' | 'delete' | 'open'>
  timeline_position?: {time_field?: string, fallback: 'created_at'}
  calendar_render?: {date_field: string, time_field?: string}
}
```

**对应到设计**
- `card_layout` → 4 种 layout（4.1）
- `accent_color` → 7 个槽位 token（3.2）
- `icon` → 优先预定义符号集，emoji 兜底
- `primary_format=currency` → mono 大字号
- `secondary_format=relative_date` → mono + text.mid
- `calendar_render` → 决定该 skill 是否上日历 + 用哪个时间字段。
  - 有 `calendar_render` → Schedule 瓦片显示 + Day Detail 进入有时间分组
  - 无 `calendar_render` 但有 `created_at` → 进入 Day Detail 的「今日捕捉」分组（如 idea / contact）

**关于资产容器的可扩展性**

Timepage 的容器固化为「事件 + 待办」。Eureka 不这样：Day Detail 的分组列表由 `calendar_render` 字段动态推导，新加 skill = 配置 `calendar_render`，无需改前端。当前 demo 阶段只配 event + todo + idea + expense + contact，未来可以加入任何带时间或日期的新 skill。

---

## 九、Light Mode（未来）

Tokens 文件中已为 brand 留了 `light` 值（如 `brand: #2a4d8f` 用于亮模式）。
本轮交付暗色为主，亮模式作为 v1.1 单独迭代。亮模式遵循同样的辉光哲学，但用更深的纯色 + 浅米白纸面。

---

## 十、交付物清单

| 文件 | 用途 |
|---|---|
| `DESIGN.md` | 本文档 |
| `tokens/eureka-tokens-b.json` | Atmosphere · 机器可读 tokens（**选定方向**） |
| `tokens/tokens.css` | CSS variables（B 为默认；含 atmosphere/lab 主题类备查） |
| `index.html` | Design canvas — Foundations + AI 对话 + 时间流 + SkillCard + 完整日历系统 |
| `tokens/eureka-tokens-a.json` | Slate · 存档 |
| `tokens/eureka-tokens-c.json` | Lab · 存档 |

---

## 十一、Phase D 输入（前端）

1. `tokens.css` 直接进项目，作为全局 CSS variables 源
2. `SkillCard.tsx` 按 §4.1 的 4 种 layout × accent.bg 渲染
3. `CalendarPage.tsx` 实现 5 个状态：
   - 默认 SCHEDULE，左右滑切换 MONTH/YEAR，垂直 IntersectionObserver 触发无限滚
   - Day Detail / Event Editor 用 sheet 上拉模式或全屏 push
4. `ChatPage.tsx` 按 §4.2 实现，token 流式间隔 30ms，资产卡片 stagger 60ms 浮入
5. 模式切换（资产为主 / 日历为主）写在 `usePresentationMode()` hook（决定 #7），用 localStorage 持久化
