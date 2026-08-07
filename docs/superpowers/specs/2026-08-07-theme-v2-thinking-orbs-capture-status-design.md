# Theme V2 Thinking Orbs Capture Status Design

**Date:** 2026-08-07

**Status:** Design approved; written spec awaiting user review

**Scope:** Theme V2 mobile capture presentation for ring, card, and audio upload

## 1. Context

Theme V2 already has mature capture workflows but presents their progress through
several unrelated mechanisms:

- ring-local phases such as recording, transcription, and Flash submission;
- card realtime and offline-file phases such as sync, transcode, upload, and
  submit;
- server events for ASR, Agent processing, completion, and failure;
- persisted Session messages after the final ASR text exists.

The product needs one calm, recognizable visual language for this work without
creating a second capture workflow or coupling the root navigation to hardware
and Agent internals. The approved direction uses the motion language of
[Jakub Antalik's thinking-orbs](https://github.com/Jakubantalik/thinking-orbs)
inside the persistent Theme V2 top navigation and matching inline states inside
the relevant Flash Session.

The upstream implementation is a React/Canvas package. Theme V2 will not embed
it through a WebView or ship an npm runtime. The mobile implementation will use
Flutter-native vector drawing and animation. If implementation code or
algorithms are ported from the upstream project rather than independently
recreated, its MIT attribution must be retained in the appropriate third-party
notice.

## 2. Goals

1. Show capture progress from the moment hardware begins recording or an audio
   file begins entering the upload workflow.
2. Give ring, realtime card, offline card, and in-app audio upload one stable set
   of user-facing stages.
3. Preserve the existing ownership of recording, upload, ASR, Agent execution,
   persistence, retry, and notification behavior.
4. Support multiple queued captures without turning the top navigation into a
   task dashboard.
5. Keep an already-open matching Flash Session live without inserting fake text
   or empty persisted turns.
6. Recover truthfully after duplicate events, event reordering, SSE reconnect,
   backgrounding, and app restart.

## 3. Non-goals and Deferred Work

This slice does not:

- add thinking-orbs to the Home gravity chamber or Asset bubbles;
- redesign capture, ASR, Agent, Session, notification, or retry architecture;
- create a Session turn before final ASR text exists;
- expose technical stages such as S3 upload, codec conversion, provider polling,
  or individual Agent tool calls to the user;
- add a cancel action to the takeover bar; capture stop and cancellation remain
  owned by the originating hardware or upload surface;
- import the upstream React package or add a WebView;
- add a dedicated reduced-motion implementation in the first slice;
- add new thinking-orbs accessibility labels or semantics in the first slice.

The last two items are explicitly deferred. Existing navigation semantics must
not be removed outside the period in which the navigation is visually replaced,
but first-slice acceptance does not include new reduced-motion or accessibility
coverage for the takeover itself.

## 4. Approved Product Decisions

### 4.1 Placement

The thinking-orb does not enter the Home gravity chamber. It replaces the full
56 px Theme V2 global top-navigation row while a capture task is active.

The takeover:

- keeps the row height unchanged so page content never jumps;
- replaces the wordmark, device entry, theme toggle, and notification entry;
- appears on root Theme V2 surfaces that already mount the global top nav;
- does not inject a new global bar into Session, detail, editor, or other routes
  that intentionally hide the root top nav.

### 4.2 Trigger boundary

The takeover begins at the earliest real event available:

- ring or card hardware begins listening;
- an offline card file enters the local sync queue; or
- an in-app audio upload enters its receiving/upload task.

It continues through transcription and Agent work until the task reaches a
terminal result. It does not wait for the backend to know about the recording.

### 4.3 User-facing stages

The UI exposes five product stages. A flow may skip a stage that does not apply,
but it may not invent one or advance on a timer.

| Product stage | Copy | Orb motion | Typical real sources |
| --- | --- | --- | --- |
| `listening` | 正在聆听 | `listening` | ring/card recording start; live hardware listening |
| `receiving` | 正在接收 | `connecting` | card sync, transcode, upload, submit; app audio upload |
| `transcribing` | 正在转写 | `weaving` | ring-local ASR, client-sync ASR, server `asr_processing` |
| `understanding` | 正在理解 | `searching` | final ASR accepted; Agent dispatch/execution starts |
| `organizing` | 正在整理 | `composing` | Agent result presentation and persistence begins |

The backend recording status enum does not need a new database state for visual
progress. Existing `agent_processing` remains durable. The current outbox/SSE
payload adds a typed `display_phase` field so the capture job can publish
`understanding` when execution begins and `organizing` after execution returns
and result presentation begins. Reconnect fallback maps durable
`agent_processing` to `understanding` until a newer typed display phase arrives.

### 4.4 Top-bar contents and interaction

The takeover contains:

- a purpose-tuned orb at the left;
- a small source label such as `UREKA 戒指`, `UREKA 录音卡`, or `音频上传`;
- the current product-stage copy;
- `另有 N 条` when additional tasks are queued.

Before a real Session turn exists, the bar is display-only. After final ASR has
materialized a real input turn and `session_id`, the full bar becomes tappable
and opens that Flash Session. No empty Session or placeholder persisted turn is
created for navigation.

### 4.5 Terminal behavior

- **Success:** show `已整理` and the produced Asset count, when available, for
  approximately 1.5 seconds. Restore normal navigation unless another task is
  queued.
- **Failure:** show `这条闪念暂未整理完成` for approximately 3 seconds and allow
  `查看` when a real Session exists. Then restore normal navigation. Retry stays
  on the corresponding Session turn.
- **Empty capture:** show `没有识别到内容` for approximately 2 seconds, create no
  Session turn, and restore navigation.
- **Next queued task:** transition directly to the next task without briefly
  restoring the normal navigation between tasks.

Terminal dwell timers control only how long a known result remains visible.
They never decide whether work succeeded or failed.

## 5. Architecture

### 5.1 Capture Activity Coordinator

Theme V2 adds one app-level, typed presentation coordinator at the App Shell
boundary. It is a projection of existing workflow state, not a workflow engine.

Its inputs are:

1. typed local ring capture events;
2. typed card realtime/offline task events and recoverable task snapshots;
3. typed in-app audio-upload events;
4. capture and Session SSE events from Theme V2;
5. recovery snapshots from persisted local tasks and the recording list/status
   APIs.

Its outputs are immutable view models for:

- the active global takeover;
- the number of queued tasks;
- a matching Session's transient user-side capture state;
- a route target after a real Session turn exists;
- short terminal presentation.

The coordinator must not call BLE commands, upload files, poll ASR, execute
Agent tools, mutate Assets, retry captures, or mark jobs complete.

### 5.2 Typed task identity

Each activity is represented by one logical task with fields equivalent to:

- local task key;
- `client_task_id`;
- optional backend `recording_id`;
- optional `session_id` and `input_turn_id`;
- source: ring, realtime card, offline card, or audio upload;
- capture time and last trusted update time;
- product phase;
- running, success, empty, or failed terminal state;
- result summary and produced-record count when known.

The terminal `done` event adds an optional typed `result_count`; when it is not
available, the success copy remains `已整理` rather than inventing a number.

The local key or `client_task_id` owns the task before backend acceptance. The
same task gains `recording_id` when the server accepts it. These identifiers are
merged; acceptance must not create a second visual activity.

SSE payloads continue to include `client_task_id` and `recording_id`. Local
workflow adapters must emit typed phase events rather than requiring the
coordinator to parse strings such as `正在上传` or `Reka听到`.

### 5.3 Monotonic reduction

Within one non-terminal attempt, phase ordering is monotonic:

`listening -> receiving -> transcribing -> understanding -> organizing`

A valid source may skip stages. Duplicate and late events are idempotent and
cannot move a task backward. A terminal server event always wins over an
in-flight local event for the same task.

A user-initiated retry is a new attempt of the same recording. It may return to
the appropriate real stage, but it must not create another Session input turn or
increment the hardware Flash count.

### 5.4 Multi-task selection

Only one task is rendered in the top bar.

1. An active realtime capture has priority over offline/upload work.
2. A realtime task may preempt the currently displayed offline task; the
   offline task stays queued and resumes presentation afterward.
3. Otherwise, the current active selection remains stable until terminal so
   concurrent pipeline updates do not make the bar flicker between tasks.
4. Remaining tasks are ordered by original capture time, not discovery or
   processing time.
5. The bar shows `另有 N 条` instead of rendering multiple small orbs.

## 6. Session Presentation

The top bar and Session share the coordinator and stage vocabulary, but do not
share the same layout.

### 6.1 Before final ASR

If a daily Flash Session for the task's capture date is already open, it may
show one transient user-side status on the right for `listening`, `receiving`,
or `transcribing`.

This transient state:

- is not a persisted message;
- contains no guessed transcript;
- is shown only when the open Session matches the task's daily Flash Session;
- disappears on empty/failure before materialization;
- is replaced, not duplicated, when final ASR creates the real user message.

If no matching Session is open, the top bar is the only pre-ASR presentation.
The app does not create or navigate to an empty Session.

### 6.2 After final ASR

When final ASR materializes the capture:

1. the real user text appears immediately;
2. the same persisted Agent message enters `running`;
3. its inline orb shows `正在理解`, followed by `正在整理` when that real phase
   arrives;
4. the same Agent message updates in place to reply text, cards,
   `waiting_confirmation`, or a turn-local failure.

Leaving and returning reloads persisted user and Agent messages. It must not
duplicate the transient state, user text, Agent placeholder, Asset cards, or
turn count.

### 6.3 Failure ownership

The top bar only provides a short global acknowledgement. The durable failure
belongs to the matching Agent message in the Session. There is no session-wide
bottom error banner and no technical provider exception in product copy.

## 7. Recovery and Lifecycle

### 7.1 SSE reconnect and event disorder

- On SSE loss, retain the last trusted phase; do not infer success or failure.
- On reconnect, reconcile known recording IDs with backend state and apply only
  equal-or-newer phases or terminal results.
- Duplicate SSE frames and duplicate local callbacks are idempotent.
- A terminal backend result removes the activity after its approved dwell even
  if a late local upload event arrives.

### 7.2 App restart

On startup, the coordinator rebuilds from:

- persisted card/upload tasks;
- known backend recording IDs attached to those tasks; and
- recent non-terminal recordings returned by the existing recording list/status
  APIs.

An interrupted live hardware recording that never became a durable task is not
resurrected. Once accepted by the backend, its durable recording can be
recovered. Terminal recordings are not re-presented as new work after restart.

### 7.3 Backgrounding

Animation painting may pause while the app is not visible, but capture and
backend workflows continue under their existing lifecycle rules. Returning to
the foreground renders the coordinator's latest trusted state rather than
replaying missed animation steps.

## 8. Visual Component Boundary

The Flutter renderer exposes one visual state enum and purpose-tuned visual
sizes rather than scaling one large animation indiscriminately:

- a top-navigation orb sized for the 56 px takeover row;
- a smaller inline Session orb designed for chat-row legibility.

Both use Theme V2 foreground/accent tokens in Light and Dark modes. The renderer
does not own strings, task selection, terminal timers, routing, or workflow
state. Those remain in the presentation coordinator and containing widgets.

Reduced-motion behavior and new accessibility semantics are deferred from this
first implementation slice.

## 9. Verification Strategy

### 9.1 Unit tests

Cover:

- local-key to `client_task_id` to `recording_id` identity merging;
- phase skips, duplicate events, late events, and monotonic reduction;
- terminal precedence;
- realtime preemption and stable offline selection;
- queue count and capture-time ordering;
- retry attempt behavior without duplicate turns;
- restart/reconnect reconciliation.

### 9.2 Widget tests

Cover:

- normal top nav to full takeover without a height change;
- Light and Dark rendering;
- source label, phase copy, queue count, and terminal copy;
- bar disabled before `session_id` and tappable afterward;
- success, failure, empty, and direct-next-task transitions;
- matching Session's transient user-side state;
- final ASR replacing the transient state with one real user message;
- Agent `running` state updating in place to answer/cards/failure;
- top nav hidden routes remaining structurally unchanged.

Reduced-motion and new accessibility semantics are not acceptance gates for the
first slice.

### 9.3 Integration and real-device acceptance

Verify four end-to-end paths:

1. ring live recording;
2. card live recording;
3. card reconnect with one and multiple offline files;
4. in-app audio-file upload.

For each applicable path, verify real phase movement, final transcript, one
Session turn, Agent completion or turn-local failure, produced Assets,
notification behavior, top-bar restoration, and leaving/returning to the
Session. Also verify SSE reconnect and app restart during a durable pending
task.

## 10. Acceptance Summary

The slice is complete when:

- capture work takes over the existing root top nav from the earliest real
  local event;
- one typed coordinator merges local and server truth without moving workflow
  ownership;
- one current task and `另有 N 条` accurately represent concurrent work;
- the five approved stages are driven only by real events;
- the takeover opens a Session only after a real turn exists;
- an open matching Session transitions from transient capture state to final
  user text and one persisted Agent message without refresh or duplication;
- terminal and recovery behavior cannot leave the global navigation stuck;
- all four capture paths pass focused automated tests and proportional
  real-device acceptance;
- reduced-motion and new accessibility work remain recorded as deferred rather
  than being reported complete.
