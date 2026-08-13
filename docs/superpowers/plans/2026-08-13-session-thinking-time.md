# Session Thinking Time Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a live thinking timer and authoritative completed thinking duration to Theme V2 chat and Flash Session turns without counting Flash upload or ASR time.

**Architecture:** `ChatMessage.processingStartedAt` carries client-only live timing state while the existing `elapsedMs` carries the server-authoritative final duration. A focused Theme V2 timer component refreshes once per second without notifying the full transcript. Ordinary chat starts locally when its assistant placeholder is created; hardware Flash starts from the capture activity phase transition into agent processing. The server accumulates only active capture-agent execution time across workflow retries and persists it on the materialized Flash agent message.

**Tech Stack:** Flutter/Dart (`Timer`, widget tests), Python 3.12, FastAPI SSE, SQLAlchemy async sessions, pytest, MySQL-backed integration tests.

## Global Constraints

- Ordinary chat and Flash both show a live timer and a completed final duration.
- Flash timing starts only at `agent_processing`; recording, upload, retry queue delay, and ASR are excluded.
- The running format is `mm:ss` below one hour and `h:mm:ss` at or above one hour.
- The completed format is natural Chinese, including `思考不足 1 秒` for 0–999 ms.
- Running UI uses the approved layout A: timer on the right of the processing card; completed metadata sits below the assistant response.
- The final value is server-authoritative `elapsed_ms`; client time is only a live estimate.
- Theme V2 does not show token counts in this metadata row.
- The timer must not become a once-per-second accessibility live announcement.
- No new per-second server event, model name, internal reasoning, or report timing is added.

---

## File Structure

- Create `mobile/lib/theme_v2/session/session_thinking_time.dart`: duration formatting, the isolated live timer widget, and the completed metadata widget.
- Create `mobile/test/theme_v2/session/session_thinking_time_test.dart`: pure formatting and focused widget timer/footer tests.
- Modify `mobile/lib/chat/chat_models.dart`: add the client-only `processingStartedAt` message state.
- Modify `mobile/lib/chat/chat_controller.dart`: inject a clock, start ordinary-chat timing, restore running messages safely, and consume failed-turn elapsed SSE data.
- Modify `mobile/test/theme_v2/session/chat_controller_retry_test.dart`: prove ordinary-chat start, completion calibration, history restore, and retry reset.
- Modify `mobile/lib/theme_v2/capture/capture_activity_models.dart`: expose `phaseStartedAt` independently from task creation time.
- Modify `mobile/lib/theme_v2/capture/capture_activity_coordinator.dart`: advance `phaseStartedAt` only when the phase advances.
- Modify `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart`: prove phase timing is not inherited from listening/transcribing.
- Modify `mobile/lib/theme_v2/capture/capture_session_controller.dart`: inject a clock, start typed-chat timers immediately, start hardware Flash timers only in understanding/organizing, and restore final elapsed values.
- Modify `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`: prove Flash timing excludes earlier phases and uses the agent phase start.
- Modify `mobile/test/theme_v2/capture/capture_session_unified_chat_test.dart`: prove typed follow-ups and historical Flash messages carry the correct timing state.
- Modify `mobile/lib/theme_v2/session/session_analysis_block.dart`: render the live timer and elapsed-aware failure copy.
- Modify `mobile/lib/theme_v2/session/session_transcript.dart`: pass live timing to analysis blocks, suppress the legacy cost footer, and render Theme V2 final thinking metadata.
- Modify `mobile/lib/pages/chat_page.dart`: add a `showCostFooter` seam so legacy chat retains its existing footer while Theme V2 owns its final metadata.
- Modify `mobile/test/theme_v2/session/session_state_test.dart`: verify running, completed, failed, and accessibility presentation.
- Modify `theme_v2_service/app/domains/capture/jobs.py`: accumulate active provider duration across retries and persist it to the Flash agent message.
- Modify `theme_v2_service/tests/integration/test_capture_jobs.py`: verify success, permanent failure, exhausted retry, and queue exclusion.
- Modify `theme_v2_service/app/domains/sessions/api_chat.py`: include authoritative `elapsed_ms` in failed chat SSE frames.
- Modify `theme_v2_service/tests/contract/test_chat_api.py`: lock the failed SSE timing contract.

---

### Task 1: Persist Authoritative Server Durations

**Files:**
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Modify: `theme_v2_service/app/domains/sessions/api_chat.py`
- Modify: `theme_v2_service/tests/contract/test_chat_api.py`

**Interfaces:**
- Consumes: `WorkflowJob.checkpoint_json`, `SessionMessage.elapsed_ms`, and `CompletedChatTurn.elapsed_ms`.
- Produces: Flash agent messages with `elapsed_ms: int`; failed chat SSE frames shaped as `{"message": str, "elapsed_ms": int}`.

- [ ] **Step 1: Write failing capture-job duration tests**

Extend the process registry test helper so a deterministic monotonic clock can be injected:

```python
def _process_registry(
    provider: FakeCaptureAgentProvider,
    *,
    tool_runtime=None,
    monotonic_clock=None,
) -> JobHandlerRegistry:
    registry = JobHandlerRegistry()
    options = {"clock": lambda: NOW, "tool_runtime": tool_runtime}
    if monotonic_clock is not None:
        options["monotonic_clock"] = monotonic_clock
    registry.register(
        "capture_process",
        capture_process_handler(provider, **options),
    )
    return registry
```

Add a tiny sequence clock and a success assertion to `test_capture_job_creates_multiple_records_and_notification`:

```python
def _monotonic_sequence(*values: float):
    iterator = iter(values)
    return lambda: next(iterator)

# Registry receives 100.0 then 101.25.
registry = _process_registry(
    provider,
    monotonic_clock=_monotonic_sequence(100.0, 101.25),
)
# After the worker completes:
agent_message = await database_session.get(
    SessionMessage,
    recording.agent_message_id,
)
assert agent_message.elapsed_ms == 1250
```

In `test_permanent_capture_provider_error_fails_without_retry`, inject `_monotonic_sequence(20.0, 20.25)`, load the agent message, and assert `agent_message.elapsed_ms == 250`.

In `test_exhausted_agent_retry_updates_persisted_agent_message`, inject `_monotonic_sequence(30.0, 30.5)`, then add:

```python
assert agent_message.elapsed_ms == 500
```

Add this two-attempt test. It advances the workflow's wall clock to `retry_at`, but the expected final value is only the sum of active provider attempts:

```python
async def test_capture_agent_elapsed_accumulates_compute_not_retry_queue(session):
    provider = FakeCaptureAgentProvider(
        RetryableCaptureAgentError("temporary provider issue")
    )
    recording_id, job_id = await _seed_transcribed_capture()
    registry = _process_registry(
        provider,
        monotonic_clock=_monotonic_sequence(10.0, 10.4, 20.0, 20.6),
    )

    await run_worker_once(
        registry,
        owner="worker-a",
        lease_seconds=60,
        now=NOW,
    )
    async with AsyncSessionFactory() as database_session:
        job = await database_session.get(WorkflowJob, job_id)
        retry_at = job.available_at
        assert job.checkpoint_json["agent_elapsed_ms"] == 400

    provider.result = _event_and_expense_result()
    await run_worker_once(
        registry,
        owner="worker-b",
        lease_seconds=60,
        now=retry_at,
    )

    async with AsyncSessionFactory() as database_session:
        recording = await database_session.get(CaptureRecording, recording_id)
        agent_message = await database_session.get(
            SessionMessage,
            recording.agent_message_id,
        )
    assert agent_message.elapsed_ms == 1000
```

- [ ] **Step 2: Run the capture integration tests and verify RED**

Run from the repository root with the existing Theme V2 test database available:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  pytest tests/integration/test_capture_jobs.py -q
```

Expected: FAIL because `capture_process_handler` does not accept `monotonic_clock` and Flash agent messages have no `elapsed_ms`.

- [ ] **Step 3: Implement active-time accumulation and persistence**

In `jobs.py`, import `monotonic` and add a checkpoint helper that updates only the leased workflow job:

```python
from time import monotonic


async def _checkpoint_agent_elapsed(
    *,
    job_id: str,
    owner: str,
    elapsed_ms: int,
) -> int:
    async with session_scope() as session:
        job = await session.scalar(
            select(WorkflowJob)
            .where(
                WorkflowJob.id == job_id,
                WorkflowJob.status == "running",
                WorkflowJob.lease_owner == owner,
            )
            .with_for_update()
        )
        if job is None:
            raise RuntimeError("capture process lease lost while timing")
        checkpoint = dict(job.checkpoint_json or {})
        total = max(0, int(checkpoint.get("agent_elapsed_ms") or 0)) + max(
            0, elapsed_ms
        )
        checkpoint["agent_elapsed_ms"] = total
        job.checkpoint_json = checkpoint
        return total
```

Add `elapsed_ms: int` to `_persist_flash_execution` and `_fail_agent_capture`, then assign `agent_message.elapsed_ms = max(0, elapsed_ms)` beside their terminal status updates.

Extend `capture_process_handler`:

```python
def capture_process_handler(
    provider: FlashExecutionProvider,
    *,
    clock: Callable[[], datetime] = utc_now,
    monotonic_clock: Callable[[], float] = monotonic,
    timezone_name: str = "Asia/Shanghai",
    tool_runtime=None,
):
```

Immediately before `provider.execute`, capture `attempt_started = monotonic_clock()`. On every provider success or provider exception, calculate:

```python
attempt_elapsed_ms = max(
    0,
    int((monotonic_clock() - attempt_started) * 1000),
)
total_elapsed_ms = await _checkpoint_agent_elapsed(
    job_id=job.id,
    owner=job.lease_owner,
    elapsed_ms=attempt_elapsed_ms,
)
```

Pass `total_elapsed_ms` into the success/permanent/exhausted terminal persistence functions. For a retryable non-terminal exception, checkpoint the attempt before re-raising. This accumulates provider execution but excludes the job's queued backoff.

- [ ] **Step 4: Re-run capture tests and verify GREEN**

Run the same Docker pytest command. Expected: all `test_capture_jobs.py` tests PASS.

- [ ] **Step 5: Write the failed chat SSE contract test**

In `test_chat_persists_unexpected_provider_failure_as_terminal`, add:

```python
assert isinstance(frames[-1][1]["elapsed_ms"], int)
assert frames[-1][1]["elapsed_ms"] >= 0
assert message.elapsed_ms == frames[-1][1]["elapsed_ms"]
```

- [ ] **Step 6: Run the chat contract test and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  pytest tests/contract/test_chat_api.py::test_chat_persists_unexpected_provider_failure_as_terminal -q
```

Expected: FAIL with missing `elapsed_ms` in the error frame.

- [ ] **Step 7: Add elapsed time to the failed SSE frame**

Change the failure branch in `api_chat.py` to:

```python
elif completed.public_error is not None:
    yield _frame(
        "error",
        {
            "message": completed.public_error,
            "elapsed_ms": completed.elapsed_ms,
        },
    )
```

- [ ] **Step 8: Run both server suites and commit**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  pytest tests/integration/test_capture_jobs.py tests/contract/test_chat_api.py -q
git add theme_v2_service/app/domains/capture/jobs.py \
  theme_v2_service/tests/integration/test_capture_jobs.py \
  theme_v2_service/app/domains/sessions/api_chat.py \
  theme_v2_service/tests/contract/test_chat_api.py
git commit -m "feat: persist session thinking durations"
```

Expected: both suites PASS; commit contains only these four files.

---

### Task 2: Add Mobile Timing State and Formatting

**Files:**
- Create: `mobile/lib/theme_v2/session/session_thinking_time.dart`
- Create: `mobile/test/theme_v2/session/session_thinking_time_test.dart`
- Modify: `mobile/lib/chat/chat_models.dart`
- Modify: `mobile/lib/chat/chat_controller.dart`
- Modify: `mobile/test/theme_v2/session/chat_controller_retry_test.dart`

**Interfaces:**
- Consumes: server `elapsed_ms` from live and historical chat messages.
- Produces: `ChatMessage.processingStartedAt: DateTime?`, `formatThinkingTimer(Duration) -> String`, and `formatThinkingSummary(int, {String verb}) -> String`.

- [ ] **Step 1: Write failing formatter and message-state tests**

Create `session_thinking_time_test.dart` with boundary expectations:

```dart
test('formats running thinking time at second minute and hour boundaries', () {
  expect(formatThinkingTimer(Duration.zero), '00:00');
  expect(formatThinkingTimer(const Duration(seconds: 8)), '00:08');
  expect(formatThinkingTimer(const Duration(seconds: 59)), '00:59');
  expect(formatThinkingTimer(const Duration(seconds: 60)), '01:00');
  expect(formatThinkingTimer(const Duration(seconds: 68)), '01:08');
  expect(formatThinkingTimer(const Duration(seconds: 3599)), '59:59');
  expect(formatThinkingTimer(const Duration(seconds: 3600)), '1:00:00');
});

test('formats final thinking time in natural Chinese', () {
  expect(formatThinkingSummary(0), '思考不足 1 秒');
  expect(formatThinkingSummary(999), '思考不足 1 秒');
  expect(formatThinkingSummary(8000), '思考 8 秒');
  expect(formatThinkingSummary(68000), '思考 1 分 8 秒');
  expect(formatThinkingSummary(3728000), '思考 1 小时 2 分 8 秒');
  expect(formatThinkingSummary(-50), '思考不足 1 秒');
});
```

In `chat_controller_retry_test.dart`, inject a fixed clock and assert a freshly created ordinary-chat agent has that start time; after a `done` frame assert the same agent has the server `elapsedMs`. Add a failed SSE test asserting `elapsed_ms` is consumed. Add a retry test asserting the second agent gets a new start time and does not inherit the first agent's `elapsedMs`.

- [ ] **Step 2: Run focused Flutter tests and verify RED**

```bash
cd mobile
flutter test \
  test/theme_v2/session/session_thinking_time_test.dart \
  test/theme_v2/session/chat_controller_retry_test.dart
```

Expected: FAIL because formatters, `processingStartedAt`, and controller clock injection do not exist.

- [ ] **Step 3: Implement formatting and model state**

Create `session_thinking_time.dart` with pure functions:

```dart
String formatThinkingTimer(Duration elapsed) {
  final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = remainder.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String formatThinkingSummary(int elapsedMs, {String verb = '思考'}) {
  final milliseconds = elapsedMs < 0 ? 0 : elapsedMs;
  if (milliseconds < 1000) return '$verb不足 1 秒';
  final seconds = milliseconds ~/ 1000;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  final parts = <String>[
    if (hours > 0) '$hours 小时',
    if (minutes > 0) '$minutes 分',
    if (remainder > 0 || (hours == 0 && minutes == 0)) '$remainder 秒',
  ];
  return '$verb ${parts.join(' ')}';
}
```

Add `DateTime? processingStartedAt;` to `ChatMessage`.

- [ ] **Step 4: Start and settle ordinary-chat timing**

Add `DateTime Function() now = DateTime.now` to `ChatController` and store it as `_now`. Create live agents as:

```dart
final agent = ChatMessage.agent('a-$stamp')
  ..processingStartedAt = _now();
```

For history messages with `status == 'running'`, set `processingStartedAt = _now()` because no reliable server phase start exists. Parse `elapsed_ms` on both `error` and `done` frames. Do not derive elapsed time locally when a stream ends without a server value.

- [ ] **Step 5: Re-run focused tests and commit**

```bash
cd mobile
flutter test \
  test/theme_v2/session/session_thinking_time_test.dart \
  test/theme_v2/session/chat_controller_retry_test.dart
cd ..
git add mobile/lib/theme_v2/session/session_thinking_time.dart \
  mobile/test/theme_v2/session/session_thinking_time_test.dart \
  mobile/lib/chat/chat_models.dart \
  mobile/lib/chat/chat_controller.dart \
  mobile/test/theme_v2/session/chat_controller_retry_test.dart
git commit -m "feat: track chat thinking time"
```

Expected: focused tests PASS; retry creates a distinct timing cycle.

---

### Task 3: Start Hardware Flash Timing at Agent Processing

**Files:**
- Modify: `mobile/lib/theme_v2/capture/capture_activity_models.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_activity_coordinator.dart`
- Modify: `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Modify: `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_session_unified_chat_test.dart`

**Interfaces:**
- Consumes: `CaptureActivityEvent.occurredAt` for each phase transition and `ChatMessage.processingStartedAt` from Task 2.
- Produces: `CaptureActivityItem.phaseStartedAt: DateTime`; hardware agent messages start at the understanding/organizing phase observation and completed history restores `elapsedMs`.

- [ ] **Step 1: Write a failing phase-start coordinator test**

Add a test that applies the same aliases at three distinct times:

```dart
final listeningAt = DateTime.utc(2026, 8, 13, 10);
final transcribingAt = listeningAt.add(const Duration(seconds: 4));
final agentAt = listeningAt.add(const Duration(seconds: 9));

coordinator.apply(event(
  aliases: {'recording:r1'},
  phase: CaptureActivityPhase.listening,
  occurredAt: listeningAt,
));
coordinator.apply(event(
  aliases: {'recording:r1'},
  phase: CaptureActivityPhase.transcribing,
  occurredAt: transcribingAt,
));
coordinator.apply(event(
  aliases: {'recording:r1'},
  phase: CaptureActivityPhase.understanding,
  occurredAt: agentAt,
));

expect(coordinator.snapshot.active!.occurredAt, listeningAt);
expect(coordinator.snapshot.active!.phaseStartedAt, agentAt);
```

- [ ] **Step 2: Run the coordinator test and verify RED**

```bash
cd mobile
flutter test test/theme_v2/capture/capture_activity_coordinator_test.dart
```

Expected: FAIL because `phaseStartedAt` does not exist.

- [ ] **Step 3: Preserve phase transition time**

Add required `phaseStartedAt` to `CaptureActivityItem`. Initialize `_CaptureTask.phaseStartedAt = event.occurredAt`. In `_CaptureTask.apply`, when an incoming terminal or higher-ranked phase is accepted, assign both `phase` and `phaseStartedAt = event.occurredAt`. In `mergeTask`, carry `phaseStartedAt` from whichever task contributes the winning phase. Pass it through `toItem()`.

Keep `occurredAt` unchanged as the earliest task time so queue ordering and date matching do not regress.

- [ ] **Step 4: Write failing Flash controller timing tests**

In `capture_session_realtime_test.dart`, load a running Flash agent message, then apply listening and transcribing activities and assert `processingStartedAt` stays null. Apply understanding with `inputTurnId: 'turn-1'` and a known `phaseStartedAt`, then assert:

```dart
expect(controller.messages.last.processingStartedAt, agentStartedAt);
```

On the refreshed completed response include `'elapsed_ms': 1420` and assert the restored agent has `elapsedMs == 1420` and `processingStartedAt == null`.

In `capture_session_unified_chat_test.dart`, inject `now`, send a typed follow-up, and assert its local assistant starts immediately at `now`; verify existing unified historical messages restore their `elapsed_ms`.

- [ ] **Step 5: Run Flash controller tests and verify RED**

```bash
cd mobile
flutter test \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_unified_chat_test.dart
```

Expected: FAIL because the Flash controller does not set `processingStartedAt` and the realtime fixture does not restore final elapsed state.

- [ ] **Step 6: Implement Flash timing boundaries**

Add `DateTime Function() now = DateTime.now` to `CaptureSessionController`. For typed follow-up assistant messages, set `processingStartedAt = _now()` exactly as ordinary chat does.

While loading a daily Flash Session, collect input-turn IDs whose recording status is `agent_processing`. After unified messages are restored, give matching running agents `_now()` as a fallback start. Then call `_syncActivityState`; when a reliable activity exists, prefer its earlier `phaseStartedAt` over that fallback.

In `_syncActivityState`, only set hardware message timing for `understanding` and `organizing`:

```dart
final isAgentProcessing = const {
  CaptureActivityPhase.understanding,
  CaptureActivityPhase.organizing,
}.contains(activity.phase);
if (isAgentProcessing) {
  final observedStart = activity.phaseStartedAt.toLocal();
  final existingStart = message.processingStartedAt;
  if (existingStart == null || observedStart.isBefore(existingStart)) {
    message.processingStartedAt = observedStart;
  }
}
```

Listening, receiving, and transcribing must not set the field. `_messagesFromUnified` continues restoring `elapsed_ms`; completed messages keep `processingStartedAt == null`. Parse failed typed-chat SSE `elapsed_ms` in `_applyTurnEvent`.

- [ ] **Step 7: Run all focused capture tests and commit**

```bash
cd mobile
flutter test \
  test/theme_v2/capture/capture_activity_coordinator_test.dart \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_unified_chat_test.dart
cd ..
git add mobile/lib/theme_v2/capture/capture_activity_models.dart \
  mobile/lib/theme_v2/capture/capture_activity_coordinator.dart \
  mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart \
  mobile/lib/theme_v2/capture/capture_session_controller.dart \
  mobile/test/theme_v2/capture/capture_session_realtime_test.dart \
  mobile/test/theme_v2/capture/capture_session_unified_chat_test.dart
git commit -m "feat: time flash agent processing"
```

Expected: all focused capture tests PASS; earlier phases never start thinking time.

---

### Task 4: Render Live and Final Thinking Time

**Files:**
- Modify: `mobile/lib/theme_v2/session/session_thinking_time.dart`
- Modify: `mobile/test/theme_v2/session/session_thinking_time_test.dart`
- Modify: `mobile/lib/theme_v2/session/session_analysis_block.dart`
- Modify: `mobile/lib/theme_v2/session/session_transcript.dart`
- Modify: `mobile/lib/pages/chat_page.dart`
- Modify: `mobile/test/theme_v2/session/session_state_test.dart`

**Interfaces:**
- Consumes: `ChatMessage.processingStartedAt`, `ChatMessage.elapsedMs`, `formatThinkingTimer`, and `formatThinkingSummary`.
- Produces: `SessionThinkingTimer`, `SessionThinkingFooter`, `SessionAnalysisBlock(processingStartedAt:)`, and `SessionTurnFailureBlock(elapsedMs:)`.

- [ ] **Step 1: Write failing isolated timer/footer widget tests**

In `session_thinking_time_test.dart`, use a mutable injected clock:

```dart
testWidgets('live timer updates locally and is excluded from live semantics', (
  tester,
) async {
  final startedAt = DateTime(2026, 8, 13, 10);
  var now = startedAt;
  await tester.pumpWidget(testHost(
    SessionThinkingTimer(startedAt: startedAt, now: () => now),
  ));
  expect(find.text('00:00'), findsOneWidget);

  now = startedAt.add(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  expect(find.text('00:01'), findsOneWidget);
  expect(
    tester.getSemantics(find.byType(SessionThinkingTimer)).hasFlag(
      SemanticsFlag.isLiveRegion,
    ),
    isFalse,
  );
});

testWidgets('final footer uses natural language and never shows tokens', (
  tester,
) async {
  await tester.pumpWidget(testHost(const SessionThinkingFooter(elapsedMs: 68000)));
  expect(find.text('思考 1 分 8 秒'), findsOneWidget);
  expect(find.textContaining('token'), findsNothing);
});
```

- [ ] **Step 2: Write failing Session transcript presentation tests**

In `session_state_test.dart`, add widget tests for:

1. A streaming agent with `processingStartedAt` shows a timer on the right of `session-analyzing`.
2. A completed agent with `elapsedMs = 68000` shows `思考 1 分 8 秒` below the reply and no token copy even if `tokens` is set.
3. A failed agent with `elapsedMs = 12000` shows `处理 12 秒后未完成`.
4. A failed agent without elapsed time keeps `这条回复暂未完成`.

- [ ] **Step 3: Run focused widget tests and verify RED**

```bash
cd mobile
flutter test \
  test/theme_v2/session/session_thinking_time_test.dart \
  test/theme_v2/session/session_state_test.dart
```

Expected: FAIL because the timer/footer widgets and elapsed-aware transcript rendering do not exist.

- [ ] **Step 4: Implement isolated timer and final footer widgets**

In `session_thinking_time.dart`, add a stateful `SessionThinkingTimer` that owns one `Timer.periodic(const Duration(seconds: 1), ...)`, cancels it in `dispose`, restarts it only when `startedAt` changes, and wraps only its text in `ExcludeSemantics`. Accept `DateTime Function()? now` as a test seam.

Add `SessionThinkingFooter(elapsedMs:)` using Theme V2 muted color, a top divider, a small non-animated icon, and `formatThinkingSummary(elapsedMs)`.

- [ ] **Step 5: Wire the approved layout into analysis and transcript**

Change `SessionAnalysisBlock` to accept `DateTime? processingStartedAt`. Replace the right-side `处理中` text with `SessionThinkingTimer` when start time exists, retaining `处理中` only for transient global analysis without a message start.

Change `SessionTurnFailureBlock` to accept `int? elapsedMs`; use:

```dart
final failureLabel = elapsedMs == null
    ? '这条回复暂未完成'
    : '${formatThinkingSummary(elapsedMs, verb: '处理')}后未完成';
```

In `SessionTranscript._messageRow`:

- Pass `message.processingStartedAt` to the inline `SessionAnalysisBlock`.
- Render `SessionThinkingFooter` only when `!message.streaming`, `message.elapsedMs != null`, and the message has no `ErrorPart`.
- Pass `message.elapsedMs` to the failure block.
- Keep the global no-message `SessionAnalysisBlock` without a timer.

Add `showCostFooter = true` to `ChatMessageBubble` and gate its existing `_costFooter`. Theme V2 passes `showCostFooter: false`; legacy chat leaves the default untouched.

- [ ] **Step 6: Run focused widget tests, format, and commit**

```bash
cd mobile
dart format \
  lib/theme_v2/session/session_thinking_time.dart \
  lib/theme_v2/session/session_analysis_block.dart \
  lib/theme_v2/session/session_transcript.dart \
  lib/pages/chat_page.dart \
  test/theme_v2/session/session_thinking_time_test.dart \
  test/theme_v2/session/session_state_test.dart
flutter test \
  test/theme_v2/session/session_thinking_time_test.dart \
  test/theme_v2/session/session_state_test.dart
cd ..
git add mobile/lib/theme_v2/session/session_thinking_time.dart \
  mobile/test/theme_v2/session/session_thinking_time_test.dart \
  mobile/lib/theme_v2/session/session_analysis_block.dart \
  mobile/lib/theme_v2/session/session_transcript.dart \
  mobile/lib/pages/chat_page.dart \
  mobile/test/theme_v2/session/session_state_test.dart
git commit -m "feat: show session thinking time"
```

Expected: focused widget tests PASS and no Dart file changes after the final format command.

---

### Task 5: Full Regression and Visual Verification

**Files:**
- Verify: all files listed in Tasks 1–4; do not introduce another production file.

**Interfaces:**
- Consumes: all behavior from Tasks 1–4.
- Produces: verified server and mobile implementation with no unrelated worktree changes staged.

- [ ] **Step 1: Run the complete relevant server regression set**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  pytest \
    tests/integration/test_capture_jobs.py \
    tests/contract/test_chat_api.py \
    tests/unit/test_flash_agent_runner.py \
    tests/unit/test_flash_dispatcher.py \
    tests/unit/test_capture_activity_status.py \
    -q
```

Expected: all selected server tests PASS.

- [ ] **Step 2: Run the complete Theme V2 session and capture mobile suites**

```bash
cd mobile
flutter test test/theme_v2/session test/theme_v2/capture
```

Expected: all Theme V2 Session and capture tests PASS with no leaked timer warnings.

- [ ] **Step 3: Run static analysis on all touched Dart files**

```bash
cd mobile
flutter analyze \
  lib/chat/chat_models.dart \
  lib/chat/chat_controller.dart \
  lib/pages/chat_page.dart \
  lib/theme_v2/capture/capture_activity_models.dart \
  lib/theme_v2/capture/capture_activity_coordinator.dart \
  lib/theme_v2/capture/capture_session_controller.dart \
  lib/theme_v2/session/session_thinking_time.dart \
  lib/theme_v2/session/session_analysis_block.dart \
  lib/theme_v2/session/session_transcript.dart \
  test/theme_v2/session/session_thinking_time_test.dart \
  test/theme_v2/session/chat_controller_retry_test.dart \
  test/theme_v2/session/session_state_test.dart \
  test/theme_v2/capture/capture_activity_coordinator_test.dart \
  test/theme_v2/capture/capture_session_realtime_test.dart \
  test/theme_v2/capture/capture_session_unified_chat_test.dart
```

Expected: `No issues found!`

- [ ] **Step 4: Perform a real-device acceptance pass**

With the app connected to the updated Theme V2 backend:

1. Send an ordinary chat turn; verify `00:00` appears and increments, then settles to `思考 N 秒`.
2. Create a voice Flash; verify listening/transcribing show no timer.
3. Wait for “正在理解/正在整理”; verify the timer begins then.
4. Reopen the completed Session; verify final duration persists and does not restart.
5. Trigger or simulate one failed chat; verify `处理 N 秒后未完成` when the server frame includes elapsed time.
6. Enable TalkBack/VoiceOver; verify the phase is announced but the timer is not announced every second.

Expected: all six checks match the approved design A.

- [ ] **Step 5: Verify diff boundaries and commit any final in-scope corrections**

```bash
git diff --check
git status --short
git diff --stat -- \
  theme_v2_service/app/domains/capture/jobs.py \
  theme_v2_service/app/domains/sessions/api_chat.py \
  theme_v2_service/tests/integration/test_capture_jobs.py \
  theme_v2_service/tests/contract/test_chat_api.py \
  mobile/lib/chat/chat_models.dart \
  mobile/lib/chat/chat_controller.dart \
  mobile/lib/pages/chat_page.dart \
  mobile/lib/theme_v2/capture \
  mobile/lib/theme_v2/session \
  mobile/test/theme_v2/capture \
  mobile/test/theme_v2/session
```

Do not stage the pre-existing calendar, report illustration, design, or `dist/` changes. If a regression fails, return to the task that owns that behavior, repeat its RED/GREEN cycle, and amend only that task's explicit commit paths.

Expected: `git diff --check` is clean and only thinking-time files appear in the Task 1–4 commits.
