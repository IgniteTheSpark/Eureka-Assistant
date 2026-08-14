# Theme V2 Today Reka Dither Output World Design

**Date:** 2026-08-14
**Status:** Approved design
**Scope:** Theme V2 Today light surface, header schedule slot, Reka content layering, Reka signal band, physical Asset chamber, shared Dither material, and new-object production motion

## 1. Objective

The current Today experiment is intentionally clean: a floating 3D Dithered Reka, a solid page background, and floating navigation. The next revamp must add useful Today content without returning to a card dashboard or a full-page dot field.

The page should feel like one small living system:

- Reka is the topmost content object and the visual source of new Signals and Assets.
- Signals are Dithered strips that form near Reka and float upward.
- Assets are Dithered balls that form near Reka, fall under gravity, collide, and settle in the existing bottom chamber.
- A compact optional schedule slot sits in the Today header instead of reserving a permanent Agenda banner.
- The page background remains solid. Dither appears only as a weak local field, faint borderless zone material, and the surface material of Reka-produced objects.

This document extends `2026-08-14-today-dithered-reka-floating-top-dock-design.md`. That document remains authoritative for the local 3D renderer, permanent robot eyes, drag controller, quick actions, lifecycle, Reduce Motion foundation, and floating Top Dock.

Signal detail behavior, Report phases, Rhythm detail, Todo/Event reminder preferences, and overdue Snooze are defined separately in `2026-08-14-theme-v2-reka-discovery-details-and-reminders-design.md`. The two documents are implemented together but retain separate product responsibilities.

## 2. Page Information Architecture

### 2.1 Header

The left side keeps:

- `今日`;
- local date and weekday.

When there is at least one current or future scheduled Todo/Event today, the right side shows only the next item:

- local start/due time;
- truncated title;
- a concise count or context label when space permits.

Tapping the schedule slot opens the canonical Today Agenda. If there is no remaining schedule today, the right side remains empty. The page does not render `暂无安排`, a placeholder, or an empty Agenda banner.

The schedule slot is stable factual content and does not use Dither material.

### 2.2 Main content ratio

The usable content height below the header and above the Bottom Dock is divided approximately:

| Region | Share | Purpose |
|---|---:|---|
| Signal band | 1/3 | Current actionable Reka discovery |
| Asset chamber | 2/3 | Existing physical Asset balls |

The ratio is a layout target, not a hard pixel split. Safe-area, text-scale, short-device, and Dock clearance may adjust it, but the Asset chamber remains visually dominant.

Neither region is a conventional bordered card.

### 2.3 Layering

Content z-order is:

```text
floating Top/Bottom Dock and system chrome
Reka gesture target and 3D render object
new-object production effects
Signal band content
Asset balls
borderless Signal/Asset zone material
solid page background
```

Reka is the topmost content object. It may visually cross the Signal band and Asset chamber without being clipped or entering the Asset collision simulation. Existing safe drag bounds continue to reserve the header, Docks, and system chrome.

## 3. Dither Visual Language

### 3.1 Solid page background

The Today background remains the standard Theme V2 solid background. There is no continuous full-page matrix, interactive ripple, cursor response, or page-wide Dither texture.

### 3.2 Weak Reka field

A very weak local Dither field surrounds Reka and moves with its current position.

- approximate visual radius: `1.5–2.0 ×` the rendered head width;
- no closed edge, halo outline, circular border, or hard gradient boundary;
- low contrast at rest;
- a slow, restrained density breath;
- a short density increase when a new object forms;
- no pointer interaction independent of Reka dragging.

The field communicates local production energy. It is not a container and does not own Asset physics or Signal state.

### 3.3 Signal and Asset zone material

The Signal band and Asset chamber have no visible stroke or card outline. If additional spatial separation is required after device tuning, each may use an extremely faint Dither density field:

- Signal band: horizontal density and fading ends;
- Asset chamber: density increases subtly toward the bottom.

These backgrounds remain weaker than the objects themselves and leave clear solid-background air between regions. They must never reconnect into a full-page dot field.

### 3.4 Produced-object material

Signal strips and Asset balls use a higher-contrast Bayer/Dither surface derived from the current Reka renderer's visual tokens:

- stable cell size across the three object types;
- grayscale or neutral structural material;
- Skill/accent color reserved for icon, status, or a restrained tint;
- clear solid icon and text overlays after the Dither body has formed;
- enough contrast to remain readable over the faint zone material.

The visual relationship is material, not literal shared GPU geometry. Flutter-rendered Signals and Assets may reproduce the pinned Bayer pattern without moving their physics or accessibility ownership into the Reka WebView.

## 4. Signal Band

### 4.1 Resting presentation

The Today Signal band shows one highest-priority active Signal at a time. Additional active Signals are preserved and reachable through horizontal paging/scrolling and the full Reka surface.

The visible item contains:

- Dithered strip body;
- kind icon;
- title;
- concise kind/status metadata;
- no always-visible overflow menu inside the compact strip.

Tapping opens the canonical target defined by the discovery-detail spec:

- Overdue -> existing Todo detail;
- Rhythm -> Rhythm detail sheet;
- Report -> phase-aware Report detail sheet.

The band has no border. When empty, it becomes visually absent rather than showing a large empty-state card. Report creation/history remain available through their canonical destinations, not as permanent empty-band buttons.

### 4.2 Scrolling and trail

- Horizontal user paging is allowed within the band.
- A short Dither trail appears only while an item enters, leaves, or is actively scrolled.
- Trail direction is opposite movement direction.
- Trail density decays quickly after motion stops.
- Text and icon remain attached to the stable strip body and never dissolve during ordinary reading.
- The band does not auto-scroll continuously.

## 5. Asset Chamber

The existing `ThemeV2AssetBubbleField` remains the source of truth for:

- Asset identity and Skill metadata;
- ball diameter;
- gravity and device tilt;
- collision response;
- dragging;
- settling;
- retirement/removal;
- tapping the canonical Asset detail.

The existing `ThemeV2GravityChamber` remains an open-top physical container, but its visible border is removed in this presentation. Collision walls and floor remain fully active and invisible.

The chamber may use the faint downward-density Dither material defined in section 3.3. The Asset balls themselves carry the stronger Dither surface defined in section 3.4.

Existing Assets do not originate from Reka again when Today opens. They start in their existing/restored chamber state.

## 6. Production Motion

### 6.1 Shared contract

Only a newly introduced stable object ID triggers full production motion. Initial load, rebuild, refresh, route return, and theme reassembly must not replay existing production.

Both object types:

1. take a snapshot of Reka's current visual origin when production begins;
2. form inside or immediately beside the weak Reka field;
3. use their final object category during formation;
4. detach after formation;
5. move only on the vertical axis;
6. continue independently if the user drags Reka after detachment.

There is no target pathfinding, Bezier routing, seed object, orbit, homing, or drag-time route recomputation.

### 6.2 Asset: condense, then fall

Asset production uses radial contraction:

1. local field density rises;
2. loose points contract toward one center;
3. a Dither ball reaches its stable diameter;
4. the solid Skill icon fades in near the end of formation;
5. the ball detaches and receives normal downward gravity;
6. the same physics body falls, collides, bounces, and settles in the Asset chamber.

The animation does not use a visual copy that disappears before physics begins. Formation hands the same semantic Asset object into the existing BubbleField.

### 6.3 Signal: align, then rise

Signal production uses horizontal ordering:

1. local field density rises;
2. loose points align into a horizontal strip;
3. the Dither strip reaches stable width and height;
4. icon and text fade in near the end of formation;
5. the strip detaches and rises vertically;
6. a short Dither trail decays below it;
7. the canonical Signal item becomes available in the Signal band without a second unfold animation.

The rise is a simple production transition, not a simulation that searches for the band. The renderer clamps/fades the transition inside the content-safe region and resolves the stable item into the current Signal slot. Reka position therefore changes the visible origin, not the Signal band's layout.

### 6.4 Timing and concurrency

Initial tuning targets:

| Phase | Duration target |
|---|---:|
| local field density rise | 120–180 ms |
| Asset condensation | 260–360 ms |
| Signal horizontal alignment | 220–320 ms |
| Signal vertical rise/trail | 480–700 ms |
| Asset fall | owned by existing physics after formation |
| field return to idle | 220–320 ms |

At most one production formation begins at a time. Concurrent new IDs enter a short FIFO visual queue. The underlying data becomes available immediately; the queue delays only presentation, never persistence or actions.

The queue must not grow without bound. After a small presentation cap, remaining objects appear directly in their stable destination and remain fully usable.

## 7. Data and State Flow

### 7.1 Home data

The Today surface consumes the existing Home repository result:

- `chain` supplies the optional next schedule slot;
- `rekaQueue` supplies active Signal items;
- `pool` supplies Asset balls;
- `skills` supplies Asset visual metadata.

The current empty Reka experiment must stop discarding the loaded repository result. It becomes a composed living Today surface rather than a renderer-only page.

### 7.2 New-object detection

A coordinator compares committed stable IDs across successful Home revisions:

- IDs present on initial hydration are baseline, not new;
- newly added `pool` IDs enqueue Asset production;
- newly added active `rekaQueue` IDs enqueue Signal production;
- an ID that is queued or actively producing is withheld from its stable Today destination so the page never renders both the production effect and destination object;
- successful Asset formation hands that same ID into the BubbleField, and successful Signal rise releases that same ID into the Signal band;
- removed IDs cancel pending but not-yet-started presentation;
- a mutation that removes an active object updates its destination immediately;
- repository retry cannot duplicate a queued ID.

The underlying record remains committed and accessible through canonical non-Today surfaces while Today presentation is queued. If Today becomes inactive, the production renderer fails, or the presentation cap is exceeded, queued IDs bypass animation and enter their stable Today destination immediately.

This coordinator owns presentation history only for the current Today session. It does not create a second persisted lifecycle.

## 8. Interaction and Accessibility

- Reka keeps the existing tap-versus-drag threshold and quick-action anchor.
- Reka remains above content visually, but gestures begin only inside its hit target; it must not block scrolling or tapping the full Signal band or Asset chamber.
- Signal paging wins when the drag begins inside the visible Signal strip.
- Asset dragging wins when the drag begins on an Asset ball.
- Production effects are non-interactive and excluded from semantics.
- Stable Signal strips and Asset balls expose their existing semantic labels and minimum touch targets.
- Header schedule copy truncates visually but exposes the complete title and time to semantics.

Under Reduce Motion:

- no vertical rise, fall handoff animation, bouncing entrance, or trail;
- a new Signal crossfades into its stable slot after a brief Dither threshold reveal;
- a new Asset appears directly in the existing deterministic settled presentation;
- Reka field does not pulse repeatedly.

## 9. Lifecycle and Performance

- Reka's WebView stays bounded to its existing local render region; this design does not create a full-page WebView.
- Weak field, zone material, trails, Signal strips, and Asset surfaces are Flutter-owned rendering.
- Dither rendering must use cached patterns/shaders rather than allocating per-dot widgets.
- Production animation pauses with the route/app lifecycle and resolves safely on resume.
- If Reka renderer readiness fails, stable Signals and Assets remain available; production uses a static origin/fallback or skips directly to the destination.
- Offscreen effects and completed trails release animation resources promptly.
- Continuous animation is limited to the approved Reka idle motion and physical Assets that are still awake.

## 10. Failure Handling

- A Home data failure retains the last stable scene and existing refresh-failure treatment.
- Failure to render a production effect must never hide or delay access to the stable Signal or Asset.
- If an object disappears before its queued production begins, its presentation is cancelled.
- If it disappears during production, the effect fades immediately and the stable destination remains absent.
- Failure of one Signal source family follows the partial-source isolation defined in the discovery-detail spec.
- Empty schedule, Signal, or Asset states collapse naturally without placeholder cards.

## 11. Verification

Widget/unit tests must cover:

- optional header schedule slot for scheduled and unscheduled days;
- 1/3 Signal and 2/3 Asset layout intent across supported device heights;
- Reka content z-order and reserved chrome bounds;
- borderless Signal and Asset regions;
- one visible Signal slot plus additional paging;
- Overdue/Rhythm/Report taps using canonical destinations;
- existing Asset collision, drag, tilt-gravity, and detail behavior;
- initial IDs not replaying production;
- new Asset radial condensation and physics handoff;
- new Signal horizontal alignment and vertical rise;
- straight vertical motion with no routing state;
- sequential presentation and overflow-cap behavior;
- refresh/rebuild not replaying stable IDs;
- Reduce Motion stable destinations;
- renderer/effect failure preserving content.

Golden/visual tests must cover:

- schedule present and absent;
- empty and populated Signal band;
- sparse and dense Asset chamber;
- Reka above each content region;
- weak field at rest and during formation;
- Dither object material contrast;
- short and tall phones;
- supported large text scale.

True-device acceptance must verify:

- Reka dragging across Signal and Asset regions without clipping or gesture theft;
- a newly created Asset condensing near the current Reka position, falling, colliding, and settling;
- a newly arrived Signal aligning near the current Reka position, rising, and becoming tappable in the band;
- no production replay after refresh or returning to Today;
- no full-page Dither background;
- stable frame pacing and correct lifecycle pause/resume.

## 12. Non-goals

- no full-page Dither or Matrix Dot background;
- no dark-mode redesign in this iteration;
- no visible bordered Asset container or Signal card container;
- no change to existing Asset physics rules;
- no signal pathfinding, curved route, orbit, or target-seeking animation;
- no automatic continuous Signal marquee;
- no additional Reka facial expressions or speech animation;
- no change to the Reminder, Snooze, Rhythm, or Report semantics defined by the companion discovery-detail spec.
