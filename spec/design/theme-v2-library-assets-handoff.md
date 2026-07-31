# UReka Theme V2 — Library + Assets Coding Handoff

Status: implementation source

Updated: 2026-07-29

Reference viewport: 411 × 960

Design file: `redesignureka.pen`

Canonical canvas section: `WLBLn` — `Section / Theme V2 / 30 Library + Assets`

## 1. Source of truth

Coding agents must use `WLBLn` as the only visual source for Library and Assets. Screens outside this section may be historical explorations and must not override this document or the screens listed below.

The implementation covers:

- Library hub and container directories
- Todo, Notes, Events, Contacts
- User-created Skill containers and their assets
- Asset list, detail, edit, empty, loading, and error states
- Skill Builder
- Asset-card presentation across Library, Calendar, and Session surfaces

This handoff does not redefine Calendar navigation, Session conversation UI, Goals, devices, or other product domains. Those surfaces only consume the shared asset-card variants described here.

Priority when implementation details conflict:

1. Current node inside `WLBLn`
2. This handoff
3. Shared Theme V2 tokens/components
4. Older documents or screens

## 2. Screen whitelist

All production surfaces need Light and Dark implementations from the same component tree.

| Surface | Light node | Dark node |
|---|---:|---:|
| Library Hub | `LTmYy` | `c5ejE` |
| Container Index | `B70HCg` | `RTqWK` |
| All Containers | `V0MnR` | `uSlon` |
| Configure Pinned | `rssuX` | `PnnTE` |
| Todo List | `qjb6X` | `LQf9o` |
| Todo Detail / Half Sheet | `Y2cNU` | `IPSB6` |
| Todo Detail / Full Screen | `q6HALg` | `JFSzl` |
| Todo Edit + Sticky Preview | `y49fg` | `S5GGTj` |
| Notes List | `pj81S` | `uFlEY` |
| Notes Detail / Half Sheet | `S75cTq` | `pY8cD` |
| Notes Detail / Full Screen | `n9hjm` | `vICpq` |
| Notes Edit | `l044V` | `fM6Bv` |
| Notes Empty | `d7Nb2` | `x75LG` |
| Events List | `vf4Tt` | `n1PvZ2` |
| Events Detail / Half Sheet | `KOUbK` | `y6LAI` |
| Events Detail / Full Screen | `KXjw8` | `fJWqy` |
| Events Edit | `eE8EP` | `lJuFW` |
| Events Empty | `Q9KqmR` | `bdkVg` |
| Contacts List | `xDehC` | `B0KY8` |
| Contacts Detail / Half Sheet | `pi4et` | `H2fqE` |
| Contacts Detail / Full Screen | `e9w1M` | `zaq3y` |
| Contacts Edit | `U49Ou` | `w6TRZl` |
| Contacts Empty | `I42u1B` | `Xf7MI` |
| Custom Skill List | `VLz4P` | `sfoYs` |
| Custom Skill Detail / Half Sheet | `zaQiy` | `nCrdm` |
| Custom Skill Detail / Full Screen | `t7mkt` | `xl0ra` |
| Custom Skill Edit + Sticky Preview | `tAoSU` | `czuBh` |
| Custom Skill Empty | `QxKHh` | `fBs3J` |
| Skill Builder / Describe | `ezKkD` | `CbV5X` |
| Skill Builder / Fields | `LIfKw` | `jkA0G` |
| Skill Builder / Card | `XFJNJ` | `j03Vi2` |
| Asset Card Family Comparison | `F863Sc` | shared specification frame |

## 3. Shared shell

### 3.1 Top navigation

- Library and Asset screens use the persistent app top navigation.
- Do not render breadcrumbs, path labels, or web-style navigation trails.
- The Library hub title is `资产库`.
- Do not add explanatory subtitle copy below `资产库`.
- Detail and edit screens use native back/close actions shown in the corresponding reference screen.

### 3.2 Bottom navigation

- The floating Dock is fixed to the viewport and respects the bottom safe area.
- Scroll content must include enough bottom inset to remain fully reachable above the Dock.
- Full-screen editors, modal builders, and full-screen sheets may hide the Dock where shown by the reference screen.

### 3.3 Layout baseline

- Reference viewport: 411 × 960.
- Default horizontal page inset: 18–20 px, matching the referenced screen.
- Minimum interactive target: 44 × 44 px.
- Preserve the same information hierarchy on narrower devices; do not introduce a desktop layout or breadcrumbs.

## 4. Theme V2 tokens

Use semantic tokens. Do not branch component markup between Light and Dark.

| Token | Light | Dark |
|---|---|---|
| `theme-v2/bg` | `#F7F9FC` | `#0B0D12` |
| `theme-v2/surface` | `#FFFFFF` | `#121620` |
| `theme-v2/fg` | `#101319` | `#F3F5FA` |
| `theme-v2/muted` | `#6D7480` | `#8991A0` |
| `theme-v2/border` | `#D9E0E8` | `#29303D` |
| `theme-v2/accent` | `#25B6D6` | `#8A82FF` |
| `theme-v2/accent-soft` | `#E9F8FC` | `#1A1D35` |
| `theme-v2/critical` | `#D23A57` | `#FF5F7B` |
| `theme-v2/font-primary` | Geist | Geist |
| `theme-v2/font-mono` | Geist Mono | Geist Mono |

Spacing: 4, 8, 12, 16, 24 px.

Radius: 7, 10, 14, pill.

Motion: 160 ms fast, 260 ms standard, 420 ms fluid.

Fluid easing: `cubic-bezier(0.22, 1, 0.36, 1)`.

## 5. Library hub

### 5.1 Container area

- Pinned containers appear above `最近生成`.
- Container order is managed by `Configure Pinned`.
- A container tile displays:
  - numeric ordinal only, for example `01`
  - container name
  - total asset count
- Do not append letters or status labels to the ordinal.
- Do not use an underline as selected state.
- Pressed feedback uses a subtle scale near `0.98` plus a small luminance change.

Container sizing contract:

| Variant | Radius | Padding | Count size | Name size | Gap |
|---|---:|---:|---:|---:|---:|
| Large tile | 14 | 14 | 18 | 20–24 | 6 between tiles |
| Compact row/tile | 10 | 12 horizontal | 14 | 13 | 8 vertical |

For a large tile, keep ordinal at top-left, count at top-right, and name at bottom-left. Both top values use a 14 px inset.

### 5.2 Recently Generated

- Query the newest 50 assets, ordered descending by creation time.
- Render one horizontally scrolling row.
- At 411 px, approximately six items are visible.
- Each item is the `IconTime` asset variant: asset mark plus time only.
- Do not render a second row.
- Do not paginate.
- Do not add an `全部` route from this module; users reach complete data through Calendar or the corresponding asset container.
- Preserve the row’s current scroll position when returning from an asset detail.

## 6. Container index and directories

- System containers: Todo, Notes, Events, Contacts.
- User-created Skills appear as a separate group.
- Search filters both groups locally from the same query.
- Directory rows show container name and total count with the exact spacing of `B70HCg` / `RTqWK`.
- Counts must remain legible and must not be reduced to caption-sized decorative text.
- `Create New Skill` opens Skill Builder Step 1.

Loading and failure behavior:

- Initial load: use the entity-list skeleton pattern.
- Empty search result: use entity empty state with a clear reset action.
- Fetch failure: use entity error state with retry.
- Do not replace failures with an indefinite skeleton.

## 7. Todo container

Todo uses four pill tabs:

1. `全部`
2. `今天`
3. `已完成`
4. `待安排`

Rules:

- Every tab includes its total count.
- `待安排` remains the last tab.
- A Todo is `待安排` when it has neither a date nor a time.
- Tabs scroll horizontally if the width is insufficient.
- Selected state is a filled/tinted pill, never an underline.
- Switching tabs preserves each tab’s own scroll position during the current session.
- Completing an item updates counts and list membership immediately; rollback and show feedback if persistence fails.

## 8. Asset-card family

The complete comparison is in canvas node `F863Sc`. Implement shared variants rather than one universal card stretched across every context.

| Consumer surface | Variant | Visible content |
|---|---|---|
| Calendar Flow | `MinimalRow` | time + Skill name + primary field |
| Calendar Month | `MinimalLine` | Skill name + primary field |
| Calendar Day | `RichCard` | primary field + up to 3 secondary fields |
| Schedule all-day / unscheduled | `MinimalRow` | Skill name + primary field |
| Library Recently Generated | `IconTime` | asset mark + time |
| Asset container | `RichCard` | primary field + up to 3 secondary fields |
| Session result | `RichCard` | primary field + up to 3 secondary fields |

Suggested component API:

```ts
type AssetCardVariant =
  | 'minimalRow'
  | 'minimalLine'
  | 'richCard'
  | 'iconTime'

type AssetCardProps = {
  variant: AssetCardVariant
  asset: Asset
  display: CardDisplayConfig
  onOpen?: () => void
  disabled?: boolean
}
```

### 8.1 RichCard contract

The canonical preview is:

- Light: `jnzig`
- Dark: `mLJBp`
- Custom Skill Edit preview: `kasqW` / `F1CJIJ`

Internal order:

1. Asset/Skill mark on the left
2. Primary field value on the first text row
3. Divider below the primary field
4. Up to three secondary values on the second text row

Critical geometry:

- The divider belongs to the right-hand text column.
- It must not extend under or through the left mark.
- Secondary values are separated by ` · `.
- Each secondary value has its own maximum width and truncates with `…`.
- Render no more than three secondary values.
- Do not render an empty separator.
- Hide fields that were not selected.
- If no secondary field has a value, omit the divider and secondary row; vertically center the primary title in the available text area.
- The label `实时预览` is outside the card, not inside its surface.

The 411 px Skill Builder preview uses:

- outer x: 18
- width: 375
- height: 96
- card radius: 16
- mark: 44 × 44
- text column begins at x = 76 relative to the card
- divider begins at the text column and ends at its right edge

The Custom Skill Edit preview uses:

- outer x: 20
- width: 371
- height: 86
- mark: 40 × 40
- same semantic hierarchy as the Builder preview

### 8.2 MinimalRow

- Single compact row.
- Do not display the RichCard divider or second-row metadata set.
- Use the context-provided time only where the surface requires it.
- Primary field is single-line and truncates with `…`.
- The entire row is one open-detail target.

### 8.3 MinimalLine

- Designed for the constrained Month view.
- Show Skill name and primary field only.
- Single line, no divider, no secondary fields.
- Truncate before changing cell height.

### 8.4 IconTime

- Used only by `最近生成`.
- Show asset mark and localized time.
- Do not show title, secondary fields, or a mini RichCard.
- The complete tile remains tappable.

## 9. Card display configuration

`CardDisplayConfig` controls RichCard content:

```ts
type CardDisplayConfig = {
  primaryFieldId: string
  secondaryFieldIds: string[] // ordered, length 0...3
}
```

The configuration UI is:

- Light: `G9jdFw`
- Dark: `i05EBj`

Behavior:

- List every schema field exactly once.
- Each field row shows field name, type, and meaning.
- One field is selected as the primary title using a single-choice control.
- Eligible fields use toggles for secondary information.
- Maximum secondary selection is three.
- Toggle activation order is display order:
  - first enabled → secondary position 1
  - second enabled → position 2
  - third enabled → position 3
- Turning off a selected field removes it and compacts the remaining sequence.
- The primary field cannot also be a secondary field.
- When three secondary fields are active, disable the remaining eligible toggles until one is removed.
- Do not add drag ordering.
- Do not ask users to type field names into this configuration.
- Do not add a separate density choice or arbitrary layout editor.

Reducer-level behavior:

```ts
selectPrimary(fieldId):
  primaryFieldId = fieldId
  secondaryFieldIds = secondaryFieldIds.filter(id => id !== fieldId)

toggleSecondary(fieldId):
  if fieldId === primaryFieldId: return
  if fieldId is selected: remove it and preserve remaining order
  else if secondaryFieldIds.length < 3: append it
```

The preview updates immediately and never waits for final save.

The top-right settings action inside an existing asset container opens this same Step 3 editor in configuration mode. It edits presentation only; it does not modify the Skill schema.

## 10. Asset edit screens

- Todo Edit and Custom Skill Edit must both show a live asset preview.
- The preview sits directly below the persistent header and remains sticky while the form scrolls.
- Use a stable preview height to prevent scroll jumps as values change.
- The preview uses the same `RichCard` renderer as Day, container, and Session surfaces.
- Editing a display field updates the preview immediately.
- Validation errors belong to their fields and must not replace or cover the preview.
- Keyboard appearance must keep the focused field and primary action reachable.

## 11. Asset detail sheets

Every asset type supports:

1. default half-height bottom sheet
2. expanded full-screen sheet

### 11.1 Half sheet

Reference at 411 × 960:

- sheet height: 576 px
- horizontal inset: 20 px
- rounded top corners and drag handle
- body scrolls only when necessary
- source information and bottom actions form one sticky footer region
- source information sits 8 px above the primary action row

The user can expand via the visible expand action or the supported sheet gesture.

### 11.2 Full-screen sheet

Reference geometry:

- x: 0
- y: 54
- width: 411
- height: 906

Rules:

- Header, core metadata, source, and actions remain fixed.
- Long content scrolls inside its dedicated text container.
- Closing returns to the same half-sheet state and preserves the underlying list scroll position.
- Back navigation from the half sheet returns to the exact source container and filter.

## 12. Long-text contract

Applies to Notes and any asset field or remark that can contain long text.

### Half-sheet preview

- Text container width: 371 px.
- Text container height: 120 px.
- Show approximately 5–6 lines.
- Clip overflow and provide a bottom fade where appropriate.
- Show `查看全部` only when content actually overflows.

### Full-screen reading

- Text container width: 371 px.
- Target height at 411 × 960: about 480 px.
- Minimum height on smaller devices: 320 px.
- Flex height to use available space between fixed header/metadata and fixed source/actions.
- Only the text container scrolls.
- Preserve paragraph breaks and selectable text.
- Do not expand the entire page height to fit unbounded content.

Accessibility:

- `查看全部` announces the field name and expansion result.
- Focus moves to the full-screen title or text-container heading after expansion.
- Closing restores focus to `查看全部`.

## 13. Skill Builder

Skill creation is a three-step, single-flow stepper:

1. Describe
2. Fields
3. Card

Do not collapse the flow into one large form.

### 13.1 Step 1 — Describe

- Ask the user to describe in natural language what they want to record.
- Provide a small set of example directions that populate or guide the prompt.
- Primary action generates a draft schema.
- Keep user input if generation fails and provide retry.

### 13.2 Step 2 — Fields

For every proposed field, show:

- name
- data type
- meaning
- required/optional status
- order

Users can:

- rename
- change type
- edit meaning
- toggle required
- add or remove
- reorder fields

The meaning is implementation data: it helps the agent extract and validate the correct value.

### 13.3 Step 3 — Card

- Show the external `实时预览` label followed by the live RichCard.
- Show the field-selector panel below the preview.
- Use the selection and ordering rules in section 9.
- Final confirmation creates the Skill and saves `CardDisplayConfig`.
- Re-entering from a container’s top-right settings action opens this step with the current configuration preloaded.

### 13.4 Builder navigation

- Back preserves completed step data.
- Close asks for confirmation only if there are unsaved changes.
- A saved draft may resume at the last incomplete step.
- Primary action remains above the bottom safe area.
- Step transitions use standard motion; do not slide the whole app shell.

## 14. Create New Skill banner motion

The banner is a persistent entry, not an autoplaying decorative takeover.

Idle:

- soft glow pulse every 4–6 seconds
- glow remains close to the banner boundary
- three subtle particles appear near the upper-right region
- particles drift a short distance and fade

Pressed:

- halo intensity increases briefly
- surface compresses subtly

Tap transition:

- particles converge toward the arrow/action point
- duration: approximately 280 ms
- then navigate to Skill Builder Step 1

Reduced motion:

- no particle travel
- no continuous pulsing
- use a static accent wash and standard pressed-state color change

The effect must not obscure text, lower contrast, intercept touches, or run while the banner is off-screen.

## 15. Shared components

Prefer these reusable design nodes as implementation boundaries:

| Purpose | Node |
|---|---:|
| Library section label | `hkM16` |
| Container tile | `KVpWp` |
| Add Skill tile | `h6u6A` |
| Todo list row | `qm6YN` |
| Todo completed state | `bZ0Vq` |
| Todo empty state | `WsPyF` |
| Detail field | `e41h1R` |
| Editor field | `i5YO9j` |
| Todo complete action | `kaBXq` |
| Notes tags | `Mi2HF` |
| Notes detail body | `A8P0PF` |
| Long-content expand control | `N9eHU` |
| Entity empty state | `h8eH8e` |
| Entity list skeleton | `e9GnBq` |
| Entity error state | `PVxNz` |
| Contact monogram | `B88N5` |
| Contact social row | `M6PMGq` |
| Schema field row | `TeMRy` |
| Skill Builder prompt | `CoN6F` |
| Skill preview panel | `J9aAIS` |

Recommended code boundaries:

- `LibraryShell`
- `LibraryHub`
- `ContainerDirectory`
- `AssetContainerScreen`
- `AssetCard`
- `AssetDetailSheet`
- `AssetEditScreen`
- `LongTextViewer`
- `SkillBuilder`
- `CardFieldSelector`

## 16. Data contracts

The UI should be schema-driven so system and user-created Skills share the same pipeline.

```ts
type AssetFieldDefinition = {
  id: string
  name: string
  type: 'text' | 'number' | 'date' | 'time' | 'boolean' | 'enum' | 'url'
  meaning: string
  required: boolean
  order: number
}

type AssetSkill = {
  id: string
  name: string
  fields: AssetFieldDefinition[]
  display: CardDisplayConfig
}

type Asset = {
  id: string
  skillId: string
  createdAt: string
  updatedAt: string
  values: Record<string, unknown>
  source?: {
    type: string
    label: string
  }
}
```

Rendering rules:

- Missing primary value falls back to the Skill name plus a localized untitled label.
- Missing secondary values are skipped without leaving separators.
- Unknown fields remain stored but are not rendered until included in the active schema/display configuration.
- Date and time formatting uses the user locale and timezone.
- Counts use the backend’s filtered total, not the number currently loaded in the client page.

## 17. Interaction, state, and navigation

| Trigger | Result |
|---|---|
| Tap pinned container | Open its asset list |
| Tap `全部容器` | Open All Containers directory |
| Tap Recently Generated item | Open asset half sheet |
| Tap asset list/card | Open asset half sheet |
| Expand detail | Open full-screen sheet |
| Tap edit | Open editor with sticky preview where applicable |
| Tap container card settings | Open Skill Builder Step 3 in configuration mode |
| Tap Create New Skill | Open Skill Builder Step 1 |
| Save asset | Update list/card/counts and return to prior context |
| Delete asset | Confirm, delete, close detail, update counts |

State preservation:

- Preserve list filter, tab, and scroll offset when opening/closing detail.
- Preserve half-sheet state when returning from full screen.
- Optimistic mutations must rollback on failure.
- Avoid duplicate saves by disabling the primary action while a request is pending.

## 18. Accessibility

- Minimum touch target: 44 × 44 px.
- Text and controls must meet WCAG AA contrast.
- Asset cards expose a combined accessible label: Skill, primary value, visible secondary values, and time if shown.
- Counts are announced with their tab/container name.
- Radio and toggle semantics in Card Display Settings must be native and screen-reader discoverable.
- Disabled secondary toggles explain that the maximum of three has been reached.
- All sheets trap focus while open and restore focus on close.
- Dynamic preview updates should not be announced on every keystroke; announce the saved configuration or user-triggered selection changes.
- Support Dynamic Type without hiding primary actions; long labels truncate only after accessible full text remains available.

## 19. Implementation order

1. Create semantic Theme V2 token bindings and `LibraryShell`.
2. Implement the four `AssetCard` variants and snapshot/golden tests.
3. Implement Library Hub, container tiles, and Recently Generated.
4. Implement container directories and shared loading/empty/error states.
5. Implement Todo tabs and state transitions.
6. Implement the shared half/full `AssetDetailSheet` and long-text viewer.
7. Implement schema-driven edit screens with sticky preview.
8. Implement the three-step Skill Builder and Card Display Settings.
9. Connect container card settings directly to Step 3.
10. Add Light/Dark visual regression tests and accessibility tests.

## 20. Acceptance checklist

### Shell and navigation

- [ ] Persistent app top navigation is present where specified.
- [ ] No breadcrumbs or Library subtitle are rendered.
- [ ] Dock never covers reachable content.
- [ ] Back/close returns to the prior filter and scroll position.

### Library and containers

- [ ] Container ordinals contain digits only.
- [ ] Container counts are legible and use the specified spacing.
- [ ] Selected/pressed state does not use an underline.
- [ ] Recently Generated loads at most 50 newest assets.
- [ ] Recently Generated is one horizontal row with about six items visible at 411 px.
- [ ] Recently Generated has no pagination, second row, or `全部` entry.

### Todo

- [ ] All four tabs show totals.
- [ ] `待安排` is last.
- [ ] Undated and untimed Todo assets appear in `待安排`.
- [ ] Tab selection uses a pill state, not an underline.

### Asset cards

- [ ] Each consuming surface uses the mapped card variant.
- [ ] RichCard divider starts after the left mark and stays inside the text column.
- [ ] RichCard shows at most three secondary values.
- [ ] Secondary values use ` · ` separators and per-item ellipsis.
- [ ] Missing values do not leave empty separators.
- [ ] `实时预览` is outside the preview card.
- [ ] Day, container, and Session use the same RichCard renderer.

### Details and long text

- [ ] Every asset type opens a half sheet and can expand full screen.
- [ ] Source and actions remain sticky at the bottom.
- [ ] Half-sheet long text is 371 × 120 at the reference viewport.
- [ ] `查看全部` appears only on overflow.
- [ ] Full-screen text scrolls inside a dedicated container.

### Skill Builder

- [ ] Step 1 collects natural-language intent and offers examples.
- [ ] Step 2 supports field name, type, meaning, required status, and order.
- [ ] Step 3 lists every field once.
- [ ] Exactly one primary field can be selected.
- [ ] No more than three secondary fields can be toggled.
- [ ] Secondary order follows toggle activation order.
- [ ] Existing container settings open Step 3 with saved values.
- [ ] Preview updates live and stays above settings.

### Quality

- [ ] Light and Dark use one semantic component tree.
- [ ] Loading, empty, error, pending, and retry states are implemented.
- [ ] Touch targets and contrast pass accessibility checks.
- [ ] 411 × 960 golden tests match the whitelisted canvas nodes.
