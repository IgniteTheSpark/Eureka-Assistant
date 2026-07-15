# Ring Demo A1 Mode Scenes Design

## Outcome

Replace the flat Flash and Vibe mode fields on the Home page with two clearly separated real-life scenes. The existing live 3D Ring remains the continuous product object: it arrives in a neutral center runway, then moves toward the photographed hand when the visitor focuses a mode. The final portion of the movement hands off from the live 3D Ring to the ring already present in the photograph.

This work changes only the Home page mode-selection section. The Hero, connection section, Flash page, Vibe page, Ring Desktop routing, and backend behavior remain unchanged.

## Approved Direction

Use the A1 “central product runway” composition:

- Flash uses the driving scene on the left.
- Vibe uses the office/Codex scene on the right.
- A neutral vertical runway separates the scenes and holds the live Ring.
- The images never touch and never read as one continuous photograph.
- Hover, keyboard focus, or touch press expands one scene while the other recedes.
- The live Ring moves from the runway toward the corresponding photographed finger.
- Clicking follows the existing `/flash` or `/vibe` route without waiting for the movement to finish.

## Image Treatment

Create two cleaned derivatives from the supplied images and store them as optimized web assets under `ring-demo/public/scenes/`.

Remove:

- the QR code;
- the `Early Bird Access` block and its supporting copy;
- the circular Ring magnifier;
- connector lines belonging to the removed magnifier or QR treatment;
- the rasterized voice-command bubble and `Speak freely. Capture quietly.` treatment.

Keep:

- the person, environment, computer, vehicle, coffee, and photographed Ring;
- the original cinematic lighting and black wardrobe.

Recreate the voice-command copy and `Speak freely. Capture quietly.` as responsive, semantic HTML overlays above the cleaned images. Their wording and narrative role remain, but their layout can adapt cleanly without duplicating rasterized text.

The cleaned images must not invent a second Ring or change the finger wearing the Ring. The photographic Ring is the final visual target for the live 3D handoff.

For the web composition, use responsive crops rather than stretching. Desktop crops should keep the face, speaking hand, photographed Ring, and the defining environmental cue visible. The QR-free lower area may be cropped away when it does not help the composition.

## Desktop Composition

The mode stage replaces the current `mode-fields` visual treatment while preserving two semantic route links.

At rest:

- Flash scene: approximately 41% of the stage width.
- Center runway: 16–18% of the stage width.
- Vibe scene: approximately 41% of the stage width.
- The runway uses the existing light-page palette with a darker neutral inset, subtle vertical borders, and controlled shadow depth.
- The live Ring sits centered in the runway and remains fully visible above the scene backgrounds.
- Flash and Vibe labels stay inside their corresponding scene, clear of the photographed hands and hint bubbles.

The exact percentages may move by up to two points during visual calibration, but the runway must never become narrower than 10% of the stage on desktop.

## Interaction and Motion

### Arrival

The existing native page scroll continues to control the Home journey. As the visitor reaches the mode stage, the Ring settles into the center runway. No mode is active on arrival.

The mode stage must not pin the page, hijack the wheel, or map physical Ring gestures to the Home page.

### Flash intent

When Flash receives pointer hover, keyboard focus, or touch press:

- Flash expands to approximately 59%.
- Vibe recedes to approximately 29% and becomes darker.
- The runway narrows to approximately 12% and shifts right.
- The live Ring moves along a short curved path toward the photographed Ring on the Flash hand.
- The Flash voice-command bubble and hint become more legible.

### Vibe intent

When Vibe receives pointer hover, keyboard focus, or touch press:

- Vibe expands to approximately 59%.
- Flash recedes to approximately 29% and becomes darker.
- The runway narrows to approximately 12% and shifts left.
- The live Ring moves along a short curved path toward the photographed Ring on the Vibe hand.
- The Vibe voice-command bubble and hint become more legible.

### 3D-to-photo handoff

Each scene defines a normalized screen-space handoff target for the photographed Ring. Target calibration belongs to the scene configuration, not hard-coded component CSS.

During the first 85–90% of the focused movement, the live Ring remains opaque and interpolates position, rotation, and scale toward the target. During the final 10–15%, it fades to zero while the photograph remains unchanged. This avoids a double Ring and makes the photographic Ring appear to receive the live object.

Leaving the stage or removing focus reverses the movement and returns the Ring to the center runway. Motion should feel deliberate and weighted, using the existing spring/interpolation approach rather than a linear CSS slide.

Clicking either scene navigates immediately. The motion must not delay routing by more than the existing 350 ms interaction boundary.

## Content Layering

Use three explicit visual layers:

1. Scene backgrounds and their dimming treatment.
2. The persistent 3D Ring canvas.
3. Mode labels, descriptions, focus outlines, and link hit areas.

The scene images must never cover the live Ring during arrival or travel. Text remains readable and interactive above both the photography and Ring. A dark local gradient may sit behind text, but there is no global dark overlay that makes the photographs muddy.

The current Flash and Vibe descriptions, voice-command copy, and `Speak freely. Capture quietly.` hints remain available in semantic DOM and render as HTML overlays. None of this copy remains rasterized in the cleaned scene images.

## Component Boundaries

- `HomePage` owns semantic scene links and focused-mode intent.
- A dedicated mode-scene component owns layout, crops, labels, scene expansion, and accessible interaction states.
- Scene configuration owns image URL, crop position, handoff target, Ring target rotation, and target scale for Flash and Vibe.
- The pure Ring journey resolver accepts the focused scene target and returns the center, Flash, or Vibe pose.
- `LivingRingScene` renders and interpolates the resolved pose; it does not know page copy or route behavior.

The configuration must make later crop or target calibration possible without rewriting the motion component.

## Responsive Behavior

Desktop exhibition layouts at 1440 px and 1920 px are the primary target.

Between 761 px and 1040 px:

- keep the split composition;
- reduce the runway width and Ring scale proportionally;
- use breakpoint-specific crop and handoff calibration;
- preserve keyboard focus and show the focused treatment during touch press without creating a first-tap navigation trap.

At 760 px and below:

- stack Flash and Vibe as separate scene cards;
- keep the Ring in a neutral product position instead of attempting finger alignment;
- use tap/focus to reveal the selected scene copy;
- retain direct navigation and visible focus states.

## Reduced Motion and Fallbacks

With `prefers-reduced-motion`:

- do not move the Ring toward a hand;
- switch scene emphasis using short opacity changes;
- keep the Ring centered in the runway;
- keep both routes fully usable.

If WebGL or the GLB fails, retain the existing poster fallback in the runway. If a scene asset fails, show a neutral field with its mode label and route rather than collapsing the layout.

## Performance

- Export cleaned scene derivatives as WebP or AVIF with a practical desktop maximum width of 1800–2000 px.
- Provide a smaller responsive source where useful.
- Do not add another WebGL canvas or video background.
- Animate transforms, clip/grid proportions, opacity, and the existing Ring pose only.
- Avoid per-frame React state updates.
- Lazy-load scene images before the mode section approaches the viewport, without delaying Hero rendering.

## Verification

Automated checks:

- unit-test neutral, Flash-focused, and Vibe-focused layout-state resolution;
- unit-test center, Flash-target, and Vibe-target Ring poses;
- verify Flash and Vibe links remain available while disconnected;
- verify pointer and keyboard focus update the same focused-mode state;
- verify blur/pointer leave restores neutral state;
- verify reduced-motion keeps the Ring centered;
- run the full test suite, typecheck, and production build.

Browser checks at 1920×1080 and 1440×900:

- scenes remain visibly separated at all times;
- no QR code or magnifier remains;
- the hint bubble and `Speak freely. Capture quietly.` remain readable;
- the live Ring is not clipped by scene backgrounds;
- the focused scene expands without layout overflow;
- the live Ring reaches the correct photographed hand and disappears without a double-Ring frame;
- clicking each scene reaches the correct dedicated page;
- focus outlines and reduced motion remain usable.

## Acceptance Criteria

- The neutral mode stage reads as two distinct environments divided by a center product runway.
- The live Ring arrives and rests in the center runway.
- Flash and Vibe emphasis works with hover, keyboard focus, and touch press.
- Each focused state moves the live Ring toward the correct photographed finger.
- The final handoff contains no visible double Ring.
- QR, Early Bird content, and the circular magnifier are absent.
- Voice-command bubbles and `Speak freely. Capture quietly.` are retained.
- Existing connection behavior, mode routes, Flash flow, and Vibe flow continue to work.

## Non-goals

- No changes to the dedicated Flash or Vibe pages in this phase.
- No physical Ring gesture controls for Home navigation.
- No new backend, database, authentication, or Ring Desktop behavior.
- No video generation or full-page cinematic takeover.
- No Claude mode or additional mode destination.
