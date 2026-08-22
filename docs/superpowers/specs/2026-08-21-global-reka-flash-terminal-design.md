# Global Reka Flash Terminal Design

- **Date:** 2026-08-21
- **Status:** Approved for written review
- **Branch:** `codex/skill-dither-report-revamp`
- **Scope:** App and hardware Flash capture status across Theme V2 root pages

## 1. Context

Flash capture currently has two disconnected presentations. App voice capture starts from the full Reka on Today and renders a temporary status panel near the top of the page. Hardware capture replaces the global top navigation with `CaptureActivityTopBar`. Neither treatment creates a consistent Reka-owned experience, and the top placement is difficult to hold during one-handed use.

This design gives Flash one persistent presentation model and two route-aware forms:

- the existing full draggable Reka on Today;
- a lightweight mini Reka centered immediately above the floating Dock on other root pages.

Both forms own the same upward-opening terminal. The terminal presents the entire capture lifecycle, from live listening through the final backend result. The normal top navigation remains visible throughout.

## 2. Goals

- Allow users to start Flash by holding Reka from every root page that displays the Dock.
- Keep the interaction reachable with one hand: hold to record, release to send, and slide upward to cancel.
- Present live transcription and all later processing states inside one Reka terminal.
- Use the existing Thinking Orb as a premium, immediately legible state signal.
- Represent hardware and App captures through the same terminal without inventing unavailable hardware transcript data.
- Keep capture state alive while route chrome or a Bottom Sheet temporarily hides its presentation.
- Correlate App voice capture with its backend activity so the terminal hands off without flicker or duplicate tasks.
- Reserve shared page space for the mini Reka without adding route-specific padding.

## 3. Non-goals

- Changing the cloud ASR provider, streaming protocol, recording limits, or backend Flash pipeline.
- Showing Reka or capture state on detail pages whose shell configuration hides the Dock.
- Keeping Reka visible above Bottom Sheets, dialogs, or other foreground modal surfaces.
- Adding live hardware transcription before the hardware event protocol supplies transcript content.
- Designing asset attachment, context association, retry, pause, or transcript editing.
- Replacing the existing full Today Reka with a second rendering engine.
- Changing the behavior of voice input inside ordinary text fields or Session chat.

## 4. Product Behavior

### 4.1 Today

Today retains the existing full-size, draggable Reka. Holding it starts Flash recording. The terminal opens upward from Reka's current position and follows it while remaining clamped to the safe viewport.

The full Reka does not physically animate through the navigation stack into another page. Route changes use a short scale-and-crossfade between the existing Today Reka and the shell mini Reka. With reduced motion enabled, the presentation switches immediately.

### 4.2 Other Dock pages

Calendar and Library root surfaces show a mini Reka centered above the floating Dock. It preserves the recognizable head, visor, and eye language but uses a lightweight Flutter rendering rather than another 3D WebView.

- Long press starts Flash.
- Continuing to hold records speech.
- Releasing sends the recognized text immediately, with no edit step.
- Sliding upward by the existing cancellation threshold cancels.
- A normal tap retains Reka's existing quick-action entry point.

The terminal expands upward from the mini Reka. The mini Reka remains visually associated with the Dock but is not embedded inside a Dock destination.

### 4.3 Hidden contexts

- If `ThemeV2PageScaffold.showDock` is false, neither mini Reka nor its terminal is rendered.
- A Bottom Sheet naturally paints over the Dock, mini Reka, and terminal. Capture or backend processing continues underneath.
- Returning to a Dock page shows a currently active task unless the user dismissed that task or its terminal dwell time has expired.
- Hiding the presentation never changes backend task ownership.

## 5. Terminal Visual Design

### 5.1 Structure

The terminal has a stable dark body and a state-responsive header.

The header contains:

- the existing morphing Thinking Orb;
- a short phase label such as `聆听中`, `正在转录`, or `正在整理`;
- a tinted background that transitions with state.

The body contains the primary transcript or processing message, compact terminal metadata, queued-task count when needed, and a close action. The terminal uses restrained technical typography rather than imitating a literal command prompt.

### 5.2 Visual hierarchy

- Live transcript: 16–17 px, medium weight, up to four visible lines.
- Processing and result messages: approximately 13 px.
- Source, command, time, and gesture hints: approximately 10 px monospace.
- Interactive targets, including close, remain at least 48 by 48 logical pixels.

Once the transcript exceeds four lines, the body keeps a fixed height and scrolls internally to the latest text. Each streaming update deliberately follows the tail; it does not remain at the end of the previously visible fourth line.

### 5.3 State color

The Orb and header tint provide the first visual signal while the terminal body remains stable:

| Phase | Header treatment |
| --- | --- |
| Connecting / listening | Cyan |
| Receiving / transcribing | Violet-blue |
| Understanding / organizing | Violet with restrained coral accents |
| Done | Green-gold |
| Empty / failed | Restrained coral |

Color supports, but never replaces, the text phase label.

## 6. State Model

### 6.1 Normalized presentation model

The Shell exposes a provider-neutral `RekaTerminalModel` containing only presentation data:

- stable activity identity and aliases;
- source (`app`, `ring`, `card`, or `audioUpload`);
- normalized phase;
- partial or final transcript when available;
- result count;
- queued count;
- whether a result detail can be opened;
- whether the current task has been dismissed.

Provider protocol details remain in their current adapters and coordinators.

### 6.2 App capture states

The local `RekaVoiceCaptureCoordinator` remains authoritative during direct interaction:

1. `connecting`
2. `listening`
3. `cancelArmed`
4. `stopping`
5. `sending`
6. `error` or idle

While listening, its streaming transcript is the terminal's primary content. Release finalizes the text and submits it as a text Flash. Slide-up or close cancels and creates nothing.

The voice session identifier is submitted as `client_task_id`. The Shell treats the corresponding backend aliases as the same logical activity and hands presentation from the local voice coordinator to `CaptureActivityCoordinator` without hiding, reopening, or duplicating the terminal.

### 6.3 Hardware capture states

Hardware events enter through the existing capture activity pipeline:

1. receiving
2. transcribing
3. understanding
4. organizing
5. done, empty, or failed

The terminal labels the source, for example `REKA://RING` or `REKA://CARD`, and shows only real phase information. Because the current event model does not carry transcript text, hardware capture must not display fabricated partial or final speech content.

When both `sessionId` and `inputTurnId` are available, tapping a completed terminal opens the existing activity detail. Before then, the terminal is status-only.

### 6.4 Priority and queueing

Only one activity occupies the terminal:

1. A user-held App recording has highest priority.
2. Otherwise the existing coordinator's realtime activity wins.
3. Otherwise the oldest pending activity is shown.

Additional activities are summarized as `另有 N 条`. They remain owned and ordered by `CaptureActivityCoordinator`; the companion does not create a second queue.

## 7. Lifecycle and Dismissal

- Listening, transcribing, understanding, and organizing remain visible while the companion itself is visible.
- Done remains for approximately two seconds.
- Empty remains for approximately three seconds.
- Failed remains for approximately four seconds.
- The user may manually close the terminal at any time.
- Closing during connecting, listening, cancel-armed, or stopping cancels local capture and releases the microphone.
- Closing after submission hides presentation only. Backend work continues.
- A manually dismissed activity identity cannot reopen when that same activity advances to a later phase.
- Dismissal ends when that activity leaves the coordinator. A new task may show normally.
- App backgrounding, audio interruption, or call interruption cancels local recording. Already-submitted App work and hardware work continue.
- An empty final ASR result creates no Flash and shows `未识别到有效内容` before the empty dwell expires.

## 8. Architecture and Component Boundaries

### 8.1 `RekaCompanionController`

A Shell-owned controller adapts the local voice coordinator and capture activity coordinator into `RekaTerminalModel`. It is responsible for identity merging, presentation priority, dismissal suppression, terminal dwell, and route-independent lifecycle.

It does not render widgets, perform ASR, own backend tasks, or duplicate the capture queue.

### 8.2 `RekaShellCompanion`

The Shell-level presentation chooses among three view modes:

- full Today anchor;
- centered mini Reka above the Dock;
- hidden when the active page does not show the Dock.

It owns gesture routing, safe terminal placement, mini/full visual transition, and modal-compatible stacking. It consumes the controller but does not interpret provider events itself.

### 8.3 `RekaTerminal`

The terminal is a reusable pure presentation of `RekaTerminalModel`. It owns header color, Orb phase, transcript tail-follow, result affordance, close semantics, and reduced-motion rendering.

### 8.4 Existing components

- `RekaVoiceCaptureCoordinator` continues to own local recording, ASR, cancel, release-to-send, and cleanup.
- `CaptureActivityCoordinator` continues to own server and hardware activity merging and queueing.
- `CaptureActivityTopBar` no longer replaces the global navigation for Flash status. Its status behavior moves into the companion; unrelated top navigation behavior remains unchanged.
- `ThemeV2AppShell` owns and wires the companion so pages do not create independent microphone or activity state.

This boundary guarantees that one signed-in user has one App-level voice capture owner. Page changes cannot create competing microphone sessions or surface an `another input is using the microphone` error.

## 9. Layout Integration

`ThemeV2PageScaffold` centrally reserves the mini Reka footprint whenever `showDock` is true. On non-immersive Dock pages, total bottom content clearance is 136 logical pixels plus the existing device safe-area contribution, replacing the current Dock-only 80-pixel clearance.

The terminal itself is transient overlay content and does not increase page padding; opening it must not make page content jump. Pages must not add their own Reka padding.

Today's immersive layout remains responsible for its existing full Reka space. The Shell uses the Today anchor geometry for terminal placement rather than adding mini-Reka clearance there.

## 10. Error Handling

- Microphone permission denial shows a terminal error and creates no Flash.
- Network or ASR connection failure shows a terminal error, restores idle ownership, and creates no Flash.
- Repeated start or close gestures are idempotent at the controller boundary.
- Cancellation and interruption always dispose audio streams and release microphone ownership.
- A backend failure after submission does not restore recording; it remains a failed activity that may be dismissed.
- Missing hardware transcript data is represented by phase copy, not placeholder transcript text.
- If a detail identifier is incomplete, result navigation remains disabled rather than guessing a destination.

## 11. Accessibility and Motion

- The terminal announces phase changes as a live region but does not announce every partial transcript update.
- Color is accompanied by phase text and accessible semantics.
- Long press, close, result, and quick-action targets remain at least 48 by 48.
- The slide-to-cancel gesture retains a visible and announced cancellation threshold.
- With reduced motion enabled, the Orb uses a static state form, recurring animation stops, and mini/full switching is immediate.
- Text contrast, header contrast, safe-area bounds, and large text scaling are verified in light and dark themes.
- At large text scales, the transcript remains internally scrollable and actions remain reachable without overflow.

## 12. Testing Strategy

### 12.1 Controller tests

- Normalize every App and hardware phase into the terminal model.
- Merge local `voiceSessionId` and backend `client_task_id` aliases into one activity.
- Prove local-to-backend handoff has no idle frame, duplicate task, or reopened terminal.
- Verify held App capture priority, realtime priority, oldest-task fallback, and queued count.
- Verify dismissal suppresses every later phase of the same activity but not a new activity.
- Verify done, empty, and failure dwell timers and timer cancellation on a new task.
- Verify no-Dock presentation changes do not pause or cancel processing.

### 12.2 Widget and layout tests

- Today uses the full Reka anchor; Calendar and Library roots use the centered mini Reka.
- Calendar and Library detail surfaces with `showDock == false` render neither mini Reka nor terminal.
- A Bottom Sheet covers Dock, mini Reka, and terminal without altering capture state.
- Shared bottom clearance prevents root-page content from being covered.
- The terminal opens upward, clamps to the viewport, and does not resize page content.
- Transcript updates beyond four lines keep the newest text visible.
- Header tint, Orb phase, close affordance, result affordance, queued count, and source labels match the model.
- Standard top navigation is never replaced by capture state.
- Reduced motion and large text scaling produce no overflow or unreachable controls.

### 12.3 Lifecycle and regression tests

- Hold, release-to-send, slide-up cancellation, close-to-cancel, empty speech, permission denial, ASR failure, and call interruption each release the microphone exactly once.
- Route changes during recording preserve the same capture owner and terminal state.
- Route changes after submission preserve backend processing.
- Hardware capture remains visible through each real phase and never renders an invented transcript.
- Ordinary field voice input and Session voice input remain functionally unchanged.
- No second WebView or duplicate Reka engine is created.

### 12.4 Physical-device verification

On the connected Android device, verify:

- one-handed long press from Today, Calendar, and Library root surfaces;
- release send and slide-up cancellation;
- Terminal following a dragged Today Reka;
- four-line transcript tail-follow during streaming speech;
- navigation during recording and processing;
- Bottom Sheet occlusion and state recovery;
- microphone permission and phone-call interruption cleanup;
- smooth route transition and stable frame/rendering performance.

## 13. Acceptance Criteria

- Every root page that displays the Dock provides the same Reka hold-to-Flash interaction.
- Today shows the full Reka; other Dock pages show one centered mini Reka directly above the Dock.
- Pages reserve enough shared bottom space that mini Reka does not obscure content.
- No-Dock pages and foreground Bottom Sheets do not show the companion.
- The terminal presents live App transcription, backend processing, and final status in one uninterrupted activity.
- Live transcript is the terminal's primary text, displays up to four lines, and continuously follows the newest content.
- Hardware capture uses the same terminal with accurate source and phase copy but no invented transcript.
- The Thinking Orb and header background communicate state without replacing textual status.
- Closing during recording cancels; closing after submission hides only; dismissed tasks do not reappear.
- The global top navigation remains stable for the entire capture lifecycle.
- Navigation cannot create a second voice owner or a competing-microphone error.
- Existing ASR, backend Flash behavior, ordinary field voice input, and Session voice input remain unchanged.
