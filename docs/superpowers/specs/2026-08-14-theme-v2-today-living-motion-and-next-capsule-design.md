# Theme V2 Today Living Motion and Next Capsule Design

**Date:** 2026-08-14  
**Status:** Approved design, pending written-spec review  
**Scope:** Theme V2 Today light surface, date header, Next capsule, three-lane Reka discovery motion, Reka-following Dither field, dynamic Signal and Asset materials, and paired count watermarks

## 1. Authority and Objective

This document is the implementation authority for the Today behavior in its stated scope. When an earlier Today document or prototype conflicts with this document, this document wins for:

- the date and Next presentation in the header;
- the number, direction, and lifecycle of Signal lanes;
- the placement and naming of the Signal and Asset count watermarks;
- the continuous Dither motion of Reka, Signals, and Assets;
- refresh, lifecycle, and Reduce Motion behavior for those animations.

The design must make Today feel like one calm, living production surface without introducing a full-page dot background or returning to a bordered dashboard. Reka remains the visual source of discoveries and generated Assets. Discoveries rise from Reka and enter a continuous horizontal flow; generated Assets condense near Reka and fall into the existing physical chamber.

This specification is self-contained. Implementation does not depend on a separate design handoff to interpret these behaviors.

## 2. Page Structure

The Today surface uses the following vertical structure:

1. floating Top Dock;
2. date and Next capsule row;
3. Reka discovery region, approximately one third of the remaining content height;
4. Reka generation region, approximately two thirds of the remaining content height;
5. floating Bottom Dock.

The one-third/two-thirds ratio is a target rather than a fixed pixel split. Safe areas, text scaling, short devices, and Dock clearance may adjust it. The generation region remains visually dominant.

Neither content region is a conventional card. Both retain a solid page background with only a very faint, local, irregular Dither atmosphere.

## 3. Date and Next Capsule

### 3.1 Date

The header does not display the title `今日`.

The left side displays one localized date line using the compact pattern:

```text
8月14日 · 周五
```

The date is the primary header text. It must remain on one line and must not be compressed by the Next capsule.

### 3.2 Capsule appearance

The right side uses a stable floating capsule that belongs to the same visual family as the Top and Bottom Docks:

- rounded translucent solid surface;
- soft elevation shadow;
- no visible stroke;
- no Dither material;
- no English `NEXT` label;
- stable height and width between populated and empty states.

The capsule is visually lighter and smaller than either navigation Dock. It must read as an information entry, not as a third navigation bar or a temporary text placeholder.

### 3.3 Populated state

The capsule displays:

- the item's local start or due time, such as `14:30`;
- one truncated title line;
- a relative countdown such as `45 分钟后` or `1 小时 20 分钟后`;
- a restrained chevron that communicates the Agenda entry.

The countdown updates at minute precision. A positive partial minute rounds up, so an item 20 seconds away displays `1 分钟后`; reaching the item's displayed local minute advances the capsule. It never displays seconds and never displays an `进行中` state.

Timed Events use their start time. Timed Todos use their due time. Untimed and date-only content does not enter the Next capsule.

### 3.4 Advancement

Next always represents work whose displayed time has not arrived.

At the displayed minute, the current item immediately leaves Next and the capsule selects the next future timed item. The previous item is not retained as current or ongoing. If multiple items share the same displayed local minute, the entire minute group advances together.

For a same-minute group, the capsule displays the first item from the repository's canonical chain order plus `+N`. Tapping opens the canonical Today Agenda focused on that minute group.

### 3.5 Empty state

When there is no future timed item today, the capsule remains in place and displays:

```text
今天暂无安排
```

The same copy is used whether the day began without timed items or all earlier items have reached their time. There is no separate completed-day message.

The populated and empty capsules are both tappable and open the canonical Today Agenda. Keeping the capsule present prevents the date row from changing geometry as time advances.

### 3.6 Failure state

A request failure must not be rendered as a valid empty schedule. The surface keeps the last valid Next value when available and uses the existing recoverable Today refresh failure treatment. `今天暂无安排` appears only after a successful load determines that no future timed item exists.

## 4. Paired Region Watermarks

The two content regions share one count-watermark component and use different horizontal anchors.

### 4.1 Reka discovery watermark

The Signal region uses:

```text
5
Reka 发现
```

- anchored on the left side of the Signal region;
- large low-opacity count above a small monospaced label;
- left-aligned;
- count equals all currently valid Reka Signals, not only the strips visible in the three lanes.

### 4.2 Reka generation watermark

The Asset region uses:

```text
12
Reka 生成
```

- anchored on the right side of the Asset region;
- large low-opacity count above a small monospaced label;
- right-aligned;
- count equals the canonical true Asset count represented by the chamber.

`Reka 生成` replaces the previous `今日生成` label.

### 4.3 Shared behavior

The two watermarks use the same typography, accent color, opacity, spacing, and count formatting tokens. Their left/right offset creates an intentional vertical stagger rather than two duplicated right-side templates.

Watermarks sit behind moving content, ignore pointers, and are excluded from accessibility semantics. They are region identity and count, not buttons. A zero-count watermark is absent; the page does not add separate Signal or Asset empty-state copy in this tranche.

## 5. Reka Discovery Region

### 5.1 Three continuous lanes

The Signal region contains at most three horizontal motion lanes.

- Signals move continuously from left to right.
- One to three active Signals occupy distinct lanes without duplicating content to fill empty lanes.
- More than three Signals rotate through the three lanes according to the existing Signal priority order.
- A following strip may enter only after the previous strip on that lane has cleared the right boundary and the lane's stagger delay has elapsed.
- Lanes use different vertical positions, speeds, and re-entry delays so they do not form a synchronized grid.
- Signal IDs determine stable lane, speed-band, delay, and Dither seed choices.

The region edges dissolve the strip material naturally. There is no bordered viewport, hard clipping line, or visible marquee container.

### 5.2 Signal interaction

Signal strips are not draggable. A pointer down or tap pauses only the targeted strip long enough to preserve a reliable hit target. A completed tap opens the Signal's canonical detail surface. Closing or cancelling the interaction resumes its lane.

The watermark does not open the full Signal list. Existing Reka navigation remains responsible for the full list.

### 5.3 New Signal production

A genuinely new Signal first forms near the current Reka position:

1. local points increase in density;
2. the points align horizontally and condense into the strip body;
3. solid icon and text appear after the body is legible;
4. the strip rises into an available discovery lane;
5. ownership transfers to the continuous lane system.

Signals already present on the initial successful load enter their stable lanes directly. Initial load, ordinary refresh, and app resume do not replay production.

## 6. Reka Generation Region

The existing Asset balls retain their physical behavior:

- newly generated Assets condense near Reka;
- the completed ball falls into the Asset region;
- gravity, device tilt, dragging, collisions, and settling remain owned by the Asset chamber;
- Reka is not part of the collision simulation;
- stable Assets do not replay generation after refresh or app resume.

The Dither motion inside a ball must not modify the ball's collision radius, silhouette, hit target, or physical center.

## 7. Continuous Dither System

### 7.1 Shared clock and independent seeds

Reka's local field, Signal materials, zone atmospheres, and Asset materials share one lifecycle-aware animation clock. Each object derives a stable seed and phase offset from its identity. This keeps animation efficient without making the page breathe in sync.

The animation system must avoid per-object unbounded controllers. One shared listenable or ticker may drive multiple painters, while each painter computes its local phase from the shared time plus its seed.

### 7.2 Reka-following field

A weak local Dither field follows Reka's current center with restrained spring lag.

- it moves whenever Reka moves;
- it continues a slow density breath while Reka rests;
- it has no visible outline, circular border, or closed halo;
- it briefly gains density during Signal or Asset formation;
- it never expands into a full-page point field;
- it has no gesture behavior independent of Reka.

The follow lag may smooth abrupt drag updates, but the field must remain visibly attached to Reka rather than trailing as a separate object.

### 7.3 Signal material

Signal strips combine two motion layers:

1. the whole strip travels through its lane from left to right;
2. its internal Dither phase drifts horizontally and changes density slightly.

The internal drift may create a short fading tail near the trailing edge. Text, icon, hit target, and semantic label remain stable and readable. Point movement must not resemble noise flicker.

### 7.4 Asset material

Each Asset ball uses a different slow phase direction, amplitude, and density breath. The motion remains local to the ball and intentionally irregular. It must not rotate the label, deform the circle boundary, or cause visible shimmering at text edges.

### 7.5 Zone atmosphere

The discovery and generation regions may each use an extremely faint dynamic Dither field:

- discovery: horizontally biased drift that supports the lane direction;
- generation: small irregular density changes that become slightly stronger toward the floor.

These atmospheres remain weaker than Reka and all produced objects. Solid background air remains visible between the regions.

## 8. Refresh and Lifecycle Stability

Ordinary data refresh reconciles identities instead of restarting the scene.

- Existing Signal IDs retain their lane family, speed band, delay seed, and Dither seed.
- Existing Asset IDs retain their physics ownership and material seed.
- Only added identities enter the production coordinator.
- Removed identities retire through their existing bounded exit behavior.
- A refresh must not return every Signal to the left edge.
- A refresh must not respawn stable Asset balls near Reka.

A partial or full request failure keeps the last valid Signal and Asset source data when available. Failure does not fabricate a zero count, clear a watermark, or replay production. The existing recoverable Today refresh treatment communicates the failure independently.

When Today becomes inactive, the app enters the background, or the surface leaves the tree, continuous ticker and physics work pause. Resume recomputes a reasonable current phase without replaying every off-screen loop or production event.

## 9. Layering and Boundaries

The visual order is:

```text
floating Top and Bottom Docks
Next capsule and system chrome
Reka gesture target and 3D object
new Signal and Asset production effects
Signal strips and Asset balls
Reka 发现 and Reka 生成 watermarks
weak local zone atmospheres
solid page background
```

Reka remains the topmost content object and may visually cross the boundary between discovery and generation. Its drag bounds continue to reserve the date/Next row, both navigation Docks, and system safe areas.

Signal strips cannot enter the date/Next row or the Bottom Dock clearance. Asset balls cannot enter the Signal lanes or navigation clearance.

## 10. Accessibility and Reduced Motion

- The date and full Next title/time/countdown are available to semantics even when the visual title truncates.
- The empty Next capsule exposes `今天暂无安排，打开今日安排`.
- Each Signal exposes its full static label and action independent of its animated position.
- Watermarks are decorative and excluded from semantics because canonical counts are available through their content surfaces.
- Text scaling preserves a one-line date and a usable capsule hit target; compact layouts may reduce visual title width before reducing touch size.
- Minimum interactive target size remains 44 logical pixels.

With Reduce Motion enabled:

- Signal lane translation stops;
- Signal and Asset internal Dither drift stops;
- Reka's field becomes static at its current position;
- production resolves through a short opacity/position handoff without looping particles;
- Next still advances when time changes;
- Asset physics uses its existing reduced-motion stable layout.

## 11. Verification

### 11.1 Widget and unit tests

Tests must cover:

- localized date without the `今日` title;
- populated and empty Next capsule geometry;
- minute-level countdown updates;
- immediate advancement at the displayed minute with no `进行中` state;
- same-minute group removal and `+N` presentation;
- untimed and date-only items excluded from Next;
- failure preserving last valid Next data rather than showing valid empty copy;
- one, two, and three Signal lane assignments without duplication;
- more than three Signals rotating through three lanes;
- stable lane and seed assignment across refresh;
- Signal tap pause and canonical detail opening;
- left-aligned `Reka 发现` and right-aligned `Reka 生成` watermarks;
- watermark counts using canonical totals and disappearing at zero;
- initial load not replaying production;
- new Signal rising into a lane and new Asset falling into the chamber;
- app lifecycle pause/resume;
- Reduce Motion behavior.

### 11.2 Device verification

Verify on the connected Android device at normal and enlarged text scale:

- the date never collides with the Next capsule;
- the capsule looks like a deliberate lightweight sibling of the Docks;
- three lanes remain readable and visually independent;
- left/right watermark staggering is visible without competing with content;
- Reka's local field follows dragging without detaching;
- Signal and Asset point motion is irregular but calm;
- sustained animation remains smooth and does not cause abnormal battery, GPU, or WebView activity;
- no object enters the navigation or system safe areas.

## 12. Non-goals

- no full-page matrix or dot background;
- no interactive point field independent of Reka;
- no manual dragging or scrubbing of Signal lanes;
- no new Agenda information architecture;
- no `进行中` state in the Next capsule;
- no separate empty-state illustration for Signals or Assets;
- no Dark Mode treatment in this tranche;
- no application of the Dither system to other pages.
