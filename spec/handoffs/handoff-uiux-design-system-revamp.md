# Handoff · UReka UIUX Design System Revamp

> 给 coding agent / design agent。目标是把 UReka 当前偏彩色、模块各自生长的 UI，收敛为 **Quiet Warm Minimalism**：克制、温暖、可信的个人记录系统。

---

## 0. Read First

长期真值 / 参考：

- [design-system-revamp.md](../design/design-system-revamp.md) —— 本轮 UIUX revamp 总 brief，含 taxonomy。
- [quiet-warm-minimalism-demo.html](../design/quiet-warm-minimalism-demo.html) —— 当前视觉方向 demo。
- [05-design-system.md](../05-design-system.md) —— 现有 token / Theme 契约。
- [04-frontend.md](../04-frontend.md) —— 当前 Flutter 页面结构。
- [08-domain-system.md](../08-domain-system.md) —— 8 个 domain 与颜色语义。

不要直接照搬 demo 的所有布局。demo 只证明风格：少颜色、轻边框、低阴影、暖灰底、domain 色小信号、Reka 保留温度。

---

## 1. Product Decision

### 1.1 Style Baseline

本轮风格基线：

```text
Quiet Warm Minimalism
克制、温暖、可信的个人记录系统
```

含义：

- 数据界面专业、安静、少颜色。
- Reka 是主要情绪层，不让整套数据 UI 都变可爱。
- 8 个 domain 色只做小点、细线、轻 badge，不做大面积卡片底色。
- 卡片默认是 quiet paper tile：neutral surface + 1px border + 低阴影。
- 动效只解释状态变化，不做展示型炫技。

### 1.2 Astryx Positioning

可以参考 Astryx 的设计系统组织方式：

- token-first
- component docs
- template / pattern docs
- agent-ready docs

但 Flutter 主 app **不引入 Astryx runtime**。UReka 自建 Flutter-first design system。

---

## 2. Scope

### In Scope · 本轮做

1. **Token audit + first token layer**
   - 收敛现有 `EurekaColors` / `domainColor` / hardcoded colors。
   - 引入 quiet warm palette。
   - 建立 Flutter-first token 命名。

2. **Core Surface component**
   - 统一 neutral card / panel / tile 的质感。
   - 默认 1px border、低阴影、8-12 radius。

3. **Library Surface**
   - 重做资产库 skill / asset type container 的视觉语言。
   - 移除大面积彩色容器。
   - 不使用 `M / T / N` 这类大字母占位 glyph。

4. **Asset Surface System alignment**
   - Bubble / timeline item / SkillCard / detail sheet / edit page 保持同一套密度层级。
   - domain 色只作为小信号。

5. **Dynamic Edit baseline**
   - `AssetEditPage` / dynamic schema fields 视觉收敛为 quiet form。
   - 只改视觉与组件结构，不改变字段语义。

6. **Agent / Skill Creation interaction language**
   - 为 AddSkillWizard / Reka Offer / Agent Session 定义：
     - Capability Cloud
     - Generated Preview Stack
     - Offer Stack
   - 视觉使用低饱和纸片，不使用彩虹 capsule。

### Out of Scope · 本轮不做

- 不重写业务逻辑。
- 不改 API / data model。
- 不重新设计 Reka 形象本身。
- 不一次性重画所有页面。
- 不把 Flutter app 嵌入 React / Astryx。
- 不做完整 admin web design system。

---

## 3. Visual Rules

### 3.1 Color

必须：

- 页面主体使用 warm monochrome。
- brand blue 只做 action / focus / active。
- domain colors 降饱和，只做 dot / hairline / tiny badge。
- status colors 只用于错误、成功、警告，不和 domain color 混用。

禁止：

- 大面积彩色 skill card。
- rainbow chips。
- 多个高饱和 offer card 堆叠。
- 每个 skill 自己发明 accent color。

### 3.2 Container Texture

默认 container = quiet paper tile：

```text
background: neutral surface
border: 1px low contrast
radius: 8-12
shadow: none / ultra-low
padding: 14-16
```

Light:

```text
page bg   #F6F4EF
tile bg   #FFFFFF / #FBFAF7
border    rgba(33,31,25,0.08)
shadow    0 1px 2px rgba(24,22,18,0.04)
```

Dark:

```text
page bg   #0B0D10
tile bg   #13161A
border    rgba(255,255,255,0.07)
shadow    none / ultra-low
```

### 3.3 Icon / Emoji

- System UI 用统一 line icon / symbol。
- 系统基础类型：
  - 记账: receipt / coin
  - 待办: check-list
  - 随记: note
  - 名片: person
  - 事件: calendar
  - 报告: document
- 自定义 skill 可以用 wizard 生成的 emoji/icon，但必须小、淡、放进 28-32px icon well。
- 不使用 `M / T / N` 作为正式 library glyph。

---

## 4. Component / Pattern Taxonomy

### 4.1 Tokens

```text
mobile/lib/theme/
  ureka_tokens.dart        # target if new file is useful
  eureka_colors.dart       # existing palette, gradually aligned
  domains.dart             # domain colors stay here or become token-backed
  app_theme.dart
```

### 4.2 Components

Priority components:

```text
UQuietSurface / UCardSurface
ULibraryTile
UAssetCard visual variant
UTimelineItem visual variant
UDynamicEditField
URekaBubble
UOfferCard
```

### 4.3 Patterns

Required pattern docs / implementation language:

```text
Agent Session
Create/Edit Flow
Skill Creation Flow
Capability Cloud
Generated Preview Stack
Offer Stack
Library Browsing
```

Important classification:

- `DynamicEditPage` = component-level schema-driven edit surface.
- `Create/Edit Flow` = pattern that uses `DynamicEditPage`.
- `AddSkillWizard` = `Skill Creation Flow` pattern.
- `Agent Session` = pattern, not chat bubble component.

---

## 5. Library Tile Spec

正式 Library tile 应该像：

```text
┌────────────────────┐
│ 记账              •│
│ 今日 3 · 总计 126  │
│ 最近 午饭 38 元    │
└────────────────────┘
```

Required:

- Neutral background.
- 1px low-contrast border.
- Small system icon or weak custom emoji.
- Title + count + recent preview.
- Domain signal as tiny dot / hairline.
- No full-card domain fill.
- No big letter placeholder.

States:

| State | Visual |
|---|---|
| Default | quiet paper tile |
| Pressed | border slightly stronger, surface slightly darker/lighter |
| Empty | title + soft helper text, no fake metrics |
| Custom skill | small generated emoji/icon in icon well |
| System skill | standard line icon |

---

## 6. Agent Interaction Pattern

The video reference discussed in product review maps to this pattern:

```text
Capability Cloud
→ Generated Preview Stack
→ Confirm / Regenerate / Execute
```

Use cases:

- `AddSkillWizard`: user describes a record need → capability tags appear → schema/card previews stack → regenerate/save.
- `Reka Offer`: today’s available Reka help items → offer stack → execute/dismiss.
- `Agent Session`: suggested actions after a flash/chat/report → small capability chips → generated cards.

Visual constraints:

- Use muted paper chips, not rainbow capsules.
- One focused item may use brand blue / warm accent.
- Background items stay neutral.
- Motion should be calm: fade / slide / stack shift, not bounce/glow.

---

## 7. Suggested Implementation Order

### Phase 0 · Audit

- Find hardcoded high-saturation color usage in `mobile/lib`.
- Inventory current cards / tiles / sheets.
- Identify where skill colors still fill containers.

### Phase 1 · Tokens + Surface

- Add or align quiet palette tokens.
- Build a reusable quiet surface component.
- Replace library tile container styling first.

### Phase 2 · Library

- Redesign Library skill/entity/report containers.
- Remove large color fills.
- Add recent preview / count hierarchy.
- Align system icon / custom emoji rules.

### Phase 3 · Asset Surfaces

- Align `SkillCard`, timeline item, detail sheet, edit page.
- Ensure domain color is small signal only.

### Phase 4 · Agent Patterns

- Add visual primitives for Capability Cloud / Generated Preview Stack.
- Use in AddSkillWizard first.
- Then reuse in Reka Offer / Agent Session.

---

## 8. Validation

### Visual QA

- Compare against [quiet-warm-minimalism-demo.html](../design/quiet-warm-minimalism-demo.html).
- Screenshot light and dark themes.
- Verify Library no longer reads as colorful containers.
- Verify Reka remains emotionally visible but does not dominate data pages.

### Engineering QA

- `flutter analyze`
- Smoke test:
  - Today
  - Calendar stream/day detail
  - Library
  - Asset detail
  - Asset edit/create
  - AddSkillWizard
  - Reka Offer / notifications

### Acceptance

- App feels quieter and more coherent.
- Color no longer competes across modules.
- Library tiles look like refined record containers, not skill-color boxes.
- Dynamic edit pages feel like part of the same system.
- AddSkillWizard has a clear premium interaction model.
- Agent session feels like “AI doing work”, not a generic chat list.

---

## 9. Do Not

- Do not remove domain colors entirely.
- Do not flatten everything into black/white utility UI.
- Do not make Reka disappear.
- Do not introduce a new dependency just for visual styling.
- Do not build React/Astryx inside Flutter.
- Do not port the HTML demo as production code.
