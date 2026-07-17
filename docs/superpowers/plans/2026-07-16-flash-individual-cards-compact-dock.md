# Flash Individual Cards and Compact Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render every Flash asset as an independent opaque domain-colored stack card and replace the current variable Journey Dock with the approved compact four-state flow.

**Architecture:** Keep newest-first `FlashAssetBatch[]` in `FlashPage` for transcript provenance, flatten those batches into stable per-asset view items inside `FlashAssetFolder`, and keep `ScrollStack` presentation-only. Extend `AssetCard` to resolve the canonical eight-domain label and token. Model `Assets Created` as an explicit page phase with its card count so the Dock can hold completion feedback before exiting.

**Tech Stack:** React 18, TypeScript, Vitest, Testing Library, React Three Fiber Dither, Lenis, CSS custom properties and transforms.

## Global Constraints

- Ring gestures, Ring Desktop events, ASR, Flash API submission, and request invalidation remain unchanged.
- One backend asset equals one visible Scroll Stack item; no visible batch wrapper remains.
- Every card remains fully opaque at every stack depth.
- Domain surface colors use the canonical eight-domain palette from `spec/08-domain-system.md`.
- The four primary Dock phases are `Capturing`, `Transcribing`, `Analyzing semantics`, and `Assets Created`.
- Dock desktop geometry is `width: min(780px, calc(100vw - 48px))` and `height: 122px` for every phase.
- Completion remains visible for at least 900 ms and reports the normalized card count.
- Existing unrelated worktree changes must be preserved; do not stage or commit implementation automatically.

---

## File Structure

- Modify `ring-demo/src/components/AssetCard.tsx`: resolve explicit/meta/fallback domain, render domain identity row, enforce at most two metadata values.
- Modify `ring-demo/src/components/AssetCard.test.tsx`: prove domain precedence, domain token, and compact metadata.
- Modify `ring-demo/src/features/flash/flash-assets.ts`: expose stable flattened `FlashAssetItem` values without removing batch provenance.
- Modify `ring-demo/src/features/flash/flash-assets.test.ts`: prove newest-first flattening and per-asset stable IDs.
- Modify `ring-demo/src/features/flash/FlashAssetFolder.tsx`: render one `ScrollStackItem` per asset and reset only for a new latest response.
- Modify `ring-demo/src/features/flash/FlashAssetFolder.test.tsx`: prove no batch wrapper, independent items, opaque history contract, and auto-front behavior.
- Modify `ring-demo/src/features/flash/FlashJourneyDock.tsx`: fixed transcript rail, four primary phases, count copy, and phase palettes.
- Modify `ring-demo/src/features/flash/FlashJourneyDock.test.tsx`: prove copy, transcript persistence, palettes, singular/plural count, and hidden states.
- Modify `ring-demo/src/pages/FlashPage.tsx`: replace acknowledgement/processing/revealed presentation mapping with analyzing/created timing and count.
- Modify `ring-demo/src/pages/FlashPage.test.tsx`: prove immediate request, semantic-analysis transition, 900 ms completion hold, multi-card arrival, failure, and reset.
- Modify `ring-demo/src/styles.css`: individual stack cards, domain surfaces, compact Dock geometry, phase color treatment, responsive and reduced motion rules.

---

### Task 1: Canonical Domain Card Contract

**Files:**
- Modify: `ring-demo/src/components/AssetCard.test.tsx`
- Modify: `ring-demo/src/components/AssetCard.tsx`
- Modify: `ring-demo/src/features/flash/flash-assets.test.ts`
- Modify: `ring-demo/src/features/flash/flash-assets.ts`

**Interfaces:**
- Produces: `AssetLifeDomain`, `resolveAssetLifeDomain(card)`, `flattenFlashAssetBatches(batches): FlashAssetItem[]`.
- Consumes: existing `FlashAssetBatch` and arbitrary backend card records.

- [ ] **Step 1: Write failing domain and flattening tests**

Add assertions that an explicit `domain: "工作"` wins, a `meta_fields` domain is used when explicit domain is absent, an idea without either falls back to `灵感`, only two metadata values render, and `[newBatch, oldBatch]` flattens to IDs `new-0`, `new-1`, `old-0`.

```tsx
expect(screen.getByLabelText("工作 domain")).toBeVisible();
expect(screen.getByLabelText("日程 card")).toHaveAttribute("data-domain", "work");
expect(screen.getAllByRole("listitem")).toHaveLength(2);
```

```ts
expect(flattenFlashAssetBatches([newBatch, oldBatch]).map(item => item.id))
  .toEqual(["new-0", "new-1", "old-0"]);
```

- [ ] **Step 2: Run tests and verify RED**

Run: `cd ring-demo && npm test -- --run src/components/AssetCard.test.tsx src/features/flash/flash-assets.test.ts`

Expected: FAIL because domain label/token resolution and `flattenFlashAssetBatches` do not exist.

- [ ] **Step 3: Implement minimal domain and item helpers**

Use this exact domain contract:

```ts
export type AssetLifeDomain =
  | "工作" | "学习" | "健康" | "运动"
  | "社交" | "娱乐" | "生活" | "灵感";

export interface FlashAssetItem {
  id: string;
  batchId: string;
  batchOrder: number;
  createdAt: number;
  card: Record<string, unknown>;
}
```

Resolve explicit `card.domain`, then a `meta_fields` entry whose `field` is `domain`, then deterministic type fallback. Map domain labels to stable CSS tokens `work`, `learning`, `health`, `sport`, `social`, `entertainment`, `life`, and `idea`.

Render the domain on the identity row and slice metadata with `.slice(0, 2)`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `cd ring-demo && npm test -- --run src/components/AssetCard.test.tsx src/features/flash/flash-assets.test.ts`

Expected: all focused tests pass.

---

### Task 2: One Asset Per Opaque Stack Item

**Files:**
- Modify: `ring-demo/src/features/flash/FlashAssetFolder.test.tsx`
- Modify: `ring-demo/src/features/flash/FlashAssetFolder.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `flattenFlashAssetBatches(batches)` and `AssetCard` domain rendering.
- Produces: one `.flash-asset-stack-item` per normalized asset.

- [ ] **Step 1: Write failing folder tests**

For a two-card newest response plus one older card, assert three elements with `data-testid^="asset-"`, three Scroll Stack item wrappers, no `.flash-asset-batch`, no `JUST NOW`/`EARLIER`, total count `3`, and `scrollToStart()` called only when `batches[0].id` changes.

- [ ] **Step 2: Run test and verify RED**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashAssetFolder.test.tsx`

Expected: FAIL because the component still renders one stack item per batch and includes batch wrappers.

- [ ] **Step 3: Render flattened card items**

Map `flattenFlashAssetBatches(batches)` directly to `ScrollStackItem`. Apply the response-local card order as the stagger index and pass no latest/history opacity state.

```tsx
{items.map(item => (
  <ScrollStackItem key={item.id} itemClassName="flash-asset-stack-item">
    <div data-testid={`asset-${item.id}`} className="flash-asset-entry">
      <AssetCard card={item.card} index={item.batchOrder} />
    </div>
  </ScrollStackItem>
))}
```

- [ ] **Step 4: Replace batch CSS with opaque card-stack CSS**

Remove `.flash-asset-batch`, `.is-history`, `.flash-batch-meta`, and `.flash-batch-cards`. Give every asset card an opaque surface via `--asset-domain-surface`, fixed compact geometry, neutral border, and depth-only shadow differences. Remove the old colored side stripe.

- [ ] **Step 5: Run test and verify GREEN**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashAssetFolder.test.tsx src/components/ScrollStack.test.tsx`

Expected: folder and Scroll Stack tests pass.

---

### Task 3: Compact Four-State Journey Dock

**Files:**
- Modify: `ring-demo/src/features/flash/FlashJourneyDock.test.tsx`
- Modify: `ring-demo/src/features/flash/FlashJourneyDock.tsx`
- Modify: `ring-demo/src/pages/FlashPage.test.tsx`
- Modify: `ring-demo/src/pages/FlashPage.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- `FlashJourneyDock` consumes `phase`, `transcript`, `createdCount`, `error`, and `onRetry`.
- `FlashPage` produces `phase: "listening" | "transcribing" | "analyzing" | "created"` for the primary journey.

- [ ] **Step 1: Write failing Dock tests**

Assert exact palettes and copy:

```ts
const palettes = {
  listening: "0.32,0.57,1",
  transcribing: "0.67,0.47,0.9",
  analyzing: "0.18,0.76,0.73",
  created: "0.28,0.73,0.48",
};
```

Assert that transcript uses a dedicated `.flash-journey-transcript` rail, `createdCount={1}` renders `1 card added`, and `createdCount={2}` renders `2 cards added`.

- [ ] **Step 2: Run Dock test and verify RED**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashJourneyDock.test.tsx`

Expected: FAIL because `analyzing`, `created`, `createdCount`, and the transcript rail do not exist.

- [ ] **Step 3: Implement minimal Dock phase configuration**

Use a configuration table for title, support copy, palette, speed, and footer. Keep one fixed DOM grid across phases: transcript rail, centered status, utility footer. Render live wave only for `listening`; preserve the compact retry surface for `failed` without adding a Dither palette.

- [ ] **Step 4: Write failing page timing tests**

Use fake timers to prove the backend starts immediately, the page enters `Analyzing semantics` after the existing 700 ms transcript acknowledgement, successful normalized cards set `Assets Created`, `2 cards added` remains visible at 899 ms, and the Dock exits at 900 ms.

- [ ] **Step 5: Run page test and verify RED**

Run: `cd ring-demo && npm test -- --run src/pages/FlashPage.test.tsx`

Expected: FAIL because the reducer has no `analyzing` or `created` state and exits after 250 ms.

- [ ] **Step 6: Implement the page state and timing**

Rename the `processing` action/phase to `analyzing`. Change `revealed` to `created` with `createdCount` and optional batch. Keep the request start immediate. After normalization, dispatch created state, insert the batch, wait `ASSETS_CREATED_HOLD_MS = 900`, then dispatch a separate `settled` action to hide the Dock while keeping cards.

- [ ] **Step 7: Implement compact Dock CSS**

Set fixed 122 px height and 780 px maximum width. Use a 30 px transcript row, centered status row, and 20 px footer. Add phase-specific tint overlays while Dither receives its palette from React. Keep the same geometry on mobile and disable continuous effects for reduced motion.

- [ ] **Step 8: Run focused tests and verify GREEN**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashJourneyDock.test.tsx src/pages/FlashPage.test.tsx`

Expected: all focused Dock and page tests pass.

---

### Task 4: Regression and Browser Verification

**Files:**
- Verify only.

**Interfaces:**
- Consumes the completed Flash UI.
- Produces evidence that the demo remains buildable and usable.

- [ ] **Step 1: Run the complete Ring Demo test suite**

Run: `cd ring-demo && npm test -- --run`

Expected: all tests pass with no unhandled warnings.

- [ ] **Step 2: Run typecheck and production build**

Run: `cd ring-demo && npm run typecheck`

Expected: TypeScript exits 0.

Run: `cd ring-demo && npm run build`

Expected: Vite production build exits 0.

- [ ] **Step 3: Run browser QA at `/flash`**

Verify at desktop width and one narrow viewport:

- multiple returned assets are independent opaque cards;
- newest cards are at the front and downward scrolling reveals older cards;
- domain label and surface color agree;
- all four Dock phases have identical outer geometry;
- transcript stays in the top rail;
- `Assets Created · N cards added` is readable before Dock exit;
- Ring connect/disconnect and operator controls remain usable.

- [ ] **Step 4: Review the scoped diff**

Run: `git diff --check` and `git status --short`.

Expected: no whitespace errors; only approved documentation and Ring Demo implementation files are changed by this pass.
