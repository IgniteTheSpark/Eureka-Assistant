# Library + Assets V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring every Theme V2 Library and Asset surface into the approved app-shell, container, Todo, preview, detail-sheet, and motion contract.

**Architecture:** Treat `redesignureka.pen` as the visual source of truth and update Light/Dark pairs together. Work in isolated screen groups, validate each group with Pencil structural checks and screenshots, then organize the approved originals under the Library + Assets implementation section.

**Tech Stack:** Pencil `.pen` document, Pencil MCP `Get/Update/Insert/Copy/Move`, Markdown design specification.

## Global Constraints

- Design file: `/Users/admin/workwork/eureka-staff/Eureka-Assistant/spec/design/redesignureka.pen`.
- Approved specification: `docs/superpowers/specs/2026-07-29-library-assets-v2-design.md`.
- Reference viewport: `411 × 960`.
- Light and Dark use the same geometry and behavior.
- Do not add breadcrumbs, path-eyebrow copy, container selection underlines, alphabetic card suffixes, or a Recently Generated “全部” route.
- Preserve unrelated user changes and do not edit the deferred cross-product icon mapping system.
- Every modified root frame is `placeholder: true` while being edited and reset to `false` when complete.

---

### Task 1: Library Hub Shell, Containers, Recently Generated, and Banner Motion

**Files:**
- Modify: `redesignureka.pen`
- Reference: `docs/superpowers/specs/2026-07-29-library-assets-v2-design.md`

**Interfaces:**
- Consumes: existing global top-nav components `Gcce8` and `t7nGi`.
- Produces: approved Hub screens `LTmYy` and `c5ejE`, plus normalized container card geometry used by later Library screens.

- [ ] **Step 1: Capture the current Hub structure**

Use Pencil `Get` on `LTmYy` and `c5ejE` at depth 4. Record the IDs for title/subtitle, container cards, container counts, Recently Generated cells, Dock, and both Skill Creation banners.

- [ ] **Step 2: Replace the Hub header**

Set both Hub roots to `placeholder: true`. Insert the correct Theme V2 global top-nav variant below the status bar. Remove `LIBRARY / …` breadcrumb text and the subtitle below `资产库`. Keep `资产库` as the only page title and align it to the app-shell content inset.

- [ ] **Step 3: Normalize all Hub container cards**

For every large and compact card in both themes:

```text
ordinal: 01, 02, 03...
remove: / A, / B, / ACTIVE
large padding: 14
compact horizontal padding: 12
large count: 18px Geist Mono semibold
compact count: 14px Geist Mono semibold
large card gap: 6px
compact stacked-row gap: 8px
```

Delete selection signal rectangles such as `guWkL`. Remove persistent selected strokes that exist only to indicate the originating card.

- [ ] **Step 4: Rebuild Recently Generated as one horizontal viewport**

Create a clipped row with page-side inset `16px`, cell gap `8px`, and one visible line. Place 6 complete reference cells across the 411px viewport and a partially entering seventh cell as the horizontal-scroll affordance. Set metadata:

```json
{
  "type": "horizontal-collection",
  "limit": 50,
  "order": "newest-first",
  "pagination": false,
  "allRoute": false
}
```

Remove any second row and remove the count if it implies the visible item count rather than the 50-item collection.

- [ ] **Step 5: Document Banner motion on the actual banner nodes**

Update the Light/Dark Skill Creation banner metadata to:

```text
edge glow loop 4–6s;
three particles drift locally in upper-right;
particle opacity breathes;
press halo pulses once at left symbol;
tap converges glow and particles toward arrow in 280ms;
reduce motion keeps static gradient and press feedback only
```

Keep all particles clipped inside the banner.

- [ ] **Step 6: Validate and finish Hub**

Reset both roots to `placeholder: false`. Run `Get` with `ctx.problems` on both roots. Screenshot `LTmYy`, `c5ejE`, one large container card, and both banner variants. Expected: no breadcrumbs/subtitle, no underline, legible counts, one horizontal Recent row, and no content behind the Dock.

---

### Task 2: Container Index and All Containers

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: Task 1 ordinal, count, spacing, and pressed-state contract.
- Produces: approved container browsing screens `B70HCg`, `RTqWK`, `V0MnR`, and `uSlon`.

- [ ] **Step 1: Inspect and mark roots**

Read the four screen trees, then set all four roots to `placeholder: true`.

- [ ] **Step 2: Apply the global Library shell**

Use the same global top navigation and title hierarchy as the Hub. Delete breadcrumbs and explanatory copy. Preserve search and container-specific controls.

- [ ] **Step 3: Normalize rows and counts**

Remove alphabetic suffixes from every ordinal. Set compact count text to `14px` and align each count to a shared right inset of `12px`. Set row horizontal padding to `12px`, minimum row height to `54px`, and vertical gap to `8px`.

- [ ] **Step 4: Remove web-like selection treatments**

Delete underlines and persistent `ACTIVE` labels. Use only press metadata:

```json
{"type":"press-state","scale":0.98,"luminanceDelta":-0.04}
```

- [ ] **Step 5: Validate and finish**

Reset placeholders. Check layout problems and screenshot all four screens. Expected: matching Light/Dark geometry, uniform header, readable counts, and stable row spacing.

---

### Task 3: Todo Tabs and Todo Edit Preview

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: global Library shell and Asset preview-card reading hierarchy.
- Produces: Todo screens `qjb6X`, `LQf9o`, `y49fg`, and `S5GGTj`.

- [ ] **Step 1: Update Todo list shells**

Set `qjb6X` and `LQf9o` to placeholders. Replace the breadcrumb header with the persistent app top nav and retain `待办` as the page title.

- [ ] **Step 2: Build four count-bearing tabs**

Replace the current filters with:

```text
全部 48
今天 6
已完成 18
待安排 9
```

Use pill selection, no underline. Make the tab container a clipped horizontal scroller so localized copy and large counts do not compress.

- [ ] **Step 3: Define unscheduled behavior**

Add metadata to the `待安排` tab:

```json
{
  "type": "todo-filter",
  "filter": "unscheduled",
  "predicate": "due_date == null && due_time == null",
  "position": "last"
}
```

- [ ] **Step 4: Add Todo Edit live previews**

Set `y49fg` and `S5GGTj` to placeholders. Insert a `预览` label and a stable preview card below editable fields and above the primary Save action. The card displays title, due state, notes summary, and reminder/completion state. Empty values render placeholders and do not collapse the card.

- [ ] **Step 5: Validate and finish Todo**

Reset all four placeholders. Run structural checks and capture Light/Dark list and edit screenshots. Expected: four readable tabs with totals and a preview card that does not collide with Save or Dock.

---

### Task 4: User-created Skill Edit Preview

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: existing Tennis schema and existing custom Skill detail hierarchy.
- Produces: preview-enabled edit screens `tAoSU` and `czuBh`.

- [ ] **Step 1: Inspect schema and detail hierarchy**

Read `tAoSU`, `czuBh`, `zaQiy`, and `nCrdm`. Identify field IDs and the detail card order.

- [ ] **Step 2: Add live preview cards**

Set edit roots to placeholders. Insert a `预览` section after the final editable field. Use the same order and typography as the Tennis Asset detail, populated from current draft values. Add metadata:

```json
{
  "type": "asset-draft-preview",
  "skill": "tennis",
  "createsAsset": false,
  "updatesOn": "field-change"
}
```

- [ ] **Step 3: Preserve edit actions**

Keep Save/Edit actions reachable. If the preview extends beyond the viewport, make the form body the vertical scroll region and preserve the bottom action inset above the Dock or safe area.

- [ ] **Step 4: Validate and finish**

Reset placeholders, run problem checks, and screenshot both themes. Expected: matching field-to-preview values and no preview overlap.

---

### Task 5: Standardize All Asset Detail Sheets

**Files:**
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: the approved half/full-sheet geometry.
- Produces: consistent detail states for Todo, Notes, Events, Contacts, and custom Skill Assets.

- [ ] **Step 1: Inventory detail roots**

Inspect:

```text
Todo full: q6HALg / JFSzl
Notes half: S75cTq / pY8cD
Events half: KOUbK / y6LAI
Contacts half: pi4et / H2fqE
Custom Skill half: zaQiy / nCrdm
```

Identify sheet, header, metadata, long-text, and action IDs for every pair.

- [ ] **Step 2: Normalize half sheets**

For Notes, Events, Contacts, and custom Skill details:

```text
sheet height: 576
sheet y: 384
horizontal inset: 20
long-text width: 371
long-text max height: 120
overflow affordance: bottom fade + 查看全部
```

Short text shrinks. Header, metadata, tags, and actions remain outside the long-text container.

- [ ] **Step 3: Add missing full-screen counterparts**

Use the existing Todo full-screen and Notes full-screen patterns as visual references. Create Light/Dark full-screen states for Events, Contacts, and custom Skill details. Use:

```text
x: 0
y: 54
width: 411
height: 906
text width: 371
reference text height: 480
minimum text height: 320
```

Only the text container scrolls. Header, metadata, tags, and bottom actions remain fixed.

- [ ] **Step 4: Connect half-to-full behavior**

Add matching metadata on every half and full pair:

```json
{
  "type": "asset-detail-presentation",
  "open": "half-sheet",
  "expandAction": "查看全部",
  "expanded": "full-screen-sheet",
  "restore": "same-half-sheet-and-list-offset"
}
```

- [ ] **Step 5: Validate and finish**

Check every Light/Dark pair structurally. Screenshot at least Notes, Events, Contacts, and custom Skill in half and full states. Expected: identical geometry, internal long-text scroll, fixed actions, and no Dock collision.

---

### Task 6: Organize Library + Assets Implementation Source and Final QA

**Files:**
- Modify: `redesignureka.pen`
- Modify: `docs/superpowers/specs/2026-07-29-library-assets-v2-design.md`

**Interfaces:**
- Consumes: all approved screens from Tasks 1–5.
- Produces: one coding-agent reference section with validated source nodes.

- [ ] **Step 1: Expand the Library section**

Resize `WLBLn` to contain the approved Library + Assets screen matrix. Keep the section header, then organize rows as Hub/Containers, Todo, Notes, Events, Contacts, custom Skill, and shared detail-sheet states.

- [ ] **Step 2: Move approved originals**

Move the approved Theme V2 roots into `WLBLn`; do not copy them. Preserve node IDs. Keep deprecated, exploration, and legacy `UReka · Screen` frames outside the implementation source.

- [ ] **Step 3: Add implementation labels**

Add concise row labels and a motion-contract card for the Skill Creation banner. Labels are canvas documentation only and must be outside 411px app frames.

- [ ] **Step 4: Run structural QA**

For `WLBLn` and every contained app frame, print `ctx.problems`. Fix unintended clipping, collapsed layout, off-screen text, and Dock overlap. Intentional clipping is limited to the Recently Generated horizontal viewport, banner particles, and long-text containers.

- [ ] **Step 5: Run visual QA**

Capture the whole `WLBLn` section, then focused screenshots for:

```text
Hub Light/Dark
Todo list and edit Light/Dark
Custom Skill edit Light/Dark
each Asset half/full detail pair
Skill Creation banner Light/Dark
```

Compare geometry, hierarchy, contrast, and touch targets.

- [ ] **Step 6: Update specification status**

Change the design specification status to `IMPLEMENTED IN CANVAS · READY FOR HANDOFF`, add `WLBLn` as the implementation source, and list the final Node ID whitelist.
