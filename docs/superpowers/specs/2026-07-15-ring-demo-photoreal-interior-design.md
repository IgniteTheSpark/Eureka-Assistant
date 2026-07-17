# Ring Demo Photoreal Interior Correction

## Goal

Remove the toy-like appearance of the Ring interior while preserving the approved Living Object interaction. The result should read like premium hardware product photography: the exterior silhouette is primary, the interior is physically plausible but visually restrained, and connection effects never look like an inserted UI ring.

## Scope

This correction changes only the Home page 3D presentation and its PNG fallback pose. It does not change Ring Desktop protocols, physical Ring gesture mappings, connection behavior, or the Flash and Vibe pages.

## Product pose

- The Hero uses a three-quarter product angle with 25–35 degrees of yaw. The exterior shell and edge highlight occupy most of the visual attention.
- The camera must not look straight through the center of the Ring.
- The launcher settles closer to frontal but retains 12–18 degrees of yaw so the object keeps depth and the simplified interior is never presented as a technical cutaway.
- Flash and Vibe focus add only a small directional lean on top of the launcher base angle.

## Materials

- Remove the synthetic gray inner torus from the 3D scene.
- Treat the inner liner as near-black, moderately rough material. It should receive soft reflections without creating broad white patches.
- Keep the outer shell as dark metal with narrow, controlled highlights.
- Preserve gold contacts and sensor details as separate accents. They may catch light, but must not emit a constant glow.
- Do not rebuild or invent additional interior hardware in this pass.

## Lighting

- Replace hard direct illumination with a soft key light, a weaker cool fill, and a narrow rim light.
- The key light should reveal the outer curvature without illuminating the entire interior.
- The interior remains approximately one to two stops darker than the exterior edge highlight.
- Avoid post-processing bloom and environment effects that flatten the matte-black finish.

## Connection effects

- Scanning moves to a background orbit or exterior-edge sweep. It must not draw a complete ring inside the product.
- Connecting may tighten the background orbit and rotate the product toward its launcher pose.
- Connected state uses a very subtle warm pulse at real contact or sensor locations. If those mesh locations cannot be isolated reliably, use a restrained light reflection instead of a fabricated sensor glow.
- Failure and disconnected states do not add new visual effects.

## Fallback and reduced motion

- The PNG fallback uses the same three-quarter visual hierarchy and remains visible until WebGL and the GLB are ready.
- Reduced motion uses stable Hero and launcher poses with no idle drift or scan rotation.
- WebGL failure must leave all Home content, connection controls, and mode links usable.

## Acceptance criteria

- At the initial Hero viewport, the exterior silhouette and controlled metal highlight are noticed before any interior component.
- No full gray or emissive torus is visible inside the Ring.
- No broad white material patch appears on the inner liner in the verified desktop WebGL capture.
- The launcher Ring does not obscure either mode title in the neutral state.
- Flash and Vibe focus remain visibly distinct without exposing a straight-on interior view.
- Desktop and mobile layouts retain no horizontal overflow.
- Existing Home, Ring connection, Flash, and Vibe automated tests continue to pass.
