# Voice Input Field Status and Session Composer Design

- **Date:** 2026-08-20
- **Status:** Approved
- **Branch:** `codex/skill-dither-report-revamp`
- **Scope:** In-field voice status across ordinary text inputs and stable Session composer layout

## 1. Context

The shared cloud voice-input lifecycle is already available from Session, report, Skill, Flash, and other free-text authoring surfaces. The current ordinary-field presentation still has two usability defects:

1. Voice state is communicated only by changing an action button outside the text field. A user reading the provisional transcript does not have a clear in-field signal that the App is still listening or finalizing.
2. The Session composer uses nested rows for its growing text field, voice controls, and send control. With long input, the text field grows independently and the right-side controls no longer share one stable baseline.

This design adds a shared in-field status presentation and gives the Session composer a bounded, internally scrolling text area with a fixed action rail. It refines the ordinary-field cancellation presentation in `2026-08-20-mobile-cloud-voice-input-design.md`; the shared ownership and lifecycle guarantees in `2026-08-20-shared-voice-input-lifecycle-design.md` remain unchanged.

## 2. Goals

- Make connecting, listening, and finalizing visible inside every adopted ordinary voice-input field.
- Keep the state indicator visually quiet, space-efficient, and accessible.
- Prevent long Session messages from pushing or misaligning voice and send controls.
- Preserve editable final transcripts and explicit send/save behavior.
- Use one state-to-presentation mapping rather than page-specific voice indicators.
- Reduce ordinary-field recording controls to one unambiguous stop action while recording.

## 3. Non-goals

- Changing the ASR provider, streaming protocol, microphone ownership, or backend lifecycle.
- Adding pause/resume, retry, audio playback, or retained audio.
- Changing Reka's long-press, release-to-send, and slide-up-to-cancel interaction.
- Automatically submitting ordinary text fields.
- Adding a control that clears all text from an ordinary field.

## 4. Product Behavior

### 4.1 In-field voice status

Every adopted ordinary free-text input shows a non-interactive status icon inside the field while voice input is active:

| Voice state | In-field presentation |
| --- | --- |
| `idle` | No status icon |
| `connecting` | Compact progress indicator |
| `listening` | Animated pulse or waveform icon in the field's accent color |
| `stopping` / finalizing | Compact progress indicator |

The indicator reserves only the space it needs while present and must not cover text, selection handles, validation UI, or an existing field action. It carries a semantic label such as “正在连接语音”, “正在聆听”, or “正在完成转录”; visible status text is intentionally omitted to preserve room for long content.

Animation respects the platform reduced-motion setting. With reduced motion enabled, the listening state uses a static waveform or microphone-level icon.

### 4.2 Ordinary-field controls

An ordinary field remains tap-to-start and tap-to-stop:

1. At idle, the microphone action starts voice input.
2. While connecting, listening, or finalizing, the in-field status icon communicates the current state.
3. Once stopping is allowed, the microphone action becomes a square stop action. Stopping retains and finalizes the transcript.
4. There is no separate visible cancel or delete action beside the field.

The removed visible cancel action does not remove lifecycle cancellation. Starting voice input in another target, leaving the page, app backgrounding, interruption, logout, and failure still cancel through the shared coordinator, discard this recording's provisional text, and restore the exact pre-recording text and selection.

No ordinary-field action clears pre-existing text. A user can edit the finalized transcript normally.

### 4.3 Reka remains distinct

Reka is the only user-facing voice interaction with an explicit cancellation gesture. Long press starts recording, release normally finalizes and sends, and sliding upward before release cancels. The ordinary-field control simplification does not change Reka presentation or submission behavior.

## 5. Session Composer Layout

### 5.1 Bounded text region

The Session text field grows from one line to a maximum of five visible lines. After reaching that bound:

- The composer stops growing.
- Additional content scrolls vertically inside the text field.
- The current caret remains visible while editing or receiving provisional transcript updates.
- Existing leading context action and the in-field voice status indicator remain inside the field without overlapping text.

The height bound must be explicit at the composer boundary rather than relying only on nested intrinsic layout behavior.

### 5.2 Fixed action rail

The microphone/stop action and send action share one fixed action rail aligned to the bottom of the bounded text field. Their touch targets, spacing, and baseline do not change as text grows or scrolls.

Because ordinary fields no longer show a separate cancel action, the Session composer has at most two trailing actions:

- Microphone at idle or stop while actively listening.
- Send when the field contains text and voice input is idle.

Finalizing may temporarily disable both actions while the in-field progress indicator remains visible. Duration warnings and error copy render below the composer body and do not become part of the action rail's alignment calculation.

## 6. Component Architecture

### 6.1 Shared status presentation

The voice-input package owns one reusable status presentation that maps the provider-neutral controller state to icon, animation, color, and semantics. Pages do not inspect provider events or invent their own connecting/listening/finalizing visuals.

The ordinary-field builder contract exposes sufficient presentation state for each concrete input decoration to place the shared indicator inside its actual border. This is preferred over a generic overlay because an overlay cannot safely account for existing prefix icons, suffix actions, multiline padding, validation messages, and editor-specific decoration.

Existing voice-capable call sites are migrated explicitly so the indicator is genuinely inside each field rather than merely adjacent to it.

### 6.2 Shared ordinary controls

The existing reusable voice field continues to own start/stop action semantics, duration warning, and error copy. Its separate cancel button is removed. Internal cancellation remains available on the controller/coordinator for lifecycle and target replacement.

### 6.3 Session-specific composition

Session owns the final horizontal composition of its bounded field and fixed action rail. The voice package supplies the shared status and ordinary voice action; Session supplies its existing add-context and send actions. One alignment system controls all trailing actions.

## 7. Accessibility

- State changes are exposed through concise semantic labels without announcing every provisional transcript update.
- Microphone and stop actions retain distinct tooltips and button labels.
- The status icon is not exposed as a button.
- All controls retain the existing minimum touch target.
- Accent color is not the only status signal; icon shape and semantics also change.
- Reduced-motion settings disable repeating pulse animation.

## 8. Testing Strategy

### 8.1 Shared component tests

- No in-field status icon is rendered at idle.
- Connecting renders the progress presentation and correct semantics.
- Listening renders the waveform/pulse presentation and correct semantics.
- Finalizing renders the progress presentation and correct semantics.
- Reduced motion renders a static listening icon.
- Active ordinary input exposes a stop action and no visible cancel/delete action.
- Lifecycle cancellation still restores the pre-recording text and selection.

### 8.2 Session layout tests

- One-line input keeps the existing compact composer height.
- Five-line input reaches but does not exceed the designed height.
- Much longer input scrolls internally without render overflow.
- Microphone/stop and send controls keep equal fixed touch targets and a stable bottom alignment for short and long text.
- Connecting, listening, finalizing, duration-warning, keyboard-inset, and error states do not move the action rail out of alignment.
- Provisional transcript updates keep the caret visible without growing beyond the bound.

### 8.3 Cross-surface checks

- Session, report creation, Skill creation, Flash, and adopted editors all render the shared in-field status.
- No surface retains the old visible cancel button.
- Reka continues to show and execute slide-up cancellation independently.

## 9. Acceptance Criteria

- A user can identify that an ordinary field is connecting, listening, or finalizing by looking inside that field.
- The indicator never covers authored or provisional text.
- Ordinary fields show no separate cancel/delete button; stopping retains the transcript.
- Lifecycle and target-switch cancellation still restore pre-recording content exactly.
- Session displays at most five text lines and scrolls additional content internally.
- Session voice/stop and send controls remain fixed and aligned for arbitrarily long input.
- All supported voice-input surfaces use the same state mapping and accessible semantics.
- Reka release-to-send and slide-up-to-cancel behavior is unchanged.
