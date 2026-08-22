# Shared Voice Input Lifecycle Design

- **Date:** 2026-08-20
- **Status:** Approved
- **Branch:** `codex/skill-dither-report-revamp`
- **Scope:** App-wide voice-input ownership and provider-neutral streaming ASR lifecycle

## 1. Context

The first cloud voice-input implementation successfully connected Session, report, Skill, ordinary text fields, and the Reka shortcut to one streaming ASR service. Physical-device testing then exposed a lifecycle defect: an upstream provider could remain in startup long after the mobile ready deadline. The abandoned server task kept the current user's active-session slot, later attempts were rejected, and the eventual provider-ready event was sent to a disconnected client.

This is not a Session-specific defect and must not be fixed with a page-level workaround. Every voice-capable surface needs the same ownership, cancellation, target switching, isolation, and cleanup guarantees.

This design refines and supersedes the ownership and lifecycle portions of `2026-08-20-mobile-cloud-voice-input-design.md`. Its product behavior, provider choice, privacy constraints, language scope, ordinary-field behavior, and Reka behavior remain unchanged.

## 2. Goals

- Let a user start voice input from any supported App surface without restarting the App or waiting for a stale session.
- Make switching between voice targets a normal action rather than a user-visible microphone conflict.
- Cancel voice input automatically when its owning page or field leaves the active UI.
- Guarantee that every terminal path releases microphone, client socket, provider task, and server-side user ownership.
- Isolate all active-session state by `user_id`; one user's provider delay or failure cannot affect another user.
- Preserve the ordinary-field and Reka product behaviors already approved.
- Keep provider-specific lifecycle details behind the Eureka gateway.

## 3. Non-goals

- Retaining audio for retry, reconnecting automatically, or adding a retry button.
- Supporting simultaneous microphone streams inside one App process.
- Changing the existing hardware ASR paths.
- Moving Alibaba credentials or provider protocol into the App.
- Changing language support, text editing, or Reka submission semantics.
- Designing account login policy or multi-device account management.

## 4. Product Rules

### 4.1 One active target, latest explicit target wins

The App owns one microphone stream at a time. If the user starts voice input in another supported field, the new explicit action supersedes the old target:

1. Invalidate the old target generation.
2. Restore the old target's exact pre-recording text and selection.
3. Cancel and await bounded cleanup of the old voice session.
4. Capture the new target's text snapshot and begin the new session.

This transition is not presented as an error. Rapid actions are serialized and only the latest requested target may receive events.

### 4.2 Navigation and lifecycle

If the active field or page leaves the active UI, its target binding is disposed. Disposal invalidates its generation, discards provisional text, cancels the session, and releases the microphone. Recording never continues in the background and never writes back into a page that is no longer active.

App backgrounding, calls, audio-session interruption, logout, and authentication expiry use the same cancellation path.

### 4.3 Failure behavior

On network loss, provider unavailability, timeout, or malformed protocol:

- End the current session and release all resources.
- Restore the ordinary field's original text and selection.
- Discard provisional and unconfirmed transcript text.
- Show a concise error at the active target.
- Leave typed input available immediately.
- Do not retry or reconnect automatically.

### 4.4 Existing completion behavior

- Ordinary inputs remain tap-to-start and tap-to-stop. A final transcript stays editable in the field and never auto-submits.
- Reka remains long-press to speak, release to submit, and slide upward to cancel. A valid final transcript is submitted once through the existing text Flash flow.
- Ordinary input remains limited to five minutes. Reka remains limited to one minute.

## 5. Mobile Architecture

### 5.1 App-owned coordinator

The App root owns one `VoiceInputCoordinator`. It replaces independent page ownership of service and microphone lifecycle. The coordinator owns:

- The microphone capture resource.
- The gateway connection and provider-neutral session handle.
- The active target binding.
- A monotonically increasing generation.
- Serialized start, switch, stop, cancel, and lifecycle operations.
- The authoritative state: `idle`, `connecting`, `listening`, or `finalizing`.

Pages do not construct a shared singleton service directly. They obtain the coordinator from the App-level scope and create lightweight target bindings.

### 5.2 Target binding

A voice-capable surface binds a target with:

- A stable target identity for that widget lifetime.
- `ordinary` or `reka` mode.
- Snapshot and restoration behavior.
- Provisional, stable, final, cancel, and error callbacks.
- A disposal signal tied to the route/widget lifecycle.

The binding never owns the microphone or WebSocket. It only translates coordinator state into its local presentation.

Ordinary text fields share one adapter that captures text and selection, renders provisional ranges, commits final text, and restores the snapshot. Reka uses a separate presentation adapter over the same coordinator session.

### 5.3 Generation and late-event safety

Every start or target switch creates a new generation. Provider and socket callbacks carry both `voiceSessionId` and the local generation. A callback may mutate UI only when both still match the active binding.

Invalidating a binding is synchronous. Cleanup may finish asynchronously, but late partial, stable, final, failure, and completion events are ignored immediately.

### 5.4 Serialized switching

Start and switch requests enter one serialized coordinator operation queue. A newer target request supersedes any queued older request. Cleanup of the previous session is bounded; after its local generation is invalidated, a cleanup delay cannot mutate either target.

There is no user-visible `busy` state for switching between App inputs. Internal mutual exclusion exists only to preserve ordering and single-microphone ownership.

## 6. Backend Architecture

### 6.1 Explicit connection state machine

Each accepted WebSocket creates one `StreamingAsrSession` with explicit phases:

```text
accepted
  -> validating
  -> provider_starting
  -> ready
  -> streaming
  -> finalizing
  -> completed | cancelled | failed
  -> closed
```

The session owns its provider, provider tasks, client receive task, duration timer, byte counter, and cleanup guard. No provider task outlives its session.

### 6.2 Bounded operations

The following operations have separate server-owned, configurable deadlines:

- Provider connection and readiness.
- Normal finalization, including `finish` and the final provider event.
- Provider cancellation and socket close.

The mobile ready deadline must be longer than the server provider-start deadline plus a fixed transport margin. Configuration validation rejects an invalid relationship.

Provider startup races three signals: provider ready, client disconnect/cancel, and the provider-start deadline. The first terminal signal wins; every losing task is cancelled and drained.

### 6.3 Per-user session ownership

The registry is partitioned by `user_id`; there is no global active-session lock. A stalled user A session cannot block user B from acquiring or running a provider stream.

Within one user, the latest valid start supersedes a stale existing session. Registration atomically installs the new session and requests bounded cancellation of the previous session. This mirrors the mobile latest-target-wins rule and prevents an abandoned client connection from turning into a user-visible microphone conflict.

Rate limiting remains per user and is distinct from active-session replacement. A genuine rate-limit response is never used to represent an internal lifecycle conflict.

### 6.4 Authoritative cleanup

All exits run one idempotent cleanup routine in this order:

1. Mark the session terminal so no more events can be emitted.
2. Cancel and drain client, provider, timer, and forwarding tasks.
3. Stop or cancel the provider within its cleanup deadline.
4. Close the client socket when still writable.
5. Release the exact per-user registry lease in an unconditional outer `finally`.

Cleanup errors are recorded as content-free metrics but never prevent registry release. Provider adapters must close partially initialized sockets when startup is cancelled, including cancellation exceptions outside the normal `Exception` hierarchy.

### 6.5 Existing protocol and limits

The authenticated `/api/asr/stream` contract remains provider-neutral. Existing `ready`, `partial`, `stable`, `final`, and `error` events remain compatible.

The gateway also enforces the authoritative cumulative PCM byte limit for the selected mode before forwarding a frame. This makes the one-minute and five-minute limits independent of client pacing.

## 7. Error Model

User-visible categories remain limited to actionable conditions:

- Microphone permission is unavailable.
- Network or gateway connection failed.
- The ASR service is temporarily unavailable.
- An active connection was interrupted.
- No clear speech was recognized.
- The server rate limit was reached.
- The audio contract is unsupported.
- Authentication is no longer valid.

Internal target switching, stale generations, previous-session cancellation, task races, and registry replacement are not user-visible errors.

No failure path auto-submits provisional text or creates a business entity.

## 8. Privacy and Observability

The existing privacy contract remains unchanged: audio is streamed in memory and is not retained by Eureka-controlled systems. ASR infrastructure logs and metrics never contain audio or transcript bodies.

Content-free metrics cover:

- Provider-start, first-partial, stop-to-final, and cleanup latency.
- Terminal phase and normalized reason code.
- Active sessions partitioned by provider and outcome, not transcript content.
- Session supersession, client disconnect, deadline expiry, and cleanup timeout.

Metrics must make it possible to distinguish provider readiness delay from client networking, recorder failure, and finalization delay.

## 9. Testing Strategy

### 9.1 Mobile state-machine tests

- Session to report, report to Skill, and Skill to Session target switching.
- Ordinary input to Reka and Reka to ordinary input switching.
- Latest rapid target request wins without a visible busy error.
- Route disposal during connecting, listening, and finalizing.
- Exact text and selection restoration on switch, cancel, failure, and lifecycle interruption.
- Late partial and final events from invalidated generations are ignored.
- Failed start returns the coordinator to reusable idle state.
- Ordinary final text remains editable; Reka final text submits exactly once.

### 9.2 Gateway state-machine tests

- Provider startup never returns: deadline cancels the provider and releases the registry lease.
- Client disconnects during provider startup: provider startup is cancelled immediately.
- Client disconnects, provider error, duration expiry, and send failure during streaming.
- Provider finish or final event hangs: the entire finalization operation is bounded.
- Cleanup itself fails or hangs: the user lease is still released.
- A second session for the same user supersedes the stale session.
- A stalled session for user A does not delay user B.
- Cumulative bytes cannot exceed the server-authoritative duration limit.
- Every terminal path emits at most one terminal event and closes provider resources once.

### 9.3 Cross-surface integration tests

- Session, report creation, Skill creation, ordinary editing, and Reka all bind to the same App coordinator.
- Repeated Session -> Reka -> Session use works without restarting the App.
- Leaving each surface during startup frees the next surface immediately.
- No transition creates an empty Session turn, report, Skill, note, or Flash.

### 9.4 Physical-device acceptance

On representative Android and iOS devices:

1. Start and stop ordinary dictation in Session.
2. Switch directly to report and Skill voice inputs.
3. Start Reka, cancel by sliding upward, then immediately start Session dictation.
4. Interrupt startup by navigating away and verify the next target starts normally.
5. Exercise provider delay and weak-network conditions without restarting the App.
6. Confirm a separate test user remains unaffected while another user's provider start is stalled.

## 10. Migration and Delivery

1. Introduce the backend session state machine and preserve the current wire protocol.
2. Add bounded provider lifecycle, disconnect races, per-user replacement, cumulative byte enforcement, and content-free metrics.
3. Introduce the App-level coordinator and target-binding API.
4. Migrate Session, report, Skill, ordinary editors, and Reka from direct service/controller ownership.
5. Remove static shared-service access and page-owned microphone lifecycle after all targets migrate.
6. Run deterministic state-machine, cross-surface, package, and physical-device gates.
7. Roll out behind the existing cloud voice-input feature boundary and monitor lifecycle metrics.

The backend change is deployed before the coordinator build so existing clients receive bounded startup and cleanup behavior during migration.

## 11. Acceptance Criteria

- Voice input can start from every adopted surface without an App restart.
- Starting a new target automatically cancels and restores the old target without a busy error.
- Leaving the active page cancels recording and prevents all late UI mutation.
- Every provider operation and cleanup phase is bounded.
- Every terminal path releases microphone, socket, provider, tasks, and the exact user lease.
- A delayed or failed session for one user has no effect on another user.
- Session, report, Skill, ordinary fields, and Reka share one coordinator and one normalized gateway contract.
- Ordinary fields and Reka preserve their approved completion behaviors.
- No automatic audio retry, audio retention, transcript infrastructure logging, or provider credential exposure is introduced.
- Physical-device Session -> Reka -> Session and cross-authoring-surface acceptance passes under normal and degraded provider conditions.
