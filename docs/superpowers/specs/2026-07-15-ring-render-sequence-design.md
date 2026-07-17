# Eureka Ring Render Sequence Design

## Goal

Replace the homepage's realtime WebGL product rendering with a scroll-driven image sequence rendered from the original Blender scene. The result must preserve the realism of the approved product stills while retaining the existing continuous hero → connect → mode-selection journey.

The ring remains a visual object on the demo website. Physical ring gestures do not control this page.

## Source of Truth

- Geometry, circuit placement, materials, bevels, normals, and relative transforms come from `戒指_副本.blend`.
- The six supplied transparent product renders (`1.png`–`6.png`) are the visual reference for silhouette, highlights, circuit visibility, and black finish.
- Hand geometry is hidden from rendering. Ring geometry is not reconstructed in the web application.
- Browser-side filters must not be used to imitate silver from black; silver receives its own physically rendered sequence.

## Deliverables

1. A reproducible Blender render script under `tools/ring-render/`.
2. Six low-sample key-pose previews for approval before a batch render.
3. Two synchronized 60-frame sequences:
   - matte black
   - silver gray
4. Optimized transparent WebP assets in:
   - `ring-demo/public/ring/sequence/black/`
   - `ring-demo/public/ring/sequence/silver/`
5. A Canvas-based sequence player replacing the realtime 3D homepage renderer.
6. A static poster fallback for unsupported or reduced-motion environments.

## Motion Choreography

The 60 frames form a closed product orbit. Frame 59 returns visually to frame 0 so continued rotation does not jump.

The orbit is a designed quaternion camera/product path rather than a mechanical rotation around one axis. It passes through five key poses derived from the approved stills:

| Frame | Reference | Purpose |
| --- | --- | --- |
| 0 / 59 | `5.png` | Hero three-quarter product pose |
| 10 | `1.png` | Thin side silhouette and exterior highlight |
| 22 | `4.png` | Interior circuit reveal and Connect pose |
| 34 | `3.png` | Full aperture and inner-wall construction |
| 46 | `6.png` | Upright three-quarter product pose |

Quaternion interpolation prevents rotational flips between key poses. The product remains centered in an identical transparent 1440 × 1440 frame throughout the sequence. Camera, focal length, exposure, world lighting, and crop remain locked across both color variants.

## Rendering Treatment

- Use the renderer and color management already stored in the Blender source when they reproduce the approved stills.
- Enable transparent film and preserve premultiplied-alpha-safe edges.
- Preserve the existing circuit materials for both variants.
- Black finish should retain a narrow neutral highlight without lifting the body into gray plastic.
- Silver gray changes only the exterior finish; the inner liner and electronics remain unchanged.
- Preview renders use reduced samples. Final renders use the source scene's production samples and denoising.
- Batch rendering starts only after the six key-pose previews visually match the approved stills.

## Asset Pipeline

Blender outputs lossless transparent PNG masters to a local ignored working directory. A deterministic optimization command converts them to WebP for the repository.

Repository asset constraints:

- 1440 × 1440 pixels per frame.
- 60 frames per color, 120 WebP files total.
- Sequential zero-padded names: `frame-000.webp` through `frame-059.webp`.
- Total optimized sequence budget: 30 MB maximum.
- If the first optimization pass exceeds 30 MB, quality is reduced before resolution or frame count. The two sequences must keep identical filenames and dimensions.
- PNG masters are not committed.

The render script records the Blender version, source-file checksum, render settings, key poses, material overrides, and output manifest so another Mac can regenerate the sequence.

## Web Architecture

### `RingSequencePlayer`

A dedicated Canvas component owns image decoding and drawing. It receives:

- journey progress
- unbounded rotation offset
- black-to-silver mix
- focused mode
- connection status
- reduced-motion preference

It resolves these inputs into a frame index, position, scale, opacity, and color-sequence blend. The component does not know page section geometry.

### Frame Selection

- The existing journey controller remains the source of scroll progress and page position.
- Journey progress selects the authored pose needed by Hero, Connect, and Mode sections.
- Additional scroll rotation wraps with modulo 60 and can continue for any number of turns.
- Frames are snapped to integer indices. Angular crossfades are avoided because they create double silhouettes.
- Black and silver frames at the same index may be blended because their geometry and camera are identical.

### Compositing

The player uses one visible Canvas rather than 120 DOM images. For each draw it composites at most two decoded images: the black frame and the matching silver frame. Existing CSS positioning still moves the product continuously between the hero, Connect, and Mode anchors.

Mode hover adds restrained side illumination as a Canvas overlay clipped to the ring image alpha. It does not modify the rendered hardware or fake new geometry.

## Loading and Performance

- The hero poster and the first six surrounding frames load immediately.
- Frames around the current scroll position load next.
- Remaining frames decode during idle time in distance-from-current order.
- A bounded decoded-image cache prevents repeated decoding while avoiding uncontrolled memory growth.
- The sequence player keeps the last successfully decoded frame visible while a requested frame loads.
- The Connect and Mode keyframes are priority-loaded because they are required demo stops.
- Rendering uses `requestAnimationFrame`; multiple scroll and pointer events collapse into a single draw.

## Fallbacks

- `prefers-reduced-motion`: show the approved hero poster and switch only at section boundaries without continuous playback.
- Canvas or image decode failure: retain the static poster and keep navigation and mode selection functional.
- Missing silver frame: draw the matching black frame rather than a CSS color filter.
- Slow decode: retain the prior frame; never flash an empty Canvas.

The current realtime GLB renderer remains available during development behind a local fallback flag. It is removed from the default homepage path once the sequence passes visual approval.

## Testing

Automated tests cover:

- progress-to-frame mapping and modulo wrapping
- authored Hero, Connect, and Mode stop frames
- synchronized black/silver filenames
- same-index color blending only
- priority preload order
- bounded cache behavior
- missing-frame fallback
- reduced-motion behavior
- Canvas draw coalescing
- no regression in ring connection or mode navigation

Build verification includes the existing unit suite, TypeScript checking, production build, and asset-manifest validation. Visual approval compares the six generated preview poses against the supplied reference renders before the full batch is rendered.

## Out of Scope

- Ring gestures controlling the marketing/demo page
- Rebuilding the ring or circuit in Three.js
- AI-generated intermediate product views
- Video-only playback without scroll control
- Changes to Flash or Vibe dedicated mode-page interactions

## Acceptance Criteria

- The homepage ring no longer exposes low-poly realtime geometry.
- Hero, Connect, and Mode poses preserve the visual quality of the approved stills.
- Scroll playback is continuous in both directions and can wrap without a visible seam.
- Black-to-silver transition does not produce geometry ghosting.
- The full sequence stays within the 30 MB optimized asset budget.
- A newly cloned local demo can use the committed WebP sequence without Blender; Blender is required only to regenerate assets.
