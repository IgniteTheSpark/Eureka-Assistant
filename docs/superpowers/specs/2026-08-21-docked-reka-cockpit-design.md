# Docked Reka Cockpit Design

**Date:** 2026-08-21  
**Status:** Approved in conversation; awaiting written-spec review  
**Branch:** `codex/skill-dither-report-revamp`

## Summary

Replace the current flat mini Reka floating above the Theme V2 Dock with a lightweight native 3D Reka embedded in a raised central Dock cockpit. Reka remains one continuous product character: the full-size Today Reka is the only Reka on Today, and it visually transitions into the Dock cockpit when the user navigates to Calendar or Library.

The interaction becomes direct and predictable. Tapping Reka resumes the most recent Session, falling back to an empty Session when no history exists. Long-pressing Reka starts Flash voice capture; sliding upward cancels, and releasing sends. The existing quick-action menu is removed.

## Product goals

- Preserve Reka's three-dimensional character outside Today without running a second Three.js WebView.
- Make Reka a structural part of the Dock instead of a separate floating icon.
- Establish two durable gestures: tap for Session, long press for Flash.
- Preserve the single global microphone owner and existing Terminal lifecycle.
- Make Today-to-Dock navigation feel like one Reka changing scale and location, never two Rekas.

## Non-goals

- Do not add a fourth navigation destination or a placeholder Dock action.
- Do not run the full Today Three.js renderer inside the Dock.
- Do not change the streaming-ASR protocol, Flash processing pipeline, Session data model, or asset-generation behavior.
- Do not show Reka on routes or sheets that intentionally hide the Dock.
- Do not reintroduce the removed quick-action menu through another gesture.

## Chosen direction

The selected direction is a **raised central 3D cockpit**.

Two alternatives were rejected:

- A flat avatar inside the existing Dock would be simpler but would lose Reka's volume and character.
- A mechanical attachment on the Dock's trailing edge would preserve the three navigation positions but would make Reka feel secondary and weaken the centered Terminal relationship.

## Visual structure

### Dock shell

- The glass shell is `248 × 64` logical pixels. Bottom safe-area padding sits outside this footprint and never rescales the shell.
- The glass Dock remains a single visual object with one material, border, shadow, and hit-test plane.
- A central cockpit rises from the Dock rather than appearing as a second stacked card.
- The cockpit target is `76 × 72` logical pixels.
- The visible mini Reka is `66 × 48` logical pixels, with `14` logical pixels of its lower body visually seated inside the Dock.
- The three destinations remain Today, Calendar, and Library. Today and Calendar occupy the left navigation region; Library occupies the full right navigation region. Optical spacing, rather than a fake fourth control, balances the composition.
- Every navigation destination and the Reka cockpit retains at least a `44 × 44` logical-pixel interactive target.

### Native mini Reka

The Dock Reka is a lightweight Flutter-rendered miniature, not a WebView. It retains the same identity as the Today renderer through:

- a warm white shell with a directional highlight and lower-body shade;
- a dark curved visor with a subtle reflected edge;
- side modules, body depth, and a soft environmental contact shadow;
- terminal-green or state-tinted pixel eyes;
- a small perspective tilt and idle breathing motion when animations are enabled;
- a static, fully legible pose when reduced motion is enabled.

If advanced paint effects are unavailable, the component falls back to a static native Reka silhouette. Navigation and gestures remain functional.

### State light and eyes

The cockpit uses abstract light rather than a sun, microphone, or other competing iconography.

| Capture state | Cockpit light | Eye behavior |
| --- | --- | --- |
| Idle | Low-intensity cool white | Neutral open pattern |
| Connecting/listening | Cyan-blue breathing light | Bright listening pattern |
| Receiving transcript | Cyan lateral motion | Directional receiving pattern |
| Transcribing/understanding/organizing | Blue-violet progression | Existing phase-specific pixel patterns |
| Done | One restrained green pulse | Completion pattern, then neutral |
| Failed/empty | One warm-red pulse, then decay | Failure pattern, then neutral |
| Slide-to-cancel armed | Warm cancel tint | Cancel pattern retained until release |

State color is redundant to the eye pattern and Terminal copy; color alone never carries meaning.

## Interaction contract

### Tap

- Tapping either the full Today Reka or the Dock Reka opens `ChatPage(themeV2Override: true)` without `startBlank`.
- The existing Session controller calls `resumeLast()`.
- If a recent Session exists, it is restored.
- If no Session exists, the user sees the existing empty Session surface.
- The old quick-action menu and its tap path are removed.

### Long press

- Long-press start immediately requests the existing global Reka voice coordinator to begin Flash capture.
- Holding continues capture and live transcription.
- Moving upward arms cancellation using the existing gesture threshold and exposes the explicit cancel state in the Terminal.
- Releasing while cancellation is armed cancels the capture and creates no Flash.
- Releasing normally finalizes transcription, sends once, and starts the existing Flash-to-assets pipeline.
- A tap must never fire after a completed or cancelled long press.

### Terminal

- The Terminal remains owned by `RekaCompanionController` and contains listening, transcript, processing, completion, empty, and error presentation.
- On Dock pages it opens centered above the cockpit, with a consistent gap and viewport margins.
- It must not cover navigation targets or intercept Dock gestures outside its own bounds.
- Closing the Terminal hides presentation state. If capture is active, close first cancels the active capture so the microphone cannot remain hidden in the background.
- Existing automatic dwell durations remain unchanged.

## One Reka across navigation

### Today

- The scene's full-size Three.js/fallback Reka remains the only rendered and interactive Reka.
- The Dock central cockpit is visually unoccupied and cannot receive Reka gestures.
- The Dock shell retains the cockpit-shaped central rise so navigation geometry does not jump. On Today it renders as an empty, subtle glass recess with no Reka semantics or hit target.

### Calendar and Library

- The full-size Today Reka is inactive.
- The native mini Reka occupies the Dock cockpit and owns tap/long-press gestures.
- The Terminal anchors to the cockpit.

### Transition

- Leaving Today uses a roughly `260 ms` position, scale, and opacity handoff: the Today Reka recedes while the cockpit Reka appears to shrink and settle into the Dock.
- Returning to Today reverses the handoff.
- The implementation does not attempt a pixel-perfect shared element across the WebView boundary.
- At every frame, at most one Reka hit target is active.
- With reduced motion, the handoff becomes a short crossfade with no travel path or scale spring.

## Architecture

### `ThemeV2FloatingDock`

- Owns the expanded glass shell, three navigation regions, central cockpit slot, and safe-area geometry.
- Accepts an optional cockpit child and state needed only for its visual integration.
- Exposes geometry constants used by content clearance and Terminal anchoring.
- Does not own Session navigation, voice capture, or Terminal state.

### `RekaMini`

- Becomes the native mini 3D renderer and gesture surface.
- Accepts the canonical capture presentation/cue rather than recreating capture state.
- Maps capture phases to eye patterns, body response, and cockpit light.
- Keeps tap and long-press callbacks provider-neutral.

### `RekaShellCompanion`

- Stops positioning mini Reka as an independent element above the Dock.
- Supplies the mini Reka to the Dock cockpit on Dock pages.
- Continues positioning the Terminal relative to either the full Today Reka or the Dock cockpit.
- Coordinates presentation handoff without owning navigation or capture business logic.

### `ThemeV2AppShell`

- Remains the single owner of companion presentation, Reka voice coordination, and route actions.
- Replaces `_openRekaQuickActions` with a direct resume-Session route.
- Supplies the same tap and long-press callbacks to both Today Reka and Dock Reka.
- Selects which Reka representation is visible and interactive from the active page and Dock visibility.

### Existing controllers

- `VoiceInputCoordinator`, `RekaVoiceCaptureCoordinator`, and `RekaCompanionController` remain the only microphone and Terminal lifecycle path.
- `ChatPage` and its current `resumeLast()` behavior remain the Session restoration path.
- No provider, account, or global mutex is added.

## Layout and accessibility

- Dock-page body clearance is derived from the expanded Dock/cockpit footprint instead of a hard-coded approximation.
- Calendar and Library scrolling content must remain reachable above the Dock at compact viewport heights.
- Large text must not resize the robot or Dock into an overflow; semantic labels scale independently from icon geometry.
- Reka semantics: `Reka，轻点继续最近对话，长按记录闪念，上滑取消，松开发送`.
- Reduced-motion behavior is deterministic and covered by tests.
- Light and dark themes preserve visor contrast, shell separation, focus indication, and state-light readability.
- Routes and bottom sheets without the Dock show neither cockpit Reka nor Terminal, matching the existing product rule.

## Error and lifecycle behavior

- A failed Session resume lands on the existing Session empty/error surface; the Dock does not invent another error toast.
- Capture connection, timeout, empty transcript, and provider failures continue to use the Terminal's existing normalized states.
- Navigating between Dock tabs does not cancel capture because the Shell remains mounted.
- Navigating to a route that hides the Dock cancels active Reka capture through the existing lifecycle path before presentation disappears.
- App backgrounding, auth identity changes, and coordinator disposal retain their existing cancellation behavior.
- Terminal dismissal and navigation transitions cannot create a second capture, double-send a transcript, or leave a hidden microphone session.

## Test strategy

### Unit and widget tests

- Native mini Reka paints each canonical capture state and respects reduced motion.
- Cockpit, three destinations, and all semantic hit targets meet the minimum size.
- Tap pushes a resumable Session route and never shows the quick-action menu.
- No-history tap produces the existing Session empty state.
- Long press, upward cancellation, normal release, and gesture cancellation each call the global coordinator exactly once.
- A long press never also fires tap.
- Today and Dock modes never expose two active Reka hit targets.
- Terminal geometry anchors above the cockpit and does not overlap destination hit targets.
- Compact viewports, large text, light/dark themes, and Library loading state have no overflow.
- Dock-free routes and sheets expose no Reka or Terminal semantics.

### Golden tests

- Dock idle in light and dark themes.
- Listening and understanding states.
- Slide-to-cancel state.
- Terminal open above the cockpit.
- Reduced-motion static state.

### Regression and device validation

- Run the existing voice-input, capture, Today, Shell, Library, and Session suites.
- Run targeted static analysis for all touched production and test files.
- Build an Android debug APK with `API_BASE=http://localhost:8000`.
- Install on the connected Android device and verify:
  - Today-to-Dock and Dock-to-Today visual handoff;
  - tap resumes the last Session;
  - long press streams Mandarin and English transcript;
  - upward cancellation creates no Flash;
  - normal release creates one Flash and reaches asset output;
  - Terminal status remains visible on Dock pages and disappears on Dock-free routes;
  - no layout obstruction on Calendar and Library.

## Acceptance criteria

The redesign is accepted when the Dock Reka visibly retains Reka's 3D identity, is structurally seated in the central cockpit, replaces the quick-action menu with direct Session resume, preserves the existing long-press Flash contract, and never duplicates Reka or microphone ownership across Today, Dock pages, routes, or transitions.
