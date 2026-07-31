# Theme V2 — Remove Goals and Adjust Home

Status: approved design

Date: 2026-07-31

Design file: `redesignureka.pen`

## 1. Decision

Goals are removed completely from the current product and implementation scope.

The current release must not expose, route to, calculate, store, suggest, or reserve a visible placeholder for Goals. This is not a feature-flagged feature and not a partially implemented module.

Home keeps the internal ability to host two layers in the future, but the current runtime renders only Today. The second layer is `null`, invisible, and non-interactive until a separate product decision defines its content.

## 2. Goals

- Remove all Goal product UI and runtime logic from the current implementation.
- Promote Today to the full Home content position.
- Preserve a generic, dormant secondary-layer boundary without exposing it.
- Keep Goal design work as archived reference rather than an implementation source.
- Prevent legacy Goal naming inside unrelated Skill Builder layers from misleading coding agents.

## 3. Non-goals

- Choosing the future content of Home’s second layer.
- Replacing Goals with Inbox, notifications, insights, or another feature.
- Implementing a disabled Goal state, teaser, placeholder, or “coming soon” screen.
- Adding a Goal feature flag.
- Removing ordinary user-authored text that happens to contain the word “目标”.

For example, a Todo titled `更新个人目标` remains valid user content and is not part of the Goal product module.

## 4. Canvas source and archive boundary

### Current implementation source

`PYuZt` — `Section / Theme V2 / 40 Today / Implementation Source`

Current Home production screens:

| State | Light | Dark |
|---|---:|---:|
| Today default | `WsOyv` | `PMCdg` |
| Today Agenda / Fishbone | `vRy65` | `J5cpE` |

### Archive only

The following content moves under an `ARCHIVE · DO NOT IMPLEMENT` boundary:

- `N0ehb` — `Section / Theme V2 / 41 Goals`
- `SuznI` — Light Home Goals Layer
- `BNmyJ` — Dark Home Goals Layer
- Goal Setting screens
- All Goals screens
- Goal Detail and adjustment screens
- Goal-specific interaction specifications

Archived screens must not appear in coding handoffs, screen whitelists, golden-test targets, routes, or implementation phases.

`VvGFs` must stop describing Today/Goals switching. It should be replaced by the current single-surface Home contract and a note that the secondary-layer slot is dormant.

## 5. Home architecture

Use a generic Home layer container:

```ts
type HomeLayerState = {
  primary: HomeSurface
  secondary: HomeSurface | null
}

const currentHomeLayers: HomeLayerState = {
  primary: todaySurface,
  secondary: null,
}
```

Current rendering rules:

- Render `primary` as the full Home surface.
- When `secondary === null`, do not render a back plate, exposed header, count, arrow, switch, edge affordance, or placeholder.
- Do not attach horizontal layer-switch gestures.
- Do not reserve visible space for a future secondary surface.
- Do not expose an accessibility element for the absent surface.

Future reactivation of two-layer behavior requires an approved secondary surface and a separate implementation change.

## 6. Home geometry

Reference viewport: 411 × 960.

### Fixed shell

- Status Bar: `x=0, y=0, w=411, h=44`
- Dock: unchanged at `x=121, y=865, w=169, h=60`
- Home indicator: unchanged

### Today surface

Promote the Today panel from:

```text
x=8, y=104, w=395, h=740
```

to:

```text
x=8, y=54, w=395, h=790
```

This applies to:

- Light Today default
- Dark Today default
- Light Today Agenda
- Dark Today Agenda

The panel bottom remains at `y=844`, so the Dock relationship does not change.

## 7. Removed Home elements

Delete or disable these elements in production Today screens:

- `Goals Back Page / Exposed Header`
- visible `目标` page title
- active/scheduled Goal counts
- bring-forward arrow
- Today/Goals two-layer switch
- Home kicker that refers to Goals
- horizontal page-switch gesture
- Goal edge reveal
- Goal switching animation

There must be no invisible hit target left behind after the visual element is removed.

## 8. Today default state

The Today panel’s internal content keeps its relative order:

1. Today title and summary
2. Next Moment
3. Reka Queue
4. Asset bubble field

Behavior after promotion:

- Title, Next Moment, and Reka Queue move upward with the panel.
- The asset bubble field gains the reclaimed vertical space.
- Dock position and bubble interactions remain unchanged.
- The full Today surface remains vertically stable when Goal data is absent because Goal data is no longer part of the view model.

## 9. Today Agenda state

The Agenda panel uses the same promoted geometry:

```text
x=8, y=54, w=395, h=790
```

Rules:

- Keep the Agenda title and collapse action at the panel top.
- Give the fishbone/agenda viewport the reclaimed 50 px.
- Keep the generated-asset chamber pinned near the panel bottom.
- Do not simply move the entire bottom chamber upward with the panel.
- Extend the available agenda region between the header and generated-asset chamber.
- Light and Dark share identical geometry and state transitions.

The Agenda expand/collapse interaction remains. Only the cross-layer Home gesture is removed.

## 10. Reka Queue

The Home queue must exclude all Goal-derived items:

- Goal progress
- Goal settlement
- Goal deadline
- Goal check-in reminder
- Goal adjustment
- Goal suggestion
- Goal creation CTA

Queue totals and empty states are calculated from the remaining supported item types.

If Goal was the only item:

- render the standard non-Goal empty queue state;
- do not render an explanatory Goal-removal message;
- do not preserve an empty Goal slot.

## 11. Navigation and routes

Do not register:

- Goal list
- Goal history
- Goal creation
- Goal success
- Goal detail
- Goal adjustment
- Goal progress/guardrail detail

Remove Goal entry points from:

- Home
- Library
- Asset detail
- Skill detail
- Session results
- notifications
- global navigation

Legacy Goal deep links should resolve to Home without showing an error or partial Goal screen.

## 12. Data and service boundary

The current implementation does not include:

- Goal model
- Goal repository
- Goal API client
- Goal database tables or migrations
- Goal progress calculation
- Goal background jobs
- Goal notification scheduling
- Goal cache
- Goal-specific analytics events

Assets and Skills must not contain required Goal foreign keys or Goal-derived presentation state.

No compatibility adapter is needed for a feature that has not shipped. If an existing development branch contains Goal prototypes, remove them from production registration and current implementation plans.

## 13. Skill Builder naming cleanup

Skill Builder remains in scope and its visible behavior does not change.

Several canvas layers use historical `Goal...` names while displaying Skill creation UI. Rename these internal layers to Skill terminology, including:

- `Goal Setting Header` → `Skill Builder Header`
- `Goal Step Segment` → `Skill Step Segment`
- `Goal Step Label` → `Skill Step Label`
- `Goal Natural Language Input` → `Skill Natural Language Input`
- `Goal Direction` → `Skill Example Direction`
- `Goal Agent Note` → `Skill Agent Note`
- `Generate Goal Draft` → `Generate Skill Draft`
- `Confirm and Create Goal` → `Confirm and Create Skill`
- `Redescribe Goal` → `Return to Fields` or the current visible Skill action

This is a layer/code naming cleanup only. It must not alter the approved three-step Skill Builder behavior.

## 14. Documentation boundary

Current coding handoffs and plans must:

- remove Goal implementation phases;
- remove Goal screens from production whitelists;
- remove Goal route and service requirements;
- describe Home as Today-only at runtime;
- retain the generic dormant secondary-layer interface only where Home architecture is documented.

Goal-specific design documents remain stored as archive references and must be clearly marked `ARCHIVE · DO NOT IMPLEMENT`.

## 15. Accessibility

- The absent secondary layer has no focusable or announced elements.
- Horizontal layer-switch gestures are unavailable to touch, keyboard, and assistive technology.
- Today becomes the Home screen’s single accessibility route.
- Focus order begins with Today content after the Status Bar.
- Removing Goal queue items must not leave incorrect list positions or totals.
- Agenda expand/collapse retains its existing accessible state and label.

## 16. Error and fallback behavior

- A legacy Goal deep link returns to Home.
- Stale local navigation state requesting the second layer resolves to Today.
- A stale Goal queue payload is filtered before rendering.
- Goal API failures cannot affect Home because no Goal request is issued.
- Home loading, empty, and error states depend only on supported Today data.

## 17. Testing

### Visual regression

Update 411 × 960 Light and Dark goldens for:

- Today default
- Today Agenda / Fishbone

Verify:

- Today panel starts at `y=54`
- Today panel height is `790`
- no Goal header is visible
- no layer switch is visible
- Dock position is unchanged
- Agenda bottom chamber remains bottom-aligned

### Interaction

- horizontal drag does not switch Home layers;
- tapping the former Goal-header region does nothing because no hit target exists;
- Agenda expand/collapse still works;
- back navigation returns to Today;
- legacy Goal deep links return to Home.

### Content and domain

- no production navigation label references the Goal module;
- no Goal-derived Reka item renders;
- Goal routes and services are absent from registration;
- ordinary user content containing `目标` remains unchanged;
- Skill Builder works after internal naming cleanup.

## 18. Acceptance criteria

- [ ] Current Home renders Today only.
- [ ] The dormant secondary layer is invisible and non-interactive.
- [ ] Today default and Agenda panels use `x=8, y=54, w=395, h=790`.
- [ ] Dock remains at `x=121, y=865, w=169, h=60`.
- [ ] No Goal header, count, arrow, switch, gesture, or edge reveal remains.
- [ ] Reka Queue contains no Goal-derived item.
- [ ] Goal routes, models, services, jobs, cache, and notifications are outside the implementation.
- [ ] Goal canvas work is archived and excluded from coding sources.
- [ ] Goal references are removed from current handoffs and implementation phases.
- [ ] Skill Builder’s historical Goal layer names are renamed without changing behavior.
- [ ] User-authored text containing `目标` is preserved.
- [ ] Light/Dark visual and interaction tests pass.
