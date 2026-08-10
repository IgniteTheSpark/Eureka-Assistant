# Theme V2 Primary Pages Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify Today, Calendar, and Library under one primary-page shell, rebuild Today as three independent containers, and standardize dock and asset icon semantics.

**Architecture:** Reuse the existing Theme V2 global top navigation and light/dark dock components. Keep page titles outside the global navigation, make the Today generated bubble field a clipped local container, and place Calendar content inside a viewport below the shared title. Apply all structural changes to canonical light and dark screens before updating handoff documentation.

**Tech Stack:** Pencil `.pen` canvas, Pencil MCP `Get` / `Insert` / `Update` / `Move` / `Delete`, Markdown handoff files.

## Global Constraints

- Primary viewport remains `411 × 960`.
- Status bar is `44px`; global top navigation is `60px` below it.
- Primary page titles are `今日`, `日历`, and `资产库`, using one `28px` display style at `x = 18`.
- Page content must end at or above `y = 855`; floating dock remains at `y = 875`, leaving `20px` target clearance.
- Today has no full-page outer rounded sheet or border.
- Today has three independent containers: Next Moment, Reka, and Today Generated.
- Asset icons resolve from canonical asset type, then configured UserSkill icon, then generic file fallback.
- Dock icons are `sun`, `calendar-days`, and `library`; selection never uses an underline.
- Goal UI remains archived and hidden.
- The current sandbox cannot write the repository Git metadata; commits are intentionally omitted and all file changes remain reviewable in the working tree.

---

### Task 1: Shared Dock Semantics

**Files:**
- Modify: `redesignureka.pen` nodes `ohIfN`, `Y7EHo`

**Interfaces:**
- Consumes: Existing shared light and dark dock components.
- Produces: Canonical three-destination dock used by all primary screens.

- [ ] **Step 1: Mark both shared dock components as in progress**

Use Pencil `Update` to set `placeholder: true` on `ohIfN` and `Y7EHo`.

- [ ] **Step 2: Replace the Today icon semantic**

Update `ohIfN/K8Nlo` and `Y7EHo/J0Xi0e` from `sparkles` to `sun`. Keep the Calendar and Library icons as `calendar-days` and `library`.

- [ ] **Step 3: Verify mobile selection styling**

Inspect both components with `Get`. Confirm there is no underline child. Preserve the existing color-based active state and dock dimensions `169 × 60`.

- [ ] **Step 4: Finish the shared components**

Set `placeholder: false` on `ohIfN` and `Y7EHo`, then capture one shared-component screenshot for visual comparison.

---

### Task 2: Today Default — Light and Dark

**Files:**
- Modify: `redesignureka.pen` nodes `WsOyv`, `PMCdg`

**Interfaces:**
- Consumes: `Gcce8`, `t7nGi`, `ohIfN`, `Y7EHo`.
- Produces: Canonical Today default layouts with three independent content containers.

- [ ] **Step 1: Add the common application shell**

Set `WsOyv` and `PMCdg` to `placeholder: true`. Insert a `Gcce8` instance at `(0, 44)` in `WsOyv` and a `t7nGi` instance at `(0, 44)` in `PMCdg`. Keep their existing light/dark status bar instances at `(0, 0)`.

- [ ] **Step 2: Remove the full-page wrapper treatment**

Update `WF8fM` and `zWoZO` to `(0, 104)`, size `411 × 751`, transparent fill, no stroke, zero corner radius, and `clip: false`. Disable the grip nodes `uGai7` and `S43lX`, the old summaries `FFpkU` and `TMX7t`, and the ambient ellipses `pQzXU` and `A3tpM`.

- [ ] **Step 3: Standardize the page title**

Update `SfLHr` and `fn334` to content `今日`, position `(18, 8)` within their content frame, `28px` size, Theme V2 display weight, and the current light/dark primary text color.

- [ ] **Step 4: Place Next Moment and Reka as sibling containers**

Update `z6eLk9` and `YVtGb` to `(18, 56)`, width `375`, height `126`. Update `iBW9j` and `ZMXns` to `(18, 194)`, width `375`, height `188`. Preserve their content and use the same surface radius and stroke treatment within each theme.

- [ ] **Step 5: Convert the generated field into the third container**

Update `YRDqv` and `rWGEY` to `(18, 394)`, size `375 × 357`, `clip: true`, with the same container surface, stroke, and radius family used by Next Moment and Reka. Add a header row containing `今日生成` and the current count. Keep any watermark subordinate to that header.

- [ ] **Step 6: Rebase generated-bubble children into the local stage**

For every direct child bubble in `YRDqv` and `rWGEY`, subtract `430px` from its current local `y`, then adjust outliers so all settled bubbles remain below the header and inside `y = 80…330`. Place the visual intake origin at the top center of the container. Confirm the container, not the page, clips bubbles.

- [ ] **Step 7: Standardize asset icons**

Inspect each bubble's icon child. Replace content-derived one-off glyphs with a representative stable set: `square-check`, `calendar-days`, canonical note, canonical contact, `mic`, `image`, `map-pin`, report icon, configured custom-skill icon, or `file` fallback. Repeated asset types must repeat the same icon.

- [ ] **Step 8: Preserve dock clearance and finish**

Keep Today docks at `(121, 875)` and home indicators unchanged. Set both roots to `placeholder: false`. Use `Get` to confirm all content ends at or above `y = 855`, then capture light and dark screenshots.

---

### Task 3: Today Agenda — Light and Dark

**Files:**
- Modify: `redesignureka.pen` nodes `vRy65`, `J5cpE`

**Interfaces:**
- Consumes: Shared shell and Today title contract from Task 2.
- Produces: Agenda-expanded Today examples aligned with the same global shell.

- [ ] **Step 1: Add global navigation and standard title placement**

Set both roots to `placeholder: true`. Insert `Gcce8` at `(0, 44)` in `vRy65` and `t7nGi` at `(0, 44)` in `J5cpE`. Move `SbbbL` and `Vwra6` to `(0, 104)`, size `411 × 751`, remove the full-sheet surface, and update `RZbW9` / `Q28A1h` to the shared `今日` title style.

- [ ] **Step 2: Make Agenda a bounded content surface**

Resize the frosted agenda layers `xcnLs` and `foLYq` to `(18, 56)`, width `375`, height `695`, with clipping enabled. Rebase fishbone elements into this surface so the static example stays above `y = 855` and does not pass behind the dock.

- [ ] **Step 3: Remove obsolete full-page generated decoration**

Disable the full-page background bubble fields `FkbCD` and `J1fRLq` while Agenda is expanded. Keep the generated chamber examples only if they are inside the bounded Agenda surface and do not compete with the fishbone timeline.

- [ ] **Step 4: Finish and verify**

Keep docks at `(121, 875)`. Set both roots to `placeholder: false`. Capture light and dark Agenda screenshots and verify the shared Top Nav, title, and dock spacing match the Today default examples.

---

### Task 4: Library Hub Alignment

**Files:**
- Modify: `redesignureka.pen` nodes `LTmYy`, `c5ejE`

**Interfaces:**
- Consumes: Shared title and dock contracts.
- Produces: Light and dark Library hubs aligned with Today and Calendar.

- [ ] **Step 1: Standardize the Library titles**

Set both roots to `placeholder: true`. Update `fEc3D` and `mQF3f` to content `资产库`, position `(18, 116)`, `28px` size, and the shared display weight. Preserve the existing global top navigation instances `kHOG7` and `i86hH`.

- [ ] **Step 2: Reflow content below the common title**

Keep the hierarchical content start at `y = 160`, preserving statistics, pinned containers, AI Skill banner, and Recently Generated hierarchy. Adjust only vertical collisions introduced by the reduced title box.

- [ ] **Step 3: Standardize dock icons**

Update the non-instance dock first icon nodes `oUCtw` and `Qvlzh` to `sun`; keep their Calendar and Library icons. Confirm Library remains the selected destination through color or soft emphasis and not an underline.

- [ ] **Step 4: Verify Recently Generated icon semantics**

Inspect the six visible Recently Generated icon cells in each theme. Replace any content-derived icon with the canonical asset-type icon used by Today for the same example type. Preserve the independent icon-plus-time layout.

- [ ] **Step 5: Finish and verify**

Set both roots to `placeholder: false`. Capture light and dark screenshots and compare title baseline, content inset, dock position, and Top Nav structure with Today.

---

### Task 5: Calendar Primary View Alignment

**Files:**
- Modify: `redesignureka.pen` nodes `BeBq4`, `J3XydT`

**Interfaces:**
- Consumes: Shared global navigation, title, and dock contracts.
- Produces: Light and dark Calendar primary views with a bounded scroll viewport.

- [ ] **Step 1: Replace ad-hoc status framing with the common shell**

Set both roots to `placeholder: true`. Keep or replace the existing `Status` frames so their rendered result matches `E92l1` and `lwbLt`. Insert `Gcce8` at `(0, 44)` in `BeBq4` and `t7nGi` at `(0, 44)` in `J3XydT`.

- [ ] **Step 2: Add the shared Calendar title**

Insert `日历` text at `(18, 116)` in both roots with the shared `28px` primary-page title style.

- [ ] **Step 3: Create a clipped Calendar viewport**

Insert a frame named `Calendar Content Viewport` at `(0, 154)`, size `411 × 701`, transparent fill, and `clip: true`. Move the sticky date rail, divider, scrolling day content, upcoming date rail, and empty date rail into it. Rebase their local positions so the current first rail begins near `y = 6` and the scrolling content begins near `y = 0`.

- [ ] **Step 4: Preserve timeline density**

Keep the existing 54px rail column and 309px scrolling content column. Do not enlarge row cards or alter scheduling semantics. Let later-day examples clip naturally at the viewport boundary rather than overlap the dock.

- [ ] **Step 5: Standardize dock icons**

Update `Y2Khdi` and `fqlZ9` to `sun`; keep Calendar and Library icons. Preserve Calendar as the selected destination without an underline.

- [ ] **Step 6: Finish and verify**

Keep docks at `(121, 875)` and home indicators unchanged. Set both roots to `placeholder: false`. Use `Get` to confirm viewport bottom `855` and dock top `875`, then capture light and dark screenshots.

---

### Task 6: Contract Documentation and Final QA

**Files:**
- Modify: `theme-v2-today-handoff.md`
- Modify: `theme-v2-calendar-handoff.md`
- Modify: `theme-v2-library-assets-handoff.md`
- Modify: `redesignureka.pen`

**Interfaces:**
- Consumes: Completed primary-page screens and shared components.
- Produces: Implementation-ready visual and written contract.

- [ ] **Step 1: Document the shared shell**

Add the exact `44 / 60 / title / content / dock` vertical contract, page-title token, and `20px` dock-clearance target to all three handoffs.

- [ ] **Step 2: Document Today's three-container and motion contract**

State that bubbles enter from the top of Today Generated, settle within its clipped stage, and use reduced-motion fade/scale fallback.

- [ ] **Step 3: Document canonical icon resolution**

Add the resolution order `asset type → configured UserSkill icon → file fallback` and the dock mapping `sun / calendar-days / library`.

- [ ] **Step 4: Run structural QA**

Use Pencil `Get` visitors on all eight canonical screen roots and both shared dock components. Report any layout problem, placeholder left enabled, content below `y = 855`, missing Top Nav, mismatched title size, or dock icon mismatch.

- [ ] **Step 5: Run visual QA**

Capture final screenshots for Today default, Today Agenda, Library, and Calendar in light and dark. Compare paired screens for matching title baselines, content insets, Top Nav structure, dock clearance, and absence of clipping.

- [ ] **Step 6: Clear the implementation state**

Confirm no modified root or shared component remains `placeholder: true`. Leave unrelated user changes untouched and summarize any intentionally deferred detail-screen alignment.
