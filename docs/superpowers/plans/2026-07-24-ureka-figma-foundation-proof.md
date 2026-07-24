# UReka Figma Foundation Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the UReka Figma source file, establish reusable visual foundations and first-party components, and prove the system with Today, Calendar, and Library high-fidelity screens.

**Architecture:** Figma variables and styles define the visual language; components consume semantic tokens; screen frames are composed from component instances. The source file follows the approved four-page single-maintainer structure and uses Quiet Warm Minimalism rather than reproducing current screenshots.

**Tech Stack:** Figma Design, Figma Plugin API through `use_figma`, Flutter source inspection, Manrope, JetBrains Mono.

## Global Constraints

- Create the design file in `KD's team / Drafts` with plan key `team::1304949616338777108`.
- Name the file `UReka Design System · Source of Truth`.
- Use only four pages: `00 · Foundations`, `01 · Components`, `02 · Hi-Fi Screens`, and `99 · Archive`.
- Use `390 × 844` as the canonical mobile frame and validate down to `360px`.
- Build the Quiet Warm Minimalism direction; screenshots and the current app are references, not visual authority.
- Domain colors appear as small identity signals, not large card fills.
- Data surfaces remain restrained; Reka carries the emotional expression layer.
- Use Auto Layout for all structurally related content.
- Bind component color, spacing, and radius properties to variables.
- Preserve the single-maintainer rule: a user-visible change updates Figma and the app in the same body of work.
- Do not add a design approval workflow, CI design gate, component version ledger, or manifest.
- Do not modify or stage unrelated user changes already present in the repository.

---

### Task 1: Create the source file and complete Phase 0 discovery

**Files:**
- Reference: `docs/superpowers/specs/2026-07-24-ureka-figma-design-source-of-truth-design.md`
- Reference: `mobile/lib/theme/eureka_colors.dart`
- Reference: `mobile/lib/theme/ureka_tokens.dart`
- Reference: `mobile/lib/theme/domains.dart`
- Reference: `mobile/lib/theme/app_theme.dart`
- Modify after creation: `docs/superpowers/specs/2026-07-24-ureka-figma-design-source-of-truth-design.md`

**Interfaces:**
- Consumes: approved Figma team plan key and design specification.
- Produces: `fileKey`, Figma URL, discovered library inventory, font inventory, and Phase 0 gap analysis.

- [ ] **Step 1: Create the blank Figma design file**

Call `create_new_file` with:

```json
{
  "editorType": "design",
  "fileName": "UReka Design System · Source of Truth",
  "planKey": "team::1304949616338777108"
}
```

Expected: a new `/design/` Figma URL and a reusable `file_key`.

- [ ] **Step 2: Inspect the blank file**

Run a read-only `use_figma` call:

```javascript
const collections = await figma.variables.getLocalVariableCollectionsAsync();
const [textStyles, effectStyles, paintStyles, fonts] = await Promise.all([
  figma.getLocalTextStylesAsync(),
  figma.getLocalEffectStylesAsync(),
  figma.getLocalPaintStylesAsync(),
  figma.listAvailableFontsAsync()
]);
return {
  pages: figma.root.children.map(p => ({ id: p.id, name: p.name, childCount: p.children.length })),
  collections: collections.map(c => ({ id: c.id, name: c.name, modes: c.modes, variableCount: c.variableIds.length })),
  styleCounts: { text: textStyles.length, effect: effectStyles.length, paint: paintStyles.length },
  requiredFonts: {
    manrope: fonts.filter(f => f.fontName.family === "Manrope").map(f => f.fontName.style),
    jetbrainsMono: fonts.filter(f => f.fontName.family === "JetBrains Mono").map(f => f.fontName.style)
  }
};
```

Expected: one blank page, zero local variables and styles, and exact available styles for Manrope and JetBrains Mono.

- [ ] **Step 3: Inspect available libraries**

Call `get_libraries` with the new `fileKey`, then search design-system libraries for `button`, `icon`, `input`, `color`, and `spacing`.

Expected: an explicit reuse decision. Reuse only editable assets with compatible naming, properties, and token architecture; otherwise build UReka-owned components.

- [ ] **Step 4: Lock the Phase 1 gap analysis**

Record and present:

```text
Code only:
- Eureka light/dark semantic palette
- 8 domain identity colors
- spacing, radius, duration constants
- partial shared Flutter widgets

Figma only:
- none in a blank file

Conflict resolution:
- Existing code values seed primitives and implementation mappings.
- Approved Quiet Warm Minimalism semantics determine Figma naming and usage.
- Existing hardcoded widget values are migration evidence, not new tokens.
```

Expected: user approval at the required Phase 0 checkpoint.

- [ ] **Step 5: Add the Figma URL to the design specification**

Add a `Figma source` line immediately below the Figma file name in the approved spec.

- [ ] **Step 6: Commit the source link**

```bash
git add docs/superpowers/specs/2026-07-24-ureka-figma-design-source-of-truth-design.md
git commit -m "docs(design): link Figma source of truth"
```

Expected: only the approved spec update is committed.

### Task 2: Build variable foundations and styles

**Files:**
- Reference: `mobile/lib/theme/eureka_colors.dart`
- Reference: `mobile/lib/theme/ureka_tokens.dart`
- Reference: `mobile/lib/theme/domains.dart`
- Reference: `spec/05-design-system.md`

**Interfaces:**
- Consumes: Figma `fileKey`, verified font styles, and the token inventory below.
- Produces: local variable collections, semantic light/dark tokens, text styles, effect styles, and their returned IDs.

- [ ] **Step 1: Create the variable collections**

Create:

```text
UReka · Primitives   — Default
UReka · Color        — Light, Dark
UReka · Dimensions   — Default
```

If the Starter plan rejects the second `UReka · Color` mode, stop and report the plan limitation. Do not silently replace the approved light/dark architecture.

- [ ] **Step 2: Create primitive color variables**

Create hidden primitive variables with `scopes = []` for:

```text
neutral/light/bg             #F6F4EF
neutral/light/surface        #FFFFFF
neutral/light/surface-raised #FBFAF7
neutral/light/border         rgba(33,31,25,0.08)
neutral/light/rule           rgba(33,31,25,0.06)
neutral/light/text-hi        #1B1D22
neutral/light/text           #34373F
neutral/light/text-mid       #5F636E
neutral/light/text-lo        #8B8F9A

neutral/dark/bg              #0B0D10
neutral/dark/surface         #13161A
neutral/dark/surface-raised  #171B20
neutral/dark/border          rgba(255,255,255,0.07)
neutral/dark/rule            rgba(255,255,255,0.06)
neutral/dark/text-hi         #F4F7FB
neutral/dark/text            #D4DBE6
neutral/dark/text-mid        #9AA6B8
neutral/dark/text-lo         #6C7689

brand/light/default          #3F6FE0
brand/light/high             #2B59C8
brand/dark/default           #6F9EFF
brand/dark/high              #A4C2FF

status/blue                  #8AB4FF
status/amber                 #F5C977
status/green                 #86E0A5
status/red                   #F7768E
status/purple                #C4A8FF
status/gray                  #A3AEC0
status/neutral               #C8CED8
status/cyan                  #67D9E8

domain/work                  #8AB4FF
domain/study                 #B89CF0
domain/health                #84C9A0
domain/sport                 #6FD0D8
domain/social                #F5C977
domain/entertainment         #F08A8A
domain/life                  #9FB0C9
domain/inspiration           #C3BCD0
```

Set WEB, ANDROID, and iOS code syntax on every variable. Use the exact Flutter field or domain mapping name for ANDROID/iOS syntax.

- [ ] **Step 3: Create semantic light/dark color variables**

Create aliases with explicit scopes:

```text
color/bg/default             FRAME_FILL, SHAPE_FILL
color/surface/default        FRAME_FILL, SHAPE_FILL
color/surface/raised         FRAME_FILL, SHAPE_FILL
color/border/default         STROKE_COLOR
color/rule/default           STROKE_COLOR
color/text/high              TEXT_FILL
color/text/default           TEXT_FILL
color/text/secondary         TEXT_FILL
color/text/muted             TEXT_FILL
color/action/primary         FRAME_FILL, SHAPE_FILL, TEXT_FILL
color/action/primary-hover   FRAME_FILL, SHAPE_FILL, TEXT_FILL
color/status/info            FRAME_FILL, SHAPE_FILL, TEXT_FILL
color/status/warning         FRAME_FILL, SHAPE_FILL, TEXT_FILL
color/status/success         FRAME_FILL, SHAPE_FILL, TEXT_FILL
color/status/error           FRAME_FILL, SHAPE_FILL, TEXT_FILL
```

Light and Dark mode values alias the corresponding primitive variables,
including the explicit translucent border and rule primitives.

- [ ] **Step 4: Create dimension variables**

Create:

```text
spacing/xs   4
spacing/sm   8
spacing/md   12
spacing/lg   16
spacing/xl   24
spacing/2xl  32
spacing/3xl  48
spacing/4xl  64

radius/sm    6
radius/md    8
radius/card  10
radius/xl    14
radius/full  999

motion/fast    150
motion/normal  250
motion/slow    400
```

Use `GAP` scope for spacing, `CORNER_RADIUS` for radius, and an empty scope for motion values.

- [ ] **Step 5: Create text styles**

After verifying exact font style names, create:

```text
Display/44       Manrope 700, 44/52
Display/38       Manrope 700, 38/46
Heading/32       Manrope 700, 32/40
Heading/26       Manrope 600, 26/34
Heading/20       Manrope 600, 20/28
Body/17          Manrope 500, 17/26
Body/15          Manrope 400, 15/23
Meta/13          Manrope 400, 13/19
Caption/11       Manrope 500, 11/16
Mono/13          JetBrains Mono 500, 13/18
Caption/Caps/11  Manrope 600, 11/16, 18% letter spacing
```

- [ ] **Step 6: Create effect styles**

Create:

```text
Elevation/Quiet/Light — y 2, blur 12, black 8%
Elevation/Raised/Light — y 8, blur 24, black 12%
Elevation/Quiet/Dark — y 2, blur 14, black 24%
Elevation/Raised/Dark — y 8, blur 28, black 36%
```

- [ ] **Step 7: Validate foundations**

Run a read-only `use_figma` audit returning collection names, mode names, variable count by collection, missing scopes, missing code syntax, and complete text/effect style lists.

Expected: zero `ALL_SCOPES`, zero missing code syntax, no `Mode 1`, and all planned styles present.

### Task 3: Create the four-page structure and Foundations documentation

**Files:**
- Reference: `docs/superpowers/specs/2026-07-24-ureka-figma-design-source-of-truth-design.md`

**Interfaces:**
- Consumes: created collections, variables, text styles, and effect styles.
- Produces: four named Figma pages and visual documentation frames on `00 · Foundations`.

- [ ] **Step 1: Rename the initial page and create the remaining pages**

Create exactly:

```text
00 · Foundations
01 · Components
02 · Hi-Fi Screens
99 · Archive
```

Expected: no extra blank `Page 1`.

- [ ] **Step 2: Build the Foundations cover**

Create an Auto Layout cover frame containing the file title, the Quiet Warm Minimalism direction, canonical frame information, and the single maintenance rule.

- [ ] **Step 3: Build color documentation**

Create Light and Dark semantic color boards using variable-bound swatches. Add a separate row for the eight domain identity colors.

- [ ] **Step 4: Build typography documentation**

Create a bilingual specimen for every text style using `UReka 记录伙伴 / Your everyday AI companion`.

- [ ] **Step 5: Build spacing, radius, and elevation documentation**

Create bound visual samples for every spacing and radius token and display all four effect styles.

- [ ] **Step 6: Validate the page structure and Foundations visuals**

Use metadata to verify page names and hierarchy. Capture a screenshot of the complete Foundations documentation.

Expected: no overlapping top-level frames, no clipped text, and semantic colors visibly switch between Light and Dark examples.

### Task 4: Build the first reusable component set

**Files:**
- Reference: `mobile/lib/widgets/quiet_surface.dart`
- Reference: `mobile/lib/widgets/global_header.dart`
- Reference: `mobile/lib/widgets/toast.dart`
- Reference: `mobile/lib/widgets/skeleton_loader.dart`

**Interfaces:**
- Consumes: semantic color and dimension variables, text styles, and effect styles.
- Produces: reusable components and instances on `01 · Components`.

- [ ] **Step 1: Search libraries immediately before component creation**

Search for each component family. Reuse only when the API and token model match; otherwise build locally.

- [ ] **Step 2: Build Button**

Create a component set with:

```text
Style: Primary, Secondary, Ghost
Size: Small, Medium, Large
State: Default, Pressed, Disabled, Loading
```

Cap the matrix by splitting Loading into a nested content component if the total exceeds 30 variants. Provide a text property for the label and a boolean property for icon visibility.

- [ ] **Step 3: Build Icon Button**

Create:

```text
Size: Small, Medium, Large
Style: Neutral, Primary
State: Default, Pressed, Disabled
```

Use an `INSTANCE_SWAP` property for the icon.

- [ ] **Step 4: Build Input**

Create:

```text
State: Empty, Filled, Focused, Error, Disabled
Size: Medium, Large
```

Expose label, placeholder, value, helper text, and leading/trailing icon visibility.

- [ ] **Step 5: Build Chip and Badge**

Create compact semantic and domain-signal variants. Domain identity uses a dot and label; it does not fill the whole container with domain color.

- [ ] **Step 6: Build Quiet Surface**

Create:

```text
Level: Base, Raised
Mode: Light, Dark
Padding: Compact, Default, Spacious
```

Bind surface, border, radius, spacing, and effect properties.

- [ ] **Step 7: Build Page Header, Toast, and Skeleton**

Build these as separate component families with the minimum states used by the current app.

- [ ] **Step 8: Validate every component before moving on**

For each component family:

1. Inspect component properties and child hierarchy.
2. Verify variable bindings.
3. Capture a screenshot.
4. Correct clipping, overlap, missing states, and unnamed layers immediately.

Expected: all planned variants exist, component labels are editable, and no component uses an unbound visual value except intentionally fixed icon geometry.

### Task 5: Build Global Shell and three core high-fidelity screens

**Files:**
- Reference: `mobile/lib/pages/today_page.dart`
- Reference: `mobile/lib/pages/calendar_page.dart`
- Reference: `mobile/lib/pages/library_page.dart`
- Reference: `mobile/lib/widgets/global_header.dart`
- Reference: `mobile/lib/widgets/floating_dock.dart`
- Reference: `mobile/lib/today/`
- Reference: `spec/design/design-system-revamp.md`
- Reference: `spec/design/today-home/`

**Interfaces:**
- Consumes: Foundations and first reusable components.
- Produces: Global Shell plus Today, Calendar, and Library canonical frames on `02 · Hi-Fi Screens`.

- [ ] **Step 1: Load the `figma-generate-design` skill**

Read the mandatory screen-building workflow and the code-first component reuse guidance before constructing full pages.

- [ ] **Step 2: Build Global Shell**

Create a reusable mobile shell containing safe-area structure, Global Header slot, scrollable content slot, Floating Dock, and Floating Reka anchor.

- [ ] **Step 3: Build Today**

Compose:

```text
Greeting / date context
Today summary
Next action
Timeline or bubble-pool content
Reka offer
Global navigation
```

Create Light and Dark canonical frames plus one meaningful loading/empty state.

- [ ] **Step 4: Build Calendar**

Compose the approved time-oriented hierarchy, domain dots, selected-day content, and event surfaces. Create Light and Dark canonical frames plus one meaningful empty state.

- [ ] **Step 5: Build Library**

Compose search/filter, section hierarchy, quiet asset surfaces, domain signals, and skill management entry points. Create Light and Dark canonical frames plus one meaningful empty state.

- [ ] **Step 6: Validate at canonical and minimum widths**

For each screen:

1. Capture the `390 × 844` frame.
2. Duplicate as a `360px` width validation frame.
3. Confirm no clipping, overlap, or inaccessible touch target.
4. Confirm every repeated surface is a component instance.

Expected: Today, Calendar, and Library remain usable at `360px` and share one coherent shell and component language.

### Task 6: Complete Phase 1 QA and handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-07-24-ureka-figma-design-source-of-truth-design.md`
- Create: `docs/design/ureka-figma-foundation-proof.md`

**Interfaces:**
- Consumes: completed Figma file and validation results.
- Produces: final source link, object inventory, known limitations, and Phase 2 entry point.

- [ ] **Step 1: Run the final Figma audit**

Return:

```text
Page names and top-level frame counts
Collection names, modes, and variable counts
Variables with missing scopes or code syntax
Text and effect style names
Component and component-set names
Hardcoded fills/strokes in reusable component subtrees
Screen instance counts
```

Expected: no duplicate page names, no unnamed components, no unresolved token bindings, and no detached repeated elements.

- [ ] **Step 2: Capture final review images**

Capture Foundations, Components, Today, Calendar, and Library.

- [ ] **Step 3: Write the local handoff**

Document:

- Figma file URL
- Completed Foundations and components
- Core screen node IDs
- Light/dark and `360px` validation result
- Remaining page families for Phase 2
- Any Starter-plan limitation that was explicitly accepted

- [ ] **Step 4: Commit documentation**

```bash
git add docs/superpowers/specs/2026-07-24-ureka-figma-design-source-of-truth-design.md docs/design/ureka-figma-foundation-proof.md
git commit -m "docs(design): record Figma foundation proof"
```

Expected: only the Figma source-of-truth documentation is committed.
