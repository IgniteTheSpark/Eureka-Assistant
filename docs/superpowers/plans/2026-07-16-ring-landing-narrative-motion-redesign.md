# Eureka Ring Landing Narrative Motion Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorder the Chinese Eureka Ring landing page around Flash, Vibe, system, and 说/触/感 chapters while preserving one full-screen scroll-driven 3D Ring across the complete journey.

**Architecture:** Keep `LivingRingStage` as the only fixed WebGL surface. Move the two scenario images into `LandingStory`, replace one-stop-per-section motion with DOM anchor-driven stops, and remove redundant feature/hardware chapters. Use one data model for copy and one deterministic journey resolver for both the poster and WebGL model.

**Tech Stack:** React 18, TypeScript, GSAP ScrollTrigger, React Three Fiber, Three.js, Vitest, Testing Library, CSS.

## Global Constraints

- Keep exactly one fixed full-screen `LivingRingStage`; do not add another Canvas or duplicate the GLB.
- Remove all links to `/flash` and `/vibe` from the landing page.
- Codex and DingTalk must be described as example software, not the complete support list.
- Remove the five-feature chapter and hardware structure chapter.
- Add three semantic capability chapters: 说 = voice input, 触 = 7 gestures, 感 = 3 vibration patterns.
- Drive all movement from scroll progress; no new permanent animation loop.
- Reduced-motion mode removes handoff, hop, and tumble movement while preserving readable content.
- Preserve the QR placeholder as a direct image element; never restore the recursive `<object>` fallback.

---

### Task 1: Rebuild the semantic landing story

**Files:**
- Modify: `ring-demo/src/components/landing/landing-content.ts`
- Modify: `ring-demo/src/components/landing/landing-content.test.ts`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/pages/HomePage.test.tsx`

**Interfaces:**
- Consumes: `LANDING_CONTENT`, `/scenes/flash-driving-clean.webp`, `/scenes/vibe-office-clean.webp`.
- Produces: `LandingStory` with `flash-intro`, `flash-scene`, `vibe-intro`, `vibe-scene`, `system-start`, `system-end`, `speak`, `touch`, and `feel` anchors.

- [ ] **Step 1: Write failing content and page tests**

```tsx
expect(screen.getByRole("img", { name: /驾驶途中用戒指捕捉闪念/ }))
  .toHaveAttribute("data-ring-chapter", "flash-scene");
expect(screen.getByRole("img", { name: /在 Codex 前用戒指发出指令/ }))
  .toHaveAttribute("data-ring-chapter", "vibe-scene");
expect(screen.getByRole("heading", { name: "说" })).toBeInTheDocument();
expect(screen.getByText(/7 种不同的手势交互/)).toBeInTheDocument();
expect(screen.getByText(/3 种不同的震动反馈/)).toBeInTheDocument();
expect(screen.queryByText("一枚戒指背后的五件事")).not.toBeInTheDocument();
expect(screen.queryByText("从三个视角，看见内外一体的结构。")).not.toBeInTheDocument();
expect(screen.queryByTestId("mode-scene-stage")).not.toBeInTheDocument();
```

- [ ] **Step 2: Run tests and verify RED**

Run: `npm test -- --run src/components/landing/landing-content.test.ts src/components/landing/LandingStory.test.tsx src/pages/HomePage.test.tsx`

Expected: failures because the scenes still live in `ModeSceneStage`, `features` and `hardware` still render, and `senses` does not exist.

- [ ] **Step 3: Implement the content model and semantic sections**

Use this content contract:

```ts
senses: [
  { id: "speak", title: "说", metric: "自然语音输入", description: "无需寻找另一块屏幕，直接说出想法或指令。" },
  { id: "touch", title: "触", metric: "7 种手势交互", description: "用不同手势完成唤醒、切换与控制。" },
  { id: "feel", title: "感", metric: "3 种震动反馈", description: "通过可区分的震动模式确认不同状态。" },
]
```

Render scenario figures inside their matching sections:

```tsx
<figure className="landing-scene landing-scene-flash" data-ring-chapter="flash-scene">
  <img alt="驾驶途中用戒指捕捉闪念" loading="lazy" src="/scenes/flash-driving-clean.webp" />
</figure>
```

Remove `ModeSceneStage` and the `focusedMode` state from `HomePage`. Keep a text-only `demo-launcher` transition and pass `focusedMode={null}` to `LivingRingStage`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `npm test -- --run src/components/landing/landing-content.test.ts src/components/landing/LandingStory.test.tsx src/pages/HomePage.test.tsx`

Expected: all targeted tests pass.

### Task 2: Replace section stops with internal scroll anchors

**Files:**
- Modify: `ring-demo/src/components/living-ring/landing-journey.ts`
- Modify: `ring-demo/src/components/living-ring/landing-journey.test.ts`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingStage.tsx`
- Modify: `ring-demo/src/components/living-ring/LivingRingScene.tsx`

**Interfaces:**
- Consumes: DOM elements with `data-ring-chapter` values from Task 1.
- Produces: `LANDING_RING_STOPS` and `resolveLandingRingFrame()` for twelve ordered anchors.

- [ ] **Step 1: Write failing journey tests**

```ts
expect(LANDING_RING_STOPS.map(({ id }) => id)).toEqual([
  "hero", "modes", "flash-intro", "flash-scene", "vibe-intro", "vibe-scene",
  "system-start", "system-end", "speak", "touch", "feel", "community",
]);
expect(stop("flash-scene").opacity).toBe(0);
expect(stop("vibe-scene").opacity).toBe(0);
expect(stop("system-start").scale).toBeLessThanOrEqual(0.32);
expect(stop("speak").position[0]).toBeGreaterThan(0.9);
expect(stop("touch").rotation[1]).toBeGreaterThan(stop("speak").rotation[1] + Math.PI);
```

- [ ] **Step 2: Run tests and verify RED**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts`

Expected: failures because the old eight-stop journey has no scene handoff or senses anchors.

- [ ] **Step 3: Implement the twelve-stop deterministic journey**

Set exact stop progress values in ascending order:

```ts
const progress = {
  hero: 0,
  modes: 0.12,
  "flash-intro": 0.22,
  "flash-scene": 0.34,
  "vibe-intro": 0.43,
  "vibe-scene": 0.55,
  "system-start": 0.64,
  "system-end": 0.72,
  speak: 0.80,
  touch: 0.87,
  feel: 0.94,
  community: 1,
};
```

Use `opacity: 0` at both scene handoff stops, a centered `scale <= 0.32` for system stops, and right-rail positions for all three senses. Give `touch` and `feel` monotonically increasing Y-axis rotations to produce one scroll-controlled tumble per transition.

Change the anchor query to:

```ts
home.querySelectorAll<HTMLElement>("[data-ring-chapter]")
```

Remove obsolete mode-hover handoff calculations from both poster and WebGL scene; the landing journey is now the only pose source.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `npm test -- --run src/components/living-ring/landing-journey.test.ts src/components/living-ring/LivingRingStage.test.tsx src/pages/HomePage.test.tsx`

Expected: all targeted tests pass.

### Task 3: Art-direct scenes, Neon system rail, and senses rail

**Files:**
- Modify: `ring-demo/src/styles.css`
- Modify: `ring-demo/src/components/landing/LandingStory.tsx`
- Modify: `ring-demo/src/components/landing/LandingStory.test.tsx`

**Interfaces:**
- Consumes: semantic classes and anchors from Task 1.
- Produces: desktop, tablet, mobile, and reduced-motion layouts without text overlap.

- [ ] **Step 1: Add failing structural assertions**

```tsx
expect(container.querySelector(".landing-system-rail")).toBeInTheDocument();
expect(container.querySelectorAll(".sense-row")).toHaveLength(3);
expect(container.querySelector(".hardware-gallery")).not.toBeInTheDocument();
expect(container.querySelector(".feature-bands")).not.toBeInTheDocument();
```

- [ ] **Step 2: Run test and verify RED**

Run: `npm test -- --run src/components/landing/LandingStory.test.tsx`

Expected: failure because the new Neon rail and sense rows are not present.

- [ ] **Step 3: Implement responsive CSS and visual hierarchy**

Use a single central pseudo-element for the system rail:

```css
.landing-system-rail::before {
  content: "";
  position: absolute;
  inset-block: 0;
  left: 50%;
  width: 1px;
  background: linear-gradient(transparent, #39d7c1 12%, #d9fffa 50%, #39d7c1 88%, transparent);
  box-shadow: 0 0 10px rgb(57 215 193 / 42%), 0 0 28px rgb(57 215 193 / 20%);
}
```

Give each scenario figure a wide crop and safe handoff zone. Make the senses section three tall rule-separated rows with `padding-right` reserved for the Ring rail. At `max-width: 760px`, stack content, remove the Neon glow, remove the right rail reservation, and rely on the compact journey behavior.

- [ ] **Step 4: Run tests and build**

Run: `npm test -- --run src/components/landing/LandingStory.test.tsx src/pages/HomePage.test.tsx && npm run build`

Expected: tests pass and Vite production build exits 0.

### Task 4: Full regression, visual QA, and performance verification

**Files:**
- Verify only; modify the smallest relevant file if a regression test exposes a defect.

**Interfaces:**
- Consumes: complete landing implementation.
- Produces: browser-verified, responsive, stable page at `http://127.0.0.1:5173/`.

- [ ] **Step 1: Run complete automated verification**

Run: `npm test -- --run && npm run build`

Expected: all Vitest tests pass and production build exits 0.

- [ ] **Step 2: Verify desktop and responsive layouts with gstack browse**

Check 1440×900, 1024×768, and 390×844. Capture Hero, Flash scene, Vibe scene, system rail, senses, and community screenshots. Confirm no heading overflow, double Ring, image miscrop, or text obstruction.

- [ ] **Step 3: Verify browser errors and network requests**

Use `browse console --errors` and `browse network`. Expected: no console errors, no `/connection` requests, no missing QR PNG, and exactly one app document.

- [ ] **Step 4: Verify memory stability**

Capture `browse memory --json`, wait ten seconds, and capture it again. Expected: document, node, and listener counts remain stable; JS heap must not show monotonic runaway growth.

- [ ] **Step 5: Review the final diff**

Run: `git diff --check` and `git diff -- ring-demo/src docs/superpowers/specs/2026-07-16-ring-landing-narrative-motion-redesign.md`

Expected: no whitespace errors and no unrelated user changes included in the implementation review.
