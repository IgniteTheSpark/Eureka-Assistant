# Ring Demo Continuous Product Journey Design

Date: 2026-07-15
Status: Approved for implementation

## Goal

Replace the Home page's discrete poster jumps with one continuous, scroll-driven
Ring journey. The Ring remains the same living product from Hero through Connect
and into mode selection. Its position, scale, orientation, rotation, material
color, and lighting respond continuously to scroll and hover.

This change is limited to Home and the mode-selection presentation. Flash and
Vibe workflows, Ring Desktop behavior, connection behavior, and mode routes do
not change.

## Product Journey

The page exposes one normalized journey progress value from `0` to `1`, derived
from the actual Home scroll range rather than a `hero` / `launcher` threshold.
The product presentation interpolates between three anchors:

1. **Hero anchor** — a large Ring sits to the right of the headline in matte
   graphite-black titanium.
2. **Connect anchor** — the Ring moves into the left-hand connection showcase.
   Its spatial position holds through the Connect reading interval while its
   rotational angle and black-to-silver material transition continue responding
   to scroll.
3. **Mode anchor** — the Ring leaves Connect and moves onto the vertical axis
   between Flash and Vibe. Its vertical diameter aligns with the split so one
   half belongs visually to each mode.

The movement curve is piecewise but continuous. Anchor holds are created by
mapping a progress interval to the same spatial pose, not by pinning or blocking
the document. The user can always continue scrolling normally.

## Rotation

Rotation is not capped to a fixed number of turns. The target rotation is
derived from absolute scroll distance, so additional scrolling continues the
360-degree product inspection. A damped renderer follows the target, producing
weight when scrolling starts and a natural settle when scrolling stops.

The Ring keeps a modest fixed product-camera tilt while its product axis rotates.
This prevents a flat front-on pose and keeps both the outer shell and restrained
inner structure legible.

Reduced-motion users receive the same spatial anchors without continuous spin or
pointer parallax.

## Geometry and Rendering

Home defaults to real-time WebGL rather than switching between still images.
The current GLB remains the source for internal electronics and product details.
Its low-resolution visible shell is replaced by a high-segment procedural band
whose profile has:

- a broad, nearly flat exterior face;
- softly rounded outer shoulders;
- a restrained rounded inner liner;
- sufficient radial segmentation to preserve a circular silhouette at Hero
  scale.

The existing PNG renders remain as load/error fallbacks only.

The procedural shell and retained details live under one transform group so
scroll motion never reveals a handoff between render media.

## Materials and Color Journey

The shell uses a micro-textured titanium treatment rather than glossy plastic:

- high but not mirror-like metalness;
- medium micro-roughness;
- broad softbox reflections;
- subtle normal variation without visible decorative noise;
- a darker, rougher inner liner so the interior stays visually subordinate.

The base product color follows the journey continuously:

- Hero: deep graphite black;
- Connect arrival: cool silver-gray titanium;
- Connect departure through Mode: return to graphite black.

The interpolation affects base color, roughness, metalness, and reflection
intensity together so the transition reads as a material finish change rather
than a simple RGB fade.

## Mode Hover Lighting

At the Mode anchor the Ring straddles the Flash / Vibe split.

- Hover or keyboard-focus on Flash introduces a warm gold key light on the left
  half.
- Hover or keyboard-focus on Vibe introduces a cool blue key light on the right
  half.
- The opposite half remains black titanium with restrained neutral reflections.
- Leaving both modes eases both accent lights back to zero.

The shell material itself does not turn gold or blue. The response is lighting,
not recoloring, so the two real product finishes remain credible.

## Scroll and Component Architecture

`HomePage` owns scroll measurement. A GSAP ScrollTrigger writes one continuous
journey progress and an uncapped rotational distance. React state is limited to
coarse semantic state such as focused mode and connection activity; per-frame
motion is held in mutable refs to avoid render-driven stepping.

`LivingRingStage` owns the persistent viewport-level product layer and fallback.
It does not infer location from a progress threshold.

`LivingRingScene` owns WebGL interpolation, procedural shell geometry, retained
GLB detail meshes, material interpolation, damped rotation, and accent lights.

Pure motion functions define anchor interpolation and material phase values so
the journey can be tested without WebGL.

## Responsive Behavior

Desktop and tablet use the full three-anchor journey. On narrow mobile layouts,
the Ring remains in the Hero composition and fades before the vertically stacked
mode cards; it does not cover actionable content. Mobile keeps the product color
transition but disables pointer parallax and mode-split lighting when the Ring is
not visible.

## Failure and Performance Behavior

- If WebGL or GLB loading fails, the best matching PNG fallback remains visible.
- The fallback follows the same spatial CSS variables but does not attempt
  material-color interpolation.
- Device pixel ratio remains capped.
- The procedural band is created once and materials are mutated in place.
- No React state update occurs on every render frame.

## Verification

Automated verification covers:

- continuous anchor interpolation with no threshold jump;
- Connect spatial hold while rotation and color continue;
- final mode-axis placement;
- black-to-silver-to-black material phases;
- reduced-motion stabilization;
- left/right hover-light selection;
- existing Home navigation, connection, Flash, and Vibe regressions.

Manual browser verification covers desktop scroll continuity, Connect alignment,
mode-axis alignment, hover lighting, material realism, WebGL fallback, and a
390-pixel viewport with no horizontal overflow.
