# Session Composer State Machine Design

- **Date:** 2026-08-21
- **Status:** Approved for written review
- **Branch:** `codex/skill-dither-report-revamp`
- **Scope:** Session composer layout, focus, voice, draft, and agent-response states

## 1. Context

The current Session composer caps its `TextField` at five visible lines and keeps microphone and send actions in an external horizontal rail. That prevents unbounded growth, but it does not create a coherent long-input experience:

1. Long text and provisional speech compete with a persistent action rail for horizontal space.
2. A read-only field receiving provisional speech does not reliably follow its newest text after it exceeds five lines.
3. Send remains visually present while speech is active even though a partial transcript must not be submitted.
4. The idle composer exposes controls that are only useful after a user starts editing.

This design replaces those independent conditions with a derived Session-specific state machine and one integrated composer card. It refines the Session portion of `2026-08-20-voice-input-field-status-and-session-composer-design.md`; the shared voice coordinator, ASR service, other ordinary input fields, and Reka interaction remain unchanged.

## 2. Goals

- Keep the idle composer visually compact: one input region and one voice action.
- Expand the composer only after keyboard editing begins or unsent content exists.
- Hide send throughout voice connection, listening, and finalization.
- Keep the newest spoken content visible after the transcript exceeds five lines.
- Keep typed drafts and finalized voice transcripts sendable after the keyboard closes.
- Prevent both sending and recording while the Agent is replying.
- Treat the leading sparkle as decoration only until context attachment receives a separate product design.
- Express the behavior as explicit derived states with deterministic widget tests.

## 3. Non-goals

- Changing the ASR provider, streaming protocol, microphone ownership, or five-minute recording limit.
- Changing voice behavior outside the Session composer.
- Changing Reka long-press, release-to-send, or slide-up-to-cancel behavior.
- Designing or retaining an interactive context-asset attachment entry point.
- Adding auto-send for ordinary Session voice input.
- Changing Session request, response, or error protocols.

## 4. Derived State Model

The composer derives presentation from four inputs rather than storing independent presentation booleans:

- whether the Agent is replying (`streaming`);
- the provider-neutral voice controller state;
- whether the text field owns keyboard focus;
- whether the current text contains a non-whitespace draft.

The base presentation states are:

| State | Condition | Presentation |
| --- | --- | --- |
| `collapsedIdle` | Voice idle, field unfocused, no draft | Compact input region with decorative sparkle and one microphone action; no footer and no send action |
| `editing` | Voice idle and field focused | Expanded integrated card; input area above a footer containing microphone and send actions; send is disabled while text is empty |
| `voiceActive` | Voice connecting, listening, or finalizing | Keyboard dismissed; input is read-only; footer contains voice status and the applicable stop/finalization presentation; send is absent |
| `reviewReady` | Voice idle, field unfocused, and a draft exists | Keyboard remains closed; expanded card retains microphone and send actions so the draft can be submitted without reopening the keyboard |

Agent reply is a higher-priority interaction lock applied to the derived layout. While `streaming` is true:

- starting voice input is impossible;
- sending is impossible at both the button and submission-method boundaries;
- existing draft text remains visible and is not discarded;
- the composer does not resize merely because controls become disabled.

Text overflow is orthogonal to the base state. It changes only the input region's height and scroll position; it does not create another business state.

## 5. State Transitions

### 5.1 Keyboard input

1. Tapping the idle input requests focus and opens the keyboard.
2. The card expands to `editing` and reveals its footer.
3. The user may type from one to any number of lines.
4. Manually dismissing the keyboard with a non-empty draft enters `reviewReady`; send remains visible.
5. Submitting immediately clears the draft, removes focus, closes the keyboard, and returns the presentation to `collapsedIdle` while the Agent reply lock becomes active.

### 5.2 Voice input

1. Tapping the idle or editing microphone starts the existing voice controller.
2. As soon as voice activation begins, the composer removes keyboard focus and enters `voiceActive`.
3. Connecting, listening, and finalizing use the shared in-field voice status semantics.
4. Send is not built anywhere in `voiceActive`, including when provisional text is non-empty.
5. While listening, the footer exposes one stop action. Connecting and finalizing preserve the footer geometry but do not expose an invalid stop action.
6. Successful finalization retains the transcript and enters `reviewReady` with the keyboard closed and send restored.
7. Cancellation or failure uses the existing snapshot contract. A restored non-empty draft enters `reviewReady`; an empty snapshot returns to `collapsedIdle`.

Starting voice while editing records at the current controller selection using the existing insertion-range behavior. Cancelling restores the exact pre-recording text and selection.

### 5.3 Re-editing and resubmission

- Tapping a `reviewReady` transcript restores focus and enters `editing` without changing its text.
- Starting another recording from `reviewReady` keeps the current draft as the new voice snapshot.
- Sending is allowed only when text is non-empty, voice is idle, and the Agent is not replying.

## 6. Layout

### 6.1 Idle composition

The unfocused empty composer consists of:

- one rounded input region containing placeholder copy and a subtle leading sparkle;
- one separate 48-by-48 microphone action;
- no send action and no bottom toolbar.

The sparkle is wrapped with pointer and semantics exclusion. It cannot be tapped, focused, or announced as a button. No context-asset callback is wired in this design.

### 6.2 Expanded composition

`editing`, `voiceActive`, and `reviewReady` use one rounded card with two vertical regions:

1. a full-width text region;
2. a fixed-height footer separated by a subtle divider.

Keyboard/review footers place microphone and send on the trailing side. The voice footer places status on the leading side and the active stop control on the trailing side. Actions remain 48-by-48 and the footer height never depends on text length.

State changes use the existing reduced-motion preference: the card may animate size when motion is allowed and changes immediately otherwise.

### 6.3 One to five lines

- The text region grows naturally from one through five visible lines.
- The footer stays fixed below it rather than sharing its horizontal row.
- Large text scaling recalculates the five-line height from the effective line height and still preserves the footer and touch targets.

### 6.4 More than five lines

- The text region stops growing at five visible lines.
- Additional text scrolls vertically inside that region.
- Footer geometry and the surrounding transcript layout do not move.
- Manual keyboard editing uses Flutter's caret visibility behavior.
- Voice updates use a Session-owned scroll controller. Each provisional or stable voice update schedules a post-layout jump to the current maximum scroll extent.
- Final voice text receives the same tail-follow treatment before `reviewReady` is rendered.
- If a user scrolls upward while speech is active, the next speech update deliberately returns to the tail. The requirement is to keep the newest spoken content visible continuously.

## 7. Component Boundaries

### 7.1 Session composer state owner

`SessionComposer` becomes stateful so it can own:

- the text field's vertical `ScrollController`;
- focus and text-controller listeners;
- post-frame tail-follow scheduling;
- the pure derivation of composer presentation from focus, text, voice, and Agent reply state.

No provider events or ASR protocol types enter the widget. It consumes only the existing provider-neutral `VoiceInputController` state and `VoiceInputTextController` value.

### 7.2 Shared voice components

The shared status presentation and controller lifecycle remain authoritative for connecting, listening, finalizing, cancellation, errors, and duration warnings. Session may arrange their presentation but must not duplicate their lifecycle rules.

The shared ordinary-field API may receive a narrowly scoped composition hook only if required to place Session actions inside the integrated footer. Other call sites retain their existing appearance and behavior.

## 8. Error and Edge Behavior

- Voice failure restores the pre-recording snapshot and renders the existing error copy below the card.
- Duration warnings render below the card and do not change footer alignment.
- Repeated start, stop, or send attempts remain guarded by the controller and submission method, not only by disabled UI.
- Starting voice dismisses the keyboard before provisional text arrives.
- Agent reply disables both voice and send even if focus or draft state changes during the reply.
- Session switching retains the existing rule that the previous Session draft is cleared.
- No new persistence, retry, pause, auto-send, or context-attachment behavior is introduced.

## 9. Accessibility

- Input, microphone, stop, and send retain explicit semantics and tooltips.
- The decorative sparkle is excluded from interaction and semantics.
- Voice status remains a live region but does not announce every provisional transcript mutation.
- Hidden actions are removed from the semantics tree rather than merely made transparent.
- Disabled Agent-reply actions cannot receive activation.
- Every action retains a minimum 48-by-48 touch target.
- Repeating listening animation remains disabled when reduced motion is requested.

## 10. Testing Strategy

### 10.1 State derivation

- Empty and unfocused produces `collapsedIdle` with no send action or footer.
- Focusing produces `editing`; an empty draft disables send and a non-empty draft enables it.
- Any active voice state produces `voiceActive` and removes send regardless of provisional content.
- Final voice text with no focus produces `reviewReady` and restores send.
- Dismissing the keyboard with a typed draft produces the same `reviewReady` presentation.
- Agent reply prevents send and voice activation at UI and method boundaries.

### 10.2 Layout and scrolling

- One-line input stays compact after expansion.
- Five lines reach the designed maximum without overflow.
- More than five lines scroll internally without increasing the composer height.
- Footer size and action alignment remain identical for short and long content.
- Repeated provisional and stable voice updates leave the internal scroll position at the new maximum extent.
- The final transcript tail remains visible after voice returns to idle.
- Large text scale, keyboard inset, warnings, and errors do not cause render overflow.

### 10.3 Interaction and regression

- Voice activation dismisses an open keyboard.
- Send immediately clears content and dismisses the keyboard before an asynchronous request completes.
- Cancel and failure restore the original draft and selection.
- Session switching still clears the previous draft.
- Existing voice surfaces outside Session and Reka remain unchanged.
- Session visual baselines cover idle, editing, listening, long listening, review-ready, keyboard, Agent-reply, light, and dark states.
- A new debug build is installed on the connected Android device for final interaction verification.

## 11. Acceptance Criteria

- An empty, unfocused Session composer shows only the input region and microphone action; it does not show send.
- Focusing the input opens the keyboard and reveals a footer with microphone and send.
- Voice activation closes the keyboard and removes send until voice finalization completes.
- Finalized voice text is visible and sendable without reopening the keyboard.
- Manually dismissed typed drafts remain sendable.
- Text beyond five lines never grows the composer further and always shows the latest spoken tail during streaming transcription.
- Sending clears the composer, closes the keyboard, and restores the compact idle presentation.
- Agent reply blocks both sending and recording.
- The sparkle is decorative only and no context-asset action is reachable from it.
- Other voice-input surfaces, ASR behavior, and Reka interaction are unchanged.
