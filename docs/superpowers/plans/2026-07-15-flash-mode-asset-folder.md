# Flash Mode Asset Folder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Flash Mode into a stable ring workbench with an independently scrolling asset stack and a bottom Journey Dock for capture, transcript acknowledgement, processing, and multi-card arrival.

**Architecture:** Keep Ring Desktop events and backend submission in `FlashPage`, move presentation into focused `FlashJourneyDock` and `FlashAssetFolder` components, and store responses as explicit newest-first batches. Adapt React Bits Scroll Stack behind a typed component/ref interface so Flash ordering and auto-focus do not depend on animation internals.

**Tech Stack:** React 18, TypeScript, Vitest, Testing Library, React Three Fiber Dither, Lenis, CSS transforms and transitions.

## Global Constraints

- Ring gestures, Ring Desktop events, ASR, and the backend Flash API remain unchanged.
- The Asset Folder uses container scrolling with `useWindowScroll={false}`.
- One accepted transcript creates at most one batch containing one or more cards.
- Only the newest successful batch has domain colors; every prior batch is neutral gray.
- Transcript acknowledgement remains visible for at least 700 ms while the backend request starts immediately.
- Processing Dither uses `waveColor={[0.28, 0.46, 0.62]}`.
- Existing demo reset clears active UI and in-memory batches.
- Do not load historical backend assets in this iteration.
- Do not redesign asset-card information architecture or final domain palette.
- The worktree already contains unrelated uncommitted Ring Demo changes. Do not stage or commit implementation files automatically; preserve those changes and provide a scoped diff for user-controlled staging.

---

## File Structure

- Create `ring-demo/src/components/ScrollStack.tsx`: typed React Bits adaptation, Lenis lifecycle, internal scroll, imperative `scrollToStart()`.
- Create `ring-demo/src/components/ScrollStack.css`: component-only scroller and transform surfaces.
- Create `ring-demo/src/components/ScrollStack.test.tsx`: DOM contract, internal scrolling, imperative reset, and cleanup.
- Create `ring-demo/src/features/flash/flash-assets.ts`: response-to-card normalization, batch creation, and domain classification.
- Create `ring-demo/src/features/flash/flash-assets.test.ts`: pure batch and fallback contracts.
- Create `ring-demo/src/features/flash/FlashAssetFolder.tsx`: empty state, newest/history batches, and folder auto-focus.
- Create `ring-demo/src/features/flash/FlashAssetFolder.test.tsx`: multi-card batches, old-batch treatment, and reset behavior.
- Create `ring-demo/src/features/flash/FlashJourneyDock.tsx`: state-specific Dither, transcript, audio wave, retry, and accessibility.
- Create `ring-demo/src/features/flash/FlashJourneyDock.test.tsx`: dock state and palette contracts.
- Modify `ring-demo/src/pages/FlashPage.tsx`: state machine, 700 ms acknowledgement gate, batch accumulation, and component composition.
- Modify `ring-demo/src/pages/FlashPage.test.tsx`: real-event integration, timing, success/failure batching, and reset.
- Modify `ring-demo/src/styles.css`: workbench, folder, dock, batch, domain-token, responsive, and reduced-motion styling.
- Modify `ring-demo/package.json` and `ring-demo/package-lock.json`: add `lenis`.

---

### Task 1: Add the Typed Scroll Stack Primitive

**Files:**
- Create: `ring-demo/src/components/ScrollStack.tsx`
- Create: `ring-demo/src/components/ScrollStack.css`
- Create: `ring-demo/src/components/ScrollStack.test.tsx`
- Modify: `ring-demo/package.json`
- Modify: `ring-demo/package-lock.json`

**Interfaces:**
- Consumes: `ReactNode`, `forwardRef`, `useImperativeHandle`, and `Lenis`.
- Produces: `ScrollStack`, `ScrollStackItem`, `ScrollStackHandle.scrollToStart(): void`, and `ScrollStackProps`.

- [ ] **Step 1: Install Lenis**

Run: `cd ring-demo && npm install lenis`

Expected: `lenis` appears in dependencies and the lockfile resolves one compatible version without audit errors.

- [ ] **Step 2: Write the failing Scroll Stack tests**

Create tests with a mocked Lenis constructor:

```tsx
vi.mock("lenis", () => ({
  default: vi.fn(() => ({
    destroy: vi.fn(),
    on: vi.fn(),
    raf: vi.fn(),
    scrollTo: vi.fn(),
  })),
}));

it("uses an internal scroller and exposes scrollToStart", () => {
  const ref = createRef<ScrollStackHandle>();
  const { container } = render(
    <ScrollStack ref={ref} useWindowScroll={false}>
      <ScrollStackItem>One</ScrollStackItem>
      <ScrollStackItem>Two</ScrollStackItem>
    </ScrollStack>,
  );
  expect(container.querySelector(".scroll-stack-scroller")).toBeVisible();
  expect(container.querySelectorAll(".scroll-stack-card")).toHaveLength(2);
  act(() => ref.current?.scrollToStart());
  expect(Lenis).toHaveBeenCalledWith(expect.objectContaining({
    wrapper: expect.any(HTMLElement),
  }));
});
```

- [ ] **Step 3: Run the focused test and verify failure**

Run: `cd ring-demo && npm test -- --run src/components/ScrollStack.test.tsx`

Expected: FAIL because `ScrollStack` and its interfaces do not exist.

- [ ] **Step 4: Adapt the React Bits implementation**

Implement the documented props with typed defaults:

```tsx
export interface ScrollStackHandle {
  scrollToStart(): void;
}

export interface ScrollStackProps {
  children: ReactNode;
  className?: string;
  itemDistance?: number;
  itemScale?: number;
  itemStackDistance?: number;
  stackPosition?: string;
  scaleEndPosition?: string;
  baseScale?: number;
  scaleDuration?: number;
  rotationAmount?: number;
  blurAmount?: number;
  useWindowScroll?: boolean;
  onStackComplete?: () => void;
}

export function ScrollStackItem({
  children,
  itemClassName = "",
}: {
  children: ReactNode;
  itemClassName?: string;
}) {
  return (
    <div className={`scroll-stack-card ${itemClassName}`.trim()}>{children}</div>
  );
}

export const ScrollStack = forwardRef<ScrollStackHandle, ScrollStackProps>(
  function ScrollStack({ useWindowScroll = false, ...props }, forwardedRef) {
    useImperativeHandle(forwardedRef, () => ({
      scrollToStart() {
        if (lenisRef.current) lenisRef.current.scrollTo(0, { immediate: false });
        else if (useWindowScroll) window.scrollTo({ top: 0, behavior: "smooth" });
        else scrollerRef.current?.scrollTo({ top: 0, behavior: "smooth" });
      },
    }), [useWindowScroll]);
    return (
      <div className={`scroll-stack-scroller ${className}`.trim()} ref={scrollerRef}>
        <div className="scroll-stack-inner">
          {children}
          <div className="scroll-stack-end" />
        </div>
      </div>
    );
  },
);
```

Inside `useLayoutEffect`, collect `.scroll-stack-card` elements; calculate progress from scroll top, stack position, and release-marker offset; apply `translate3d`, `scale`, optional rotation, and optional blur only when values changed; create Lenis with the internal scroller as `wrapper`; drive Lenis from one RAF; and cancel the RAF plus `destroy()` Lenis during cleanup. Use `window.matchMedia("(prefers-reduced-motion: reduce)")` to skip Lenis and leave transforms at their settled CSS values. Keep `rotationAmount={0}`, `blurAmount={0}`, and `useWindowScroll={false}` at the Flash call site.

- [ ] **Step 5: Add component CSS**

```css
.scroll-stack-scroller {
  width: 100%;
  height: 100%;
  position: relative;
  overflow-y: auto;
  overflow-x: hidden;
  overscroll-behavior: contain;
  -webkit-overflow-scrolling: touch;
}

.scroll-stack-inner {
  min-height: 100%;
  padding: 72px 28px 320px;
}

.scroll-stack-card {
  width: 100%;
  position: relative;
  transform-origin: top center;
  backface-visibility: hidden;
  will-change: transform, filter;
}

.scroll-stack-end { width: 100%; height: 1px; }
```

- [ ] **Step 6: Verify the primitive**

Run: `cd ring-demo && npm test -- --run src/components/ScrollStack.test.tsx && npm run typecheck`

Expected: focused tests and TypeScript pass.

---

### Task 2: Model Flash Asset Batches and Domains

**Files:**
- Create: `ring-demo/src/features/flash/flash-assets.ts`
- Create: `ring-demo/src/features/flash/flash-assets.test.ts`

**Interfaces:**
- Consumes: `FlashResponse` from `ring-demo/src/lib/types.ts`.
- Produces: `FlashAssetBatch`, `normalizeFlashCards(result)`, `createFlashAssetBatch(transcript, result, id, createdAt)`, and `assetDomain(card)`.

- [ ] **Step 1: Write failing pure-function tests**

```ts
it("creates one ordered batch from every card in one response", () => {
  const batch = createFlashAssetBatch(
    "准备展会",
    { ok: true, cards: [
      { card_type: "todo", content: "打印物料" },
      { card_type: "event", title: "布展" },
    ] },
    "batch-1",
    100,
  );
  expect(batch).toMatchObject({ id: "batch-1", transcript: "准备展会" });
  expect(batch.cards).toHaveLength(2);
  expect(batch.cards.map(assetDomain)).toEqual(["todo", "event"]);
});

it("creates a one-card note batch for a text-only response", () => {
  const batch = createFlashAssetBatch(
    "随手记一下",
    { ok: true, summary: "随手记一下" },
    "batch-2",
    200,
  );
  expect(batch.cards).toEqual([
    expect.objectContaining({ card_type: "note", content: "随手记一下" }),
  ]);
});
```

- [ ] **Step 2: Verify the tests fail**

Run: `cd ring-demo && npm test -- --run src/features/flash/flash-assets.test.ts`

Expected: FAIL because the module does not exist.

- [ ] **Step 3: Implement exact normalization and classification**

```ts
export type AssetDomain =
  | "todo" | "event" | "contact" | "idea" | "note" | "expense" | "generic";

export interface FlashAssetBatch {
  id: string;
  transcript: string;
  createdAt: number;
  cards: Array<Record<string, unknown>>;
}

export function assetDomain(card: Record<string, unknown>): AssetDomain {
  const nested = typeof card.card === "object" && card.card !== null
    ? card.card as Record<string, unknown>
    : card;
  const type = String(
    nested.card_type ?? nested.user_skill_name ?? nested.skill_name ?? nested.type ?? "",
  ).toLowerCase();
  if (["todo", "event", "contact", "idea", "expense"].includes(type)) {
    return type as AssetDomain;
  }
  if (["note", "notes", "misc"].includes(type)) return "note";
  return "generic";
}
```

Implement the current response precedence explicitly:

```ts
export function normalizeFlashCards(result: FlashResponse) {
  if (result.cards?.length) return result.cards;
  if (result.derived_assets?.length) {
    return result.derived_assets.map((asset) => {
      const nested = asset.card;
      return typeof nested === "object" && nested !== null && !Array.isArray(nested)
        ? nested as Record<string, unknown>
        : asset;
    });
  }
  const fallback = result.summary?.trim() || result.reply?.trim();
  return fallback ? [{ card_type: "note", content: fallback }] : [];
}

export function createFlashAssetBatch(
  transcript: string,
  result: FlashResponse,
  id: string,
  createdAt: number,
): FlashAssetBatch {
  return { id, transcript, createdAt, cards: normalizeFlashCards(result) };
}
```

- [ ] **Step 4: Verify pure functions**

Run: `cd ring-demo && npm test -- --run src/features/flash/flash-assets.test.ts && npm run typecheck`

Expected: focused tests and TypeScript pass.

---

### Task 3: Build the Independently Scrolling Asset Folder

**Files:**
- Create: `ring-demo/src/features/flash/FlashAssetFolder.tsx`
- Create: `ring-demo/src/features/flash/FlashAssetFolder.test.tsx`
- Modify: `ring-demo/src/components/AssetCard.tsx`

**Interfaces:**
- Consumes: newest-first `FlashAssetBatch[]`, `AssetCard`, and `ScrollStackHandle`.
- Produces: `FlashAssetFolder({ batches })` and `AssetCard.domain` presentation hook.

- [ ] **Step 1: Write failing folder tests**

Mock only the motion primitive, preserving its imperative contract:

```tsx
const scrollToStart = vi.fn();
vi.mock("../../components/ScrollStack", async () => {
  const React = await import("react");
  return {
    ScrollStack: React.forwardRef(({ children }: { children: React.ReactNode }, ref) => {
      React.useImperativeHandle(ref, () => ({ scrollToStart }));
      return <div data-testid="asset-scroll-stack">{children}</div>;
    }),
    ScrollStackItem: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
  };
});

it("colors only the newest batch and renders every card in each batch", () => {
  render(<FlashAssetFolder batches={[newBatch, oldBatch]} />);
  expect(screen.getByTestId("batch-new")).toHaveClass("is-latest");
  expect(screen.getByTestId("batch-old")).toHaveClass("is-history");
  expect(screen.getAllByRole("article")).toHaveLength(
    newBatch.cards.length + oldBatch.cards.length,
  );
});
```

Add these exact test cases:

```tsx
it("shows a quiet empty state before the first batch", () => {
  render(<FlashAssetFolder batches={[]} />);
  expect(screen.getByText("Your assets will gather here.")).toBeVisible();
  expect(screen.queryByTestId("asset-scroll-stack")).not.toBeInTheDocument();
});

it("returns to the front only when the latest batch changes", () => {
  const { rerender } = render(<FlashAssetFolder batches={[newBatch, oldBatch]} />);
  expect(scrollToStart).toHaveBeenCalledTimes(1);
  rerender(<FlashAssetFolder batches={[newBatch, oldBatch]} />);
  expect(scrollToStart).toHaveBeenCalledTimes(1);
  rerender(<FlashAssetFolder batches={[newerBatch, newBatch, oldBatch]} />);
  expect(scrollToStart).toHaveBeenCalledTimes(2);
});
```

- [ ] **Step 2: Verify folder tests fail**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashAssetFolder.test.tsx`

Expected: FAIL because `FlashAssetFolder` does not exist.

- [ ] **Step 3: Implement the folder**

```tsx
export function FlashAssetFolder({ batches }: { batches: FlashAssetBatch[] }) {
  const stackRef = useRef<ScrollStackHandle>(null);
  const latestId = batches[0]?.id;

  useEffect(() => {
    if (latestId) stackRef.current?.scrollToStart();
  }, [latestId]);

  return (
    <section className="flash-asset-folder" aria-label="Generated assets">
      <header><span>ASSET FOLDER</span><strong>{batches.reduce((n, b) => n + b.cards.length, 0)}</strong></header>
      {batches.length === 0 ? <p className="flash-folder-empty">Your assets will gather here.</p> : (
        <ScrollStack ref={stackRef} itemDistance={128} itemStackDistance={26}
          stackPosition="14%" scaleEndPosition="7%" baseScale={0.9}
          rotationAmount={0} blurAmount={0} useWindowScroll={false}>
          {batches.map((batch, batchIndex) => (
            <ScrollStackItem key={batch.id} itemClassName="flash-batch-stack-item">
              <section data-testid={`batch-${batch.id}`}
                className={`flash-asset-batch ${batchIndex === 0 ? "is-latest" : "is-history"}`}>
                {batch.cards.map((card, cardIndex) => (
                  <AssetCard card={card} domain={assetDomain(card)} index={cardIndex}
                    key={`${batch.id}-${cardIndex}`} />
                ))}
              </section>
            </ScrollStackItem>
          ))}
        </ScrollStack>
      )}
    </section>
  );
}
```

Add `domain?: string` to `AssetCard` and render `data-domain={domain}` on its article so CSS uses semantic tokens without altering card data.

- [ ] **Step 4: Verify the folder**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashAssetFolder.test.tsx src/components/AssetCard.test.tsx && npm run typecheck`

Expected: focused tests and existing asset-card tests pass.

---

### Task 4: Build the Floating Journey Dock

**Files:**
- Create: `ring-demo/src/features/flash/FlashJourneyDock.tsx`
- Create: `ring-demo/src/features/flash/FlashJourneyDock.test.tsx`

**Interfaces:**
- Consumes: `phase`, `transcript`, `error`, and `onRetry`.
- Produces: a polite live region with capture, transcription, acknowledgement, processing, and failure content.

- [ ] **Step 1: Write failing dock tests**

```tsx
vi.mock("../../components/Dither", () => ({
  Dither: (props: { waveColor: [number, number, number] }) =>
    <output data-testid="dock-dither">{props.waveColor.join(",")}</output>,
}));

it("keeps the transcript while processing and changes the Dither palette", () => {
  const { rerender } = render(
    <FlashJourneyDock phase="acknowledging" transcript="联系 Alex" error={null} onRetry={vi.fn()} />,
  );
  expect(screen.getByText("联系 Alex")).toBeVisible();
  expect(screen.getByTestId("dock-dither")).toHaveTextContent("0.5,0.5,0.5");

  rerender(<FlashJourneyDock phase="processing" transcript="联系 Alex" error={null} onRetry={vi.fn()} />);
  expect(screen.getByText("联系 Alex")).toBeVisible();
  expect(screen.getByText("Creating assets")).toBeVisible();
  expect(screen.getByTestId("dock-dither")).toHaveTextContent("0.28,0.46,0.62");
});
```

Add these exact assertions:

```tsx
it.each(["ready", "revealed", "disconnected"] as const)("hides during %s", phase => {
  const { container } = render(
    <FlashJourneyDock phase={phase} transcript="" error={null} onRetry={vi.fn()} />,
  );
  expect(container).toBeEmptyDOMElement();
});

it("stops the live wave after recording and retains retry context on failure", () => {
  const onRetry = vi.fn();
  const { rerender } = render(
    <FlashJourneyDock phase="listening" transcript="" error={null} onRetry={onRetry} />,
  );
  expect(screen.getByTestId("live-wave")).toBeVisible();
  rerender(<FlashJourneyDock phase="transcribing" transcript="" error={null} onRetry={onRetry} />);
  expect(screen.queryByTestId("live-wave")).not.toBeInTheDocument();
  rerender(<FlashJourneyDock phase="failed" transcript="联系 Alex" error="Unavailable" onRetry={onRetry} />);
  expect(screen.getByText("联系 Alex")).toBeVisible();
  fireEvent.click(screen.getByRole("button", { name: "Retry Flash" }));
  expect(onRetry).toHaveBeenCalledOnce();
});
```

- [ ] **Step 2: Verify dock tests fail**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashJourneyDock.test.tsx`

Expected: FAIL because the component does not exist.

- [ ] **Step 3: Implement the dock**

```tsx
export type FlashJourneyPhase =
  | "disconnected" | "ready" | "listening" | "transcribing"
  | "acknowledging" | "processing" | "revealed" | "failed";

const visible = new Set<FlashJourneyPhase>([
  "listening", "transcribing", "acknowledging", "processing", "failed",
]);

export function FlashJourneyDock({ phase, transcript, error, onRetry }: Props) {
  if (!visible.has(phase)) return null;
  const processing = phase === "processing";
  return (
    <aside className={`flash-journey-dock is-${phase}`} aria-live="polite">
      <div aria-hidden className="flash-journey-dither">
        <Dither
          waveColor={processing ? [0.28, 0.46, 0.62] : [0.5, 0.5, 0.5]}
          waveSpeed={phase === "transcribing" ? 0.015 : 0.05}
          waveAmplitude={0.3} waveFrequency={3} colorNum={4}
          enableMouseInteraction mouseRadius={0.3}
        />
      </div>
      <div className="flash-journey-content">
        {phase === "listening" ? <><p>LIVE INPUT</p><h2>Capturing</h2><LiveWave /></> : null}
        {phase === "transcribing" ? <><p>ASR</p><h2>Transcribing</h2></> : null}
        {phase === "acknowledging" ? <><p>CAPTURED</p><blockquote>{transcript}</blockquote></> : null}
        {phase === "processing" ? <><p>Creating assets</p><blockquote>{transcript}</blockquote></> : null}
        {phase === "failed" ? <><blockquote>{transcript}</blockquote><p role="alert">{error}</p><button onClick={onRetry}>Retry Flash</button></> : null}
      </div>
    </aside>
  );
}
```

- [ ] **Step 4: Verify the dock**

Run: `cd ring-demo && npm test -- --run src/features/flash/FlashJourneyDock.test.tsx && npm run typecheck`

Expected: focused tests and TypeScript pass.

---

### Task 5: Integrate Timing, Batches, Folder, and Dock in FlashPage

**Files:**
- Modify: `ring-demo/src/pages/FlashPage.tsx`
- Modify: `ring-demo/src/pages/FlashPage.test.tsx`
- Modify: `ring-demo/src/styles.css`

**Interfaces:**
- Consumes: `FlashJourneyDock`, `FlashAssetFolder`, and `createFlashAssetBatch`.
- Produces: the complete real-ring Flash experience with stale-request protection and reset-safe batches.

- [ ] **Step 1: Replace current integration expectations with failing journey tests**

Use fake timers only for the acknowledgement threshold:

```tsx
it("acknowledges transcript for 700ms before processing and inserts one N-card batch", async () => {
  vi.useFakeTimers();
  dependencies.backendClient.flash.mockResolvedValue({
    ok: true,
    cards: [
      { card_type: "todo", content: "打印物料" },
      { card_type: "event", title: "布展" },
    ],
  });
  renderPage(dependencies);
  await act(async () => dependencies.emit("transcript.ready", matchingData("准备展会")));
  expect(screen.getByText("准备展会")).toBeVisible();
  expect(screen.queryByText("Creating assets")).not.toBeInTheDocument();
  await act(async () => vi.advanceTimersByTimeAsync(700));
  expect(screen.getByText("Creating assets")).toBeVisible();
  await act(async () => vi.runAllTimersAsync());
  expect(await screen.findAllByRole("article")).toHaveLength(2);
  vi.useRealTimers();
});
```

Add integration tests for:

- `recording.started` shows the dock without replacing the folder;
- `recording.stopped` removes the live wave but keeps the dock;
- two successful responses produce two batches and gray only the first;
- a failure keeps the former latest batch colored;
- starting a new recording invalidates a stale response;
- demo reset removes dock and every batch.

- [ ] **Step 2: Run the Flash integration test and verify failure**

Run: `cd ring-demo && npm test -- --run src/pages/FlashPage.test.tsx`

Expected: FAIL because current `FlashPage` still owns one result and renders Dither/cards inside the right panel.

- [ ] **Step 3: Extend the reducer**

```ts
type FlashPhase =
  | "disconnected" | "ready" | "listening" | "transcribing"
  | "acknowledging" | "processing" | "revealed" | "failed";

type FlashState = {
  phase: FlashPhase;
  transcript: string;
  batches: FlashAssetBatch[];
  error: string | null;
};

// `recording-started` clears only transient transcript/error and preserves batches.
// `acknowledging` stores transcript.
// `processing` preserves transcript and batches.
// `revealed` prepends one batch and clears transient error.
// `failed` preserves transcript and batches.
// `reset` clears batches and all transient state.
```

- [ ] **Step 4: Implement the acknowledgement and request timing**

```ts
const ACKNOWLEDGEMENT_MS = 700;
const FAST_RESULT_PROCESSING_MS = 250;

const submitTranscript = useCallback(async (transcript: string) => {
  const request = ++requestSerial.current;
  dispatch({ type: "acknowledging", transcript });
  demo.beginFlashProcessing();
  const requestStartedAt = performance.now();
  const responsePromise = backendClient.flash(transcript);
  try {
    await wait(Math.max(0, ACKNOWLEDGEMENT_MS - (performance.now() - requestStartedAt)));
    if (!active.current || request !== requestSerial.current) return;
    dispatch({ type: "processing" });
    const processingStartedAt = performance.now();
    const result = await responsePromise;
    if (!result.ok) throw new Error("UReka could not process this recording");
    await wait(Math.max(0, FAST_RESULT_PROCESSING_MS - (performance.now() - processingStartedAt)));
    if (!active.current || request !== requestSerial.current) return;
    const batch = createFlashAssetBatch(
      transcript,
      result,
      `${demo.generation}-${recordingCycle.current}-${request}`,
      Date.now(),
    );
    dispatch({ type: "revealed", batch });
  } catch (error) {
    if (active.current && request === requestSerial.current) {
      dispatch({ type: "failed", message: error instanceof Error ? error.message : "Flash request failed" });
    }
  } finally {
    demo.endFlashProcessing();
  }
}, [backendClient, demo.beginFlashProcessing, demo.endFlashProcessing, demo.generation]);
```

Ensure unmount, reset, and a new recording invalidate both the response and pending visual timers.

- [ ] **Step 5: Compose the stable workbench**

Replace the right `flash-canvas` with:

```tsx
<FlashAssetFolder batches={state.batches} />
<FlashJourneyDock
  error={state.error}
  onRetry={() => void submitTranscript(state.transcript)}
  phase={state.phase}
  transcript={state.transcript}
/>
```

Keep `RingConnection` and guidance in the left panel. Remove the old in-panel Dither, transcript, summary, reply, and flat card list.

- [ ] **Step 6: Add final page styling**

Add concrete page-level styles:

```css
.flash-asset-folder { min-height: 520px; height: 520px; position: relative; overflow: hidden; }
.flash-asset-batch { display: grid; gap: 12px; transition: filter 320ms ease, opacity 320ms ease; }
.flash-asset-batch.is-history { filter: grayscale(1) saturate(0); opacity: .58; }
.flash-asset-batch.is-latest [data-domain="todo"] { --asset-accent: #d2a85e; }
.flash-asset-batch.is-latest [data-domain="event"] { --asset-accent: #9485d8; }
.flash-asset-batch.is-latest [data-domain="contact"] { --asset-accent: #63aeb9; }
.flash-asset-batch.is-latest [data-domain="idea"] { --asset-accent: #c57da3; }
.flash-asset-batch.is-latest [data-domain="note"] { --asset-accent: #78a87e; }
.flash-asset-batch.is-latest [data-domain="expense"] { --asset-accent: #c98068; }
.flash-journey-dock {
  position: fixed;
  z-index: 40;
  left: max(24px, calc((100vw - 1280px) / 2));
  right: max(24px, calc((100vw - 1280px) / 2));
  bottom: 24px;
  min-height: 168px;
  overflow: hidden;
  border: 1px solid #4a4946;
  border-radius: 24px;
  box-shadow: 0 28px 80px rgb(0 0 0 / 52%);
}
@media (max-width: 760px) {
  .flash-journey-dock { left: 16px; right: 16px; bottom: 16px; max-height: 42svh; }
}
@media (prefers-reduced-motion: reduce) {
  .flash-journey-dock, .flash-asset-batch, .scroll-stack-card { transition: none; animation: none; }
}
```

- [ ] **Step 7: Run integration verification**

Run: `cd ring-demo && npm test -- --run src/pages/FlashPage.test.tsx src/features/flash/FlashJourneyDock.test.tsx src/features/flash/FlashAssetFolder.test.tsx src/features/flash/flash-assets.test.ts src/components/ScrollStack.test.tsx src/components/AssetCard.test.tsx`

Expected: all focused tests pass.

Run: `cd ring-demo && npm run typecheck && npx vite build`

Expected: TypeScript and Vite production build pass. Existing unrelated 3D-model test failures are reported separately rather than changed in this feature.

- [ ] **Step 8: Browser QA with the real ring flow**

Run the existing local demo, open `http://127.0.0.1:5173/flash`, and verify:

1. first double tap opens the grayscale dock;
2. second double tap stops the live wave;
3. transcript is readable before processing color begins;
4. processing keeps transcript visible and uses steel-blue Dither;
5. N generated cards arrive as one colored front batch;
6. the former batch becomes gray only after success;
7. the right folder scrolls without moving the page;
8. Reset clears the folder and dock.

Capture desktop and narrow-screen screenshots, inspect browser console, and leave the dev server running for user testing.
