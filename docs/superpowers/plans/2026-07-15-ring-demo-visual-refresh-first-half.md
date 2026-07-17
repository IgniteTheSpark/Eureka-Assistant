# Ring Demo Visual Refresh First Half Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved two-screen Ring product home page and move account authentication behind an operator-specific surface without changing Flash/Vibe internals.

**Architecture:** Keep the existing React Router and `DemoProvider` lifecycle. Extend the protected shell so Home can render the shared `RingConnection`, rename the setup route as operator-owned, and add a navigation callback to Operator Controls. Use static transparent PNG assets from `ring-demo/public/ring/` and page-scoped CSS for the visual refresh.

**Tech Stack:** React 18, React Router 6, TypeScript, Vite, Vitest, Testing Library, CSS.

## Global Constraints

- Ring connection is optional and must never disable either mode link.
- Do not embed demo account credentials in the frontend or repository.
- Do not redesign the internal Flash or Vibe workspaces in this pass.
- Preserve all existing real Ring, Flash, Vibe, reset, and mode-switch behavior.
- Use only the user-provided Ring PNG renders; do not generate replacement product art.

---

### Task 1: Operator-owned authentication route

**Files:**
- Modify: `ring-demo/src/app/App.tsx`
- Modify: `ring-demo/src/pages/SetupPage.tsx`
- Modify: `ring-demo/src/components/OperatorControls.tsx`
- Test: `ring-demo/src/app/App.test.tsx`
- Test: `ring-demo/src/components/OperatorControls.test.tsx`

**Interfaces:**
- Consumes: existing `AUTH_TOKEN_KEY`, `BackendClient.login`, `BackendClient.register`, and React Router navigation.
- Produces: `/operator/setup` route and `OperatorControls.onManageAccount: () => void`.

- [ ] **Step 1: Write failing route and Operator Controls tests**

Assert unauthenticated navigation reaches the operator setup heading and the Operator Controls account action calls `onManageAccount`.

- [ ] **Step 2: Run focused tests to verify RED**

Run: `npm test -- src/app/App.test.tsx src/components/OperatorControls.test.tsx --run`

Expected: FAIL because `/operator/setup`, the operator-specific copy, and `onManageAccount` do not exist.

- [ ] **Step 3: Implement the operator route and account action**

Change the route and all invalid-auth redirects to `/operator/setup`; label the setup content as operator-only; add a low-emphasis `Manage demo account` action in Operator Controls that navigates without deleting the current token.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run: `npm test -- src/app/App.test.tsx src/components/OperatorControls.test.tsx --run`

Expected: both test files pass.

### Task 2: Two-screen product home

**Files:**
- Copy: `ring-demo/public/ring/ring-hero.png`
- Copy: `ring-demo/public/ring/ring-connect.png`
- Copy: `ring-demo/public/ring/ring-flash.png`
- Copy: `ring-demo/public/ring/ring-vibe.png`
- Modify: `ring-demo/src/pages/HomePage.tsx`
- Modify: `ring-demo/src/app/App.tsx`
- Test: `ring-demo/src/pages/HomePage.test.tsx`
- Test: `ring-demo/src/app/App.test.tsx`

**Interfaces:**
- Consumes: `RingConnection`, the existing `DemoProvider`, and `AppRingClient` scan/connect/disconnect methods.
- Produces: `HomePage({ ringClient })`, `#demo-launcher`, and always-enabled `/flash` and `/vibe` links.

- [ ] **Step 1: Write failing Home tests**

Wrap `HomePage` in a real `DemoProvider` with a fake Ring client. Assert the Hero image, Ring connection region, demo launcher, and both mode links render while disconnected.

- [ ] **Step 2: Run the Home test to verify RED**

Run: `npm test -- src/pages/HomePage.test.tsx --run`

Expected: FAIL because the product images, launcher identifier, and Ring connection are absent.

- [ ] **Step 3: Copy the approved images and implement semantic markup**

Copy `6.png`, `4.png`, `5.png`, and `7.png` to the descriptive public paths. Render a dedicated Hero followed by a launcher containing the shared Ring connection and two image-led mode links.

- [ ] **Step 4: Run the Home and App tests to verify GREEN**

Run: `npm test -- src/pages/HomePage.test.tsx src/app/App.test.tsx --run`

Expected: both test files pass.

### Task 3: Obsidian Hardware layout and verification

**Files:**
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: semantic classes introduced by Task 2.
- Produces: responsive two-screen layout, visual tokens, focus states, and mode-specific accent treatment.

- [ ] **Step 1: Add page-scoped layout and visual tokens**

Define a compact spacing scale, asymmetric desktop grids, stacked mobile structure, restrained metallic highlights, and image treatments without altering Flash/Vibe functional markup.

- [ ] **Step 2: Run automated verification**

Run: `npm test -- --run`

Expected: all demo tests pass.

Run: `npm run typecheck`

Expected: TypeScript exits successfully.

Run: `npm run build`

Expected: Vite production build succeeds.

- [ ] **Step 3: Re-run the Impeccable layout detector**

Run: `node /Users/admin/.codex/skills/impeccable/scripts/detect.mjs --json --scope layout ring-demo/src`

Expected: no unresolved mechanical layout findings.

- [ ] **Step 4: Inspect desktop and mobile renders**

Open the local page at desktop and narrow mobile widths. Confirm Hero hierarchy, mode-link availability while disconnected, image containment, focus visibility, and absence of horizontal overflow.
