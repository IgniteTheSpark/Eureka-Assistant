# Theme V2 Calendar Scale Droplet Design

> Date: 2026-07-29
> Product source of truth: `spec/design/theme-v2-calendar-handoff.md`
> Parent design: `docs/superpowers/specs/2026-07-29-theme-v2-calendar-revamp-design.md`
> Scope: Flow / Month / Year horizontal scale-switch feedback only

## Goal

Refine the existing Calendar scale-switch droplet so it feels like restrained
premium frosted glass and emerges from the user's actual gesture position.

This change does not alter the existing scale-switch thresholds, PageView
navigation, confirmation feedback, Calendar content, or shared shell.

## Chosen approach

Use a Flutter-native layered glass treatment:

- clip the existing edge-attached droplet geometry;
- blur the live Calendar content behind it with `BackdropFilter`;
- add a translucent, brightness-aware surface tint;
- add a fine gradient rim, restrained specular highlight, faint accent
  reflection, and soft ambient shadow;
- keep the overlay isolated in a `RepaintBoundary`.

This approach was chosen over:

1. a fragment shader with physical refraction, which adds compatibility and
   rendering cost beyond the requested restrained material;
2. a paint-only glass imitation, which cannot react to the live background and
   would retain the current flat appearance.

The result should read as frosted glass, not a transparent magnifying lens.
Background content may remain recognizable through blur, but it must not
visibly warp or compete with the scale label.

## Interaction

### Origin and vertical tracking

The droplet begins at the pointer-down Y coordinate local to the Calendar
content viewport rather than at the viewport center.

Once horizontal intent is locked:

- the droplet follows the pointer's vertical movement with damped tracking;
- it applies 60 percent of vertical displacement relative to the pointer-down
  position;
- sub-3-pixel vertical changes are ignored to suppress incidental jitter;
- the rendered center is eased between updates so it feels tethered rather
  than mechanically attached.

The droplet stays inside the Calendar content viewport. Its center is clamped
by half of its current height plus a 12-pixel margin at the top and bottom.
Because the Calendar viewport already sits below the global navigation and
above the floating Dock clearance, this keeps the feedback out of both chrome
regions without hard-coding device coordinates.

Pointer coordinates must use `PointerEvent.localPosition`. Global screen
coordinates must not be mixed with Calendar-local layout coordinates.

### Horizontal behavior

Existing interaction semantics remain unchanged:

- direction is inferred from horizontal displacement;
- the edge bulges after the established activation distance;
- the view name appears at the established label threshold;
- PageView owns commit, cancellation, and page settling;
- successful changes retain the existing short confirmation.

The droplet grows from the active edge while its vertical center follows the
damped gesture position. Releasing or cancelling removes the feedback without
leaving a persistent scale control.

### Reduced motion

When Reduce Motion is enabled:

- remove shape morphing and spring-like vertical interpolation;
- show the static frosted edge label at the clamped current gesture position;
- retain direct position updates and opacity feedback;
- preserve the same navigation and accessibility semantics.

## Visual system

### Shape

Keep the edge-attached waterdrop silhouette and left/right mirroring. The
attachment neck remains flush with the viewport edge. The outer bulge expands
with the existing `shapeProgress`.

The visual stack, back to front, is:

1. soft neutral ambient shadow outside the shape;
2. clipped background blur;
3. translucent Theme V2 surface tint;
4. subtle accent reflection near the attachment edge;
5. broad low-opacity specular wash toward the upper outer curve;
6. one-pixel gradient rim with its strongest highlight on the upper curve;
7. foreground scale label.

### Light theme

- medium background blur;
- approximately 30–36 percent surface tint;
- bright neutral rim at restrained opacity;
- very faint foreground shadow;
- accent reflection remains below the label contrast level.

### Dark theme

- slightly lower surface tint opacity so background depth survives;
- a brighter rim than the base surface but no glowing white outline;
- a deeper neutral shadow and a slightly clearer accent reflection;
- label continues to use the standard Theme V2 foreground token.

Exact alpha values may be tuned against golden and device screenshots. The
relative hierarchy above is the acceptance criterion; hard-coded colors that
bypass Theme V2 tokens are not allowed.

## State and rendering boundaries

Extend Calendar's ephemeral drag feedback with a local vertical center. The
value is initialized on pointer down and updated only while horizontal intent
is active.

Only the overlay should rebuild while the pointer moves. Flow, Month, Year,
their data projections, and the PageView item tree must remain mounted and
must not be rebuilt by vertical droplet tracking.

The path geometry must be shared between clipping and painting so blur, tint,
rim, and hit-independent visual layers cannot drift apart.

## Accessibility

- The droplet remains visual feedback only and does not become a separate
  focusable control.
- The label continues to describe the target scale.
- Glass opacity and blur must maintain readable foreground contrast in both
  themes over dense and empty Calendar backgrounds.
- No meaning relies on the accent reflection or motion alone.

## Performance constraints

- No fragment shader, backdrop snapshot, or full-page image capture.
- Restrict backdrop filtering to the droplet bounds.
- Keep the overlay in a `RepaintBoundary`.
- Do not trigger Calendar data work or PageView child rebuilds per pointer
  update.
- Validate on the existing Android test device and compare frame timing with
  the prior scale-switch baseline.

## Test strategy

1. Widget test that a drag near the top renders the droplet near that local Y.
2. Widget test that a drag near the bottom renders it near the bottom rather
   than the viewport center.
3. Widget test that vertical movement during a horizontal drag changes the
   droplet center by the damped amount.
4. Widget tests for top and bottom clamping.
5. Reduced Motion test for position-aware static feedback.
6. Structural test for clipped `BackdropFilter` glass and repaint isolation.
7. Light/Dark goldens at high and low gesture origins.
8. Existing Calendar scale-switch tests remain green.
9. Static analysis, Calendar test suite, Android debug build, real-device
   interaction, screenshot, and frame-timing verification.

## Acceptance criteria

- The droplet appears where the gesture begins, not at a fixed vertical center.
- It follows vertical finger movement with stable damped motion and no visible
  micro-jitter.
- It never overlaps the global navigation or floating Dock.
- The material reads as restrained frosted glass in Light and Dark themes.
- Scale labels remain legible over real Calendar content.
- Existing scale switching, thresholds, confirmation, and Reduce Motion
  behavior remain intact.
- Device frame timing does not regress perceptibly from the current Calendar
  scale-switch implementation.
