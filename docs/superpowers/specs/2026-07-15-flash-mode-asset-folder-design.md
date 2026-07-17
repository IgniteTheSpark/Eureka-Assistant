# Flash Mode Asset Cards and Journey Dock Design

**Date:** 2026-07-16
**Status:** Approved for implementation

## Goal

Separate the transient lifecycle of one spoken Flash from the persistent assets it creates, while making every returned asset feel like an individual result.

- The left panel remains the stable connected-ring product and guidance surface.
- The right panel is an independently scrollable Asset Folder.
- Capture, transcription, semantic analysis, and completion appear in a compact floating Journey Dock.
- One spoken Flash may create one or many cards; every asset becomes its own opaque stack item.

This design applies the canonical card rules in [`spec/04-frontend.md`](../../../spec/04-frontend.md), color rules in [`spec/05-design-system.md`](../../../spec/05-design-system.md), and eight-domain palette in [`spec/08-domain-system.md`](../../../spec/08-domain-system.md).

## Page Structure

### Connected Ring Panel

The left panel always displays the Ring product visual, the real Ring Desktop connection state and controls, and the instruction to double tap, speak, and double tap again. Recording and processing states never replace this panel.

### Asset Folder

The right panel is a stable folder for generated assets. It uses the existing React Bits-style `ScrollStack` inside its own scroll container with window scrolling disabled.

- Scrolling the folder does not move the Ring panel or page header.
- The newest card sits at the front of the stack.
- Older cards remain behind it and are revealed by scrolling downward.
- The front card moves downward into a lower tucked position before the next older card becomes primary.
- The folder returns to the front whenever one or more new cards arrive.
- The folder has a quiet empty state before the first successful Flash.

## One Asset, One Card

The backend remains free to return multiple `cards` or `derived_assets` for one transcript. The UI preserves transcript provenance internally but flattens the response for presentation.

```ts
interface FlashAssetBatch {
  id: string;
  transcript: string;
  createdAt: number;
  cards: Array<Record<string, unknown>>;
}

interface FlashAssetItem {
  id: string;
  batchId: string;
  batchOrder: number;
  createdAt: number;
  card: Record<string, unknown>;
}
```

- A response containing `N` assets creates `N` independent `FlashAssetItem` stack entries.
- No visible batch wrapper, batch heading, or batch count encloses those cards.
- Items from the newest response arrive in response order with a 60 ms stagger.
- New responses prepend their items while existing items keep their relative order.
- The header count reports total cards, not transcript batches.
- The note fallback remains one independent card.

## Card Visual System

Cards use the approved **Neutral Record Slip** information structure with domain-colored surfaces.

### Three-line DNA

Each card has a fixed presentation height and follows the canonical compact structure:

1. identity row: skill icon and display name on the left; domain dot and domain name on the right;
2. title and optional single-line subtitle;
3. at most two compact metadata values on one non-wrapping row.

Long content truncates in the card instead of changing stack geometry. Full-detail presentation remains outside this demo pass.

### Domain Color

The right-side domain indicator and the card surface use the same domain token.

- The card surface is a fully opaque, low-saturation tint derived from its domain color; it is never translucent.
- Text and borders remain neutral so domain color does not reduce legibility.
- Older cards keep their domain surface. History is never represented with grayscale or reduced opacity.
- Stack depth is expressed only through position, restrained scale, and softer shadow.
- Canonical domain tokens are `工作`, `学习`, `健康`, `运动`, `社交`, `娱乐`, `生活`, and `灵感` from `spec/08-domain-system.md`.
- The card reads an explicit card-level `domain` first, then a `domain` meta field. If neither exists, the demo uses a deterministic type fallback so every card still renders safely.

## Stack Direction and Motion

The default folder state shows the newest card in front and older cards behind it.

- Downward wheel, trackpad, keyboard, or touch scrolling tucks the current front card toward the bottom and reveals the next older card.
- Cards are always opaque, including during overlap.
- Rotation and blur remain zero.
- Scale differences are restrained and must not make older cards look disabled.
- A newly returned group scrolls the folder back to the front, then cards enter one by one with the existing 60 ms stagger.
- With reduced motion, transforms settle immediately and arrival uses opacity only.

## Compact Journey Dock

The Dock is fixed near the bottom of the viewport, centered to the page, and narrower than the workbench. Every primary phase uses the exact same outer width and height.

- Desktop target: `width: min(780px, calc(100vw - 48px))` and `height: 122px`.
- Mobile target: `width: calc(100vw - 32px)` with the same compact internal rows.
- Internal rows are: 30 px transcript rail, flexible centered status, and a 20 px utility footer.
- The transcript rail is a single line with ellipsis and never changes Dock height.
- The centered phase title is the dominant Dock element: large white type over a restrained dark contrast veil, with white supporting copy. Dither color identifies the phase without competing with its label.
- The Dock overlays the page and never changes workbench layout.

## Journey Sequence

### 1. Capturing

Triggered by the real `recording.started` event.

- The Dock enters from below the viewport.
- The transcript rail displays a quiet placeholder.
- The center reads `Capturing`.
- Dither is the only live capture visualization; no secondary audio waveform is rendered.
- Dither uses signal blue: `[0.32, 0.57, 1.0]`.

### 2. Transcribing

Triggered by `recording.stopped` or `asr.started`.

- The audio wave stops immediately.
- The center reads `Transcribing`.
- The transcript rail shows the recognized text as soon as `transcript.ready` arrives.
- Dither uses language violet: `[0.67, 0.47, 0.90]`.

### 3. Analyzing

Triggered after transcript acknowledgement while the existing backend Flash request is active.

- The transcript remains in the top rail.
- The center reads `Analyzing`.
- Dither uses semantic teal: `[0.18, 0.76, 0.73]`.
- The backend request still starts immediately when the transcript arrives; presentation timing never delays the API call.

### 4. Generated

Triggered by a successful response with at least one normalized card.

- The transcript remains in the top rail.
- The center reads `Generated`.
- The supporting result reads `{N} card added` or `{N} cards added`.
- Completion uses success green `[0.28, 0.73, 0.48]` with a calmer Dither field.
- The completion state remains visible until the operator selects `Close`; it never dismisses on a timer.
- New cards begin entering the folder with a 60 ms stagger. Closing the Dock does not remove or reorder those cards.

If the response succeeds without a structured card and without a text fallback, the Dock returns to Ready without showing a false `Generated` count.

## State and Component Boundaries

`FlashPage` continues to own Ring events, backend submission, request invalidation, and the approved timing gates.

- `FlashJourneyDock` maps the four primary presentation phases to copy, transcript rail, count, and Dither palette.
- `FlashAssetFolder` flattens newest-first batches into individual stable card items and owns front reset behavior.
- `AssetCard` owns the three-line card DNA, domain label, domain token, and safe generic fallback.
- `ScrollStack` remains reusable and has no Flash-specific data knowledge.
- `Dither` remains reusable and receives phase palette through props.

The existing `FlashAssetBatch` state may remain in `FlashPage` for transcript provenance. Batch boundaries must not appear in the visual folder.

## Failure, Reset, and Navigation

- The four named phases are the exhibition journey. Failure remains an exceptional compact retry surface and receives no new exhibition animation.
- A failed request inserts no cards and does not change existing card color or order.
- Starting a new recording invalidates a stale pending result through the existing request serial.
- Demo reset clears Dock state, transcript, pending request, and every in-memory card.
- Navigating away clears this mounted visual folder; persisted UReka assets remain unchanged.

## Accessibility

- The Dock remains an `aria-live="polite"` region.
- Transcript text remains available to assistive technology even when visually truncated.
- Every independent asset card has its own article label.
- Folder scrolling supports wheel, trackpad, touch, and keyboard input.
- Domain is conveyed by text and color, never color alone.
- `prefers-reduced-motion` disables continuous Dither and animated stack settling.

## Verification

Automated tests must prove:

- one response with `N` assets produces `N` independent Scroll Stack items;
- no visible batch wrapper surrounds the cards;
- old and new cards are fully opaque and retain their domain tokens;
- explicit and meta-field domains drive the domain label and surface token;
- the newest response returns the folder to the front exactly once;
- the Dock has four primary phases with stable geometry;
- Capturing, Transcribing, and Analyzing use distinct Dither palettes;
- Generated shows the correct singular/plural card count and only exits through its close control;
- transcript remains in the top rail from availability through completion;
- Capturing renders no redundant audio waveform alongside Dither;
- failure inserts no card and reset clears the complete experience;
- focused tests, typecheck, production build, and browser QA pass.

## Out of Scope

- Loading the complete historical UReka library into the demo folder.
- Full-screen asset details or editing.
- Changes to Ring Desktop gestures, recording, ASR, or mode routing.
- Changes to Flash agent skill selection or asset-generation semantics.
