# Today Outline-Free Reka, Robot Eyes, and Top Dock Design

**Date:** 2026-08-13
**Status:** Approved
**Scope:** Theme V2 Today page, light mode only

## Goal

Refine the current Today-page dot-field experiment so Reka feels like a living rise in the matrix rather than a separate white ball, give it restrained old-school robot eyes, and make the top navigation use the same floating-surface language as the bottom dock.

## Non-goals

- Do not change Calendar, Assets, Capture, or other Theme V2 pages.
- Do not introduce Reka outside the Today page.
- Do not redesign dark mode in this iteration.
- Do not add new Reka gestures, facial features, or interactive background behavior.
- Do not change device, theme, notification, or bottom-dock actions.

## Approved Visual Direction

### Outline-free Reka rise

The current bounded circular radial gradient is replaced by multiple offset, soft-edged light fields. The fields overlap around the Reka center but do not produce a closed circular silhouette. The result must read as the dot surface swelling toward the viewer rather than as a separate ball.

The configured black glow remains supported, but it is rendered as a broad, low-opacity environmental shadow. It must not form a dark ring around the white rise. `cursorRadius` continues to describe the size of the active Reka rise, while `glowRadius` controls only the wider shaded area.

### Old-school robot eyes

Each eye is a 3 by 3 warm-orange LED matrix. The central LEDs are brightest and the corner LEDs are dimmer, giving each eye the character of a small retro display module. The design has no eyelids, lashes, brows, mouth, face outline, or optical-lens detail.

The eyes use the existing eye-opacity signal:

- They fade in as the idle breathing rise approaches its brightest phase.
- They fade out while the rise falls.
- They remain hidden throughout dragging.
- Reduced-motion mode keeps the existing stable low-motion presentation and must not add a new repeating animation.

### Floating top dock

On the Today page in light mode, the full-width top navigation surface becomes one floating dock. It uses a 16 dp horizontal inset, a 60 dp content height, an 18 dp corner radius, and the same light surface, border, elevation, and shadow language as the bottom dock.

The dock retains the existing UReka wordmark, device entry, theme toggle, and notification action in their current order. Existing semantics, minimum touch targets, unread indicator, menu behavior, and narrow-screen behavior remain intact.

The dot field remains continuous behind the top region and is visible around all four sides of the dock. The existing full-width bottom divider is removed in this variant. Today content receives a floating-top-dock-aware inset so headings, drag bounds, and quick actions cannot overlap the dock.

Dark mode and all other pages keep the existing top-navigation presentation.

## Component Boundaries

### `TodayDotMatrixPainter`

- Paints the broad ambient glow.
- Paints the outline-free white rise using layered, offset gradients.
- Paints the two 3 by 3 LED matrices from the existing Reka center and eye opacity.
- Does not own animation timing or gesture state.

### `TodayDotFieldController` and simulation

No new controller or simulation state is introduced. Existing breathing amount, eye opacity, motion state, drag engagement, and reduced-motion signals remain the single source of truth.

### `ThemeV2GlobalTopNav`

Adds an explicit floating-dock presentation rather than inferring it from transparency. The default full-width presentation remains unchanged. The floating presentation exposes a stable outer extent so content layout can account for its top margin and height.

### `ThemeV2AppShell` and Today scene

The app shell enables the floating presentation only when the continuous light Today scene is active. The Today scene uses the floating extent for content placement and drag clamping. Other shell destinations and capture chrome continue to use the standard top-navigation height.

## Data and Interaction Flow

1. The existing controller produces Reka center, motion state, breath amount, and eye opacity.
2. The simulation deforms the dot field around the same center.
3. The painter renders the ambient shadow, white rise, and LED eyes from those values.
4. Dragging updates the center and motion state exactly as it does today; the painter hides the eyes during that state.
5. The app shell selects either the standard navigation or Today-only floating presentation without changing navigation actions.

No network, persistence, or asynchronous error path is added by this change.

## Responsive and Accessibility Requirements

- Preserve at least the existing minimum touch target for every top-dock action.
- Keep the dock inside horizontal safe space at the supported 360 dp minimum width.
- Prevent logo, device state, theme toggle, notification badge, and system text scaling from causing overflow at supported widths.
- Preserve all existing semantic labels and selection behavior.
- Ensure Today content and Reka drag bounds remain below the floating dock.
- Preserve reduced-motion behavior and avoid introducing flashing LED effects.

## Verification

- Painter tests confirm the outline-free rise uses layered soft fields and the eyes render as two 3 by 3 matrices.
- Motion-state tests confirm eyes are visible only at the intended breathing phase and hidden while dragging.
- Top-navigation widget tests confirm the standard and floating variants have separate geometry and that actions and semantics remain available.
- App-shell tests confirm only light-mode Today enables the floating variant.
- Golden tests cover idle, bright-eye, dragging, reduced-motion, narrow-width, and tall-device Today states.
- Regression tests confirm dark Today and non-Today destinations retain the existing navigation presentation.
- A production build and physical-device pass verify breathing, eye fade, dragging, quick-action anchoring, top-dock spacing, and device-menu positioning.

## Acceptance Criteria

1. Reka has no visible circular edge or dark outline at any breathing phase.
2. The white rise remains spatially clear enough to drag and still uses the configured cursor and glow radii.
3. At the bright breathing phase, two warm-orange 3 by 3 robot-eye modules appear; they fade with the current eye-opacity signal and disappear during dragging.
4. Today light mode shows one floating top dock with dot matrix visible around it.
5. The top and bottom docks share surface, border, radius, elevation, and shadow language without requiring equal width.
6. Existing top navigation actions, accessibility labels, notification badge, and device menu continue to work.
7. Other pages and dark mode are unchanged.
