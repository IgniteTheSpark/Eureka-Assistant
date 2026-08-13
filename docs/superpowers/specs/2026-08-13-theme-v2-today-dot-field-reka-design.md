# Theme V2 Today Dot Field and Draggable Reka Design

> Date: 2026-08-13
>
> Status: Approved design; awaiting written-spec review
>
> Product surface: Theme V2 Today / Light / experimental empty scene
>
> Reference behavior: ReactBits `Dot Field`

## 1. Outcome

Replace the current passive dot-matrix Reka experiment with a native Flutter dot-field scene built around one small interaction loop:

```text
drag Reka
→ nearby dots deform according to drag speed
→ release returns dots to their anchors
→ Reka resumes a local breathing cycle
→ orange eyes appear during exhalation
→ tap still opens Reka quick actions
```

This design supersedes the visual and interaction behavior in `spec/design/docs/superpowers/specs/2026-08-13-theme-v2-today-dot-experiment-design.md`. The existing experiment flag, Light-only evaluation boundary, refresh flow, shell routing, and three quick actions remain in force unless this document changes them explicitly.

The work remains a minimal device-feedback loop. It does not reconnect schedule, signals, asset balls, or other active Today content. It does not add Dark Mode or apply the treatment to other pages.

## 2. Product Principles

- The dot field is the visual material of the page, not an information visualization.
- Reka belongs to the same material instead of appearing as an unrelated illustration laid over it.
- Motion communicates presence and touch. It must not compete with Today content or resemble a game effect.
- Only dragging Reka affects the field. Touching or swiping empty background does not.
- The scene must feel calm when untouched and responsive when dragged.
- Reka's expression is eyes only. No mouth, emote, speech animation, sparkle, or glow is added.

## 3. Scope and Rollout

The current compile-time experiment remains the entry seam:

```text
--dart-define=TODAY_DOT_EXPERIMENT=true
```

When disabled, the current production `ThemeV2HomePage` remains unchanged. When enabled, Today renders the revised Light experimental scene.

In scope:

- native Flutter dot-field simulation and painting;
- draggable Reka;
- speed-sensitive local dot deformation;
- light inertia, soft edge attraction, and spring return;
- local idle breathing;
- exhale-timed orange eyes;
- existing Reka quick actions;
- existing pull-to-refresh behavior;
- Reduce Motion behavior;
- widget, simulation, Golden, and real-device verification.

Out of scope:

- active Today schedule, Reka signals, and asset balls;
- global wave motion;
- direct background interaction;
- cross-restart Reka-position persistence;
- mouth or additional expressions;
- sparkle, glow, rainbow, or colored gradients;
- WebView, React, Canvas UI, or new rendering packages;
- Dark Mode and other pages.

## 4. Interaction State Model

Reka has three mutually exclusive motion states.

### 4.1 Idle breathing

After the scene becomes stable, Reka runs a slow breathing loop of approximately `5.2 s`.

- Inhale: the organic dot silhouette expands slightly and the eyes remain hidden.
- Exhale: the silhouette relaxes, nearby dots move softly outward, and the orange eyes fade in.
- Before the next inhale: the eyes fade out so their appearance feels tied to exhalation rather than permanently painted.
- Only the Reka-local region moves. The rest of the field stays anchored.

The breathing influence is approximately `120 logical px` around the Reka center. The exact curve may be tuned on device, but it must have no loop seam and no abrupt phase transition.

### 4.2 Dragging

Drag recognition starts only inside Reka's hit target. Empty background does not register a dot-field gesture.

When drag begins:

- breathing pauses;
- eye opacity moves toward zero;
- Reka follows the pointer within its safe movement bounds;
- recent drag velocity becomes the deformation engagement value;
- nearby dots move away from the Reka center with a smooth distance falloff;
- faster movement creates stronger displacement up to a fixed cap.

The touch target remains at least `64 × 64 logical px`, even when the visible dithered silhouette is smaller or locally sparse.

### 4.3 Release and settling

On release:

- Reka carries a small amount of bounded inertia;
- the final center is softly attracted toward an eligible nearby edge rather than snapping;
- dots spring back toward their original anchors with damping;
- Reka stays fully visible and outside the title, Dock, system insets, and other reserved chrome;
- idle breathing resumes only after the field has settled.

The dropped position is retained while the Today scene remains mounted. It is not persisted across application restarts in this tranche.

### 4.4 Tap versus drag

A tap inside the Reka target continues to open the existing three-action menu. A movement threshold separates tap and drag so a short touch does not move Reka and a completed drag does not open the menu.

The three actions remain:

1. Create Asset;
2. Create Report;
3. Start New Chat.

## 5. Visual Contract

The scene keeps the approved Light surface and restrained brand palette:

| Element | Treatment |
|---|---|
| Surface | warm gray-green, approximately `#E3EAE5` |
| Base dots | low-contrast gray-green |
| Reka dots | slightly darker and denser than base dots |
| Eyes | warm orange-red, approximately `#C6532F` |
| Foreground text | existing Today Light foreground token |

Reka starts near the middle-left of the usable scene rather than near the bottom. Placement adapts to the viewport and keeps a safe distance from the Today heading and Dock.

The visible Reka body is an approximately `90 px` asymmetric soft silhouette created from the same dot field through dot radius, density, color, and displacement changes. It has no solid fill, circular outline, card, halo, or imported image.

The two eyes are short orange dot clusters. They are the only expression layer and only become prominent during exhalation.

The drag influence radius begins near `160 logical px`. Maximum displacement is capped so the matrix never looks torn or chaotic. Exact radius, falloff, damping, dot interval, and maximum displacement are device-tuning values rather than new product settings.

Explicitly excluded visual treatments:

- full-screen or continuous wave;
- random sparkle;
- cursor glow;
- color cycling or gradient animation;
- a mouth or additional facial features;
- direct feedback when the user touches empty background.

## 6. Architecture and Component Boundaries

The implementation stays native to Flutter and extends the current experiment instead of embedding a web renderer.

```text
TodayDotExperimentPage
└── TodayDotMatrixScene
    ├── TodayDotFieldController
    ├── TodayDotFieldSimulation
    ├── TodayDotFieldPainter
    ├── TodayRekaGestureTarget
    └── TodayRekaQuickActions
```

### 6.1 `TodayDotExperimentPage`

Retains repository lifecycle, pull-to-refresh, route callbacks, failure feedback, and experiment composition. It has no knowledge of individual dots or motion equations.

### 6.2 `TodayDotMatrixScene`

Owns responsive scene geometry, ticker lifecycle, app/page activity, Reduce Motion selection, and the bridge between gestures and the controller.

### 6.3 `TodayDotFieldController`

Owns the high-level interaction state:

- Reka normalized position;
- pointer samples and drag velocity;
- idle, dragging, or settling state;
- breathing phase;
- eye opacity;
- safe movement bounds.

The controller exposes stable values to the simulation and painter without knowing repository or navigation state.

### 6.4 `TodayDotFieldSimulation`

Owns reusable per-dot state:

- anchor position;
- current displacement or rendered position;
- velocity when required by the settling model.

It applies local drag bulge, damping, anchor return, idle breathing, resize rebuilds, and displacement caps. It uses deterministic stepping so behavior can be tested without wall-clock timing.

### 6.5 `TodayDotFieldPainter`

Paints the surface, base dots, Reka-local treatment, and eyes. It contains no gesture recognition, route handling, or repository behavior.

The painter draws in one `RepaintBoundary`, does not create a Widget per dot, and does not allocate a new dot collection on every frame.

### 6.6 `TodayRekaGestureTarget`

Owns hit testing, tap/drag arbitration, semantic labeling, and pointer cancellation. Its geometry is derived from the same scene model used to paint Reka so the visible object and interactive target cannot drift apart.

## 7. Data and Motion Flow

### Drag

```text
pointer starts inside Reka target
→ scene pauses breathing and hides eyes
→ pointer samples update Reka center and filtered velocity
→ controller publishes engagement and center
→ simulation displaces nearby dots with capped falloff
→ painter draws the updated field
```

### Release

```text
pointer ends or cancels
→ controller enters settling
→ bounded inertia and edge attraction update Reka center
→ simulation damps dots toward anchors
→ settle thresholds are reached
→ controller enters idle and resumes breathing
```

### Breathing

```text
idle ticker advances normalized breath phase
→ inhale/exhale curves update local silhouette and field displacement
→ exhale curve controls eye opacity
→ painter draws only the resulting values
```

### Resize

```text
viewport changes
→ scene recomputes safe bounds
→ normalized Reka position maps into the new bounds
→ dot anchors rebuild once
→ current state resumes without placing Reka under reserved chrome
```

## 8. Performance and Lifecycle

- Use one canvas-based painter rather than thousands of Widgets.
- Reuse dot state and drawing objects across frames.
- Avoid per-frame list rebuilding and unnecessary object allocation.
- Keep the field inside a dedicated `RepaintBoundary`.
- Stop animation ticks when Today is inactive, the route is obscured, or the app is paused.
- Rebuild dot anchors only when size, dot radius, or spacing changes.
- Cap simulation delta time after lifecycle interruptions so a resumed frame cannot produce an unstable jump.
- Tune density and influence radius in profile mode on the target Android device before broadening the experiment.

The design starts with `CustomPainter` because the existing experiment already uses it and the ReactBits reference is itself a per-dot Canvas simulation. A fragment shader and WebView implementation are intentionally rejected for this tranche.

## 9. Accessibility and Reduced Motion

Reka exposes:

```text
name: Reka 快捷操作，可拖动
role: button
state: collapsed / expanded
```

The hit target remains at least `64 × 64 logical px` and respects text scaling and safe insets.

With Reduce Motion enabled:

- breathing stops;
- release inertia and edge glide are disabled;
- drag follows directly with small, immediate local deformation;
- dots do not run a prolonged spring animation;
- eyes remain quietly visible so Reka stays identifiable;
- the quick-action menu uses the product's reduced-motion transition.

No semantics are attached to individual dots.

## 10. Error and Edge Handling

- Gesture cancellation enters a stable settle or immediate stop; it cannot leave Reka in a dragging state.
- App pause and route deactivation stop ticks and clear active pointer state.
- A zero-sized or not-yet-laid-out scene skips simulation safely.
- Resize preserves normalized Reka position and clamps it into new safe bounds.
- Very fast or sparse pointer samples are filtered and capped before they reach the simulation.
- Repeated refresh requests remain coalesced by the page's existing refresh lifecycle.
- Refresh failure preserves the scene and existing retry feedback.
- Quick-action route failures remain isolated from the dot simulation.
- No network or external asset is required to render the dot field or Reka.

## 11. Verification

### Unit tests

- deterministic inhale, exhale, and eye-opacity phases;
- drag speed maps monotonically to deformation engagement until the cap;
- local falloff affects nearby dots and leaves distant dots at their anchors;
- settling returns dots within the defined tolerance;
- inertia and edge attraction remain bounded;
- resize preserves normalized Reka position;
- Reduce Motion produces a static idle state and minimal direct drag response.

### Widget tests

- dragging starts only inside Reka's target;
- touching or swiping empty background does not deform the field;
- movement below threshold opens quick actions as a tap;
- movement above threshold drags without opening quick actions;
- drag, release, settle, and resumed breathing transition in order;
- eye visibility occurs during exhale and not inhale or active drag;
- route/page deactivation stops the ticker;
- semantics expose the combined button and draggable description;
- pull-to-refresh and its failure path remain functional.

### Golden tests

Capture at minimum:

1. idle inhale;
2. idle exhale with orange eyes;
3. active drag deformation;
4. release/settling state;
5. Reduce Motion idle state.

The primary reference viewport remains `411 × 860`, with one taller device Golden to validate safe placement.

### Real-device validation

On the target Android device, inspect:

- drag latency and hit-target confidence;
- whether fast and slow movement produce meaningfully different but controlled deformation;
- spring return without jitter or oscillation;
- initial placement and edge attraction;
- breathing loop naturalness;
- eye appearance at exhale without reading as an alert;
- sustained profile-mode frame timing and memory stability;
- pull-to-refresh and quick actions after repeated drag cycles.

## 12. Acceptance Checklist

- [ ] The experiment remains opt-in and the current Home remains unchanged when disabled.
- [ ] Reka starts in the middle-left safe region rather than near the bottom.
- [ ] Only a drag that starts on Reka affects the dot field.
- [ ] Empty background has no direct interaction.
- [ ] Drag speed controls a capped local bulge.
- [ ] Release returns dots to their anchors and leaves Reka in a safe resting position.
- [ ] Idle Reka creates a restrained local breathing field.
- [ ] Orange eyes appear during exhale and are hidden during inhale and drag.
- [ ] Reka has no mouth, sparkle, glow, or additional expression.
- [ ] Tap still opens the existing three quick actions.
- [ ] Reduce Motion removes breathing, inertia, and prolonged settling.
- [ ] Pull-to-refresh and recoverable failure feedback remain intact.
- [ ] Animation stops when Today is inactive.
- [ ] Real-device performance and visual feel are reviewed before any Dark Mode or other-page expansion.

## 13. Follow-up Boundary

Only after this loop is approved on device should the project consider:

1. reconnecting active Today content over the field;
2. deriving and reviewing a Dark Mode treatment;
3. deciding whether the dot material should appear on any page other than Today;
4. persisting Reka's resting position across application restarts.
