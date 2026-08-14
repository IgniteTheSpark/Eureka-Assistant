# Theme V2 Calendar and Library Dither Background Design

Date: 2026-08-15
Status: Approved for implementation planning

## Summary

Reuse the Today page's dither material across every Calendar view and the full
Library navigation stack. Calendar and Library each render one continuous,
non-interactive background field. Visible foreground content creates local,
constant-strength pressure in that field, making the content feel seated in the
same material system as Today without turning dense information surfaces into
glass panels.

Calendar flows horizontally to suggest time advancing. Library flows downward
to suggest accumulated assets settling. The content pressure never changes in
response to taps, scrolling, dragging, or selection; only source position and
visibility change.

## Goals

- Establish a shared Theme V2 dither material across Today, Calendar, and
  Library.
- Cover every Calendar surface: flow, month, year, day detail, and schedule.
- Cover the full Library stack: hub, container indexes, pinned configuration,
  all containers, and asset lists.
- Let visible content locally displace the field with a stable, uniform
  pressure.
- Preserve Calendar and Library readability, navigation, scrolling, and
  current card hierarchy.
- Keep animation continuous across internal surface transitions.
- Bound shader and layout work on dense pages.

## Non-goals

- No dither inside asset-detail, event-detail, editor, picker, or other bottom
  sheets.
- No new dither interaction. Pointer input remains owned entirely by existing
  page content.
- No pressure boost on tap, drag, scroll velocity, selection, or hover.
- No conversion of Calendar or Library cards into visibly blurred glass.
- No dither-driven changes to content colors, typography, spacing, or
  information architecture.
- No page-specific shader implementation. The pages vary only through shared
  presets and source geometry.

## Chosen Direction

Three directions were compared:

1. Ambient-only field with no content displacement.
2. Local displacement from visible foreground content.
3. Continuous, dense displacement from every page element.

Direction 2 is selected. It preserves the material relationship to Today while
keeping whitespace and card boundaries legible. Empty grid cells, decorative
controls, and offscreen content do not become pressure sources.

## Shared Architecture

### Shared dither primitive

Move the reusable shader-backed primitive out of the Today feature namespace
and expose it as a Theme V2 foundation component:

- `ThemeV2DitherField`
- `ThemeV2DitherFieldConfig`
- `ThemeV2DitherSource`
- `ThemeV2DitherSourceShape`

Today migrates to the shared names without changing its approved visual
behavior. The shader asset and deterministic non-shader fallback remain shared.

### One field per page root

Calendar and Library each own one `ThemeV2DitherSurface` at their page root.
The surface stacks these layers in order:

1. Theme V2 background color.
2. One full-size `ThemeV2DitherField`.
3. Existing page content.

Internal Calendar or Library navigation replaces only layer 3. The dither
surface and its animation controller stay mounted, so phase does not reset when
switching views.

The field is wrapped in `IgnorePointer` and never enters hit testing or
semantics.

### Source reporting

`ThemeV2DitherSourceReporter` is a non-painting wrapper for foreground content.
It reports a stable ID, source shape, priority, and its current rectangle in
surface-local coordinates to `ThemeV2DitherSurfaceController`.

The reporter updates geometry after layout and while scrolling. It unregisters
when disposed or fully outside the viewport. The controller publishes one
bounded, deterministic source list to the page-level shader. Reporters never
create shaders or blur filters.

Source selection is deterministic:

1. Keep priority content such as Today and the selected date.
2. Keep other visible semantic content nearest the viewport center.
3. Break ties by stable source ID.
4. Emit at most 24 sources.

This prevents a dense grid from changing source membership arbitrarily between
frames.

## Calendar Mapping

All Calendar surfaces share the Calendar preset and horizontal flow direction.

### Flow, day detail, and schedule

- Every visible event or Todo card reports one capsule source.
- Card geometry determines capsule width and height.
- Headers, separators, time labels, and navigation controls do not report
  sources.

### Month view

- Visible event strips report capsule sources.
- Today and the selected date each report a circular source.
- Empty dates and dates without displayed content do not report sources.

### Year view

- Each visible month panel reports one aggregated capsule source.
- Individual day cells do not report sources.
- The month containing Today and the selected month receive priority, not
  additional pressure strength.

### Transitions

Changing Calendar scale or opening a day replaces the registered source set but
does not recreate the background field. New geometry takes effect on the next
layout frame without restarting dither phase.

## Library Mapping

All Library surfaces share the Library preset and downward flow direction.

### Hub and container indexes

- Visible container cards report capsule sources.
- Visible recent-asset items report sources matching their rendered shape.
- Navigation labels, section headings, and action buttons do not report
  sources.

### Pinned configuration and all containers

- Visible configurable container rows or cards report capsule sources.
- Drag handles and controls do not add separate sources.

### Asset container and asset list

- Round asset visuals report circular sources.
- Asset rows and rectangular asset cards report capsule sources.
- Only visible list items participate.

Asset-detail bottom sheets and any sheets launched from Library remain on the
ordinary Theme V2 background and surface tokens.

## Visual and Motion Presets

Both presets use the shared foreground color as `waveColor`, four color levels,
and four-pixel dither cells.

### Calendar calm preset

- `pixelSize`: `4`
- `colorNum`: `4`
- `waveAmplitude`: `.24`
- `waveFrequency`: `2.8`
- `waveSpeed`: `.035`
- `flowDirection`: `Offset(1, .08)`
- `opacity`: `.28` in light mode, `.26` in dark mode
- `displacementStrength`: `.84`

### Library settle preset

- `pixelSize`: `4`
- `colorNum`: `4`
- `waveAmplitude`: `.24`
- `waveFrequency`: `2.6`
- `waveSpeed`: `.028`
- `flowDirection`: `Offset(.1, 1)`
- `opacity`: `.28` in light mode, `.26` in dark mode
- `displacementStrength`: `.84`

All content sources use the same normalized pressure energy: `0`. Geometry can
change the area of displacement but not its intensity.

Calendar and Library preserve their current surface colors and alpha values.
This change does not add per-card `BackdropFilter` layers. Dither is expected to
remain most visible in page whitespace and around displaced content edges.

## Lifecycle and Accessibility

- Pause page-level dither animation when its bottom-navigation tab is inactive
  or the app is not resumed.
- Resume from the existing phase rather than rebuilding the field.
- Under Reduce Motion, render phase `0` while retaining the static pattern and
  all content pressure.
- Keep the deterministic painter fallback when fragment shaders are
  unavailable.
- Loading, error, offline, and empty states retain the weak ambient field with
  no content sources unless the state itself contains an approved semantic
  content card.
- Dither remains excluded from semantics and cannot intercept gestures.

## Performance Constraints

- Exactly one dither shader surface per Calendar page and one per Library page.
- At most 24 active pressure sources per page.
- No per-card shader, blur, animation controller, or continuous `setState`.
- Geometry updates are coalesced to one controller notification per frame.
- Source lists use stable IDs and deterministic ordering.
- Offscreen sources are removed before shader uniforms are assembled.

## Testing

### Shared primitive

- Existing Today shader and fallback behavior remains unchanged after the
  namespace migration.
- Calendar and Library presets expose the specified parameters.
- Source selection respects priority, viewport distance, stable-ID tie-break,
  and the 24-source cap.

### Calendar

- Flow, day detail, schedule, month, and year all retain one shared field.
- Each surface reports only the approved source types.
- Month empty dates and Year individual day cells never become sources.
- Switching Calendar surfaces preserves the field state and animation phase.
- Scrolling moves sources without changing their energy.

### Library

- Hub, indexes, pinned configuration, all containers, and asset lists retain
  one shared field.
- Circular and capsule geometry matches rendered asset/container shapes.
- Internal Library navigation preserves the field state and animation phase.
- Asset-detail bottom sheets contain no dither field.

### Cross-cutting

- Light mode uses opacity `.28`; dark mode uses `.26`.
- Reduce Motion freezes phase but retains displacement.
- Inactive tabs and background lifecycle pause animation.
- Loading, error, offline, and empty states render the ambient field safely.
- Existing taps, drags, scrolling, navigation, and semantics remain unchanged.
- Device QA covers a dense Calendar day, Month and Year transitions, a dense
  asset list, Library internal navigation, light/dark mode, and Reduce Motion.

## Acceptance Criteria

- Every approved Calendar and Library surface visibly shares the Today dither
  material at a calmer intensity.
- Visible semantic content locally pushes the field at one uniform strength.
- Calendar moves horizontally; Library settles vertically.
- Internal navigation and scrolling produce no full-field reset or mechanical
  refresh.
- Dense pages remain readable and never exceed 24 pressure sources.
- Bottom sheets remain unchanged.
- The feature introduces no additional interactive layer and no per-card blur
  cost.
