# 05 · 设计系统（Design System）

> 本章是「视觉契约」。前端所有颜色、字体、间距、圆角、动效都从一组 `--eu-*` CSS
> 变量（design token）推导。**组件里几乎不写裸 hex / px**，而是消费 token。Flutter 版
> 必须把这套 token 1:1 搬成一个 `ThemeData` / 常量表，否则两端视觉一定漂移。
>
> 三个文件构成设计系统的全部真相：
> - `frontend/src/styles/tokens.css` — token 定义，**按主题 class 分组**（4 套主题）。
> - `frontend/src/styles/globals.css` — base reset + keyframe 动画 + safe-area 工具类。
> - `frontend/tailwind.config.ts` — 把 `--eu-*` 桥接成 Tailwind 工具类（`bg-eu-surface` 等）。

---

## 5.0 架构：token → 主题 class → 工具类

```
tokens.css  :root { --eu-* }            ← 默认主题 = "Slate"
            .theme-atmosphere { --eu-* } ← 覆盖子集
            .theme-lab { --eu-* }
            .theme-light { --eu-* }
                    │
                    │  (CSS 变量按 <html class> 切换)
                    ▼
tailwind.config.ts  colors["eu-surface"] = "var(--eu-surface)"
                    fontSize["eu-lg"]    = "var(--eu-fs-lg)"
                    ...
                    │
                    ▼
组件          className="bg-eu-surface text-eu-lg rounded-eu-md"
```

三条铁律：

1. **主题切换 = 换 `<html>` 上的 class**，不改组件。`.theme-atmosphere` / `.theme-lab` /
   `.theme-light` 各自重定义一部分 `--eu-*`；没被重定义的继承 `:root`（Slate）。
2. **`darkMode: ["class", ".theme-atmosphere"]`**（tailwind.config.ts:17）：Tailwind 的
   `dark:` 前缀在 `.theme-atmosphere` 下生效。MVP 实际只用到 atmosphere(暗) / light(亮) 两套，
   `ThemeContext` 只 toggle 这两者（见 §4.9）。`.theme-lab` 与默认 Slate 是设计预留，组件不主动切。
3. **组件不读裸值**。要新增一个 token：① 在 tokens.css 加 `--eu-x`；② 在 tailwind.config.ts
   映射 `"eu-x": "var(--eu-x)"`；③ 组件用 `eu-x`。Flutter 端等价：① 加常量；② 加 ThemeExtension 字段；③ 用它。

---

## 5.1 默认主题 :root —— "Slate"

`:root` 是 fallback 基线，所有其它主题在它之上做差量覆盖。Flutter 应以此为 base ThemeData。

### 字体族

| token | 值 |
|---|---|
| `--eu-font-sans` | `"IBM Plex Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif` |
| `--eu-font-mono` | `"IBM Plex Mono", "SF Mono", Menlo, monospace` |
| `--eu-font-display` | = `--eu-font-sans`（默认不分离） |

### 字号阶梯（`--eu-fs-*`）

| token | px | 典型用途 |
|---|---|---|
| `--eu-fs-xs` | 11 | caption / 角标 / 时间戳 |
| `--eu-fs-sm` | 13 | meta 字段、次要文字 |
| `--eu-fs-base` | 15 | 正文默认（body 基准） |
| `--eu-fs-md` | 17 | 卡片主字段、列表标题 |
| `--eu-fs-lg` | 20 | 区块标题 |
| `--eu-fs-xl` | 26 | 页面 H2 |
| `--eu-fs-2xl` | 32 | 页面 H1 |
| `--eu-fs-3xl` | 38 | 大数字 / 空状态主标 |
| `--eu-fs-4xl` | 44 | hero |

### 字重 / 行高 / 字距

| token | 值 |
|---|---|
| `--eu-fw-regular` | 400 |
| `--eu-fw-medium` | 500 |
| `--eu-fw-semibold` | 600 |
| `--eu-lh-tight` | 1.3（标题） |
| `--eu-lh-body` | 1.5（正文） |
| `--eu-lh-loose` | 1.65（长文阅读） |
| `--eu-ls-caps` | 0.18em（全大写 caption 字距） |
| `--eu-ls-body` | 0（正文不加字距） |

> `--eu-ls-caps 0.18em` 是「分区小标题」（如 Library 的 `常驻` / `启用的技能`）的标志性外观：
> 全大写 + 宽字距 + `--eu-fs-xs`。Flutter 务必复刻 letterSpacing。

### 颜色 —— ink 模型

Slate 用一个 **ink RGB 基色** + 透明度派生文字层级，这样切到 light 主题时只翻转 `--eu-ink`
即可整体反相。

| token | 值 | 含义 |
|---|---|---|
| `--eu-ink` | `255, 255, 255` | 文字基色（RGB 三元组，给 rgba() 用） |
| `--eu-text` | `rgba(var(--eu-ink), 0.82)` | 正文 |
| `--eu-text-hi` | `#e6edf3`（≈ ink 0.95） | 高强调标题 |
| `--eu-text-mid` | `rgba(var(--eu-ink), 0.66)` | 次要 |
| `--eu-text-lo` | `rgba(var(--eu-ink), 0.48)` | 弱 |
| `--eu-text-muted` | `rgba(var(--eu-ink), 0.34)` | 最弱 / 占位 |

表面与描边：

| token | 值 |
|---|---|
| `--eu-bg` | `#0d1117`（页面底） |
| `--eu-surface` | `#161b22`（卡片） |
| `--eu-surface-raised` | `#1c2128`（浮起：sheet / 下拉） |
| `--eu-surface-hover` | `rgba(var(--eu-ink), 0.04)` |
| `--eu-border` | `rgba(var(--eu-ink), 0.08)` |
| `--eu-border-strong` | `rgba(var(--eu-ink), 0.14)` |
| `--eu-rule` | `rgba(var(--eu-ink), 0.06)`（分隔线） |

品牌色（蓝）：

| token | 值 |
|---|---|
| `--eu-brand` | `#5b8def` |
| `--eu-brand-hi` | `#7ba8f5`（hover/亮） |
| `--eu-brand-faint` | `rgba(91, 141, 239, 0.14)`（选区/填充底） |
| `--eu-brand-line` | `rgba(91, 141, 239, 0.4)` |
| `--eu-brand-glow` | `rgba(91, 141, 239, 0.25)`（聆听光晕） |

状态色：`--eu-success`、`--eu-warning`、`--eu-error`、`--eu-info`（语义同名，值见 tokens.css；
组件多数走下方 accent 调色板而非这些）。

### Accent 调色板 —— **render_spec 的颜色来源**

`render_spec.accent_color` 取以下 key 之一，前端映射到「同名 accent 四元组」。这是
SkillCard 通用渲染**唯一的颜色分支来源**（不存在 if-type-equals）。

8 个 slot：`blue / amber / green / red / purple / gray / neutral / cyan`。
每个 slot 4 个变量：

| 后缀 | 用途 |
|---|---|
| `-bg` | 卡片/badge 填充底（低透明） |
| `-edge` | 描边 |
| `-fg` | 文字/图标前景色 |
| `-solid` | 实心强调（进度条、圆点） |

例（blue）：`--eu-accent-blue-bg`、`--eu-accent-blue-edge`、`--eu-accent-blue-fg`、
`--eu-accent-blue-solid`。其余 slot 同构。

> **注意 tailwind.config.ts 只桥接了 7 个 accent**（blue/purple/amber/green/red/gray/neutral），
> **漏了 `cyan`**。tokens.css 里 cyan 四元组存在，但没有 `eu-accent-cyan-*` 工具类。
> 若 render_spec 用 `accent_color:"cyan"`，前端 buildCard 的 ACCENT map（见 §4.7）需自行兜底——
> 实测兜底到 neutral。**Flutter 端建议把 cyan 也补全**，避免同样的洞。

### 间距 / 圆角 / 阴影 / 动效基线

| 类别 | token → 值 |
|---|---|
| 间距 | `--eu-sp-xs 4` / `sm 8` / `md 12` / `lg 16` / `xl 24` / `2xl 32` / `3xl 48` / `4xl 64`（px） |
| 圆角 | `--eu-r-sm 4` / `md 6` / `lg 10` / `xl 14` / `full 9999`（px） |
| 阴影 | `--eu-shadow-sm/md/lg`（值见 tokens.css，逐级加深） |
| 时长 | `--eu-dur-fast 150ms` / `normal 250ms` / `slow 400ms` |
| 缓动 | `--eu-ease-in-out: cubic-bezier(.2,.7,.3,1)`（另有 in/out） |
| 交错 | `--eu-stagger-card 60ms`（卡片逐个入场）/ `--eu-stagger-token 32ms`（流式 token） |

`--eu-stagger-card 60ms` 与 `--eu-stagger-token 32ms` 是「列表卡片逐个浮现」「SSE 文本逐
token 浮现」的节奏常量，是 Eureka「有生命感」观感的一部分，Flutter 应复刻。

---

## 5.2 主题差量

下表只列**相对 :root 被覆盖**的 token。未列出的继承 Slate。

### `.theme-atmosphere`（暗 · 实际主用暗色主题）

| token | 值 | 相对 Slate |
|---|---|---|
| `--eu-font-sans` | `"Manrope", …` | 换字体 |
| `--eu-font-mono` | `"JetBrains Mono", …` | 换等宽 |
| `--eu-bg` | `#0b1220` | 更深、偏蓝 |
| `--eu-surface` | `rgba(255,255,255,0.03)` | 半透明白（玻璃感） |
| `--eu-surface-raised` | `rgba(255,255,255,0.06)` | |
| `--eu-rule` | `rgba(255,255,255,0.06)` | |
| `--eu-brand` | `#6f9eff` | 更亮 |
| accent `-fg` 全系 | 提亮（blue `#8ab4ff` 等） | 暗底上更跳 |
| 圆角 | sm8 / md12 / lg16 / xl24 | **整体更圆** |
| 时长 | fast150 / normal280 / slow420 | 略慢、更顺 |

> atmosphere 是 demo 默认呈现的「氛围感暗色」：Manrope + JetBrains Mono、半透明玻璃表面、
> 更大圆角、更亮强调。**这是用户实际看到的样子**，Flutter 默认主题应对标 atmosphere，
> 不是 :root Slate。

### `.theme-lab`（暗 · 锐利，设计预留）

| token | 值 |
|---|---|
| `--eu-bg` | `#0a0c10`（最深） |
| 圆角 | sm2 / md4 / lg8 / xl12（**最锐**） |
| 时长 | fast120 / normal240 / slow400（最快） |

工程/技术感变体，组件不主动切，留作风格开关。

### `.theme-light`（亮 · 暖纸）

| token | 值 | 说明 |
|---|---|---|
| `--eu-font-sans` | `"Manrope", …` | 同 atmosphere |
| `--eu-ink` | `26, 24, 16` | **翻转为深墨**——文字层级随之整体反相 |
| `--eu-bg` | `#f4f2ec` | 暖纸底 |
| `--eu-surface` | （暖白，见 tokens.css） | |
| `--eu-surface-raised` | `#fbfaf6` | |
| accent `-fg` 全系 | 加深（blue `#2f63d6` 等） | 亮底上保证对比 |
| `--eu-brand` | `#3f6fe0` | 加深 |
| 阴影 | 暖色柔和 | |
| 圆角 | sm8 / md12 / lg16 / xl24 | 同 atmosphere |

> light 的精髓是 **`--eu-ink` 翻转**：因为文字色都是 `rgba(var(--eu-ink), α)` 派生，
> 只要把 ink 从 `255,255,255` 改成 `26,24,16`，整套文字层级（text/hi/mid/lo/muted）
> 自动从「白上透明」变「墨上透明」，无需逐条改。**Flutter 复刻时务必用同样的 ink-derived
> 体系**，否则 light/dark 两套要各维护一份文字色，极易漂移。

---

## 5.3 keyframe 动画（globals.css）

全部定义在 globals.css，挂成 `.eu-*` 工具类。Flutter 用 `AnimationController` + 对应曲线复刻。

| keyframe / class | 时长 · 缓动 | 行为 | 用在 |
|---|---|---|---|
| `eu-sheet-up` / `.eu-sheet-up` | 280ms · `cubic-bezier(.2,.7,.3,1)` | `translateY(100%)→0` | 底部 sheet 升起（AssetDetailDrawer、各 modal） |
| `eu-sheet-left` / `.eu-sheet-left` | 280ms · 同上 | `translateX(-100%)→0` | 侧入面板 |
| `eu-sheet-down` / `.eu-sheet-down` | 240ms · 同上 | `translateY(-16px)+fade` | **Toast 从顶部落入** |
| `eu-fade-in` / `.eu-fade-in` | 200ms · `ease-out` | `opacity 0→1` | 背板/遮罩淡入 |
| `eu-wiggle` / `.eu-wiggle` | 220ms · `ease-in-out` · **infinite** | `rotate ±0.9deg` 微抖 | Library SKILLS 编辑态（iOS 抖动删除） |
| `eu-eq` | — · infinite | `scaleY 0.35↔1` | 「正在聆听」语音均衡条（多条错相） |
| `eu-breathe` | — · infinite | `scale 0.92↔1.12` + opacity | 聆听光球呼吸（Siri 式） |

无障碍：`@media (prefers-reduced-motion: reduce)` 下 sheet/fade/wiggle 全部 `animation:none`。
**Flutter 必须同样尊重系统「减弱动态效果」**（`MediaQuery.disableAnimations` / accessibleNavigation）。

> 动效语义约定：**sheet 从屏幕边缘进、toast 从顶边落、遮罩淡入**。这套方向语言要在
> Flutter 端保持一致，否则同一交互观感会变。

---

## 5.4 base reset 与 safe-area（globals.css）

迁移时易漏的全局规则：

- `html, body, #root { min-height: 100dvh }`：用 **dvh**（动态视口高度），适配移动端地址栏伸缩。
  Flutter 天然全屏，等价为根布局占满。
- `::selection`：背景 `--eu-brand-faint`、文字 `--eu-text-hi`。
- `button,[role=button]`：`-webkit-tap-highlight-color:transparent` + `touch-action:manipulation`
  （去点击高亮、禁双击缩放）。Flutter 用 `InkWell`/自定义 splash 控制。
- **键盘焦点环**：`:where(...):focus-visible { outline: 2px solid var(--eu-brand); offset 2px }`。
  用 `:where()` 保持 specificity 0，组件可覆盖。只对键盘导航（非鼠标点击）显示。
- **safe-area 工具类**：`.pt-safe/.pb-safe/.pl-safe/.pr-safe` = `env(safe-area-inset-*)`，
  适配刘海/底部 home 指示条。Flutter 用 `SafeArea` / `MediaQuery.padding`。
- **`.eu-noscroll`**：跨浏览器隐藏滚动条（保留滚动功能）。用于日历滑动 deck 接缝。
  Flutter 用 `ScrollConfiguration` 去掉滚动条。

---

## 5.5 Flutter 迁移检查表（设计系统部分）

1. **以 atmosphere 为默认主题**，不是 :root Slate——用户实际看的是 atmosphere（Manrope +
   JetBrains Mono + 半透明玻璃表面 + 大圆角 + 亮强调）。
2. **文字色走 ink-derived 体系**：定义一个 ink RGB，文字层级全部用 `ink.withOpacity(α)`
   派生（0.95/0.82/0.66/0.48/0.34）。light 主题只翻 ink 为 `26,24,16`。
3. **把 4 套主题做成 ThemeExtension**（或 4 个常量表）：Slate / atmosphere / lab / light，
   差量覆盖见 §5.2。MVP 至少实现 atmosphere + light，且 ThemeContext 只 toggle 这两者。
4. **accent 调色板 8 slot × 4 变量**全部搬过去，**并补齐 cyan**（web 端 tailwind 漏映射，别照抄漏洞）。
   render_spec 的 `accent_color` 经此 map 取色，是卡片唯一颜色分支。
5. **字号阶梯 9 级**（11→44）、**间距 8 级**（4→64）、**圆角 5 级**按主题不同（Slate 4/6/10/14
   vs atmosphere 8/12/16/24）一一对应。
6. **caption 小标题** = 全大写 + `letterSpacing 0.18em` + 11px，别简化掉。
7. **动效方向语言**：sheet 升起 280ms、toast 顶落 240ms、遮罩淡入 200ms，缓动统一
   `cubic-bezier(.2,.7,.3,1)`；尊重 reduce-motion。
8. **交错节奏**：列表卡片 60ms stagger、流式 token 32ms stagger——这是「有生命感」的关键，别省。
9. **safe-area / dvh**：用 SafeArea + 全屏根布局复刻 `100dvh` 与 inset 工具类。
10. **焦点/选区/点击高亮**等 reset 在原生端有对应概念（splash、focus traversal），逐条对照别遗漏。
