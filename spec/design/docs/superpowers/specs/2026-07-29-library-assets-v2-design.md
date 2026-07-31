# UReka Theme V2 — Library + Assets Design

Date: 2026-07-29
Status: IMPLEMENTED IN CANVAS · READY FOR HANDOFF
Implementation source: `WLBLn` — `Section / Theme V2 / 30 Library + Assets`

## 1. Scope

This specification covers the Theme V2 asset library and asset surfaces:

- Library hub and container index
- Todo, Notes, Events, Contacts, and user-created Skill containers
- Asset list, edit, preview, bottom-sheet detail, and full-screen detail states
- The “创建新技能” entry banner

Flash, Goals, Devices, and the cross-product icon mapping system are outside this scope.

## 2. Global Library Shell

- Every Library and Asset screen uses the persistent app top navigation.
- The top navigation follows the existing Theme V2 connected/disconnected variants.
- Remove web-style breadcrumbs and uppercase path labels from rendered app UI.
- The Library hub title is `资产库`.
- Remove the explanatory subtitle below `资产库`.
- The floating Dock remains fixed to the viewport and must not cover scrollable content.
- Full-screen edit and modal states may hide the Dock when the existing shell contract requires it.

## 3. Asset Container Cards

### 3.1 Content

- Container cards show an ordinal only: `01`, `02`, `03`, and so on.
- Remove alphabetic suffixes such as `/ A`, `/ B`, and `/ ACTIVE`.
- A card contains:
  1. ordinal,
  2. container name,
  3. asset count.
- Asset count is always a whole-container total, not a filtered count.

### 3.2 Layout contract

All card sizes use the same internal anchors:

- Outer card corner radius: `14px` for large cards, `10px` for compact rows.
- Large-card padding: `14px`.
- Compact-row horizontal padding: `12px`.
- Ordinal top/left inset: `14px`.
- Count top/right inset: `14px`.
- Name bottom/left inset: `14px`.
- Large-card ordinal: `10px`, Geist Mono, semibold.
- Large-card count: `18px`, Geist Mono, semibold.
- Compact-row count: `14px`, Geist Mono, semibold.
- Large-card name: `20–24px` according to card size.
- Compact-row name: `13px`.
- Adjacent cards use a `6px` gap. Stacked compact rows use an `8px` gap.

Counts must not be visually smaller than ordinals.

### 3.3 Interaction

- Container cards have no persistent selection underline or `ACTIVE` label.
- Default state uses only the card’s surface, border, and typography.
- Pressed state scales to approximately `0.98` and slightly lowers luminance.
- Current location is expressed by the destination screen title, not by keeping the originating card highlighted.

## 4. Recently Generated

- The Hub shows up to the 50 most recently generated Assets.
- Items are ordered newest first.
- The component is one horizontal row.
- On the 411px reference screen, approximately 6 items are visible.
- Overflow uses horizontal scrolling inside the row.
- Do not add pagination, a second row, or a “全部” destination.
- Users discover older Assets through Calendar and their corresponding Asset containers.
- Preserve a minimum `8px` gap between cells and at least `16px` page-side inset.
- The horizontal row must not intercept a clearly vertical page scroll.

## 5. Todo

### 5.1 Tabs

Todo uses four tabs in this order:

1. `全部 {count}`
2. `今天 {count}`
3. `已完成 {count}`
4. `待安排 {count}`

- Every tab shows its total.
- `待安排` is placed last.
- A Todo enters `待安排` when it has neither a date nor a time.
- Tab selection uses a filled or surfaced pill, not an underline.
- The tab row may scroll horizontally if localization or large counts exceed the available width.

### 5.2 Edit preview

- Todo Edit contains a live preview card.
- The preview reflects title, due state, notes summary, and completion/reminder state.
- Empty fields use stable placeholders; the preview must not collapse.
- The preview is visually separated from editable fields and labeled `预览`.

## 6. User-created Skill Edit Preview

- Every user-created Skill Edit screen contains a live preview card.
- The preview uses the Skill’s actual field schema and the same reading hierarchy as its Asset detail.
- Preview values update as fields change.
- The preview is a representation of the pending Asset, not a saved Asset.
- Saving remains the only action that creates or updates the Asset.

## 6.1 Sticky Edit Preview

This contract applies to every Asset Edit screen, including Todo and user-created Skills.

- The live preview is placed immediately below the persistent global top navigation.
- The preview region is sticky while the editable form scrolls beneath it.
- A subtle lower divider or surface separation may indicate that the preview is fixed.
- The preview must never appear below the editable fields.
- The preview keeps a stable height when draft values are empty.
- The screen title and Save/Cancel controls remain reachable and do not scroll behind the preview.

## 6.2 Skill Creation Stepper

Skill creation uses a three-step flow:

1. `描述` — the user describes what they want to record in natural language and may use suggested prompts.
2. `字段` — the user confirms generated field names, field types, human-readable meanings, required state, and order. Fields may be added, removed, or reordered.
3. `卡片` — the user configures the final Asset card using the fixed Theme V2 card skeleton.

Step 3 supports only:

- primary title field,
- summary field,
- up to three supporting fields,
- supporting-field order,
- compact or standard information density.

Step 3 does not support free positioning, arbitrary sizing, or a free-form card builder.

The upper-right settings entry in a user-created Skill container opens Step 3 directly. It edits only the card-display configuration and never changes the field schema.

Saving Step 3 updates the same Skill card presentation in the container list, Recently Generated, and Calendar Asset surfaces.

## 7. Asset Detail Sheets

This contract applies to Todo, Notes, Events, Contacts, and user-created Skill Assets.

### 7.1 Half sheet

- Default presentation is a bottom sheet.
- Reference screen: `411 × 960`.
- Sheet height: `576px`.
- Horizontal content inset: `20px`.
- Long-text preview container: `371 × 120px`.
- Short text may shrink below `120px`.
- Long text is clipped after approximately 5–6 lines with a bottom fade and a `查看全部` action.
- Half-sheet metadata and primary actions remain visible outside the text preview container.
- When an Asset has source attribution, the source row belongs to the sticky footer and sits `8px` above the primary action row.

### 7.2 Full-screen sheet

- Tapping `查看全部` opens the full-screen sheet.
- Reference bounds: `x=0, y=54, w=411, h=906`.
- Long-text container width: `371px`.
- Reference long-text container height: approximately `480px`.
- The container uses the remaining space between fixed metadata/header content and fixed bottom actions.
- Only the long-text container scrolls.
- Title, metadata, tags, and bottom actions remain fixed.
- Source attribution, when present, remains fixed with the bottom actions rather than scrolling with the body.
- Closing the full-screen sheet returns to the same half-sheet and underlying list position.

### 7.3 Responsive constraints

- Half-sheet text container height is capped at `120px`.
- Full-screen text container uses available height with a `320px` minimum.
- On taller devices, the text container expands before adding empty space.
- On shorter devices, preserve header and bottom actions, then reduce the text container to its minimum.

## 8. “创建新技能” Banner Motion

The motion belongs to the Library Hub banner itself, not the later Skill generation workflow.

- A subtle edge glow travels around the banner every `4–6s`.
- Three local particles drift only within the banner’s upper-right region.
- Particle opacity changes gently; particles never spread across the page.
- The left symbol remains stable at rest.
- Press produces one short halo pulse around the left symbol.
- After tap, glow and particles visually converge toward the upper-right arrow before navigation.
- Tap transition duration: approximately `280ms`.
- After prolonged inactivity, reduce motion amplitude and particle opacity.
- Reduce Motion: no particle drift or traveling glow; preserve the static gradient and pressed-state feedback.

## 9. Theme and Accessibility

- Light and Dark use the same component tree.
- Color tokens change by Theme V2; spacing, sizing, and behavior do not.
- Touch targets are at least `44 × 44px`.
- Horizontal scrollers expose an accessible collection name and item position.
- Tab accessible names include their counts.
- `查看全部` announces that it opens a full-screen reading view.
- Motion is decorative and never communicates the only indication of state.

## 10. Data and State Contract

```yaml
library_hub:
  total_asset_count: integer
  total_container_count: integer
  recent_assets: AssetSummary[0..50]

container_summary:
  ordinal: integer
  display_name: string
  asset_count: integer

todo_tabs:
  selected: all | today | completed | unscheduled
  counts:
    all: integer
    today: integer
    completed: integer
    unscheduled: integer

asset_detail:
  presentation: half_sheet | full_screen_sheet
  long_text_overflow: boolean
  text_scroll_offset: number

asset_edit:
  draft_values: map
  preview: AssetPreview
  is_saved: boolean
  preview_position: sticky_top

skill_builder:
  step: describe | fields | card
  description: string
  fields:
    - id: string
      name: string
      type: string
      meaning: string
      required: boolean
      order: integer
  card:
    title_field_id: string
    summary_field_id: string | null
    supporting_field_ids: string[0..3]
    density: compact | standard
```

## 11. Acceptance Criteria

- No Library or Asset app screen renders breadcrumbs or path-eyebrow copy.
- The Library hub has no subtitle below `资产库`.
- Container cards show ordinals without letters or `ACTIVE`.
- Counts meet the typography and inset contract on every container size.
- No container uses an underline as a persistent selected state.
- Recently Generated is one row, shows approximately 6 items at 411px, and can scroll through at most 50.
- Recently Generated has no “全部”, second page, or second row.
- Todo has four count-bearing tabs, with `待安排` last.
- Todo Edit and user-created Skill Edit include live preview cards.
- Every Asset Edit preview is sticky immediately below the global top navigation.
- Skill creation uses the `描述 → 字段 → 卡片` Stepper.
- The container upper-right settings entry opens the existing Skill at Step 3.
- Step 3 uses the fixed card skeleton and cannot modify the Skill field schema.
- Every Asset detail supports half-sheet and full-screen-sheet states.
- Long text uses `371 × 120px` in the half sheet and approximately `371 × 480px` in the full-screen reference state.
- The long text scrolls internally in full-screen state while header, metadata, and actions remain fixed.
- The Skill creation banner has the specified local glow and particle behavior, including Reduce Motion.
- Screenshot regression covers Light and Dark at 411px.

## 12. Canvas Whitelist

Coding agents must read the original nodes inside `WLBLn`. Legacy `UReka · Screen`,
Exploration, and deferred icon-system frames are not implementation sources.

| Surface | Light | Dark |
|---|---|---|
| Hub | `LTmYy` | `c5ejE` |
| Container Index | `B70HCg` | `RTqWK` |
| All Containers | `V0MnR` | `uSlon` |
| Todo List | `qjb6X` | `LQf9o` |
| Todo Detail Half Sheet | `Y2cNU` | `IPSB6` |
| Todo Detail Full Screen | `q6HALg` | `JFSzl` |
| Todo Edit + Preview | `y49fg` | `S5GGTj` |
| Notes Detail Half Sheet | `S75cTq` | `pY8cD` |
| Notes Detail Full Screen | `n9hjm` | `vICpq` |
| Events Detail Half Sheet | `KOUbK` | `y6LAI` |
| Events Detail Full Screen | `KXjw8` | `fJWqy` |
| Contacts Detail Half Sheet | `pi4et` | `H2fqE` |
| Contacts Detail Full Screen | `e9w1M` | `zaq3y` |
| Custom Skill Detail Half Sheet | `zaQiy` | `nCrdm` |
| Custom Skill Detail Full Screen | `t7mkt` | `xl0ra` |
| Custom Skill Edit + Preview | `tAoSU` | `czuBh` |
| Skill Builder · Step 1 Describe | `ezKkD` | `CbV5X` |
| Skill Builder · Step 2 Fields | `LIfKw` | `jkA0G` |
| Skill Builder · Step 3 Card | `XFJNJ` | `j03Vi2` |
