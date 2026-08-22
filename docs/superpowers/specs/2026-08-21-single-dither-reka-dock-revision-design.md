# Single Dither Reka Dock Revision Design

## Status

Approved on 2026-08-21. This document supersedes the conflicting Dock geometry and native-mini sections of `2026-08-21-docked-reka-cockpit-design.md`. The direct Session route, long-press Flash contract, Terminal lifecycle, and single microphone ownership from the earlier design remain unchanged.

## Problem

The first Dock implementation introduced two visual errors:

- Today retained an empty central cockpit, so the navigation bar looked as though Reka had left a placeholder behind.
- Calendar and Library rendered a realistic native miniature inside a raised container. It did not look like the dithered Today Reka and forced additional Dock footprint and page clearance.

The product should present one continuous Reka character. Moving between root pages must feel like the existing dithered Reka itself changes size and position.

## Selected Direction

Use one `TodayDitheredReka` renderer owned by the Theme V2 shell.

- Today presents that renderer at the existing full size and scene position.
- Calendar and Library present the same renderer inside a `78 × 54` logical-pixel visible frame, floating above the compact Dock.
- The shell changes only the renderer's transform, activity, and gesture target across root navigation. It never creates a second WebView-backed Reka.
- The native realistic `RekaMini` artwork and raised cockpit container are removed from production presentation.

This is preferred over a second miniature WebView because it preserves one renderer and avoids duplicate GPU/context lifecycle. It is preferred over a static image or native approximation because the actual dither treatment, transparent rendering, pixel eyes, and capture states remain identical.

## Dock Layout

### Today

- Restore the previous compact `169 × 60` three-destination Dock.
- Distribute Today, Calendar, and Library evenly with no central spacer, recess, bulge, or empty Reka target.
- Do not reserve any Dock geometry for Reka.

### Calendar and Library

- Use the same compact Dock geometry as Today.
- Position the small dither Reka in a shell-level overlay centered over the Dock's upper edge.
- Reka has a transparent background and no cockpit, card, halo container, border, or supporting pedestal.
- The visible body may overlap the Dock edge slightly, but its interactive target remains at least `72 × 72` logical pixels.
- Reka does not alter page bottom padding or content clearance. Pages use the same clearance as the compact Dock without Reka.

## Motion

- Root-page navigation transforms the single renderer between the Today scene anchor and Dock anchor over `260 ms`.
- The transform combines position, scale, and a restrained opacity blend; it does not fake a second Reka during the handoff.
- At rest on Dock pages, Reka keeps a subtle vertical breathing float and very small scale modulation.
- When system reduce-motion is enabled, travel and breathing are removed. The renderer uses a short opacity transition at the destination position.
- App backgrounding pauses renderer motion through the existing lifecycle path.

## Interaction and State

- The full and compact layouts expose the same single Reka semantics and gesture target.
- Tap opens `ChatPage(themeV2Override: true)` and resumes the latest Session, falling back to the existing empty Session.
- Long-press begins the global Flash capture; move upward arms cancellation; release cancels or finalizes according to the existing gesture threshold.
- The dither renderer receives the same listening, receiving, understanding, done, failure, and cancel-armed eye/capture cues in both layouts.
- The Terminal remains shell-owned. On Dock pages it anchors above the floating Reka and may disappear behind modal sheets together with the Dock.
- Routes without the Dock show neither the compact Reka nor its Terminal.

## Ownership and Structure

### `ThemeV2AppShell`

- Owns the one dither renderer, its root-page transform, gesture callbacks, and visibility.
- Receives or computes the Today and Dock anchors.
- Keeps navigation selection and Reka transform state synchronized.

### Today surface

- Provides the full-size scene anchor and interaction bounds to the shell.
- Stops constructing its own WebView-backed renderer.
- Keeps its surrounding dither field, motion controller inputs, output cues, and capture cues.

### `ThemeV2FloatingDock`

- Returns to the compact three-button shell.
- Has no `rekaCockpit` slot and no Reka-specific content-clearance constants.

### Companion presentation

- Continues owning voice and Terminal lifecycle.
- Supplies phase/capture state to the shell renderer instead of constructing a native miniature.

## Failure and Fallback

- The existing renderer timeout and `TodayRekaFallbackPainter` remain the fallback path. The fallback uses the same transform in both full and compact layouts.
- A renderer initialization failure never restores the removed realistic mini or cockpit.
- Navigation and voice gestures remain available when fallback art is active.

## Verification

- Widget tests prove exactly one `TodayDitheredReka` exists across Today, Calendar, Library, transitions, and reduced-motion states.
- Dock tests prove `169 × 60` geometry, three evenly distributed destinations, and no cockpit/spacer on Today.
- Scaffold tests prove Calendar and Library content clearance matches the compact Dock and is unchanged by Reka visibility.
- Motion tests prove forward/reverse transforms, one active gesture target, breathing, lifecycle pause, and reduced-motion behavior.
- Golden tests cover Today, Calendar, and Library in light/dark modes plus listening, cancel-armed, Terminal-open, and reduced-motion states.
- Existing Session, voice-input, capture, Today, Calendar, Library, and Theme V2 shell suites must remain green.
- Final acceptance uses the physical Android device to verify the dither renderer, absence of the Today placeholder, direct Session tap, long-press Flash, and the complete `8200` API/ASR proxy chain.

## Acceptance Criteria

The revision is accepted when Today visibly uses the old compact three-button Dock with no Reka placeholder; Calendar and Library show the actual dithered Reka floating above that Dock without a container or added content clearance; the character breathes subtly, remains one renderer, and preserves all Session and Flash interactions.
