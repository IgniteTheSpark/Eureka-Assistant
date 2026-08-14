# Today Dithered 3D Reka and Floating Top Dock Design

## 1. Goal

Replace the current Today-page dot-field Reka experiment with a focused minimum loop:

1. keep the existing Today content and standard page background;
2. keep the approved floating Top Dock that visually matches the Bottom Dock;
3. render Reka as a draggable, locally hosted, dithered 3D robot head;
4. keep Reka's orange old-school robot eyes visible at all times;
5. validate the result on a physical device before expanding the visual language.

This round deliberately does not establish a dot-matrix background as a product-wide design language. Brand consistency remains more important than applying a new background treatment across every page.

## 2. Approved Scope

### 2.1 Included

- Today page only.
- Existing standard Today background and content styling.
- Existing floating Top Dock treatment, using the same surface language as the Bottom Dock.
- One locally rendered dithered 3D Reka.
- A floating robot-head silhouette with a rounded shell, dark visor, and side modules.
- Two orange `3 × 3` old-school robot eyes that remain visible in every motion state.
- Dragging Reka across the Today safe region.
- A small, velocity-driven head tilt during dragging.
- Short bounded settling after release, then idle floating and breathing.
- Existing Reka tap actions and live quick-action anchoring.
- Reduce Motion and a non-WebGL fallback.
- Physical-device validation on the current Android target.

### 2.2 Excluded

- A full-page dot-matrix background.
- Dot displacement, ripple, bulge, glow, or pointer response in the page background.
- Applying dot backgrounds or Reka to other pages.
- Dark Mode work.
- User-facing dither controls.
- Camera orbit, pinch zoom, or free 3D rotation.
- Downloading a model or other render assets at runtime.
- Position persistence across application restarts.
- New Reka actions, expressions, mouth animation, or speech animation.

## 3. Reference Findings

The reference is [Canvas UI Dithered Object](https://canvasui.dev/docs/components/dithered-object).

Target-bound investigation established the following facts:

- `SOURCE`: the reference uses Three.js r185 and a main-thread `WebGLRenderer` bound to the demo canvas.
- `SOURCE`: the 3D scene renders into a multisampled offscreen target, then a fullscreen shader applies Bayer, halftone, or Floyd–Steinberg dithering.
- `SOURCE`: the default reference settings use Bayer dithering, a `4` CSS-pixel grid, grayscale output, transparent background, idle floating, idle rocking, orbit enabled, and zoom disabled.
- `SOURCE`: the public demo loads `Duck.glb`; that model is not part of the desired Reka design.
- `SOURCE`: Bayer and halftone remain GPU post-processes, while Floyd–Steinberg also reads pixels back and performs CPU diffusion.
- `SOURCE`: the reference pauses continuous floating under Reduce Motion.

For this app, the reference is an implementation basis rather than a package dependency. The project will reuse the target-bound render structure and shader behavior while replacing the demo model, interaction ownership, and eye compositing.

## 4. Visual Contract

### 4.1 Reka silhouette

Reka is a complete character even though only the head is shown. The visible geometry consists of:

- one wide rounded head shell;
- one inset dark visor;
- two compact side modules;
- no torso, legs, antenna, mouth, outline halo, or separate circular container.

The head should occupy approximately `80%` of a `216 × 216` logical-pixel render region on a typical phone. The canvas is transparent, so only the head, eyes, and their natural 3D shading appear over Today.

### 4.2 Dither treatment

The shell, visor, side modules, lighting, and shadows render through the Bayer post-process. Initial settings use the reference's source-derived baseline:

| Setting | Initial value |
|---|---:|
| method | `bayer` |
| grid size | `4 CSS px` |
| pixel size ratio | `1` |
| grayscale | `true` |
| invert | `false` |
| background | transparent |
| camera FOV | `65°` |
| camera distance | approximately `4.2` scene units |

These values are a baseline, not a promise that device tuning is unnecessary. Tuning may adjust scale, lighting, camera distance, or grid size, but must not change the approved silhouette or interaction contract.

### 4.3 Permanent eyes

The eyes are spatially part of the 3D head but are not passed through the dither threshold.

The renderer uses two layers:

1. render the head to an offscreen target and apply Bayer dithering;
2. render the orange eye meshes over the dithered output using the same camera and head transform.

Each eye is a `3 × 3` pixel matrix with its center pixel omitted. The eye meshes inherit the head's position, scale, perspective, and tilt. They remain readable during idle, dragging, settling, Reduce Motion, and lighting changes.

## 5. Page Composition

The Today experiment uses the following stack:

```text
TodayExperimentPage
├── standard Today page background
├── existing Today content
├── floating Top Dock
├── positioned TodayDitheredReka
│   ├── Flutter gesture and semantics layer
│   └── transparent local WebView render surface
└── Bottom Dock
```

There is no full-page custom painter or interactive background layer in this design.

The existing experiment entry point and feature flag remain in place for this round so the physical-device comparison path does not require unrelated routing changes. The old dot-field painter, simulation, bulge, glow, and background animation leave the active render path.

## 6. Component Boundaries

### 6.1 `TodayDitheredReka`

Flutter widget that owns:

- the `216 × 216` transparent render region;
- loading, ready, fallback, pause, and disposed states;
- the `WebViewController`;
- the local renderer asset bootstrap;
- communication with the JavaScript renderer;
- the static fallback presentation.

It does not own page position or gesture arbitration.

### 6.2 `TodayRekaMotionController`

Flutter controller that owns:

- normalized Reka position;
- idle, dragging, and settling states;
- safe bounds and clamping;
- filtered drag velocity;
- bounded release velocity;
- tilt targets;
- click-versus-drag thresholds;
- Reduce Motion behavior.

The current dot-field controller may be renamed and narrowed rather than replaced if doing so preserves its tested motion behavior without retaining background-specific responsibilities.

### 6.3 `TodayRekaGestureTarget`

Transparent Flutter layer above the non-interactive WebView. It owns:

- hit testing;
- pointer cancellation;
- tap-versus-drag arbitration;
- accessibility semantics;
- the live global rectangle used to anchor quick actions.

The WebView never receives pointer input. This prevents OrbitControls or platform-view gestures from competing with Flutter.

### 6.4 Local Three.js renderer

The renderer is loaded entirely from Flutter assets and owns:

- renderer, scene, camera, and resize handling;
- procedural robot-head geometry;
- local studio lighting;
- offscreen render target;
- Bayer post-process;
- non-dithered eye pass;
- idle floating and rocking;
- drag tilt interpolation;
- pause, resume, resize, Reduce Motion, and destroy behavior.

The renderer exposes one narrow JavaScript API rather than leaking Three.js objects to Flutter.

### 6.5 Floating Top Dock

The existing floating Top Dock stays active. It continues to share the Bottom Dock's rounded surface, quiet border, shadow, spacing, and brand treatment. This design does not add dots behind or inside either Dock.

## 7. Local Asset Strategy

All renderer inputs ship with the app:

- a vendored, pinned Three.js browser build;
- the Reka renderer JavaScript;
- the HTML bootstrap template.

The vendored Three.js build must include its upstream license notice and an explicit version record. Canvas UI source is used as a reference for the target-bound render structure; implementation must preserve any applicable notice required by the source license.

Flutter loads these files with `rootBundle`, injects them into the HTML template, and calls `loadHtmlString`, following the established local transparent-WebView pattern already used by `PetView`.

The renderer does not fetch:

- GLB or glTF models;
- Draco decoders;
- textures;
- fonts;
- scripts;
- configuration.

Procedural geometry removes model-loading latency and runtime network failure from the minimum loop.

## 8. Motion and Interaction

### 8.1 Idle

When ready and visible, Reka performs:

- restrained vertical floating;
- low-amplitude three-axis rocking;
- a slow lighting-intensity breath.

The motion must have no visible seam and must not move the Flutter hit target. Only the geometry moves inside its fixed render region.

### 8.2 Dragging

A drag begins only when the pointer starts inside Reka's hit target.

During dragging:

- Flutter moves the entire render region directly with the pointer;
- idle floating is reduced so the head stays visually attached to the finger;
- filtered velocity maps to a limited head tilt;
- horizontal and vertical tilt are clamped to approximately `8°`;
- the eyes remain visible and inherit the same head transform;
- the standard page background does not react.

Flutter coalesces pose updates sent to JavaScript. The WebView does not receive an unbounded JavaScript call for every raw pointer sample.

### 8.3 Settling

On release:

- the controller applies short, bounded inertia inside the safe region;
- position remains fully visible and outside reserved system and Dock areas;
- the head returns to neutral over approximately `220 ms`;
- idle motion resumes after settling.

Reduce Motion removes inertia and animated settling.

### 8.4 Tap and quick actions

Movement below approximately `8 logical px` remains a tap. A tap opens the existing three-action menu. A completed drag never opens the menu.

The menu anchor comes from the live global Reka rectangle after clamping and movement.

## 9. Flutter-to-JavaScript Contract

The local renderer exposes a small API equivalent to:

```text
init(options)
setMotion({ state, tiltX, tiltY })
setReduceMotion(enabled)
setPaused(paused)
resize(width, height, dpr)
destroy()
```

JavaScript reports only:

```text
ready
error(code)
```

Flutter remains the source of truth for position and motion state. JavaScript remains the source of truth for internal 3D animation and GPU resources.

## 10. Lifecycle and Performance

- Render region: approximately `216 × 216` logical pixels.
- Device pixel ratio: capped at `2`.
- Dither mode: Bayer only for the minimum loop.
- Offscreen target: downsampled according to the dither cell size.
- No per-frame GPU readback.
- No full-page WebView.
- No WebView pointer handling.
- Animation pauses when the app is backgrounded, the route is not current, or the render surface is outside the active tree.
- GPU resources, observers, animation loops, materials, geometries, textures, and render targets are released on destroy.

The first physical-device pass must check for platform-view movement jank, transparent-composition artifacts, excess heat, and lifecycle leaks. If movement of the small WebView cannot stay smooth, the fallback implementation route is a fixed transparent render surface with internal JavaScript translation, while Flutter retains gesture ownership and menu anchoring. That route is a performance contingency, not the initial architecture.

## 11. Failure and Fallback Behavior

The WebGL renderer may fail because of initialization, asset bootstrap, platform-view, or context-loss errors.

Failure behavior:

1. keep the same Flutter layout and hit target;
2. replace the WebView with a deterministic Flutter `CustomPainter` robot-head fallback using the same rounded-head, visor, side-module, and eye silhouette;
3. keep the two orange `3 × 3` eyes visible;
4. preserve dragging, tap actions, safe bounds, and quick-action anchoring;
5. stop retry loops for the current widget instance;
6. allow a fresh renderer attempt when the page is recreated.

The Today page must never show a blank hole, loading spinner that never resolves, or a blocked gesture surface.

## 12. Accessibility

Reka exposes one semantic target:

```text
label: Reka 快捷操作，可拖动
role: button
actions: tap plus custom drag semantics supplied by the existing gesture pattern
```

The WebView render content itself is excluded from semantics to avoid duplicate focus targets.

Reduce Motion keeps the static 3D identity and eyes while disabling continuous non-essential motion.

## 13. Testing

### 13.1 Unit tests

- idle → dragging → settling → idle transitions;
- normalized position and safe-bound clamping;
- velocity filtering and tilt clamping;
- tap-versus-drag threshold;
- quick-action anchor tracking;
- Reduce Motion state transitions;
- lifecycle pause state.

### 13.2 Widget tests

- standard background remains present without a full-page dot painter;
- floating Top Dock remains present and uses the approved geometry;
- Reka region is positioned and clamped correctly;
- WebView is non-interactive from Flutter's gesture perspective;
- loading, ready, failure, and fallback states preserve layout;
- Reka remains Today-only.

### 13.3 Renderer tests

- local HTML and scripts load without network access;
- WebGL initialization reports ready or a classified error;
- Bayer pass renders a non-empty alpha result;
- eye pass remains visible over dark and light head frames;
- pause stops the animation loop;
- resume restarts it once;
- destroy releases resources and cannot restart.

### 13.4 Physical-device checks

- head shape reads as a floating robot, not a sphere or white bulge;
- eyes remain visible during idle, dragging, settling, and refresh;
- drag follows the finger without WebView gesture competition;
- tilt feels responsive but never like free rotation;
- release is short and controlled;
- quick actions open only on tap and follow the live Reka position;
- Top Dock and Bottom Dock feel related;
- there is no page-level dot background or background interaction;
- foreground/background and route changes do not duplicate animation loops;
- sustained idle and repeated dragging do not cause unacceptable heat or frame loss.

## 14. Acceptance Criteria

- [ ] Today uses its standard background; no full-page dot matrix is active.
- [ ] Top navigation uses the approved floating Dock treatment.
- [ ] Reka is a local dithered 3D floating robot head.
- [ ] The reference Duck model and runtime network loading are absent.
- [ ] Reka can be dragged inside safe bounds.
- [ ] Dragging adds limited velocity-driven tilt but no orbit control.
- [ ] Both orange `3 × 3` eyes remain visible in all states.
- [ ] Idle floating, rocking, and breathing feel restrained.
- [ ] Tap opens existing quick actions; drag does not.
- [ ] Reduce Motion disables non-essential continuous and settling motion.
- [ ] WebGL failure preserves a recognizable, draggable Reka fallback.
- [ ] Reka remains exclusive to Today.
- [ ] No Dark Mode or other-page revamp is included.

## 15. Future Work

Explicitly deferred until the minimum loop is approved on a physical device:

1. Dark Mode treatment.
2. Persisting Reka's resting position.
3. Additional expressions or behavioral states.
4. Applying a background pattern across multiple pages.
5. Replacing the procedural head with an authored GLB if the simple geometry cannot carry enough character.
