# Ring Demo Living Object Motion Design

## Outcome

Turn the Home page into one continuous product experience: a single 3D Ring feels alive in the Hero, travels into the launcher as the visitor scrolls, reacts to connection state, and leans toward Flash or Vibe as those destinations receive focus.

## Interaction boundary

- Home responds only to browser scroll, pointer, touch, keyboard focus, and the Ring Desktop connection snapshot.
- Physical Ring taps and gestures never navigate or manipulate the Home page.
- Flash and Vibe stay available while disconnected.
- Existing Flash/Vibe behavior and routes remain unchanged.

## Experience

### Hero

The Ring rests in a slow, small idle motion. Pointer movement contributes at most 6–8 degrees of parallax. Copy and the exploration link remain normal semantic DOM. Scrolling toward the next screen moves the same stage into a smaller, more frontal product pose without hijacking native scrolling.

### Connection

Disconnected uses a loose orbit and dim inner surface. Scanning adds a restrained circular sweep. A discovered device remains a normal button in the connection panel. Connecting brings the Ring toward a frontal pose and tightens the orbit; connected adds an inner sensor glow. Failure leaves the disconnected pose visible with the real error message.

### Mode fields

Flash and Vibe are two adjacent environmental fields, not a step-by-step wizard. Hover, keyboard focus, or touch focus on Flash warms the environment and leans the Ring left. Vibe cools the environment and leans it right. Leaving the fields returns it to neutral. Clicking follows normal React Router navigation; any exit flourish must not delay navigation more than 350 ms.

## Architecture

- `LivingRingStage` is one persistent React Three Fiber canvas scoped to Home.
- A small pure motion-state mapper converts scroll progress, connection status, and focused mode into stable scene targets.
- GSAP ScrollTrigger supplies normalized Hero-to-launcher progress. It does not pin or replace native scrolling.
- R3F interpolates scene transforms and material/light intensity in the render loop without React state updates per frame.
- React DOM remains the accessible source of interaction and navigation.
- The supplied GLB is loaded once; the hand mesh is hidden at runtime. A poster PNG displays before WebGL is ready and remains the fallback.

## Performance and accessibility

- Lazy-load the 3D runtime after the semantic page is rendered.
- Cap renderer DPR to 1.5 and avoid post-processing.
- Animate transforms, opacity, light intensity, and shader/material values only.
- `prefers-reduced-motion` uses stable poses and short opacity changes with no scroll scrub or idle motion.
- If WebGL/model loading fails, keep the current PNG product composition fully usable.
- Keyboard focus mirrors pointer focus; visible focus rings remain.
- Mobile uses tap/focus and reduced parallax.

## Verification

- Unit-test the pure motion-state mapping and Home semantics.
- Test that both routes remain available while disconnected and that mode focus updates the stage without navigation.
- Run the full test suite, typecheck, and production build.
- Browser-check desktop and mobile for no overflow, readable copy, fallback behavior, connection-state response, and reduced-motion behavior.
