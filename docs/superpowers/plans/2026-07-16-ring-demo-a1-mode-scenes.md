# Ring Demo A1 Mode Scenes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat Home mode selector with two photographic Flash/Vibe scenes, a persistent center Ring runway, and a reversible 3D-to-photograph handoff.

**Architecture:** `HomePage` owns one focused-mode state and renders a focused `ModeSceneStage`. Pure scene-layout and Ring-target resolvers translate that state into CSS layout variables and 3D poses; `LivingRingScene` continues rendering the existing GLB and only consumes the resolved pose. Cleaned scene images contain no marketing graphics, while all retained copy is semantic HTML.

**Tech Stack:** React 18, TypeScript, React Router, Three.js / React Three Fiber, GSAP ScrollTrigger, CSS Grid, Vitest, Testing Library.

## Global Constraints

- Change only the Home mode-selection section; preserve Hero, connection, Flash, Vibe, Ring Desktop, and backend behavior.
- Keep `/flash` and `/vibe` links available while disconnected.
- Do not pin the page, hijack wheel input, or map physical Ring gestures to Home navigation.
- Remove QR, Early Bird content, circular magnifiers, connector lines, and rasterized hint copy from scene images.
- Recreate command copy and `Speak freely. Capture quietly.` as semantic HTML overlays.
- Use the existing GLB/canvas; do not add another WebGL canvas or video.
- Desktop exhibition layouts at 1440×900 and 1920×1080 are primary.
- At 760 px and below, stack scenes and keep the Ring neutral; do not align it to a photographed finger.
- With `prefers-reduced-motion`, keep the Ring centered and use opacity-only scene emphasis.

---

## File Structure

- Create `ring-demo/public/scenes/flash-driving-clean.webp`: QR-free, magnifier-free Flash scene.
- Create `ring-demo/public/scenes/vibe-office-clean.webp`: QR-free, magnifier-free Vibe scene.
- Create `ring-demo/src/components/mode-scenes/mode-scene-state.ts`: pure layout and handoff configuration/resolution.
- Create `ring-demo/src/components/mode-scenes/mode-scene-state.test.ts`: resolver coverage.
- Create `ring-demo/src/components/mode-scenes/ModeSceneStage.tsx`: semantic route links and scene overlays.
- Create `ring-demo/src/components/mode-scenes/ModeSceneStage.test.tsx`: keyboard, pointer, touch, and route behavior.
- Modify `ring-demo/src/pages/HomePage.tsx`: replace `ModeField` markup with `ModeSceneStage`.
- Modify `ring-demo/src/pages/HomePage.test.tsx`: assert A1 scene stage and Ring focus handoff state.
- Modify `ring-demo/src/components/living-ring/journey-state.ts`: add focus target interpolation and opacity.
- Modify `ring-demo/src/components/living-ring/journey-state.test.ts`: cover neutral/Flash/Vibe/reduced-motion poses.
- Modify `ring-demo/src/components/living-ring/LivingRingScene.tsx`: consume focused pose and fade the live Ring.
- Modify `ring-demo/src/components/living-ring/LivingRingStage.tsx`: expose handoff state for CSS and tests.
- Modify `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`: cover focused and reduced-motion handoff attributes.
- Modify `ring-demo/src/styles.css`: A1 photography, runway, focus expansion, overlays, responsive, and reduced-motion styling.

---

### Task 1: Produce cleaned scene assets

**Files:**
- Create: `ring-demo/public/scenes/flash-driving-clean.webp`
- Create: `ring-demo/public/scenes/vibe-office-clean.webp`

**Interfaces:**
- Consumes: supplied driving and office scene PNG files.
- Produces: opaque photographic WebP assets referenced by `/scenes/flash-driving-clean.webp` and `/scenes/vibe-office-clean.webp`.

- [ ] **Step 1: Inspect both source images at original resolution**

Confirm the face, speaking hand, photographed Ring, vehicle/monitor context, and lighting are preserved. Mark QR, Early Bird block, magnifier, connector lines, command bubble, and `Speak freely. Capture quietly.` as the only edit targets.

- [ ] **Step 2: Edit the Flash scene**

Use a precise-object edit with these invariants:

```text
Remove only the QR code, Early Bird text block, circular Ring magnifier, connector lines, voice-command bubble, and all overlaid marketing text. Reconstruct the obscured car interior and clothing photorealistically. Preserve the man's identity, face, pose, hands, photographed black Ring, vehicle, lighting, camera perspective, and every other detail. Add no new text, jewelry, fingers, logos, or UI.
```

- [ ] **Step 3: Edit the Vibe scene**

Use a precise-object edit with these invariants:

```text
Remove only the QR code, Early Bird text block, circular Ring magnifier, connector lines, voice-command bubble, and all overlaid marketing text. Reconstruct the obscured office, clothing, coffee cup, desk, and monitor areas photorealistically. Preserve the man's identity, face, pose, hands, photographed black Ring, Codex monitor context, lighting, camera perspective, and every other detail. Add no new text, jewelry, fingers, logos, or UI.
```

- [ ] **Step 4: Save project assets and verify dimensions**

Run:

```bash
file ring-demo/public/scenes/flash-driving-clean.webp ring-demo/public/scenes/vibe-office-clean.webp
```

Expected: both files are WebP images, each at least 1000 px on its long edge.

- [ ] **Step 5: Visually verify the edits**

Expected: no QR/magnifier/rasterized copy; no altered face, hand, photographed Ring, or scene geometry; reconstructed regions do not show obvious seams.

### Task 2: Add pure scene-layout and handoff configuration

**Files:**
- Create: `ring-demo/src/components/mode-scenes/mode-scene-state.ts`
- Create: `ring-demo/src/components/mode-scenes/mode-scene-state.test.ts`

**Interfaces:**
- Produces: `ModeScene = "flash" | "vibe"`, `ModeSceneFocus = ModeScene | null`, `MODE_SCENES`, and `resolveModeSceneLayout(focus, compact, reducedMotion)`.

- [ ] **Step 1: Write failing resolver tests**

```ts
import { describe, expect, it } from "vitest";
import { MODE_SCENES, resolveModeSceneLayout } from "./mode-scene-state";

describe("resolveModeSceneLayout", () => {
  it("keeps a neutral center runway", () => {
    expect(resolveModeSceneLayout(null, false, false)).toMatchObject({
      columns: [41, 18, 41],
      ringTarget: "center",
      handoffOpacity: 1,
    });
  });

  it("expands Flash and exposes its calibrated handoff", () => {
    const state = resolveModeSceneLayout("flash", false, false);
    expect(state.columns).toEqual([59, 12, 29]);
    expect(state.ringTarget).toBe("flash");
    expect(state.target).toEqual(MODE_SCENES.flash.handoff.desktop);
  });

  it("keeps the Ring centered on compact and reduced-motion layouts", () => {
    expect(resolveModeSceneLayout("vibe", true, false).ringTarget).toBe("center");
    expect(resolveModeSceneLayout("vibe", false, true).ringTarget).toBe("center");
  });
});
```

- [ ] **Step 2: Run the tests and verify failure**

Run: `npm test -- --run src/components/mode-scenes/mode-scene-state.test.ts`

Expected: FAIL because `mode-scene-state` does not exist.

- [ ] **Step 3: Implement the resolver and typed configuration**

```ts
export type ModeScene = "flash" | "vibe";
export type ModeSceneFocus = ModeScene | null;

export interface RingHandoffTarget {
  position: [number, number, number];
  rotation: [number, number, number];
  scale: number;
}

export const MODE_SCENES = {
  flash: {
    image: "/scenes/flash-driving-clean.webp",
    handoff: { desktop: { position: [-1.42, -0.5, 0], rotation: [-0.5, -0.36, -0.12], scale: 0.24 } },
  },
  vibe: {
    image: "/scenes/vibe-office-clean.webp",
    handoff: { desktop: { position: [1.48, -0.38, 0], rotation: [-0.54, 0.32, 0.12], scale: 0.22 } },
  },
} as const;

export function resolveModeSceneLayout(
  focus: ModeSceneFocus,
  compact: boolean,
  reducedMotion: boolean,
) {
  const ringTarget = compact || reducedMotion ? "center" : (focus ?? "center");
  const columns: [number, number, number] =
    focus === "flash" ? [59, 12, 29] : focus === "vibe" ? [29, 12, 59] : [41, 18, 41];
  return {
    columns,
    ringTarget,
    handoffOpacity: ringTarget === "center" ? 1 : 0,
    target: ringTarget === "center" ? null : MODE_SCENES[ringTarget].handoff.desktop,
  };
}
```

- [ ] **Step 4: Run the resolver tests**

Run: `npm test -- --run src/components/mode-scenes/mode-scene-state.test.ts`

Expected: PASS.

### Task 3: Build the semantic A1 mode scene component

**Files:**
- Create: `ring-demo/src/components/mode-scenes/ModeSceneStage.tsx`
- Create: `ring-demo/src/components/mode-scenes/ModeSceneStage.test.tsx`

**Interfaces:**
- Consumes: `focusedMode: ModeSceneFocus`, `onFocusMode(mode)`, and `reducedMotion`.
- Produces: two direct React Router links, CSS variables `--flash-column`, `--runway-column`, `--vibe-column`, and scene-specific HTML hint overlays.

- [ ] **Step 1: Write failing interaction tests**

```tsx
it("keeps both direct routes and synchronizes pointer and keyboard focus", () => {
  const onFocusMode = vi.fn();
  render(<MemoryRouter><ModeSceneStage focusedMode={null} onFocusMode={onFocusMode} reducedMotion={false} /></MemoryRouter>);
  const flash = screen.getByRole("link", { name: /explore flash/i });
  const vibe = screen.getByRole("link", { name: /explore vibe/i });
  expect(flash).toHaveAttribute("href", "/flash");
  expect(vibe).toHaveAttribute("href", "/vibe");
  fireEvent.pointerEnter(flash);
  expect(onFocusMode).toHaveBeenLastCalledWith("flash");
  fireEvent.focus(vibe);
  expect(onFocusMode).toHaveBeenLastCalledWith("vibe");
});

it("retains command and speaking hints as HTML", () => {
  render(<MemoryRouter><ModeSceneStage focusedMode="flash" onFocusMode={vi.fn()} reducedMotion={false} /></MemoryRouter>);
  expect(screen.getByText("Arrange a meeting for Kevin at 4–5pm.")).toBeInTheDocument();
  expect(screen.getAllByText("Speak freely. Capture quietly.")).toHaveLength(2);
});
```

- [ ] **Step 2: Run the tests and verify failure**

Run: `npm test -- --run src/components/mode-scenes/ModeSceneStage.test.tsx`

Expected: FAIL because `ModeSceneStage` does not exist.

- [ ] **Step 3: Implement `ModeSceneStage`**

Render a `.mode-scene-stage` containing Flash link, `.mode-runway`, and Vibe link. Each link owns an image layer, local gradient, eyebrow/title/description/CTA, `.scene-command`, and `.scene-speaking-hint`. Use `onPointerEnter`, `onPointerLeave`, `onFocus`, `onBlur`, and `onTouchStart` to update visual focus while leaving the anchor's first tap free to navigate.

Use exact copy:

```ts
const copy = {
  flash: {
    title: "Flash Mode",
    description: "Speak a thought and watch Eureka shape it into a useful asset.",
    command: "Arrange a meeting for Kevin at 4–5pm.",
    cta: "Explore Flash",
  },
  vibe: {
    title: "Vibe Mode",
    description: "Use voice and gesture to move directly through Codex and DingTalk.",
    command: "Help me execute this plan and push it to GitHub.",
    cta: "Explore Vibe",
  },
} as const;
```

- [ ] **Step 4: Run component tests**

Run: `npm test -- --run src/components/mode-scenes/ModeSceneStage.test.tsx`

Expected: PASS.

### Task 4: Connect the scene stage to Home

**Files:**
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/pages/HomePage.test.tsx`

**Interfaces:**
- Consumes: `ModeSceneStage`.
- Produces: focused mode shared by the scene stage and persistent Ring canvas.

- [ ] **Step 1: Update the Home test to require A1 scene markup**

Add assertions:

```ts
expect(screen.getByTestId("mode-scene-stage")).toHaveAttribute("data-focused-mode", "neutral");
expect(screen.getByAltText("Flash Mode: Ring capture while driving")).toHaveAttribute("src", "/scenes/flash-driving-clean.webp");
expect(screen.getByAltText("Vibe Mode: Ring control beside Codex")).toHaveAttribute("src", "/scenes/vibe-office-clean.webp");
```

Remove assertions for `.mode-fields-backdrop`.

- [ ] **Step 2: Run the Home test and verify failure**

Run: `npm test -- --run src/pages/HomePage.test.tsx`

Expected: FAIL because A1 scene markup is absent.

- [ ] **Step 3: Replace `ModeField` and `.mode-fields`**

Delete the local `ModeField` component from `HomePage.tsx`, import `ModeSceneStage`, and render:

```tsx
<ModeSceneStage
  focusedMode={focusedMode}
  onFocusMode={setFocusedMode}
  reducedMotion={reducedMotion}
/>
```

- [ ] **Step 4: Run the Home test**

Run: `npm test -- --run src/pages/HomePage.test.tsx`

Expected: PASS.

### Task 5: Add Ring focus targets and live-to-photo fade

**Files:**
- Modify: `ring-demo/src/components/living-ring/journey-state.ts`
- Modify: `ring-demo/src/components/living-ring/journey-state.test.ts`
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.test.tsx`

**Interfaces:**
- Consumes: `focusedMode`, compact viewport, reduced motion, and `MODE_SCENES` targets.
- Produces: `RingJourneyPose.opacity` plus a focus-adjusted position/rotation/scale.

- [ ] **Step 1: Write failing journey tests**

```ts
it("moves from the runway toward the Flash photo target", () => {
  const neutral = resolveRingJourney(1, false, null, false);
  const flash = resolveRingJourney(1, false, "flash", false);
  expect(flash.position[0]).toBeLessThan(neutral.position[0]);
  expect(flash.scale).toBeLessThan(neutral.scale);
  expect(flash.opacity).toBe(0);
});

it("keeps reduced-motion focus centered and opaque", () => {
  const pose = resolveRingJourney(1, false, "vibe", true);
  expect(pose.position).toEqual(resolveRingJourney(1).position);
  expect(pose.opacity).toBe(1);
});
```

- [ ] **Step 2: Run journey tests and verify failure**

Run: `npm test -- --run src/components/living-ring/journey-state.test.ts`

Expected: FAIL because focused arguments and opacity are not implemented.

- [ ] **Step 3: Extend the pure journey resolver**

Change the signature to:

```ts
export function resolveRingJourney(
  rawProgress: number,
  compactViewport = false,
  focusedMode: LivingRingMode = null,
  reducedMotion = false,
): RingJourneyPose
```

After resolving the existing scroll pose, interpolate from `MODE_POSITION` to the selected `MODE_SCENES[focusedMode].handoff.desktop` target when `modeMix === 1`, the viewport is not compact, and reduced motion is off. Set `opacity` to `1 - smoothstep(0.85, 1, focusProgress)` so only the final 15% fades.

- [ ] **Step 4: Apply the focus pose to the Three.js group**

In `LivingRingScene.tsx`, call:

```ts
const pose = resolveRingJourney(
  journey.progress,
  size.width <= 760,
  input.focusedMode,
  input.reducedMotion,
);
```

Traverse the prepared object once to collect materials, set them transparent, and lerp their opacity to `pose.opacity` without changing circuit geometry or rebuilding the model.

- [ ] **Step 5: Expose handoff state on the stage**

Add `data-handoff-active={Boolean(props.focusedMode && !props.reducedMotion)}` to `LivingRingStage` and test that reduced motion returns `false`.

- [ ] **Step 6: Run living Ring tests**

Run:

```bash
npm test -- --run src/components/living-ring/journey-state.test.ts src/components/living-ring/LivingRingStage.test.tsx
```

Expected: PASS.

### Task 6: Implement A1 visual composition and responsive states

**Files:**
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `.mode-scene-stage.is-flash`, `.is-vibe`, `.mode-scene`, `.mode-runway`, and semantic overlay classes.
- Produces: 41/18/41 neutral, 59/12/29 focus, stacked mobile, and opacity-only reduced-motion visual states.

- [ ] **Step 1: Add desktop grid and photography treatment**

Use CSS variables and explicit layers:

```css
.mode-scene-stage {
  --flash-column: 41fr;
  --runway-column: 18fr;
  --vibe-column: 41fr;
  min-height: min(78svh, 820px);
  display: grid;
  grid-template-columns: var(--flash-column) var(--runway-column) var(--vibe-column);
  position: relative;
  isolation: isolate;
  overflow: clip;
  transition: grid-template-columns 720ms cubic-bezier(.2,.8,.2,1);
}
.mode-scene-stage.is-flash { --flash-column: 59fr; --runway-column: 12fr; --vibe-column: 29fr; }
.mode-scene-stage.is-vibe { --flash-column: 29fr; --runway-column: 12fr; --vibe-column: 59fr; }
.mode-scene-image { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
.mode-runway { position: relative; z-index: 1; border-inline: 1px solid var(--line); background: linear-gradient(180deg, rgb(255 255 255 / 92%), rgb(217 223 229 / 74%)); }
```

Keep copy in local high-contrast gradients and set unfocused scenes to approximately `filter: brightness(.58) saturate(.72)`.

- [ ] **Step 2: Calibrate crops and handoff visibility**

Set separate `object-position` values for Flash and Vibe so faces, speaking hands, photographed Rings, and vehicle/monitor cues stay visible at 1440 and 1920 widths. Place command/speaking overlays away from the target finger and CTA hit area.

- [ ] **Step 3: Add responsive behavior**

At 761–1040 px, retain the split and reduce the runway. At 760 px and below, use one column, two scene cards of at least 70svh, hide `.mode-runway`, and avoid Ring handoff alignment.

- [ ] **Step 4: Add reduced-motion behavior**

Inside `@media (prefers-reduced-motion: reduce)`, disable grid/copy/image motion and use only a short opacity change for scene emphasis.

- [ ] **Step 5: Run component tests and production checks**

Run:

```bash
npm test -- --run src/pages/HomePage.test.tsx src/components/mode-scenes/ModeSceneStage.test.tsx
npm run typecheck
npm run build
```

Expected: all tests PASS; typecheck exits 0; Vite production build exits 0.

### Task 7: Browser QA and visual calibration

**Files:**
- Modify only calibration constants in `ring-demo/src/components/mode-scenes/mode-scene-state.ts` and crop/overlay declarations in `ring-demo/src/styles.css` if QA reveals misalignment.

**Interfaces:**
- Consumes: running Vite app at `http://127.0.0.1:5173/#demo-launcher`.
- Produces: verified exhibition layouts without regressions.

- [ ] **Step 1: Start the existing local services**

Run the repository's established frontend/backend/bridge commands. Verify the Home page loads without `Failed to fetch`; mode links must still work if the Ring is disconnected.

- [ ] **Step 2: QA at 1920×1080 and 1440×900**

Verify neutral separation, Ring arrival, both focus expansions, readable HTML hints, no QR/magnifier, no clipping, correct hand targets, and no double-Ring frame.

- [ ] **Step 3: QA accessibility and fallbacks**

Keyboard-tab both links, confirm visible focus, enable reduced motion, simulate WebGL unavailable, and confirm direct route navigation.

- [ ] **Step 4: Run the full verification suite**

Run:

```bash
npm test -- --run
npm run typecheck
npm run build
git diff --check
```

Expected: all tests PASS; typecheck/build exit 0; no whitespace errors.
