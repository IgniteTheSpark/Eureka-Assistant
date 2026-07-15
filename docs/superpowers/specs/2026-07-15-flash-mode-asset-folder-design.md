# Flash Mode Asset Folder and Journey Dock Design

**Date:** 2026-07-15  
**Status:** Approved interaction direction; pending written-spec review

## Goal

Separate the temporary lifecycle of one spoken Flash from the persistent display of assets it creates.

- The left panel remains a stable connected-ring product and guidance surface.
- The right panel becomes an independently scrollable Asset Folder.
- Capture, transcription, and agent processing move into a floating dock at the bottom of the page.
- A single Flash can create one or many cards, which enter the folder as one batch.

This iteration does not redesign the detailed content or typography inside each asset card. It establishes the page structure, state choreography, batch behavior, and domain-color hooks needed for that later card-design pass.

## Page Structure

### Connected ring panel

The left panel always displays:

- the ring product visual;
- the real Ring Desktop connection state and controls;
- the instruction to double tap, speak, and double tap again.

Recording and processing states do not replace this panel.

### Asset Folder

The right panel is a stable folder for generated assets. It uses a React Bits-style `ScrollStack` inside its own scroll container, with window scrolling disabled.

- Scrolling the folder does not move the ring panel or page header.
- The newest successful batch is placed at the front and the folder returns to its top position.
- Cards from earlier batches remain accessible behind it through internal scrolling.
- The folder has a quiet empty state before the first successful Flash.

### Floating Journey Dock

The dock is fixed near the bottom of the viewport and aligned to the page content width. It keeps 24 px of outer space and rounded corners instead of touching the browser edges.

- It overlays the lower portion of both panels without changing their layout dimensions.
- It appears only while one Flash is active.
- It disappears after the generated cards begin entering the Asset Folder.
- The dock does not contain historical cards.

## Interaction Sequence

### 1. Ready

- The Journey Dock is absent.
- The ring panel and Asset Folder remain visible.
- The newest existing batch, if any, keeps its domain colors.

### 2. Capturing

Triggered by the real `recording.started` event.

- The Journey Dock rises from below the viewport with a restrained spring motion.
- It shows the grayscale React Bits Dither background.
- `Capturing` and the live audio-wave treatment are visible.
- The ring panel and Asset Folder remain visible behind the dock.

### 3. Transcribing

Triggered by `recording.stopped` or `asr.started`.

- The audio wave stops immediately.
- The dock remains in place.
- Dither slows while the UI displays `Transcribing` until text is available.

### 4. Transcript acknowledged

Triggered by `transcript.ready`.

- The transcript replaces the transcribing label in the dock.
- The transcript fades in as the primary content, giving the user a clear acknowledgement of what was heard.
- The backend Flash request starts immediately; the UI holds the acknowledgement treatment for a minimum of 700 ms so the transcript is perceptible.

### 5. Creating assets

- The transcript remains visible and identifies the content being processed.
- The status changes to `Creating assets`.
- Dither transitions from grayscale to a cool steel-blue processing palette (`waveColor={[0.28, 0.46, 0.62]}`). The final palette can be tuned with the asset-card visual pass.
- The dock remains until a successful response returns.

### 6. Batch arrival

When the backend returns one or more derived assets:

1. Existing colored cards become the historical batch and transition to grayscale.
2. All cards from the response form one new batch.
3. The folder scrolls to the front.
4. The new cards travel visually from the Journey Dock toward the Asset Folder, then settle into the front of the stack in response order.
5. The Journey Dock fades and moves below the viewport after the first new card begins settling.

If the response contains no structured derived assets but produces the existing note fallback, that fallback is a one-card batch and follows the same choreography.

## Batch and Color Rules

The UI stores generated results as ordered batches rather than one flat card array.

```ts
interface FlashAssetBatch {
  id: string;
  transcript: string;
  createdAt: number;
  cards: AssetCardData[];
}
```

- One accepted transcript creates at most one batch.
- A batch can contain any positive number of cards.
- Only the newest successful batch receives domain colors.
- All prior batches receive a neutral historical treatment through presentation state; card data is never mutated.
- A failed request does not gray the current newest batch because no replacement batch exists.
- Domain classification uses the existing card type/data (`todo`, `event`, `contact`, `note`/`idea`, `expense`, and generic). The first implementation exposes semantic CSS tokens for these domains; detailed palette tuning remains part of the later card-design pass.

The first implementation accumulates batches for the current mounted Flash experience and clears them through the existing demo reset. It does not fetch historical UReka assets into the folder.

## Scroll Stack Behavior

The Asset Folder adapts the React Bits `ScrollStack` component with container scrolling:

- `useWindowScroll={false}`;
- zero rotation and zero blur for legibility;
- restrained scale and vertical stack distance;
- latest batch at the front;
- programmatic return to the front after a successful batch arrives;
- no automatic scroll when capture starts or when processing fails.

The Scroll Stack is a presentation layer. Batch ordering and latest/history state remain explicit React state so the experience does not depend on animation internals.

## State and Component Boundaries

`FlashPage` continues to own the real Ring event and backend pipeline, but presentation responsibilities are separated:

- `FlashJourneyDock`: renders capturing, transcribing, transcript acknowledgement, processing, and exit choreography.
- `FlashAssetFolder`: owns the internal scroll viewport and renders ordered batches.
- `FlashAssetBatch`: maps batch state to latest or historical treatment.
- `ScrollStack`: reusable React Bits adaptation with no Flash-specific data knowledge.
- `Dither`: remains a reusable background and accepts the capture or processing palette through props.

The Flash state model adds a transcript acknowledgement presentation phase and a batch collection. Backend processing may run during the acknowledgement phase; UI timing does not delay the API call.

## Reset, Navigation, and Failure Behavior

- The existing demo reset clears the dock, pending request, transcript, and all in-memory batches.
- Starting a new recording invalidates a stale pending result using the existing request serial behavior.
- An unsuccessful request inserts no cards and does not gray previous batches.
- The existing low-priority retry action remains available in the dock, but no new exhibition-focused failure animation is introduced.
- Navigating away from the mounted Flash experience clears the visual folder in this iteration; persisted UReka assets remain in the backend. Cross-route visual persistence is outside this scope.

## Responsive Behavior

- Desktop keeps the two-column workbench and full-width Floating Journey Dock.
- On narrow screens, the ring panel and Asset Folder stack vertically.
- The dock keeps viewport-side margins, reduces its maximum height, and truncates exceptionally long transcript display without changing the stored transcript.
- The Asset Folder remains independently scrollable at every breakpoint.

## Accessibility and Motion

- The Journey Dock is an `aria-live="polite"` region for state and transcript changes.
- Generated batches receive stable headings describing their creation order and card count.
- Folder scrolling remains keyboard and trackpad accessible.
- With reduced motion enabled, the dock and cards use opacity transitions only; Dither animation is disabled and Scroll Stack transforms settle immediately.

## Verification

Focused tests will cover:

- Dither appears only in active dock phases and uses different capture/processing palettes.
- Recording stop removes the live audio wave without dismissing the dock.
- Transcript remains visible during processing.
- One backend response with N assets creates one batch with N cards.
- A successful new batch grays every older batch and becomes the colored front batch.
- A failed request does not insert a batch or gray the previous batch.
- The folder uses internal rather than window scrolling and returns to the front only after success.
- Demo reset clears both active dock state and accumulated batches.
- Reduced-motion rendering disables continuous background and stack motion.

## Out of Scope

- Final asset-card information design and exact domain palette.
- Loading the user's complete UReka asset history into the folder.
- Changes to Ring Desktop gestures, recording, ASR, or the Flash backend pipeline.
- Grid Scan or other processing backgrounds beyond the approved Dither color transition.
