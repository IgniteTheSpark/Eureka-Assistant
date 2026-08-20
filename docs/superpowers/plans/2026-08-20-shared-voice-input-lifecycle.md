# Shared Voice Input Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make cloud voice input a single App-owned capability that can switch cleanly among Session, report, Skill, ordinary fields, and Reka, while making every backend ASR session bounded, isolated by user, and guaranteed to release its resources.

**Architecture:** The backend separates connection admission from an explicit `StreamingAsrSession` lifecycle with bounded startup, finalization, and cleanup. The mobile App mounts one `VoiceInputCoordinator` at the root; UI surfaces create disposable target bindings and never own or compete for the microphone directly. Existing wire events and the approved ordinary-field/Reka interactions remain unchanged.

**Tech Stack:** Python 3.11, FastAPI/Starlette WebSocket, asyncio, Alibaba Qwen streaming ASR, Flutter/Dart, Riverpod, `record`, `web_socket_channel`, pytest-style script tests, Flutter unit/widget tests, Docker Compose, Android physical-device verification.

---

## Delivery Rules

- Preserve the current authenticated `/api/asr/stream` wire protocol.
- Use test-first development for every task: add one focused failing behavior, observe the intended failure, implement the smallest production change, then run the focused and neighboring suites.
- Do not expose internal target switching as `busy` or `microphone in use`.
- Do not retain audio, retry automatically, log transcript bodies, or expose provider credentials.
- Mark each checkbox only after its command has produced fresh evidence.
- Commit after every task with only that task's files staged.

## Task 1: Backend Session Lifecycle and Bounded Provider Startup

**Files:**

- Create: `backend/core/asr/session.py`
- Modify: `backend/core/asr/streaming.py`
- Modify: `backend/scripts/test_asr_stream_gateway.py`

- [x] **Step 1: Replace the exploratory timeout test with lifecycle RED tests**

Add deterministic fake providers/sockets covering:

```python
async def test_provider_start_timeout_cancels_provider_and_releases_lease(): ...
async def test_disconnect_during_provider_start_cancels_immediately(): ...
async def test_cleanup_failure_still_releases_exact_lease(): ...
async def test_terminal_event_is_emitted_at_most_once(): ...
```

The hanging provider must signal when `start()` entered and record cancellation/close counts. The registry must expose test-only observable ownership through a query method rather than sleeps.

- [x] **Step 2: Run the gateway suite and observe the intended RED**

Run:

```bash
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_asr_stream_gateway
```

Expected: failure because the explicit session lifecycle/disconnect race does not exist; do not accept an unrelated import or syntax failure as RED.

- [x] **Step 3: Introduce the explicit connection state machine**

Create `StreamingAsrSession` with one-way phases and idempotent termination:

```python
class SessionPhase(StrEnum):
    ACCEPTED = "accepted"
    VALIDATING = "validating"
    PROVIDER_STARTING = "provider_starting"
    READY = "ready"
    STREAMING = "streaming"
    FINALIZING = "finalizing"
    TERMINAL = "terminal"
    CLOSED = "closed"

class StreamingAsrSession:
    async def run(self) -> None: ...
    async def supersede(self) -> None: ...
    async def close(self) -> None: ...  # idempotent and bounded
```

The session owns provider/client/timer/forwarding tasks. Provider startup races provider readiness, client disconnect/cancel, and `provider_start_timeout_seconds`. Cancel and drain every losing task. Normalize a provider deadline to the existing `service_unavailable` error without leaking raw exceptions.

- [x] **Step 4: Make the gateway an admission/lease wrapper**

Keep parsing, auth/rate-limit behavior, and event shapes in `streaming.py`, but delegate one accepted connection to `StreamingAsrSession`. Put exact lease release in the gateway's outermost `finally` so provider/socket cleanup failures cannot strand ownership.

- [x] **Step 5: Run focused and neighboring backend suites GREEN**

Run:

```bash
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_asr_stream_gateway
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_qwen_streaming_asr
```

Expected: all cases pass; the hanging-start test completes within its test deadline and records exactly one provider cancellation/close.

- [x] **Step 6: Commit Task 1**

```bash
git add backend/core/asr/session.py backend/core/asr/streaming.py \
  backend/scripts/test_asr_stream_gateway.py
git commit -m "fix(backend): bound streaming asr session startup"
```

## Task 2: Backend Replacement, Limits, and Provider Cleanup

**Files:**

- Modify: `backend/core/asr/session.py`
- Modify: `backend/core/asr/streaming.py`
- Modify: `backend/core/asr/qwen_streaming.py`
- Modify: `backend/config.py`
- Modify: `backend/requirements.txt`
- Modify: `docker-compose.yml`
- Modify: `backend/scripts/test_asr_stream_gateway.py`
- Modify: `backend/scripts/test_qwen_streaming_asr.py`
- Modify: `backend/scripts/test_asr_config.py`

- [x] **Step 1: Add RED tests for same-user replacement and different-user isolation**

Add tests that hold user A in startup, then prove:

```python
new_a = await registry.install("a", session_a2)  # supersedes a1
new_b = await registry.install("b", session_b1)  # never waits on a
assert await registry.release("a", new_a.lease_id)
assert not await registry.release("a", old_a.lease_id)
```

Also assert a stale session cannot delete a newer lease and that supersession is not sent as a user-visible `busy` error.

- [x] **Step 2: Add RED tests for finalization/cleanup deadlines and byte accumulation**

Cover provider `finish()` hanging, final provider event never arriving, downstream `send_json()` failing, provider close hanging, and many individually valid PCM frames whose cumulative bytes exceed `duration_limit_seconds * 16_000 * 2`.

Expected RED: current code either hangs, leaks ownership, or accepts cumulative audio past the authoritative duration.

- [x] **Step 3: Implement lease-token replacement and bounded finalization**

Use a registry entry containing a unique lease token plus session reference. Install a new same-user entry atomically, request cancellation of the replaced session outside the registry lock, and release only when both user and token match. Add separate settings:

```python
asr_provider_start_timeout_seconds: float
asr_provider_finalize_timeout_seconds: float
asr_provider_cleanup_timeout_seconds: float
```

Race finalization against its whole deadline, not separate unbounded `finish()` and final-event waits. Always close locally and release the lease even when client/provider cleanup times out.

- [x] **Step 4: Enforce cumulative bytes before provider forwarding**

Maintain `received_pcm_bytes`. Reject the frame that would make it exceed the mode's maximum bytes; emit one normalized terminal error and do not forward the offending bytes.

- [x] **Step 5: Harden Qwen partial startup cancellation**

Wrap socket creation/start handshake with explicit `asyncio.CancelledError` handling and close any partially initialized socket/task before re-raising cancellation. Keep provider message bodies out of application logs. Align the `websockets` dependency with the API used by the adapter (`additional_headers`).

- [x] **Step 6: Validate timeout relationships in config**

Reject non-positive deadlines and enforce that the client-ready contract remains larger than server provider-start plus transport margin. Wire environment defaults in `docker-compose.yml`; never add the API key value to tracked files.

- [x] **Step 7: Run all backend ASR gates GREEN**

Run:

```bash
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_asr_config
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_qwen_streaming_asr
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_asr_stream_gateway
```

Expected: all tests pass without unbounded sleeps; A's hanging session never delays B.

- [x] **Step 8: Commit Task 2**

```bash
git add backend/core/asr backend/config.py backend/requirements.txt \
  backend/scripts/test_asr_config.py backend/scripts/test_qwen_streaming_asr.py \
  backend/scripts/test_asr_stream_gateway.py docker-compose.yml
git commit -m "fix(backend): isolate and finalize streaming asr sessions"
```

## Task 3: App-Root Voice Input Coordinator

**Files:**

- Create: `mobile/lib/voice_input/voice_input_coordinator.dart`
- Modify: `mobile/lib/voice_input/voice_input_scope.dart`
- Modify: `mobile/lib/main.dart`
- Create: `mobile/test/voice_input/voice_input_coordinator_test.dart`
- Modify: `mobile/test/voice_input/voice_input_service_test.dart`

- [x] **Step 1: Add coordinator RED tests with a controllable fake service**

Cover target A start, B superseding A during connecting/listening/finalizing, rapid A→B→C where only C starts, app lifecycle cancellation, disposed-binding late events, failure reuse, and exact one active service session. Assert no target receives a `busy` error.

- [x] **Step 2: Run focused RED**

Run:

```bash
cd mobile
flutter test test/voice_input/voice_input_coordinator_test.dart
```

Expected: compile failure because `VoiceInputCoordinator`/binding API is absent.

- [x] **Step 3: Implement coordinator and disposable binding API**

Implement an App-owned coordinator with a monotonic generation and serialized operation tail:

```dart
enum VoiceInputTargetMode { ordinary, reka }
enum VoiceInputCoordinatorState { idle, connecting, listening, finalizing }

final class VoiceInputTargetBinding extends ChangeNotifier {
  Future<void> start();
  Future<void> stop();
  Future<void> cancel();
  Future<void> disposeAsync();
}

final class VoiceInputCoordinator {
  VoiceInputTargetBinding bind({
    required Object targetId,
    required VoiceInputTargetMode mode,
    required VoiceInputTargetCallbacks callbacks,
  });
  Future<void> cancelActive(VoiceInputCancelReason reason);
  Future<void> dispose();
}
```

Invalidation is synchronous: increment generation and restore/cancel the old target before awaiting service cleanup. Queue mutations so the latest requested binding wins. Gate every partial/stable/final/error callback by binding identity, generation, and session ID.

- [x] **Step 4: Mount a stateful owner above the App**

Replace `VoiceInputScope.sharedService` and shared lease with `VoiceInputHost`, a stateful root that constructs one service/coordinator, exposes it through `VoiceInputScope`, observes `AppLifecycleState`, and cancels on inactive/paused/detached. Ensure logout/auth expiry invokes the same coordinator cancellation path.

- [x] **Step 5: Run focused tests and analyzer GREEN**

Run:

```bash
cd mobile
flutter test test/voice_input/voice_input_coordinator_test.dart \
  test/voice_input/voice_input_service_test.dart
flutter analyze lib/voice_input lib/main.dart \
  test/voice_input/voice_input_coordinator_test.dart
```

Expected: all tests pass and analyzer reports `No issues found!`.

- [x] **Step 6: Commit Task 3**

```bash
git add mobile/lib/main.dart mobile/lib/voice_input \
  mobile/test/voice_input/voice_input_coordinator_test.dart \
  mobile/test/voice_input/voice_input_service_test.dart
git commit -m "feat(mobile): own voice input at app root"
```

## Task 4: Ordinary Text Binding and Session Migration

**Files:**

- Modify: `mobile/lib/voice_input/voice_input_controller.dart`
- Modify: `mobile/lib/voice_input/voice_input_field.dart`
- Modify: `mobile/lib/theme_v2/session/theme_v2_session_page.dart`
- Modify: `mobile/lib/theme_v2/session/session_composer.dart`
- Modify: `mobile/lib/pages/session_detail_page.dart`
- Modify: `mobile/lib/pages/chat_page.dart`
- Modify: `mobile/test/voice_input/voice_input_controller_test.dart`
- Modify: `mobile/test/voice_input/voice_input_field_test.dart`
- Add/Modify: focused Session widget tests under `mobile/test/theme_v2/session/`

- [x] **Step 1: Replace the old lease/busy test with latest-target-wins RED tests**

Assert starting controller B while A is active restores A's exact `TextEditingValue`, cancels A, starts B, and never exposes `another input is using the microphone`. Add route disposal during connect/listen/finalize and late-event suppression cases.

- [x] **Step 2: Run focused RED**

```bash
cd mobile
flutter test test/voice_input/voice_input_controller_test.dart \
  test/voice_input/voice_input_field_test.dart
```

Expected: old `VoiceInputLease` rejects B or stale A events mutate the field.

- [x] **Step 3: Convert `VoiceInputController` into an ordinary target adapter**

The controller receives a `VoiceInputCoordinator`, creates one target binding, snapshots `TextEditingValue` on start, appends provisional text only for the active generation, commits final text without submit, and restores the complete snapshot on cancel/switch/failure. `dispose()` invalidates immediately and schedules bounded cancellation through the binding.

- [x] **Step 4: Migrate current and legacy Session composers**

Obtain the coordinator from `VoiceInputScope.of(context)` after dependencies are available (`didChangeDependencies` or a scoped builder), not from a static singleton. Keep the current tap-to-start/tap-to-stop UI and editable final transcript.

- [x] **Step 5: Run Session/field suites and analyzer GREEN**

```bash
cd mobile
flutter test test/voice_input test/theme_v2/session
flutter analyze lib/voice_input lib/theme_v2/session \
  lib/pages/session_detail_page.dart lib/pages/chat_page.dart \
  test/voice_input test/theme_v2/session
```

Expected: switching tests pass; no static service/lease references remain in Session code.

- [x] **Step 6: Commit Task 4**

```bash
git add mobile/lib/voice_input mobile/lib/theme_v2/session \
  mobile/lib/pages/session_detail_page.dart mobile/lib/pages/chat_page.dart \
  mobile/test/voice_input mobile/test/theme_v2/session
git commit -m "fix(mobile): share voice input across session fields"
```

## Task 5: Report, Skill, Flash, and Editor Migration

**Files:**

- Modify: `mobile/lib/theme_v2/report/report_create_sheet.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Modify: `mobile/lib/flash/flash_sheet.dart`
- Modify: every remaining ordinary voice-input adopter reported by `rg`
- Modify/Create: corresponding widget tests under `mobile/test/theme_v2/`, `mobile/test/flash/`, and `mobile/test/voice_input/`

- [ ] **Step 1: Inventory every remaining adopter and add behavioral RED coverage**

Run:

```bash
rg -n "VoiceInputScope\.sharedService|VoiceInputLease|VoiceInputService\(" mobile/lib
```

Add tests proving report→Skill→Session switching, leaving a sheet/page frees the next target, and no canceled provisional text creates a report, Skill, Flash, asset, or chat turn.

- [ ] **Step 2: Migrate every ordinary adopter to the scoped coordinator**

Use the common ordinary adapter; do not create per-page services or locks. Preserve each surface's existing typed submission controls and ensure voice finalization never triggers them automatically.

- [ ] **Step 3: Prove direct ownership is gone**

Run:

```bash
rg -n "VoiceInputScope\.sharedService|VoiceInputLease\.shared|VoiceInputService\(" mobile/lib
```

Expected: only the App-root host constructs `VoiceInputService`; no UI surface references a shared static service or lease.

- [ ] **Step 4: Run migrated-surface tests and analyzer GREEN**

```bash
cd mobile
flutter test test/voice_input test/theme_v2 test/flash
flutter analyze lib test/voice_input test/theme_v2 test/flash
```

Expected: all selected tests pass, analyzer clean.

- [ ] **Step 5: Commit Task 5**

```bash
git add mobile/lib mobile/test
git commit -m "refactor(mobile): bind authoring voice input globally"
```

## Task 6: Reka Migration Without Gesture Regression

**Files:**

- Modify: `mobile/lib/voice_input/reka_voice_capture.dart`
- Modify: `mobile/lib/theme_v2/home/today_dot_experiment_page.dart`
- Modify: `mobile/lib/pet/floating_mascot.dart`
- Modify: `mobile/test/theme_v2/home/today_dot_experiment_page_test.dart`
- Add/Modify: Reka coordinator tests under `mobile/test/voice_input/`

- [ ] **Step 1: Add Reka switching and gesture RED tests**

Cover ordinary→Reka supersession, Reka→ordinary supersession, release-after-final submits once, slide-up cancellation submits nothing, page disposal during startup, and late final after cancellation. Assert Reka's one-minute mode and ordinary's five-minute mode reach the service correctly.

- [ ] **Step 2: Run focused RED**

```bash
cd mobile
flutter test test/theme_v2/home/today_dot_experiment_page_test.dart \
  test/voice_input/reka_voice_capture_test.dart
```

Expected: current Reka coordinator owns the service/lease independently or cannot switch through the App coordinator.

- [ ] **Step 3: Rebuild Reka presentation over a target binding**

Keep the existing `connecting/listening/cancelArmed/stopping/sending/error` presentation states, long-press gesture, provisional transcript, release-to-submit, and slide-up cancellation. Delegate microphone/session ownership to `VoiceInputCoordinator`; submit only a non-empty final transcript for the still-active generation through the existing Flash path.

- [ ] **Step 4: Migrate both current Reka entry points**

Inject/bind from `VoiceInputScope.of(context)` for the Theme V2 home and any remaining floating mascot route. Do not reintroduce the removed legacy floating Reka UI as part of this migration.

- [ ] **Step 5: Run Reka, coordinator, and analyzer gates GREEN**

```bash
cd mobile
flutter test test/voice_input test/theme_v2/home/today_dot_experiment_page_test.dart
flutter analyze lib/voice_input lib/theme_v2/home \
  lib/pet/floating_mascot.dart test/voice_input \
  test/theme_v2/home/today_dot_experiment_page_test.dart
```

Expected: all tests pass and no independent voice service/lease remains.

- [ ] **Step 6: Commit Task 6**

```bash
git add mobile/lib/voice_input/reka_voice_capture.dart \
  mobile/lib/theme_v2/home/today_dot_experiment_page.dart \
  mobile/lib/pet/floating_mascot.dart mobile/test/voice_input \
  mobile/test/theme_v2/home/today_dot_experiment_page_test.dart
git commit -m "fix(mobile): route reka through shared voice input"
```

## Task 7: Cross-Layer Regression, Packaging, and Physical Device

**Files:**

- Modify if needed: `backend/scripts/test_asr_stream_gateway.py`
- Modify if needed: `mobile/test/voice_input/voice_input_adoption_test.dart`
- Create: `docs/voice-input-acceptance.md`

- [ ] **Step 1: Add a final adoption/invariant test**

Assert the App root mounts one coordinator, all voice-capable surfaces bind through it, legacy static shared service/lease ownership is absent, and no user-facing copy contains the old microphone-conflict message.

- [ ] **Step 2: Run fresh backend verification**

```bash
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_asr_config
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_qwen_streaming_asr
docker compose -p cloud-streaming-asr -f docker-compose.yml exec -T backend \
  python -m scripts.test_asr_stream_gateway
```

Expected: all lifecycle, provider, config, isolation, and byte-limit tests pass.

- [ ] **Step 3: Run fresh mobile verification**

```bash
cd mobile
flutter test test/voice_input
flutter test test/theme_v2/session test/theme_v2/report \
  test/theme_v2/library test/theme_v2/home
flutter analyze lib test/voice_input test/theme_v2
flutter build apk --debug \
  --dart-define=API_BASE_URL=http://127.0.0.1:8200
```

Expected: tests pass, analyzer clean, debug APK builds.

- [ ] **Step 4: Rebuild/reload the backend and verify health through the proxy**

Run the project's scoped Docker Compose commands, then verify `/api/health` through port 8200 and one authenticated ASR WebSocket reaches `ready` without printing credentials or transcript content.

- [ ] **Step 5: Install the correct branch build on the connected Android device**

Install `mobile/build/app/outputs/flutter-apk/app-debug.apk`, restore `adb reverse tcp:8200 tcp:8200`, launch `com.eureka.mindapp`, and confirm the visible Theme V2 build (no removed legacy floating Reka).

- [ ] **Step 6: Perform physical-device acceptance**

Record results in `docs/voice-input-acceptance.md` for:

1. Session start/stop and editable final text.
2. Session→report→Skill target switching.
3. Session→Reka slide-up cancel→Session without restart.
4. Leaving a connecting/listening page then starting another field.
5. Network/provider failure restores original text and leaves typing usable.
6. A second backend test user is unaffected by a deliberately stalled first-user provider.

Do not change radios or device settings without capturing and restoring their prior state.

- [ ] **Step 7: Inspect the final diff and commit acceptance artifacts**

```bash
git status --short
git diff --check
git log --oneline --decorate -10
git add docs/voice-input-acceptance.md \
  backend/scripts/test_asr_stream_gateway.py \
  mobile/test/voice_input/voice_input_adoption_test.dart
git commit -m "test: verify app-wide voice input lifecycle"
```

Expected: only intentional files are staged; unrelated user changes remain untouched.

## Final Acceptance Checklist

- [ ] Any supported voice target can start without restarting the App.
- [ ] Starting a new target restores/cancels the previous one with no microphone-conflict error.
- [ ] Navigation, backgrounding, logout, interruption, and failure invalidate UI immediately and release resources.
- [ ] Ordinary fields retain editable final text and never auto-submit.
- [ ] Reka retains provisional text, release-to-send, slide-up cancel, and one submission maximum.
- [ ] Backend startup, finalization, and cleanup are all bounded.
- [ ] Same-user replacement cannot release a newer lease; different users never conflict.
- [ ] Cumulative PCM duration is enforced by the gateway.
- [ ] Audio/transcript bodies are absent from infrastructure logs and no audio retry/retention exists.
- [ ] Backend suites, Flutter tests/analyzer/build, proxy smoke, and physical-device acceptance have fresh evidence.
