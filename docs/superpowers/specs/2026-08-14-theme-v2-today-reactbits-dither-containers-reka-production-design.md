# Theme V2 Today ReactBits Dither Containers and Reka Production Design

**Date:** 2026-08-14  
**Status:** Approved design  
**Scope:** Theme V2 Today light-mode experiment only: Signal/Asset container material, object displacement, watermark placement, Reka appearance, and new-object production choreography.

## 1. Objective

The current Today surface places Dither material on individual Signal strips, individual Asset balls, and in a weak field behind Reka. This makes the objects read as decorated components instead of objects occupying one shared living field. The bottom-right `Reka 生成` watermark is also frequently covered by settled Asset balls.

This iteration reverses the material relationship:

- Dither belongs to the Signal and Asset containers.
- Stable Signal and Asset content has no independent painted body.
- Each visible object continuously displaces the Dither field behind it, using the same visual idea as ReactBits Dither's mouse interaction.
- Reka loses its local Dither halo and becomes a larger, cleaner 3D production actor.
- New Signals and Assets leave Reka as neutral seeds and acquire their final identity only at the destination boundary.

Dark mode is explicitly out of scope until the light-mode result is accepted on device.

## 2. Reference Model

The visual reference is ReactBits `Dither`:

- four-octave coherent-noise wave field;
- time-driven directional flow;
- 8 x 8 Bayer quantization;
- configurable wave color, color count, amplitude, frequency, speed, pixel size, and interaction radius;
- pointer interaction implemented by subtracting a smooth radial influence from the wave field.

The Flutter implementation reproduces the behavior and parameter model with a native runtime fragment shader. It does not embed two additional WebViews. Reka remains the only bounded WebGL/WebView renderer on Today.

For Today, pointer position becomes a collection of object displacement sources:

- Signal sources use horizontal capsule distance fields.
- Asset sources use circular distance fields.
- Each source has position, size, pressure strength, and transient motion energy.

## 3. Page Structure and Layering

The page keeps the current solid Theme V2 background and approximately `1/3 : 2/3` content split:

1. header/date/next item;
2. Signal container;
3. a narrow solid-background breathing seam;
4. Asset container;
5. floating Reka above all content;
6. floating Top and Bottom Docks above the Today content world.

Neither content container has a visible border, card fill, or conventional panel outline. The two Dither fields are independently clipped and faded so they never reconnect into a page-wide texture.

Z-order inside each container is:

```text
interactive Signal/Asset content
region watermark
container Dither field
solid page background
```

Reka remains above both containers and production overlays. Its gesture target only occupies the configured hit extent and must not block container interaction elsewhere.

## 4. Container Dither Fields

### 4.1 Shared parameter contract

Both fields expose the ReactBits-inspired parameters:

- `waveColor`;
- `colorNum`;
- `pixelSize`;
- `waveAmplitude`;
- `waveFrequency`;
- `waveSpeed`;
- `flowDirection`;
- `displacementStrength`;
- `displacementFeather`.

Initial light-mode tuning uses a neutral low-contrast structural color. Exact values remain device-tunable without changing the interaction contract.

### 4.2 Signal field

- Direction: primarily left to right with a very small vertical component.
- Relative speed: approximately `1.5x` the Asset field.
- Density: restrained and horizontally continuous.
- Edge treatment: soft horizontal fade; no capsule/card outline.
- The field continues flowing while Today is active and animation is allowed.

### 4.3 Asset field

- Direction: primarily top to bottom with a small lateral drift.
- Relative speed: slower and heavier than the Signal field.
- Density: may increase slightly toward the lower part of the chamber.
- Edge treatment: open top and invisible physical walls/floor remain; no visible chamber border.

### 4.4 Displacement lifecycle

Each stable object continuously occupies the shared field:

- a resting Signal strip maintains a capsule-shaped clear pressure area;
- a settled Asset maintains a circular clear pressure area;
- object movement, Asset collision, and Asset dragging temporarily deepen pressure;
- moving pressure may lag by a small amount to create a restrained elastic wake;
- after an object is removed, its pressure decays and the field recovers in approximately `250-350 ms`.

The displacement defines the object's visual body. It is not a glow or shadow drawn around a separate card.

## 5. Stable Signal Presentation

The Signal band keeps three continuously scrolling tracks.

Each stable Signal:

- has no painted Dither strip, solid fill, stroke, or card shadow;
- keeps its icon, title, semantics, canonical tap action, and minimum touch target;
- supplies a capsule displacement source matching the visual content extent;
- pauses according to the current tap/open behavior without losing its pressure footprint.

The existing lane speeds may remain distinct, but all three tracks move left to right.

### 5.1 First-track birth rule

The top track is also the fixed `Birth Lane` for new Signals. This avoids lane collision prediction and physical Signal collision.

When a Signal seed approaches:

1. the first track pauses;
2. currently visible first-track strips quickly leave or fade from the viewport;
3. their Signal records remain active and return in a later scroll cycle;
4. the other two tracks continue unchanged;
5. the seed hits the Signal region's upper boundary and unfolds in the cleared first track;
6. after unfolding, the first track resumes normal left-to-right motion.

New Signals use FIFO production. A second Signal does not start its birth sequence until the first has completed its unfold and lane release.

## 6. Stable Asset Presentation

`ThemeV2AssetBubbleField` and its physics remain authoritative for identity, diameter, gravity, tilt, dragging, collision, retirement, and canonical detail opening.

Each stable Asset:

- has no painted Dither circle, solid fill, stroke, or card shadow;
- keeps only its content icon and semantic/touch target;
- supplies a circular displacement source using the real physics center and radius;
- deepens pressure from velocity, collision energy, and active dragging;
- keeps a stable pressure footprint after settling.

The invisible collision chamber remains open at the top with active side walls and floor.

## 7. Watermarks

Watermarks move away from content accumulation zones and sit near the shared visual axis:

- `Reka 发现` and its count: left side, slightly above the Signal/Asset seam;
- `Reka 生成` and its count: right side, slightly below the seam.

They remain low-opacity, excluded from semantics, and ignore pointer events. They render above the container field and below interactive content. The Asset watermark must no longer sit in the bottom-right pile area.

## 8. Reka Visual Direction

### 8.1 Presence

- Remove the Flutter-owned local Dither field behind Reka.
- Increase the render extent from `248` to an initial target near `288`.
- Adjust the Three.js camera/object scale so the robot itself becomes larger; do not only enlarge transparent canvas space.
- Increase the hit extent proportionally while preserving safe drag bounds and Dock/header clearance.
- Keep the current clean capsule robot silhouette and black visor.

### 8.2 Eyes

The visor remains dedicated to the permanent old-school pixel eyes. It never displays content icons, text, alert symbols, or preview UI.

- Replace orange with a fixed terminal/phosphor green, initially near `#78FF74`.
- Keep a small emissive response inside the visor without a large neon halo.
- Signal/Asset types do not change eye color.
- Eye pixels may shift vertically to look up or down during production.

### 8.3 Ambient 3D motion

Idle motion is richer but restrained:

- slow vertical breathing;
- small pitch, yaw, and roll sway;
- subtle light breathing;
- no continuous shake.

Drag velocity remains the source of interactive tilt. Production motion blends with drag tilt rather than disabling dragging or allowing large flips.

## 9. Reka Production State Machine

There is no semantic Preview state and no icon above or inside Reka.

### 9.1 States

1. `idle`: ambient breathing and sway.
2. `charge`: a neutral Dither seed condenses beside Reka; Reka turns toward it and performs one short restrained micro-shake.
3. `emitSignal` or `emitAsset`: the seed detaches and travels vertically; Reka looks in the same direction with a small opposite recoil.
4. `follow`: Reka and the eyes briefly track the detached seed.
5. `recover`: Reka returns to its idle pose over approximately `350-450 ms`.

### 9.2 Seed origin

- Default origin: just outside Reka's right side and slightly forward.
- If right-side safe space is insufficient, use the left side.
- The origin is a snapshot at detachment.
- Dragging Reka after detachment does not move or reroute the seed.
- The seed contains no icon, text, outline, or category preview.
- It starts with the same terminal-green family as Reka's eyes and becomes more neutral as it leaves.

### 9.3 Signal choreography

1. first-track clearing begins;
2. seed condenses beside Reka;
3. Reka turns toward the seed, then looks upward;
4. seed travels upward toward the Signal upper boundary;
5. seed hits the boundary and unfolds horizontally into the full Signal content in the cleared first track;
6. the Signal immediately supplies its capsule pressure source;
7. first-track scrolling resumes;
8. Reka recovers.

### 9.4 Asset choreography

1. seed condenses beside Reka;
2. Reka turns toward the seed, then looks downward;
3. seed falls toward the Asset chamber floor;
4. at the lower boundary it expands into the same semantic Asset ball;
5. the Asset ID is handed to the real physics field at that position;
6. the ball immediately supplies its circular pressure source and participates in collision/settling;
7. Reka recovers.

## 10. Data Ownership and Synchronization

The existing `TodayOutputCoordinator` remains the single presentation queue and is extended with explicit production phases.

- IDs present during initial hydration are baseline and never replay.
- Only a newly observed stable ID enters production.
- At most one production runs at a time.
- Queued items remain accessible through canonical non-Today surfaces.
- A producing ID is withheld from the stable Today destination until handoff, preventing duplicates.
- Reka motion, seed animation, first-track clearing, and container handoff read the same phase instead of using independent timers.
- Removal cancels a queued, not-yet-started item.
- Route/app deactivation resolves active and queued items safely into their stable destinations.

## 11. Interaction, Accessibility, and Reduce Motion

- Reka remains draggable and tappable throughout production.
- Seed and production trails are non-interactive and excluded from semantics.
- Stable Signal and Asset semantics remain on their existing Flutter-owned targets.
- Dither fields ignore pointer events; they respond only to object geometry supplied by Flutter.
- Signal opening, Asset dragging, and Asset opening retain their existing behavior.

Under Reduce Motion:

- Dither flow becomes static or extremely slow;
- no micro-shake, recoil, seed travel, unfolding flight, or bouncing entrance;
- new content is handed directly to its target destination using a short opacity/pressure reveal;
- Reka eyes may change look direction briefly, but repeated idle motion is removed.

## 12. Lifecycle, Performance, and Fallback

- Runtime shaders animate only while Today is active, the app is resumed, and Reduce Motion permits animation.
- Reka WebGL uses its existing bounded WebView and pauses with the same lifecycle.
- One shared Today ticker supplies time to both container shaders.
- Shader pixel size, device-pixel ratio, update frequency, and displacement-source count have adaptive quality tiers.
- Physics is the source of Asset geometry; the shader never owns or simulates collisions.
- Offscreen and removed pressure sources release promptly.
- A shader compilation/runtime failure falls back to a restrained static container texture and readable minimal object treatment; content and actions remain available.
- A Reka renderer failure uses the existing fallback renderer and may skip production motion directly to destination handoff.

## 13. Verification

Required automated coverage includes:

- initial hydration does not enqueue production;
- FIFO Signal/Asset production and duplicate suppression;
- first-track clear, unfold, and resume behavior without deleting Signal data;
- stable Signal capsule and Asset circle displacement geometry;
- pressure decay after removal;
- Asset pressure follows physics center/radius and strengthens while dragged/moving;
- Reka production command serialization and renderer state transitions;
- terminal-green eyes in WebGL and Flutter fallback;
- local Reka Dither field removal;
- Reduce Motion direct handoff;
- lifecycle pause/resume and fallback completion.

Device verification on the connected foldable must check:

- Reka size and safe drag bounds;
- readable transparent Signal/Asset content over both Dither fields;
- no Asset watermark occlusion by the settled pile;
- no overlap during first-track Signal birth;
- stable frame pacing with Reka WebGL, two shaders, and active Asset physics;
- visual separation between the two independently flowing fields.

## 14. Out of Scope

- Dark-mode tuning;
- full-page Dither or matrix background;
- semantic icons on or above Reka;
- physical collision between Signal strips;
- predictive multi-lane scheduling;
- changes to Signal detail sheets, reminder persistence, or Report/Rhythm domain logic;
- changes to canonical Asset or Signal records.
