# Theme V2 Reka Capture, Agenda, Calendar Flow, and Seed Motion Design

**Date:** 2026-08-15  
**Status:** Approved design, pending written-spec review  
**Scope:** Theme V2 Today Reka capture feedback, Next schedule capsule, in-page Today Agenda, Calendar Flow content surfaces, and Signal/Asset seed travel timing

## 1. Authority and boundaries

This document extends the existing capture-activity and Today living-surface
designs. It is authoritative for:

- how the existing capture phases affect Reka while Today is visible;
- the layout and alignment of the compact Next schedule capsule;
- the information shown for each minute group in the in-page Today Agenda;
- stable content and empty-day surfaces in Calendar Flow;
- distance-based timing for Signal and Asset production seeds.

The intermittent red flash observed during Asset-seed descent is explicitly
deferred until its timing can be reproduced and captured. This tranche may slow
the same animation but must not claim to fix that flash without a confirmed root
cause and a dedicated regression path.

## 2. Capture state as one source of truth

Reka consumes the active `CaptureActivitySnapshot` already owned by
`CaptureActivityCoordinator`. No duplicate loading flags, timers, workflow
states, or string parsing are added to Today.

Only the coordinator's selected active capture drives Reka. Queued captures
remain represented by the Top Bar's `另有 N 条` count and do not create competing
Reka motions. Returning to Today during an active capture immediately renders
the latest trusted phase rather than replaying earlier phases.

The existing phase and terminal dwell contracts remain unchanged:

| Capture phase | Reka response |
| --- | --- |
| `listening` | Eye pixels rise and fall like a restrained level meter; the head holds an attentive forward posture. |
| `receiving` | Eye pixels travel from the outer edges toward the center; the head leans subtly toward the capture source. |
| `transcribing` | Eye pixels scan in ordered rows; the head remains steady so this reads as transcription, not searching. |
| `understanding` | The head makes a slow alternating thinking tilt while the eyes contract and expand toward the center. |
| `organizing` | The head gradually returns upright while eye pixels settle into an ordered grid. |
| `done` | One short upward acknowledgement and a brighter terminal-green eye pulse. |
| `empty` | Eyes resolve into two short horizontal lines, then return to idle. |
| `failed` | One restrained two-beat head shake; the eyes remain terminal green and communicate failure through shape and rhythm rather than introducing a red error face. |

Capture feedback is additive to Reka's existing behavior with explicit
ownership rules:

1. Direct dragging owns head orientation and position; capture continues to
   affect the eyes.
2. Signal or Asset production temporarily owns the directional head turn used
   for the handoff.
3. The active capture phase supplies the underlying eye/work posture and
   resumes fully after the production handoff.
4. When no capture is active, the current idle, drag, and production behavior
   remains unchanged.

The Top Bar remains the canonical textual status. Reka adds ambient embodied
feedback and does not render phase text or another progress indicator.

## 3. Compact Next schedule capsule

The compact schedule entry remains in the date row and remains tappable in both
populated and empty states. It changes from three vertically stacked text rows
to one aligned two-column composition.

```text
14:30        客户回访 +2
32 分钟后                 ›
```

- The capsule's right edge uses the same horizontal content gutter as the
  Signal and Asset dither containers. Independent magic right offsets are not
  allowed.
- The left column has a stable width and displays the start/due time above the
  countdown.
- The right column expands to the remaining width and displays the first
  canonical title on one line.
- If the same minute contains more items, the title is followed by `+N`, where
  `N` excludes the visible first item.
- The chevron belongs to the right column and never creates a third information
  row.
- Event remains ordered before Todo when both share a minute, matching the
  existing canonical Next grouping.
- The empty state keeps the same capsule bounds and shared right alignment.
- Semantics continue to expose the complete time, countdown, titles, and group
  count even when the visible title truncates.

The date keeps priority on compact widths. The capsule may reduce title width,
but its minimum 44 logical-pixel hit target and the shared right edge remain
stable.

## 4. In-page Today Agenda

Opening the compact schedule entry continues to replace the living Today scene
locally; it does not push a route or open the full Calendar page.

Agenda content is grouped by displayed minute. Each minute has one timeline
node and one group card. The group card lists every supported Event and Todo at
that minute in canonical order.

Each row contains:

- the canonical Event or Todo icon;
- the full item title, truncated only when the available row width requires it;
- the existing completed treatment for completed Todos;
- its existing tap action to the canonical Event or Todo detail.

The current generic dot marker is removed. A grouped card does not stop after
three rows and does not hide remaining items behind an unexplained count. The
Agenda viewport becomes vertically scrollable when all minute groups do not fit
in the available space. Same-minute rows share one time label instead of
repeating the time on every item.

The current fixed five-slot fishbone layout is replaced by one chronological
vertical timeline. A compact time column sits at the left, a thin spine and node
sit beside it, and each minute-group card consumes the remaining width on the
right. The current-time marker remains on the same spine. This preserves card
width for icons and titles and makes every group reachable through one vertical
scroll direction.

## 5. Distance-based seed motion

The current 1,440 ms animation devotes only about 51% of its progress to actual
travel, making the visible movement roughly 734 ms regardless of distance.
Signal and Asset seeds instead use distance-based travel timing.

- Formation/charge: 300 ms.
- Travel velocity target: 280 logical pixels per second.
- Travel duration clamp: 1,200–2,400 ms.
- Handoff/unfold/recovery: 350 ms.
- Signal and Asset use the same velocity contract; their durations differ only
  because their destinations are different distances from Reka.
- Existing start-at-Reka-side, Signal-upward, Asset-downward, trail, and handoff
  semantics remain intact.
- Phase callbacks are derived from segment boundaries rather than hard-coded
  fractions of one fixed total duration.

Reduce Motion keeps the current short non-travel handoff and is not stretched
to the full distance-based duration.

## 6. Calendar Flow content surfaces

### 6.1 Confirmed presentation issue

Calendar Flow records currently report each row as a dither pressure source but
do not paint a durable row or day background. The nearest scrollable seen by a
row reporter is the nested non-scrolling list inside a day, not the outer Flow
scroll. The pressure registration therefore retains stale viewport coordinates
while the day moves, which makes the apparent light background drift away and
disappear.

The approved solution is visual option A: one opaque content surface per date,
not one floating card per Event or Asset row.

### 6.2 Populated date surface

Every populated date paints one `tokens.surface` background at full opacity
behind all of that date's supported records.

- The surface uses the standard medium radius, a stable one-pixel border, and
  internal padding shared by all time bands.
- Morning, afternoon, evening, and untimed labels remain inside the same date
  surface.
- Individual records remain lightweight rows with separators where needed;
  they do not gain independent card borders or shadows.
- The date rail remains outside the surface and retains selection, Flash, and
  count behavior.
- Tapping a record continues to open that record. Tapping unused surface space
  continues to activate the date.
- Dither remains visible around the opaque date surface and may deform at its
  boundary, but it never substitutes for the content background.

The nested `NeverScrollableScrollPhysics` list is replaced by non-scrollable
content layout so the date surface's dither registration observes the real
outer Flow scroll. Flow uses one pressure source for the date surface rather
than one source for every record row. The painted surface and its pressure
geometry therefore move together.

### 6.3 Empty date surface

An empty date keeps the same footprint and interaction but separates clearly
from the dither field:

- full-opacity `tokens.surface` background;
- 1.25 logical-pixel border using `tokens.muted` at 45% opacity in light mode
  and 55% in dark mode;
- diagonal hatch using `tokens.muted` at 24% opacity in light mode and 30% in
  dark mode;
- the existing nine-pixel hatch spacing;
- the same radius and bounds when it changes into the Manual Record
  confirmation.

The stronger hatch and border must remain subordinate to real record text but
must be readable without relying on the dither pattern beneath it.

### 6.4 Calendar scope

This change applies to Calendar Flow only. Month, Year, Day Detail, and Schedule
retain their existing content structures and shared dither background behavior.

## 7. Lifecycle and error behavior

- Reka capture animation pauses when Today is inactive, the app is backgrounded,
  or Reduce Motion disables continuous movement.
- Phase changes morph from the current pose; they do not reset the WebView or
  recreate the 3D object.
- A failed or empty capture uses only its existing coordinator dwell and then
  returns to the next queued capture or idle.
- Seed animation continues to pause/resume with lifecycle state and completes
  its coordinator handoff exactly once.
- The deferred red flash investigation must compare a real WebView Reka run
  against the fallback Reka and must separately isolate seed travel from the
  Asset physics handoff before any fix is proposed.

## 8. Verification

Automated coverage must prove:

- every `CaptureActivityPhase` maps to a stable Reka visual state;
- capture state uses the shell coordinator snapshot and survives leaving and
  returning to Today;
- drag orientation remains responsive while capture controls the eyes;
- production direction temporarily overrides capture posture and restores it;
- the capsule shares the dither-container right edge at supported phone widths;
- time/countdown occupy the left column and title/`+N` occupy the right column;
- same-minute counts use `+N` excluding the visible title;
- Agenda minute groups render Event and Todo icons and titles;
- more than three same-minute items remain reachable;
- multiple minute groups scroll in chronological order;
- each populated Flow date paints one opaque surface that remains attached
  during slow drag, fling, threshold crossing, and far scrolling;
- Flow uses one moving dither pressure source per populated date rather than per
  record row;
- individual Flow records retain their independent tap targets without gaining
  independent card chrome;
- empty Flow dates use the approved light and dark border/hatch contrast;
- empty placeholder and Manual Record confirmation retain identical geometry;
- seed travel duration grows with distance and respects the duration clamps;
- handoff and completion callbacks still fire exactly once;
- Reduce Motion retains the short handoff.

Device verification on the connected Android phone must cover all five active
capture phases plus the three terminal phases, compact and grouped schedule
states, a scrollable Agenda with mixed Event/Todo rows, populated and empty
Calendar Flow dates through a long scroll, and both upward and downward seed
travel. The red flash is recorded as unresolved unless it is reproduced with
diagnostic evidence during that verification.

## 9. Non-goals

- no changes to capture, upload, ASR, Agent, retry, or persistence workflows;
- no new global loading state outside `CaptureActivityCoordinator`;
- no phase text, emoji, or icon displayed on Reka;
- no redesign of Calendar Month, Year, Day Detail, or Schedule views;
- no claim that slower seed motion fixes the deferred red flash;
- no changes to Signal or Asset data identity and reconciliation rules.
