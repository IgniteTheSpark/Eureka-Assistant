# Today Continuous Dot Field and Reka Bulge Design

**Date:** 2026-08-13
**Branch:** `首页-revamp`
**Status:** Approved direction, pending implementation plan

## Goal

Turn the Theme V2 Today experiment into one continuous native Flutter dot field that runs behind the Top Nav, content, Dock surroundings, and bottom safe area. Reka is no longer a separate dark dot cluster. Reka is the white convex bulge rising out of the field, with orange eyes inside it and a soft black glow around it.

The parameter contract mirrors every current React Bits Dot Field prop so the effect remains tunable and documented, while the implementation stays native Flutter. Reference: [React Bits Dot Field](https://reactbits.dev/backgrounds/dot-field).

## Product Decisions

- Apply this treatment only to the light Today experiment.
- Do not add dots to Calendar, Library, Dark Mode, or other routes.
- Use one continuous coordinate space from the top of the safe area to the bottom.
- Make the Today Top Nav transparent so the field remains visible behind its controls.
- Keep the floating Dock capsule white and opaque; the area around and below it remains part of the dot field.
- Keep Reka draggable. A drag must begin inside the Reka bulge target; dragging the empty field does nothing.
- Keep the three existing Reka quick actions and anchor them to Reka's live position.
- Preserve pull-to-refresh, recoverable refresh errors, tab lifecycle behavior, and Reduce Motion.

## Visual Model

The field is painted in this order:

1. Paint the light green-gray Today surface.
2. Paint the base dots using a subtle brand-neutral diagonal gradient.
3. Displace dots locally around Reka using the configured bulge and cursor values.
4. Paint a low-opacity black radial glow within `glowRadius`.
5. Paint a white radial highlight within `cursorRadius`, creating a convex raised surface rather than a separate ball.
6. Paint orange eyes inside the white highlight when the idle breathing glow is strong enough.

The white convex region is Reka. There is no additional dense dark sphere. During idle, its height and glow breathe gently. During drag, the bulge follows the pointer while the eyes remain hidden to prevent expression flicker. On release, Reka uses the existing bounded inertia and edge attraction, then resumes breathing. Reduce Motion removes breath, global wave, sparkle animation, inertia, and prolonged spring settling while preserving a calm identifiable bulge and faint eyes.

## React Bits Parameter Contract

Create an immutable `TodayDotFieldConfig` with all eleven React Bits props. Each public field must have a Dart doc comment containing its type-level purpose. Every field must affect painter or simulation behavior even when its production default disables the effect.

| React Bits prop | Flutter type | Mobile default | Native behavior |
|---|---|---:|---|
| `dotRadius` | `double` | `1.5` | Radius of each base dot. |
| `dotSpacing` | `double` | `14` | Center-to-center spacing used to build the reusable dot grid. |
| `cursorRadius` | `double` | `54` | App-adapted Reka convex-core radius, matching the approved product terminology. |
| `cursorForce` | `double` | `0.1` | Force applied to nearby dots when `bulgeOnly` is false. |
| `bulgeOnly` | `bool` | `true` | Uses a bounded radial bulge when true; enables pushed-dot physics when false. |
| `bulgeStrength` | `double` | `67` | Controls bulge height and local dot displacement strength. |
| `glowRadius` | `double` | `150` | Radius of the black radial glow around Reka. |
| `sparkle` | `bool` | `false` | Deterministically enlarges about three percent of dots when enabled. |
| `waveAmplitude` | `double` | `0` | Amplitude of the field-wide wave animation; zero keeps the background calm. |
| `gradientFrom` | `Color` | brand gray-green | Starting dot color for the diagonal field gradient. |
| `gradientTo` | `Color` | deeper brand gray-green | Ending dot color for the diagonal field gradient. |
| `glowColor` | `Color` | black | Color of Reka's radial outer glow. |

React Bits defines `cursorRadius` as the cursor interaction area. This app intentionally adapts that name to the approved product meaning: Reka's visible convex core. The gesture target remains at least `64 × 64` logical pixels and expands to cover the visible core. `glowRadius` remains independent and controls only the outer glow range.

App-specific visual constants remain separate from the React Bits contract:

- `rekaHighlightColor`: white.
- `eyeColor`: the existing warm orange.
- `breathPeriod`: approximately 5.2 seconds.
- eye visibility threshold and fade curve derived from idle bulge/glow intensity.

## Shell and Layout Architecture

Add an opt-in Today-only extended-body mode to `ThemeV2PageScaffold`:

- In standard mode, retain the existing Column layout for all current pages.
- In extended mode, let the Today body fill the safe-area height and overlay the Top Nav and Dock above it.
- Add a transparent-surface option to `ThemeV2GlobalTopNav`; use it only for the active Today dot experiment and only for the standard Top Nav.
- Preserve an opaque capture-activity Top Bar.
- Preserve the floating Dock's existing white material, border, elevation, semantics, and touch targets.

`TodayDotMatrixScene` receives the full extended size. Its heading and Reka safe bounds reserve the Top Nav height, Dock clearance, and device insets. The simulation owns one reusable node list for this full size, so dot spacing stays aligned across the former Chrome boundaries.

## Component Boundaries

- `TodayDotFieldConfig`: immutable parameter names, defaults, validation, and documentation.
- `TodayDotFieldController`: Reka motion state, live position, breathing phase, eye/glow intensity, inertia, and safe bounds.
- `TodayDotFieldSimulation`: reusable dot anchors/positions, gradient progress, bulge/force behavior, wave offsets, sparkle selection, and settling.
- `TodayDotMatrixPainter`: field surface, gradient dots, black glow, white convex highlight, and eyes.
- `TodayDotMatrixScene`: ticker, lifecycle, gesture arbitration, geometry, and painter composition.
- `ThemeV2PageScaffold` / `ThemeV2GlobalTopNav`: Today-only continuous-canvas presentation without changing other pages.

## Interaction and Accessibility

- Empty-field drags remain inert and available to pull-to-refresh.
- Reka pan starts only inside the visible core's semantic target.
- Slow and fast motion remain capped and local.
- Tap without pan opens the existing quick-action menu at the live global Reka rect.
- The semantic label remains `Reka 快捷操作，可拖动`.
- Top Nav and Dock keep their current semantic order and minimum touch sizes above the continuous field.
- Scene ticker stops when Today is inactive or the app is paused.

## Testing and Acceptance

Use TDD for each behavior change.

- Config tests cover defaults, validation, and every React Bits field.
- Simulation tests cover spacing, force versus bulge modes, strength, wave amplitude, deterministic sparkle, and node-list reuse.
- Painter tests prove the old dark sphere is absent, the white core and black glow occupy independent radii, gradients affect dots, and eyes are local to the core.
- Widget tests prove Today alone extends under Chrome, empty-field drags remain inert, the enlarged core is draggable, quick actions use the live anchor, and other pages retain opaque Chrome.
- Golden tests cover inhale, glow with eyes, drag without eyes, settling, Reduce Motion, and tall layout with continuous Top Nav/Dock surroundings.
- Run the existing rollout and navigation regression tests.
- Build with `TODAY_DOT_EXPERIMENT=true`, install on `RFCY71B21YK`, and record at least one full breath cycle plus screenshots before and after dragging.

## Non-goals

- No WebGL, WebView, React runtime, fragment shader, new dependency, or external image asset.
- No Dark Mode treatment in this round.
- No dot background on non-Today pages.
- No new Reka actions, expressions beyond eyes, or persistence across scene recreation.
