> **⚠️ 这是用户做的 hifi 原型 README（逐字保留，给 coding agent / design 当视觉参考）。** 逻辑真值以 [§4.5.0](04-frontend.md) + [handoff-calendar-design §E](handoff-calendar-design.md) 为准。
> **与本原型的几处对齐（按 spec、别照原型 demo）**：① 域色 = §8 **八**色（本文的 6 色 /「财务」是 demo 样本，忽略；记账→生活域）；② **闪念 = pill、不进池、不是记录类型**（本文把 flash 当记录类型，按 spec 去掉）；③ **早报 merge 进 Next Action**；④ Reka = 全局浮球、不当主角；⑤ 右侧 **DEMO 面板**（重力 / 晃一晃 / 记一条 / 场景切换）= 调试架，**不做**；⑥ nav = 今日 / 日历 / 资产、我的岛进 Reka 菜单。

---

# Handoff: 今日页 (Today Page) — UReka

## Overview
The Today page is UReka's home screen. It splits the day into two stacked parts inside the app shell:

1. **Next Action** — a swipeable stack of the user's upcoming timed events/todos with a live countdown, plus an expandable "no-time todos" list.
2. **Recorded (气泡池 / bubble pool)** — every asset the user captured today (记账/待办/名片/闪念/笔记/运动) rendered as a **physics-driven bubble** that falls, collides, and settles in a wall-less container behind the floating UI. A collapsible **dashboard** sits above the pool with a type filter + switchable charts (rose / bar / treemap) that drill down by domain.

A pixel-style mascot **Reka** floats on top and is freely draggable.

## About the Design Files
The file in this bundle (`今日页.dc.html`) is a **design reference created in HTML/JS** — a working prototype showing intended look, motion, and behavior. It is **not production code to copy directly**. The task is to **recreate this design in the target codebase's existing environment** (React Native / SwiftUI / Flutter / web React, etc.) using that codebase's established components, theming, and animation/physics libraries. If no environment exists yet, pick the framework most appropriate for the product (this is a mobile app — a native or RN stack is the natural fit) and implement there.

The HTML prototype uses a small in-house reactive runtime (`support.js`, `<x-dc>`/`<sc-if>`/`<sc-for>` tags). **Do not port the runtime** — read the logic class for behavior and reimplement idiomatically.

## Fidelity
**High-fidelity (hifi).** Final dark "atmosphere" palette, typography, spacing, motion, and interactions are all specified below and present in the prototype. Recreate the UI faithfully using the codebase's libraries. The one explicit exception: the **auxiliary DEMO panel** to the right of the phone (gravity buttons, 晃一晃, 记一条, scenario switcher) is a **prototype-only harness** for exercising states — it is NOT part of the product and should not be built.

---

## App Shell (context, likely already exists)
- **Global top header**: UReka logo (cloud glyph in a blue rounded square) left; moon / person / device icons right. Height ~56px. Always present.
- **Floating bottom nav** (sticky, always visible, centered pill): 今日 (active) · 日历 · 资产. Frosted (`rgba(18,26,44,.82)` + blur 18px), radius 999px, 12px shadow. Sits `bottom:20px`.
- The Today page renders **between** these.

---

## Screens / Views

### View: Today (single screen, vertical)
**Purpose**: At a glance see "what's next" and "what I captured today"; review/记录 throughout the day.

**Layout** (mobile, design width 430px, full viewport height):
- Front layer is a vertical flex column: Header → Next Action panel → Dashboard panel → ball window (flex:1) → reserved 78px gap above nav.
- Back layer is a full-screen absolutely-positioned **ball field** (`inset:0`, z-index 1) behind everything. A radial vignette overlay sits at z-index 2.
- Panels are z-index 10; they **float above** the ball field and **do not collide** with bubbles (bubbles pass behind the frosted glass).
- Bottom nav z-index 25; Reka z-index 45; record detail sheet z-index 60.

#### Component: Next Action panel
- Container: `margin:4px 14px 0`, `background:rgba(15,23,40,.66)` + `backdrop-filter:blur(12px)`, border `1px rgba(255,255,255,.09)`, radius 18px.
- **Header row** (tap to collapse): label `接下来` (JetBrains Mono, 10px, letter-spacing .16em, `rgba(255,255,255,.4)`) · when collapsed shows the focal title · right side shows `chainPos` "1 / 3" (JetBrains Mono 13px, `#8ab4ff`, 600) and a caret ▴/▾.
- **Card deck** (height 152px): a C-style fanned stack — two faint rotated peek cards (`rotate(-2.2deg)` / `rotate(1.5deg)`) behind a focal card.
  - Focal card: fixed height 124px, `linear-gradient(180deg, rgba(34,48,78,.96), rgba(22,33,57,.96))`, border `1px rgba(255,255,255,.15)`, radius 16px, shadow `0 14px 30px rgba(0,0,0,.5)`, padding 13px 16px. **Fixed height so event vs todo cards never resize.**
  - Card top row: a domain-color dot (9px, glowing) + sub text (`事件 · 评审会议室`, 12px `rgba(255,255,255,.5)`) + time label (right, JetBrains Mono 12px).
  - Title: 20px, 600, `#e6edf3`.
  - **Event card** bottom: countdown `⏳ 23 分钟 00 秒后` (JetBrains Mono 13px `#8ab4ff`, updates every second) + progress bar (height 5px, track `rgba(255,255,255,.1)`, fill `linear-gradient(90deg,#6f9eff,#8ab4ff)`), then `🔔 到点提醒你` … `在日历看 ›`.
  - **Todo card** bottom: a note + a `完成 ✓` pill button (border `1px rgba(111,158,255,.4)`, bg `rgba(111,158,255,.14)`, text `#8ab4ff`).
  - **Swipe left/right** on the deck cycles to next/prev action. Completing/time passing advances the chain.
- **Counter row** (below deck): `左右滑切换` hint (left) + `🕒 无时间待办 {N} ▾` pill (right, tap to expand).
- **No-time todos** (expand, pushes content down): dashed container `rgba(8,14,26,.7)` border `1px dashed rgba(255,255,255,.14)` radius 13px; each row = domain dot + title (14px) + a 19px circle checkbox.
- **Empty state** (no events/todos): centered 🌤️ (30px) + "今天还没有日程或待办" (15px 600) + "新的一天 —— 说一句话，Reka 就能帮你记下安排" (12px `rgba(255,255,255,.5)`).

#### Component: Dashboard panel (records summary + filter + charts)
- **Hidden entirely when there are no records today.**
- Same frosted container style as Next Action, `margin:8px 14px 0`.
- **Header row** (tap to collapse): `今天 {N} 颗` (JetBrains Mono 10px) + a ⚡ flash pill (`⚡ {flashCount}`, gradient blue, only the count of `flash`-type records) + caret.
- **Filter chips** (horizontal scroll): `全部 {total}` + one chip per asset type present (`📌 待办 N`, `💰 记账 N`, `👤 名片 N`, `⚡ 闪念 N`, `📝 笔记 N`, `🎾 运动 N`). Active chip: border `rgba(111,158,255,.5)`, bg `rgba(111,158,255,.2)`, text `#cfe0ff`. Tapping a chip **filters the bubble pool AND re-scopes the summary + charts.**
- **Summary strip**: tinted icon tile + title + sub + a big right-aligned metric. Content depends on the selected chip:
  - 全部 → "今日概览 · {top types}" · metric = record count.
  - 记账 → "今日记账汇总 · 最大 {max} · 共 N 笔" · metric = `¥{sum}` (sum parsed from titles).
  - 待办 → "待办进度" · metric = `done/total`.
  - 名片/闪念/笔记/运动 → count + content preview.
- **Charts** (height ~118px) with a label `{chartScope}` and a **selector BELOW** the chart (`✿ 玫瑰` / `▥ 柱状` / `◳ 树图`); **swipe left/right on the chart** also cycles. Hint: `← 左右滑 / 点选 切换图表 →`.
  - **Drill-down rule**: when filter = 全部, charts group by **asset type** (`今日构成 · 按类型`). When a specific type is selected, charts group by **domain within that type** (e.g. `记账 · 按领域`).
  - **玫瑰 (Nightingale/rose)**: SVG, equal-angle wedges, radius ∝ count, each wedge filled with the group color, 1px `#0e1626` stroke. Legend list beside it (color chip + label + count).
  - **柱状 (bar)**: one bar per group; height ∝ count; `linear-gradient(180deg, color, shade(color,-22))`; count above, label below.
  - **树图 (treemap)**: squarified rectangles sized by count; cell bg = domain/type color @ 0.82 alpha; label top-left, count bottom-right.

#### Component: Bubble pool (the physics field)
- Full-screen back layer. Each record = one bubble (radius 23px / 46px diameter).
- Bubble visual: `radial-gradient(circle at 34% 30%, #ffffffcc, {domainColor} 78%)`, shadow `0 3px 8px rgba(0,0,0,.4), inset 0 -3px 6px rgba(0,0,0,.18), inset 0 3px 5px rgba(255,255,255,.55)`, centered type **emoji glyph** (saturate .85). **Domain = fill color; type = glyph.**
- **Empty state** (no records): centered 🫧 (34px) + "今天还没有记录" + one explanatory line. No CTA text.
- **Interactions**:
  - **Tap a bubble** → opens the record detail sheet (bottom sheet).
  - **Drag a bubble** → throw it; it re-settles.
  - **Tilt the phone** (deviceorientation) → gravity vector follows; bubbles roll/​rise. Flipping upside-down makes them rise and rest under the panels (panels act as the ceiling; nav pill is a collider they slide past on its sides).
  - **New record** drops a bubble in from the top.
- **Physics notes** (reimplement with your engine, or port the approach): wall-less box (left/right walls, floor just above the nav, ceiling near screen top so bubbles live *behind* panels), the centered nav pill is an AABB collider (bubbles slide down its sides — never trapped behind it), circle-circle collision with **multi-pass positional relaxation (~14 iterations)** + **sleeping** (a bubble that barely moves for ~16 frames freezes; collisions / shake / gravity-change / drop wake it). Sleeping is what removes idle jitter and keeps overlap tiny. Gravity ~0.44, restitution ~0.22, linear damping ~0.97, max speed clamp.

#### Component: Record detail sheet (bottom sheet)
- Slides up from bottom, `#161b22`, radius 22px top, grabber bar.
- Big domain-tinted circle with type glyph + title + meta; two pills: `{glyph} {typeName}` (type-colored) and a domain dot + domain name.

#### Component: Reka (mascot)
- 52px circle, `radial-gradient(circle at 35% 28%, #9fc1ff, #3b63c4 75%)`, glowing gold gem at the bottom, two dark eyes; gentle float animation. **Freely draggable** anywhere on screen (top layer). Pixel-art version exists in the real app — use the existing asset.

---

## Empty / edge states (important)
The home screen must handle four cases (the prototype exposes them via a demo switcher):
1. **完整一天** — has both actions and records (default).
2. **只有日程·无记录** — Next Action shows its cards; **dashboard hidden**; pool shows the "今天还没有记录" empty state.
3. **只有记录·无日程** — Next Action shows its empty state; dashboard + pool populated.
4. **全空·清晨** — both empty states; clean welcome feel.

Rules: `flashCount` and all chip counts are derived from records (0 when none). When no records, hide the dashboard entirely; when no actions, show the Next Action empty card.

## Interactions & Behavior (summary)
- Countdown ticks every 1s.
- Deck: swipe L/R to browse; complete/time-pass advances.
- Chips: filter pool + scope summary/charts.
- Charts: tap selector or swipe to switch; drill type→domain.
- Bubbles: tap=open sheet, drag=throw, tilt=roll, new=drop-in.
- Panels: Next Action and Dashboard each independently collapse via their header caret.
- Toggle transitions ~280–380ms ease.

## State Management
- `currentActionIndex` (chain position), `now` (1s tick), `selectedSheet` (record | null), `filterKey` ('all' | type), `chartType` ('rose'|'bar'|'tree'), `naOpen`/`dashOpen` (panel collapse), `noTimeOpen`, `recordCount`. Scenario/gravity/chart-swipe demo state is prototype-only.
- Data: `records[]` ({type, domain, title, meta}), `chain[]` (timed events/todos, {kind, title, sub, domain, at, dur?, note?}), `noTimeTodos[]`.

## Design Tokens
- **Background**: page `#0b1220`; radial atmosphere `radial-gradient(130% 60% at 50% -5%, #13203a, #0b1220 60%)`. Outer (behind phone) `#070b14`.
- **Brand / accent**: `#6f9eff` (primary), `#8ab4ff` / `#cfe0ff` (lighter), tints `rgba(111,158,255,.1–.4)`.
- **Domain colors**: 财务 `#f5c977` · 工作 `#8ab4ff` · 健康 `#f08a8a` · 学习 `#b89cf0` · 生活 `#84c9a0` · 社交 `#6fd0d8`.
- **Type → glyph**: todo 📌 · money 💰 · card 👤 · flash ⚡ · note 📝 · sport 🎾.
- **Text**: primary `#e6edf3`; body `rgba(255,255,255,.82)`; muted `.5/.45/.34`.
- **Surfaces**: panels `rgba(15,23,40,.66)` + blur 12px, border `rgba(255,255,255,.09)`; nav `rgba(18,26,44,.82)` + blur 18px; sheet `#161b22`.
- **Radii**: panels 18px, cards 16px, pills 999px, treemap cells 6px, phone frame 40px.
- **Shadows**: card `0 14px 30px rgba(0,0,0,.5)`; nav `0 12px 30px rgba(0,0,0,.45)`.
- **Type**: **Manrope** (400–700) for UI; **JetBrains Mono** (400/500) for numbers, times, labels.
- **Bubble**: r=23px; physics g≈0.44, restitution≈0.22, damping≈0.97, relax≈14 iters, sleep after ~16 near-still frames.

## Assets
- No raster assets in the prototype — bubbles use CSS gradients + emoji glyphs; Reka is drawn with CSS. In the real app, use the existing **pixel-art Reka** sprite and the existing app icon set for nav/header.
- Fonts: Manrope + JetBrains Mono (Google Fonts).

## Files
- `今日页.dc.html` — the full interactive design reference (template markup + a `Component` logic class near the bottom; read it for exact behavior, data shape, and the physics implementation).
- `support.js` — the prototype runtime (reference only; do not port).
