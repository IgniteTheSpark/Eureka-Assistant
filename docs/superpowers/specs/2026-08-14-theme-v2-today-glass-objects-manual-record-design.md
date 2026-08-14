# Theme V2 Today Glass Objects and Manual Record Design

**Date:** 2026-08-14

## Goal

Calibrate the approved Today living surface without changing its information architecture:

- make the complete `Reka 发现` and `Reka 生成` watermarks reliable navigation entries;
- give each signal strip and asset bubble a very faint, color-related frosted-glass body while preserving the surrounding Dither response;
- align both watermark labels symmetrically around the seam between the signal and asset regions;
- replace Reka's `创建资产` quick action with `手动记录`, using the exact Calendar Flow manual-record picker and editor path.

## Watermark interaction and seam alignment

`TodayRegionWatermark` owns one semantic button and one opaque gesture target around its complete visual group. The count and label no longer have separate pointer behavior: tapping either opens the same destination. The hit rectangle remains tightly bounded to the watermark group so it does not take over the surrounding signal lanes or asset physics field.

The label is always the watermark element nearest the container seam:

- signal region: count above, `Reka 发现` below;
- asset region: `Reka 生成` above, count below.

Both use the same 8 px seam inset. The visual reading remains left/right staggered, but the two labels sit at equal vertical distance from the seam.

## Object-level frosted glass

The Dither fields remain container backgrounds. Signal strips and asset bubbles gain their own translucent body above the Dither layer.

### Signal strips

Signal colors are type-driven:

- `overdue`: warm red;
- `rhythm_gap`: cyan;
- `report`: violet;
- fallback: brand blue.

Each pill clips a grouped backdrop blur with a low sigma and adds a very low-alpha type color. Light mode stays especially faint; dark mode uses slightly more opacity to remain legible. The pill keeps no visible border or shadow. Text and icon contrast continue to use Theme V2 foreground/muted tokens.

### Asset bubbles

Each bubble reuses its existing outline palette as its glass tint. A shared `BackdropGroup` lets all moving bubbles use `BackdropFilter.grouped` rather than independent backdrop passes. The current thin outline remains, and the circle gains only a faint translucent fill. No new shadow is introduced.

The compact grid uses the same visual component and therefore receives the same fill behavior.

### Motion and accessibility

Glass is purely visual. It does not change Dither displacement, collision bodies, signal movement, touch targets, or Reduce Motion behavior. Existing foreground tokens remain responsible for readable content.

## Reka manual-record quick action

The quick-action label changes from `创建资产` to `手动记录`.

Selecting it runs the same production flow as Calendar Flow:

1. open `showCalendarManualRecordPicker`;
2. load options with `fetchCalendarSkillCatalog`;
3. use the current local day as `effectiveDate`;
4. pass the selected `CalendarSkillOption` to `openCalendarSkillEditor`.

No Today-specific picker, fallback catalog, or editor router is introduced. Loading, recent Skills, full catalog, failure, retry, selection, and editor behavior remain owned by the Calendar implementation.

The shared orchestration is exposed as a small Calendar helper so Today and Calendar cannot drift while retaining test seams at the Shell boundary.

## Testing

- watermark widget tests tap both count and label and expect the same callback;
- signal tests verify all type colors receive a faint glass body while item opening and scrolling behavior remain intact;
- asset tests verify the glass fill and existing outline coexist without breaking physics taps or drag targets;
- quick-action and Shell tests verify the label is `手动记录` and the shared manual-record callback is invoked;
- Calendar manual-record tests remain the contract for picker loading, retry, selection, and modal behavior;
- Today goldens are refreshed for light and dark appearance;
- focused Flutter analysis and the Today/Calendar/Shell regression suites must pass before device installation.

## Non-goals

- changing Dither parameters or flow direction;
- changing signal or asset data models;
- creating a new asset-type picker;
- changing the Calendar manual-record Bottom Sheet;
- changing report or chat quick actions.
