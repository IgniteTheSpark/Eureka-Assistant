# Theme V2 Calendar Revamp Design

> Date: 2026-07-29
> Product source of truth: `spec/design/theme-v2-calendar-handoff.md`
> Visual source of truth: `spec/design/redesignureka.pen`, Section `qIbQZ`
> Scope: Theme V2 Calendar only

## Goal

Replace the current partial Theme V2 Calendar implementation with the single-domain Calendar defined by the new handoff while preserving mature record, editor, and mutation behavior from the existing application.

This round does not redesign Today, Goal, Library, Inbox, Device, Session, or shared shell navigation. Existing changes outside Calendar remain untouched.

## Chosen approach

Use a Calendar-local replacement with adapters to mature business surfaces:

- Keep `/api/timeline`, `/api/skills`, `TimelineItem`, record detail dispatch, `EventForm`, `ContactForm`, and `AssetEditPage`.
- Replace the Calendar overview, Day Detail, Schedule, empty-day flow, Skill Picker, and Calendar-local navigation.
- Keep Calendar child surfaces inside the Calendar destination so the shared Theme V2 floating dock remains visible.
- Push full editors and Flash Session as full routes so they hide the dock.
- Use one widget tree for Light and Dark and style it exclusively with Theme V2 tokens.

The rejected alternatives are:

1. Wrapping the legacy `DayDetailPage`: quicker, but it retains obsolete modes, copy, click rules, and layout.
2. Rewriting Calendar APIs and editor data models: cleaner in isolation, but expands this UI/UX round into backend and entity migrations without product need.

## Source boundaries

Only these design nodes may drive Calendar visuals:

- Flow: `BeBq4`, `J3XydT`, `vjW39`, `n0Eup4`
- Month: `zQK41`, `nMTbd`
- Year: `a6SVbz`, `M0i6f`
- Day Detail: `K1Z2iN`, `fHRmV`, `OncEM`, `anKiT`
- Schedule: `XbCxS`, `IugNo`, `V9LoFM`, `sc1bQ`, `J20Phd`, `sGk5M`
- Manual Record Picker: `LEtWx`, `T1IwgQ`

Old Calendar screens, exploration frames, cached screenshots, `dWO0c`, and `YAu8U` are not implementation references.

## Architecture

### Calendar state

`CalendarController` remains the pure owner of:

- scale: Flow, Month, or Year;
- selected local date;
- Calendar-local surface: overview, Day Detail, or Schedule;
- empty-day manual-record confirmation;
- ephemeral inline Schedule draft;
- draft confirmation state.

The root `ThemeV2CalendarPage` remains mounted during scale changes, refreshes, and Calendar-local navigation. It keeps the `PageController`, Flow scroll state, selected date, and focus month alive.

### Calendar data projection

`CalendarData` continues to materialize the backend Timeline exactly once and bucket by `TimelineItem.effectiveAt`.

Add explicit day projections:

- `assets`: every non-`input_turn` Timeline item;
- `flashes`: every `input_turn`;
- `assetCount` and `flashCount` are independent;
- `allDay`, `untimedTodos`, `timed`, and Day Detail bands derive from the same day projection.

No Calendar code substitutes `created_at` for the backend-computed `effectiveAt`.

### Local date and watermark

Calendar boundaries use device-local calendar fields after the existing `TimelineItem.fromJson(...).toLocal()` conversion.

The formatter returns:

- `TODAY`;
- `N DAY(S) AGO/LATER` for 1–6 local calendar days;
- `N WEEK(S) AGO/LATER` for 7–29 days;
- `N MONTH(S) AGO/LATER` after crossing a stable calendar-month boundary;
- `N YEAR(S) AGO/LATER` after crossing a stable calendar-year boundary.

The app currently has no independent IANA timezone preference. This round therefore uses the device timezone and records “persisted IANA timezone selection” as a product/platform gap rather than adding a backend contract.

### Calendar-local navigation

```text
Overview populated date/date-content blank area
  -> Day Detail(date)

Overview empty date/date-content blank area
  -> show Manual Record confirmation for date
  -> Manual Record
  -> Skill Picker(date)

Day Detail Manual Record
  -> Skill Picker(date)

Day Detail Flash N
  -> existing read-only DayFlashView(date), including N=0

Day Detail Schedule
  -> Schedule(date)

Skill Picker selection
  -> close picker
  -> existing editor adapter(skill, effectiveDate)
```

The Calendar dock stays visible on Overview, Day Detail, and Schedule because these are internal Calendar surfaces. Flash Session and editor pages are pushed routes and cover the dock.

Android back and the visible record/schedule navigation action move to the previous Calendar-local surface before leaving the Calendar destination.

### Manual Record Skill Picker

The Picker loads its own complete Skill definitions from `/api/skills` because Calendar’s lightweight `SkillMeta` registry does not contain schemas.

Picker options:

- add the first-class Event option even though Event is no longer a `UserSkill`;
- include enabled, renderable system and custom Skill definitions;
- exclude `qa`, `external_ref`, and disabled/deprecated choices;
- preserve backend `position` ordering;
- use the first four ordered options for `常用`;
- display the full ordered set under `全部 Skills`.

Selection dispatch preserves the established editor model:

- Event -> `EventForm(presetDate: effectiveDate)`;
- Contact -> `ContactForm`;
- other Skill -> `AssetEditPage(..., presetDate: effectiveDate)`.

“Asset Edit” in the handoff is treated as the product-level editor destination, not a requirement that first-class entities use `AssetEditPage`.

The Picker never calls a create mutation. A record only exists after its editor saves.

### Flow

Flow is one vertically scrolling sequence with two sibling visual layers:

- date rail and divider at the left;
- day content and watermark at the right.

The current date and Flash count move as one sticky unit and are pushed by the next date. Empty dates remain in the sequence.

Populated date labels and unused content space open Day Detail on the first tap. Empty dates reveal the dated Manual Record confirmation on the first tap. No second-tap instructions or quick-create teaching copy remain.

### Month and Year

Flow, Month, and Year remain one horizontally swipeable `PageView` with the existing controller as the single scale state.

Month:

- shows the Progressive Month grid;
- selects a real date on one tap;
- updates the real Asset summary;
- opens Day Detail when the selected day summary/date action is invoked without “tap again” copy.

Year:

- shows 12 real month summaries;
- selecting a month moves to Month scale with that month focused;
- the selected month summary is derived from real Calendar data.

### Day Detail

Day Detail separates Asset and Flash counts.

The top actions are:

- `手动记录`;
- `日程`;
- `闪念 N`, always visible and actionable including `N = 0`.

Assets are shown in morning, afternoon, evening, and omitted-time bands only when the corresponding data exists. The Asset-empty state is based only on `assetCount == 0` and retains all top actions and the dock.

Record taps continue to use the mature detail dispatcher for event, contact, Asset, and source-session fallback.

### Schedule

Schedule keeps the unified header geometry across default, expanded-todo, and inline-draft states.

- All-day tray is absent for zero items and shows the real total otherwise.
- Unscheduled todos are absent for zero items, show 1–3 directly, and use a fixed 92-pixel internally scrollable tray above three.
- Timed events and records keep overlap columns.
- Same-minute todo groups are one independent block alongside other same-time blocks; expanding shows every todo without merging it with neighboring events.
- Todo completion continues to use the existing Asset mutation path.
- Empty hour slots create a 30-minute ephemeral draft.
- A draft displays its explicit start/end time and is not persisted before confirmation.
- Confirming opens the established Event editor; cancel leaves no saved record; editor failure retains a retryable draft.

### Loading, error, and refresh

Initial loading and retry preserve the current Calendar structure instead of replacing the whole destination:

- current scale and selected date remain;
- Flow rail/page title remains;
- shared dock remains;
- content uses stable skeletons.

After the first successful load, refresh uses stale-while-revalidate so the `PageView`, Flow scroll position, selected date, and focus month remain mounted. Errors with previous data keep that data and expose retry feedback.

### Accessibility and motion

- All actions use at least a 44-by-44 semantic hit target.
- Flash semantics are `7月3日，5 条闪念，查看闪念`.
- Skill semantics are `手动记录：{display_name}`.
- Picker background semantics are blocked while the dialog is open and focus enters the sheet.
- Same-time Schedule blocks follow time then left-to-right focus order.
- Selected dates use outline/shape and text, not color alone.
- Scale swipe uses 420 ms fluid snapping when programmatic.
- Rail and inline-draft transitions use 260 ms.
- Picker open uses 260 ms and close uses 160 ms.
- Reduced motion removes overshoot and shortens transitions to simple movement/opacity.

## Compatibility audit

The following mature Calendar behaviors must remain reachable:

- Today reset returns to Flow and the current local date.
- Timeline refresh reacts to `dataRevision`.
- Event, Contact, Asset, and source-session record taps open their existing detail surfaces.
- Event create/edit uses the existing complete-record fetch and editor.
- Contact uses its dedicated form.
- Schema-driven Asset create/edit and preset date remain intact.
- Flash rows remain read-only and open existing Flash/session content without creating a session.
- Todo completion, all-day events, untimed todos, timed overlaps, and 24-hour slot creation remain functional.
- Month/year navigation and horizontal scale gestures remain functional.
- Editor saves trigger existing revision refresh behavior.

Legacy-only presentation concepts—second-tap hints, old Day Detail tabs, “今天记一笔”, mathematical watermarks, quick-create teaching text, and legacy Flow routing—are intentionally removed rather than treated as lost functionality.

## Test strategy

1. Pure tests for day projection, local distance labels, ordering, and inline-draft state.
2. Widget tests for Flow first-tap behavior, empty-day confirmation, Day Detail counts/actions, Picker loading/error/selection, Schedule trays/blocks/draft, refresh persistence, and accessibility.
3. 411-pixel Light/Dark golden coverage for every handoff whitelist state.
4. Static analysis of modified Dart files.
5. Full Theme V2 Calendar test directory.
6. Android debug APK build.
7. Real-device regression through Flow, Month, Year, populated/empty Day Detail, Flash, Picker/editor dispatch, Schedule, draft, refresh, and old-function compatibility checklist.

