# Qwen Cloud Voice Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship one authenticated, cloud-streaming Mandarin/English voice-input service for Eureka mobile, including editable dictation on content fields and WeChat-style long-press capture on Reka.

**Architecture:** Flutter captures 16 kHz mono PCM16 in memory and opens an authenticated WebSocket only to Eureka. FastAPI validates the user and stream contract, then translates between a stable Eureka event protocol and Alibaba Cloud Model Studio `qwen-audio-3.0-asr-flash-streaming`; provider secrets never enter the app. Ordinary fields use a reusable controller that snapshots/restores text, while Reka reuses the same session service and creates a text Flash only after one non-empty final result.

**Tech Stack:** FastAPI WebSockets, Python 3.12 asyncio, `websockets`, Flutter/Dart, `record`, existing bearer-token auth, existing `POST /api/flash`.

## Global Constraints

- Production model: `qwen-audio-3.0-asr-flash-streaming`.
- Supported first-release speech: Mandarin, English, and Mandarin-English code-switching; no language selector and no detected-language dependency.
- Ordinary dictation cap: 300 seconds; warn at 270 seconds; stop and finalize at 300 seconds.
- Reka cap: 60 seconds; warn at 30 seconds; stop, finalize, and submit a non-empty transcript at 60 seconds.
- Audio contract: signed PCM16 little-endian, 16 kHz, mono; target frame size 6,400 bytes (200 ms); raw audio is never written to disk, database, object storage, or logs.
- Eureka accepts at most one active ASR session per user and the app accepts at most one active voice session process-wide.
- Ordinary dictation never submits the containing form; Reka normal release is the only voice gesture that directly invokes a business action.
- Cancel, network loss, route disposal, lifecycle interruption, provider error, empty final, and finalization timeout create no business entity.
- No local ASR model, no `initialize()` public step, no original-audio retry, no runtime provider fallback, and no change to hardware Tencent/card.biz ASR paths.
- Secrets are backend-only: `DASHSCOPE_API_KEY`, `DASHSCOPE_ASR_WS_URL`, and `ALI_ASR_MODEL`.
- User-facing ASR infrastructure logs contain no audio and no transcript body.

---

### Task 1: Resolve Provider Configuration and Documentation

**Files:**
- Modify: `backend/config.py`
- Modify: `.env.example`
- Modify: `backend/.env.example`
- Modify: `deploy/.env.prod.example`
- Modify: `docker-compose.yml`
- Modify: `deploy/docker-compose.prod.yml`
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-08-20-mobile-cloud-voice-input-design.md`
- Test: `backend/scripts/test_asr_config.py`

**Interfaces:**
- Consumes: repository root `.env` locally and `deploy/.env.prod` in production.
- Produces: `settings.dashscope_api_key`, `settings.dashscope_asr_ws_url`, `settings.ali_asr_model`, `settings.asr_rate_limit_per_minute`, and `validate_asr_settings()`.

- [ ] **Step 1: Write the failing configuration test**

```python
from config import settings, validate_asr_settings


def test_qwen_asr_requires_key_and_secure_workspace_websocket() -> None:
    original = (
        settings.dashscope_api_key,
        settings.dashscope_asr_ws_url,
        settings.ali_asr_model,
    )
    try:
        settings.dashscope_api_key = ""
        settings.dashscope_asr_ws_url = "wss://workspace.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
        try:
            validate_asr_settings()
        except RuntimeError as exc:
            assert "DASHSCOPE_API_KEY" in str(exc)
        else:
            raise AssertionError("blank key was accepted")

        settings.dashscope_api_key = "sk-test"
        settings.dashscope_asr_ws_url = "https://example.com/api/v1"
        try:
            validate_asr_settings()
        except RuntimeError as exc:
            assert "DASHSCOPE_ASR_WS_URL" in str(exc)
        else:
            raise AssertionError("non-WebSocket URL was accepted")
    finally:
        (
            settings.dashscope_api_key,
            settings.dashscope_asr_ws_url,
            settings.ali_asr_model,
        ) = original
```

- [ ] **Step 2: Run the test and verify RED**

Run: `cd backend && ../.venv/bin/python -m scripts.test_asr_config`

Expected: FAIL because `validate_asr_settings` does not exist.

- [ ] **Step 3: Add exact server settings and environment wiring**

```python
dashscope_api_key: str = ""
dashscope_asr_ws_url: str = ""
ali_asr_model: str = "qwen-audio-3.0-asr-flash-streaming"
asr_rate_limit_per_minute: int = 10


def validate_asr_settings() -> None:
    if not settings.dashscope_api_key.strip():
        raise RuntimeError("DASHSCOPE_API_KEY is not configured")
    if not settings.dashscope_asr_ws_url.startswith("wss://"):
        raise RuntimeError("DASHSCOPE_ASR_WS_URL must be a secure WebSocket URL")
    if settings.ali_asr_model != "qwen-audio-3.0-asr-flash-streaming":
        raise RuntimeError("ALI_ASR_MODEL must be qwen-audio-3.0-asr-flash-streaming")
```

Add empty placeholders to example env files and pass all four variables into local and production backend containers. Document that the real values remain only in ignored env files or a production secret manager.

- [ ] **Step 4: Run GREEN and regression checks**

Run: `cd backend && ../.venv/bin/python -m scripts.test_asr_config && ../.venv/bin/python -m scripts.test_config_validation`

Expected: both scripts print `PASS`.

- [ ] **Step 5: Commit**

```bash
git add backend/config.py backend/scripts/test_asr_config.py .env.example backend/.env.example deploy/.env.prod.example docker-compose.yml deploy/docker-compose.prod.yml README.md docs/superpowers/specs/2026-08-20-mobile-cloud-voice-input-design.md
git commit -m "config: select qwen streaming asr"
```

### Task 2: Qwen Streaming Provider Adapter

**Files:**
- Create: `backend/core/asr/provider.py`
- Create: `backend/core/asr/qwen_streaming.py`
- Modify: `backend/requirements.txt`
- Test: `backend/scripts/test_qwen_streaming_asr.py`

**Interfaces:**
- Consumes: validated settings from Task 1 and an injectable async WebSocket connector.
- Produces: `StreamingAsrProvider`, `ProviderTranscriptEvent`, `ProviderEventKind`, `QwenStreamingAsrProvider.start/send_audio/finish/cancel/events`.

- [ ] **Step 1: Write fake-upstream tests first**

Cover five independent behaviors in `test_qwen_streaming_asr.py`. The first test drives `start()` against a `_FakeSocket` whose first inbound item is a `task-started` JSON string, then asserts the first outbound object has action `run-task`, model `qwen-audio-3.0-asr-flash-streaming`, format `pcm`, and sample rate `16000`. The second feeds two `result-generated` messages and asserts `sentence_end=false` emits one partial while `sentence_end=true` emits one stable with no repeated prefix. The third calls `finish()`, asserts `finish-task` was sent, feeds `task-finished`, and asserts one accumulated final. The fourth feeds a `task-failed` payload containing a fake secret and asserts the public exception contains only `service_unavailable`. The fifth cancels, asserts one socket close, no `finish-task`, and no later event.

```python
async def test_start_sends_run_task_and_waits_for_task_started() -> None:
    socket = _FakeSocket([
        json.dumps({"header": {"event": "task-started", "task_id": "provider-task"}})
    ])
    provider = QwenStreamingAsrProvider(
        api_key="sk-test",
        ws_url="wss://workspace.example/api-ws/v1/inference",
        model="qwen-audio-3.0-asr-flash-streaming",
        connector=lambda **_: _Connected(socket),
        task_id_factory=lambda: "client-task",
    )

    await provider.start()

    message = json.loads(socket.sent[0])
    assert message["header"]["action"] == "run-task"
    assert message["payload"]["model"] == "qwen-audio-3.0-asr-flash-streaming"
    assert message["payload"]["parameters"] == {"format": "pcm", "sample_rate": 16000}
```

The fake socket records outbound JSON/binary values and supplies exact provider events with `header.event` values `task-started`, `result-generated`, `task-finished`, and `task-failed`. Assertions inspect only event kinds, sequence numbers, text, and stable error codes; provider payloads are never exposed to a client event.

- [ ] **Step 2: Run the tests and verify RED**

Run: `cd backend && ../.venv/bin/python -m scripts.test_qwen_streaming_asr`

Expected: FAIL because `core.asr.qwen_streaming` is missing.

- [ ] **Step 3: Define the provider contract**

```python
class ProviderEventKind(str, Enum):
    PARTIAL = "partial"
    STABLE = "stable"
    FINAL = "final"


@dataclass(frozen=True)
class ProviderTranscriptEvent:
    kind: ProviderEventKind
    sequence: int
    text: str
    duration_ms: int = 0


class StreamingAsrProvider(Protocol):
    async def start(self) -> None:
        raise NotImplementedError
    async def send_audio(self, frame: bytes) -> None:
        raise NotImplementedError
    async def finish(self) -> None:
        raise NotImplementedError
    async def cancel(self) -> None:
        raise NotImplementedError
    def events(self) -> AsyncIterator[ProviderTranscriptEvent]:
        raise NotImplementedError
```

- [ ] **Step 4: Implement the Qwen adapter**

Connect with `Authorization: Bearer <DASHSCOPE_API_KEY>`, send `run-task` for task group `audio`, task `asr`, function `recognition`, format `pcm`, sample rate `16000`, and the configured model. Map `sentence_end=false` to replaceable `partial`, `sentence_end=true` to one `stable`, and `task-finished` to one complete `final`. Guard every terminal path so cancel, finish, upstream close, and failure clean up once.

Declare `websockets>=13.1,<16` directly in `backend/requirements.txt` because the backend imports it rather than relying on Uvicorn's transitive dependency.

- [ ] **Step 5: Run GREEN and compile checks**

Run: `cd backend && ../.venv/bin/python -m scripts.test_qwen_streaming_asr`

Run: `../.venv/bin/python -m compileall -q backend/core/asr backend/scripts/test_qwen_streaming_asr.py`

Expected: provider tests print `PASS`; compile exits 0.

- [ ] **Step 6: Commit**

```bash
git add backend/core/asr/provider.py backend/core/asr/qwen_streaming.py backend/requirements.txt backend/scripts/test_qwen_streaming_asr.py
git commit -m "feat(backend): adapt qwen streaming asr"
```

### Task 3: Authenticated Eureka ASR WebSocket Gateway

**Files:**
- Create: `backend/core/asr/streaming.py`
- Create: `backend/api/asr_stream.py`
- Modify: `backend/main.py`
- Test: `backend/scripts/test_asr_stream_gateway.py`

**Interfaces:**
- Consumes: a bearer token, normalized client control/binary frames, and a `StreamingAsrProvider` factory.
- Produces: `/api/asr/stream` with `ready`, `partial`, `stable`, `final`, and `error` JSON events.

- [ ] **Step 1: Write gateway tests with fake client socket and fake provider**

Test authentication before provider allocation, exact 16 kHz/mono/PCM16 start validation, 32,000-byte maximum individual binary frame, even byte length, ordered forwarding, one active session per user, ten starts per minute, 60/300-second authoritative caps, client cancel, disconnect cleanup, 10-second final timeout, monotonic event sequence, and one terminal event.

The normalized start message is:

```json
{"type":"start","voiceSessionId":"uuid","mode":"ordinary","audio":{"encoding":"pcm_s16le","sampleRate":16000,"channels":1}}
```

The normalized final message is:

```json
{"type":"final","voiceSessionId":"uuid","sequence":4,"text":"最终文本","audioDurationMs":1200}
```

- [ ] **Step 2: Run the gateway test and verify RED**

Run: `cd backend && ../.venv/bin/python -m scripts.test_asr_stream_gateway`

Expected: FAIL because `StreamingAsrGateway` is missing.

- [ ] **Step 3: Implement validation, registry, and rate limiter**

Use `AsrSessionRegistry` with an `asyncio.Lock` and user-id set; acquisition fails closed when the user already owns a session. Use an in-memory deque-based one-minute limiter because production currently runs one backend worker. Validate auth before `provider_factory()` and never log control text, transcript text, provider bodies, or binary frames.

- [ ] **Step 4: Implement endpoint orchestration**

Authenticate from `websocket.headers["authorization"]` using `decode_token`, validate the `start` message before provider allocation, accept and send `ready` only after `provider.start()` completes, then concurrently forward client audio and provider events. A valid `stop` calls `finish` and waits at most ten seconds for final; `cancel`, disconnect, timeout, or exception calls cancel and emits at most one safe terminal error when the socket remains writable.

Register the router in `backend/main.py` with prefix `/api`.

- [ ] **Step 5: Run GREEN and all focused backend checks**

Run: `cd backend && ../.venv/bin/python -m scripts.test_asr_stream_gateway`

Run: `cd backend && ../.venv/bin/python -m scripts.test_qwen_streaming_asr`

Run: `cd backend && ../.venv/bin/python -m scripts.test_asr_config`

Expected: all print `PASS`.

- [ ] **Step 6: Commit**

```bash
git add backend/core/asr/streaming.py backend/api/asr_stream.py backend/main.py backend/scripts/test_asr_stream_gateway.py
git commit -m "feat(backend): add authenticated asr stream gateway"
```

### Task 4: Flutter Audio and Gateway Session Service

**Files:**
- Create: `mobile/lib/voice_input/voice_input_models.dart`
- Create: `mobile/lib/voice_input/voice_audio_capture.dart`
- Create: `mobile/lib/voice_input/voice_gateway.dart`
- Create: `mobile/lib/voice_input/voice_input_service.dart`
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/pubspec.lock`
- Modify: `mobile/ios/Runner/Info.plist`
- Test: `mobile/test/voice_input/voice_input_service_test.dart`

**Interfaces:**
- Consumes: `AuthStore.token`, `AppConfig.apiBase`, record-plugin PCM stream, and gateway JSON/binary events.
- Produces: `VoiceInputService.start(VoiceInputMode) -> VoiceInputSession`, with no public initialize call; `VoiceInputSession.events`, `stop`, `cancel`, and `dispose`.

- [ ] **Step 1: Write pure-Dart service tests with injected capture/socket fakes**

Cover permission denial before socket allocation, `http` to `ws` and `https` to `wss` URI conversion, Authorization header, wait-for-ready before audio capture, exact start contract, `PcmFrameChunker(frameBytes: 6400)` ordering, trailing even-byte flush on stop, partial/stable/final parsing, malformed-event fail-closed behavior, old-session event suppression, and exactly-once capture/socket cleanup.

- [ ] **Step 2: Run the service test and verify RED**

Run: `cd mobile && flutter test test/voice_input/voice_input_service_test.dart`

Expected: FAIL because `VoiceInputService` is missing.

- [ ] **Step 3: Add raw PCM capture dependency**

Run: `cd mobile && flutter pub add record`

Replace the old `speech_to_text` dependency only after `flash_sheet.dart` is migrated in Task 6. Keep `NSMicrophoneUsageDescription`; remove `NSSpeechRecognitionUsageDescription` when no code imports Apple's speech recognizer.

- [ ] **Step 4: Implement the service behind testable interfaces**

```dart
abstract interface class VoiceAudioCapture {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startPcm16();
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class VoiceGatewayConnection {
  Stream<Object?> get events;
  void sendText(String value);
  void sendBytes(Uint8List value);
  Future<void> close();
}
```

The production recorder uses `AudioEncoder.pcm16bits`, sample rate 16000, and one channel. The production socket uses `dart:io WebSocket.connect` with `Authorization: Bearer <token>`. Never log payload content.

- [ ] **Step 5: Run GREEN and analyzer**

Run: `cd mobile && flutter test test/voice_input/voice_input_service_test.dart`

Run: `cd mobile && flutter analyze lib/voice_input test/voice_input`

Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/voice_input mobile/test/voice_input/voice_input_service_test.dart mobile/pubspec.yaml mobile/pubspec.lock mobile/ios/Runner/Info.plist
git commit -m "feat(mobile): stream microphone audio to asr gateway"
```

### Task 5: Shared Voice Text Controller and Field UI

**Files:**
- Create: `mobile/lib/voice_input/voice_input_controller.dart`
- Create: `mobile/lib/voice_input/voice_input_field.dart`
- Create: `mobile/lib/voice_input/voice_input_scope.dart`
- Test: `mobile/test/voice_input/voice_input_controller_test.dart`
- Test: `mobile/test/voice_input/voice_input_field_test.dart`

**Interfaces:**
- Consumes: `VoiceInputService`, a `VoiceInputTextController`, optional `FocusNode`, and ordinary/reka duration policy.
- Produces: process-wide mutual exclusion, snapshot/restore, provisional styling, warning/countdown state, and reusable microphone/cancel UI.

- [ ] **Step 1: Write controller RED tests**

Test insertion over a selected range, insertion at a collapsed cursor while preserving both sides, provisional replacement without duplication, ordered stable segments, stale sequence rejection, cancel/error/dispose exact snapshot restoration, final text style clearing, second-entry busy rejection, stop-final timeout, 270/300-second ordinary timers, and terminal completion exactly once.

- [ ] **Step 2: Run controller tests and verify RED**

Run: `cd mobile && flutter test test/voice_input/voice_input_controller_test.dart`

Expected: FAIL because `VoiceInputController` is missing.

- [ ] **Step 3: Implement controller and process-wide lease**

`VoiceInputTextController` subclasses `TextEditingController` and overrides `buildTextSpan` to draw only the current provisional range with a weaker foreground color. `VoiceInputLease` owns one active `voiceSessionId` process-wide. `VoiceInputController.start()` captures `TextEditingValue`, acquires the lease, starts the service, and freezes keyboard edits until final/cancel/failure releases the lease.

- [ ] **Step 4: Write widget RED tests**

Test microphone semantics, tap start/stop, visible cancel, disabled submit callback signal, provisional rendering, 30-second warning copy, busy copy when another field owns the microphone, and no invocation of the field's submit action.

- [ ] **Step 5: Implement `VoiceInputField` and run GREEN**

Run: `cd mobile && flutter test test/voice_input/voice_input_controller_test.dart test/voice_input/voice_input_field_test.dart`

Run: `cd mobile && flutter analyze lib/voice_input test/voice_input`

Expected: tests pass; analyzer clean.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/voice_input mobile/test/voice_input
git commit -m "feat(mobile): add shared voice input field"
```

### Task 6: Adopt Voice Input on User-Authored Text Surfaces

**Files:**
- Modify: `mobile/lib/theme_v2/session/theme_v2_session_page.dart`
- Modify: `mobile/lib/theme_v2/session/session_composer.dart`
- Modify: `mobile/lib/pages/chat_page.dart`
- Modify: `mobile/lib/pages/session_detail_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_create_sheet.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editor.dart`
- Modify: `mobile/lib/theme_v2/asset_detail/markdown_field_editor.dart`
- Modify: `mobile/lib/flash/flash_sheet.dart`
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/pubspec.lock`
- Test: matching existing widget tests plus `mobile/test/voice_input/voice_input_adoption_test.dart`

**Interfaces:**
- Consumes: `VoiceInputField` from Task 5.
- Produces: microphone dictation on Session Chat, legacy chat/session, report intent/additional focus/free-text clarification, Skill description/free-text other answer, markdown notes, and manual Flash input.

- [ ] **Step 1: Write adoption RED tests**

Use keys to assert each listed natural-language field renders the shared microphone. Drive one fake transcription through Session Chat, report creation, Skill description, and Markdown note; assert text changes but existing send/create/save callbacks remain untouched. Assert structured search, login, date, amount, and configuration fields do not gain microphones.

- [ ] **Step 2: Run adoption tests and verify RED**

Run: `cd mobile && flutter test test/voice_input/voice_input_adoption_test.dart`

Expected: FAIL because the fields still use plain `TextField`.

- [ ] **Step 3: Migrate fields without changing their business callbacks**

Replace eligible controllers with `VoiceInputTextController`, wrap eligible fields with `VoiceInputField`, and bind `voiceBusy` to existing submit-button enablement. Preserve every existing `onChanged`, max length, input action, focus behavior, and layout decoration. In `flash_sheet.dart`, delete `speech_to_text` and its custom listening overlay, then remove the dependency and iOS speech-recognition usage string.

- [ ] **Step 4: Run focused and full mobile tests**

Run: `cd mobile && flutter test test/voice_input test/theme_v2/session test/theme_v2/report test/theme_v2/library/create_skill`

Run: `cd mobile && flutter test`

Expected: all voice tests and all repository mobile tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib mobile/test/voice_input mobile/pubspec.yaml mobile/pubspec.lock mobile/ios/Runner/Info.plist
git commit -m "feat(mobile): add voice input to authoring fields"
```

### Task 7: Reka Long-Press Voice Flash

**Files:**
- Create: `mobile/lib/voice_input/reka_voice_capture.dart`
- Modify: `mobile/lib/pet/floating_mascot.dart`
- Modify: `mobile/lib/flash/flash.dart`
- Test: `mobile/test/voice_input/reka_voice_capture_test.dart`
- Test: `mobile/test/reka_mascot_nudge_test.dart`

**Interfaces:**
- Consumes: shared voice service/controller, Reka gesture callbacks, `sendFlash`.
- Produces: long-press start, live provisional bubble, 72-pixel upward cancel threshold, release-to-finalize, 60-second auto-finalize, and exactly one text Flash for a non-empty final.

- [ ] **Step 1: Write deterministic gesture and business RED tests**

Test haptic start, release before connection readiness, provisional bubble updates, crossing and leaving the cancel threshold, cancel release creates nothing, normal release waits for final then calls Flash once, empty/error/timeout creates nothing, 30-second warning, 60-second auto-stop, stale final ignored, and widget dispose cleanup. Inject a fake haptic callback, fake clock, fake service, and fake Flash sender.

- [ ] **Step 2: Run Reka tests and verify RED**

Run: `cd mobile && flutter test test/voice_input/reka_voice_capture_test.dart`

Expected: FAIL because `RekaVoiceCaptureCoordinator` is missing.

- [ ] **Step 3: Implement gesture coordination and overlay**

Replace the existing long-press “open latest Session” behavior with `onLongPressStart`, `onLongPressMoveUpdate`, and `onLongPressEnd`. Keep short tap radial-menu behavior and ordinary drag persistence unchanged. A move with `offsetFromOrigin.dy <= -72` enters cancel state and gives one transition haptic; release in that state cancels. Normal release calls stop and creates a Flash only from a non-empty final transcript.

- [ ] **Step 4: Run GREEN and regression suite**

Run: `cd mobile && flutter test test/voice_input/reka_voice_capture_test.dart test/reka_mascot_nudge_test.dart`

Run: `cd mobile && flutter test test/voice_input`

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/voice_input/reka_voice_capture.dart mobile/lib/pet/floating_mascot.dart mobile/lib/flash/flash.dart mobile/test/voice_input/reka_voice_capture_test.dart mobile/test/reka_mascot_nudge_test.dart
git commit -m "feat(mobile): create voice flashes from reka"
```

### Task 8: Live Verification, Packaging, and Rollout Guard

**Files:**
- Create: `backend/scripts/smoke_qwen_streaming_asr.py`
- Create: `docs/qwen-cloud-asr-device-verification.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: ignored root `.env`, physical iOS/Android devices, and a short in-memory PCM fixture recorded during the smoke command.
- Produces: reproducible live-provider, package, language, latency, cancellation, and privacy evidence without committing credentials or audio.

- [ ] **Step 1: Write the opt-in smoke contract test**

The smoke command refuses to run unless `RUN_LIVE_QWEN_ASR=1`, validates secrets without printing them, streams a caller-provided PCM path without copying it, prints only event types/timings/text length, and exits nonzero on missing `ready`/`final`. Its pure option/redaction helpers receive unit coverage in `backend/scripts/test_qwen_streaming_smoke.py`.

- [ ] **Step 2: Run all static and unit gates**

Run: `cd backend && ../.venv/bin/python -m scripts.test_asr_config && ../.venv/bin/python -m scripts.test_qwen_streaming_asr && ../.venv/bin/python -m scripts.test_asr_stream_gateway && ../.venv/bin/python -m scripts.test_qwen_streaming_smoke`

Run: `cd mobile && flutter test`

Run: `cd mobile && flutter analyze`

Expected: all tests pass and analyzer reports no issues.

- [ ] **Step 3: Build production-shaped mobile artifacts**

Run: `cd mobile && flutter build apk --release --split-per-abi`

Run: `cd mobile && flutter build ios --release --no-codesign`

Expected: Android ARM APKs and unsigned iOS release app build successfully; neither artifact contains `DASHSCOPE_API_KEY`, the workspace hostname, or a local ASR model.

- [ ] **Step 4: Run real backend and device acceptance**

Start the worktree backend with the main checkout's ignored env file, then test physical iOS and Android for Mandarin, English, mixed speech, short and five-minute ordinary dictation, Reka normal/cancel/60-second behavior, weak network, disconnect, backgrounding, and permissions. Record first-partial and final latencies; do not record serial numbers, raw audio, transcript bodies, or credentials in the document.

- [ ] **Step 5: Verify privacy and repository scope**

Run: `git grep -n "DASHSCOPE_API_KEY=" -- ':!*.example' ':!docs/**'`

Expected: no tracked real value.

Run: `git status --short` and `git diff --check`.

Expected: only planned files are changed and diff check is clean.

- [ ] **Step 6: Commit verification artifacts**

```bash
git add backend/scripts/smoke_qwen_streaming_asr.py backend/scripts/test_qwen_streaming_smoke.py docs/qwen-cloud-asr-device-verification.md README.md
git commit -m "test: verify qwen cloud voice input"
```

## Self-Review

- Spec coverage: provider decision, credentials, gateway security, normalized protocol, one active session, 60/300-second limits, ordinary edit-before-submit, Reka release/cancel, field inventory, no retention/retry, existing hardware isolation, and physical acceptance each map to a task.
- Placeholder scan: implementation steps contain exact model, variables, paths, messages, commands, and thresholds; no unresolved implementation placeholder remains.
- Type consistency: `StreamingAsrProvider` feeds `StreamingAsrGateway`; the gateway feeds `VoiceInputService`; `VoiceInputController` and `RekaVoiceCaptureCoordinator` consume the same service/session types; field and Reka outcomes remain separate.
