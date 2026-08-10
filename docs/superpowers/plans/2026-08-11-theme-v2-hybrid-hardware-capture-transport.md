# Theme V2 Hybrid Hardware Capture Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Chiplet Ring and W1/W2 card an immediate online capture experience plus acknowledgement-driven local-file recovery across screen-off, process loss, BLE loss, network loss, and supported phone-off scenarios.

**Architecture:** Keep the existing card file workflow and Theme V2 capture backend. Add a durable ring file workflow in which the hardware-local file is the recovery source of truth and live ring PCM is only a latency optimization; use stable device capture identity to make online submission and reconnect recovery exactly-once. Verify the vendor BLE foreground service before adding any App-owned Android service, and treat powered-off-phone ring recording as a hardware capability gate rather than an App assumption.

**Tech Stack:** Flutter/Dart, Android/Kotlin, Chiplet Ring BraveChip SDK, W1/W2 BLE SDK, SharedPreferences, FastAPI, Pydantic 2, SQLAlchemy 2 async, Alembic, MySQL 8, Pytest, Flutter Test, ADB, Docker Compose.

## Global Constraints

- Build and test only Theme V2; do not launch or validate the legacy mobile shell.
- Keep the independent `eureka-theme-v2` Docker runtime and existing MySQL job/outbox architecture.
- Do not add Redis, Kafka, Celery, a second capture backend, or backend audio streaming.
- Do not replace Tencent ASR, the capture Agent, MCP execution, Session persistence, or Asset creation.
- Preserve `正在聆听` for a real connected recording-start event.
- A recovered hardware file displays `正在同步离线闪念`, never a fake listening state.
- The ring’s 8 MB is a temporary safety buffer; never overwrite or delete an unacknowledged file.
- Delete hardware audio only after the phone has a usable transcript and Theme V2 has durably accepted that capture.
- A capture retry or reconnect must create exactly one recording, one Session input turn, one Agent run, and one set of Assets.
- Use the original hardware capture time for Session and Timeline semantics; discovery/reconnect time is only the final fallback.
- Do not claim powered-off-phone ring support unless the physical ring creates a complete file without a connected phone.
- Reuse the vendor `com.lm.sdk.BLEService` if it passes screen-off acceptance; add no parallel service without a failing device test.
- Android is the delivery platform for this slice; the Chiplet Ring plugin has no iOS implementation.
- Do not touch or stage unrelated existing mobile changes in the working tree.
- Commit only to `codex/theme-v2-ui-refactor`; do not merge into `main`.

---

## File Structure

### New mobile files

- `mobile/packages/chiplet_ring/lib/src/ring_file_event.dart` — typed device file, download, memory, and completion events.
- `mobile/lib/ring/ring_capability_probe.dart` — repeatable live/local/storage capability measurement.
- `mobile/lib/ring/ring_capture_task.dart` — durable ring capture state and stable identity.
- `mobile/lib/ring/ring_capture_store.dart` — authenticated-user-scoped task persistence.
- `mobile/lib/ring/ring_file_gateway.dart` — serial typed wrapper around file list/download/delete SDK commands.
- `mobile/lib/ring/ring_file_workflow.dart` — file association, recovery, ASR, backend acceptance, and deletion.
- `mobile/test/ring/ring_capability_probe_test.dart` — capability calculation and probe state tests.
- `mobile/test/ring/ring_capture_task_test.dart` — serialization and stable-key tests.
- `mobile/test/ring/ring_capture_store_test.dart` — user scoping and restart recovery tests.
- `mobile/test/ring/ring_file_gateway_test.dart` — event correlation, timeout, and serial-operation tests.
- `mobile/test/ring/ring_file_workflow_test.dart` — online/reconnect/retry/deletion workflow tests.

### Modified mobile files

- `mobile/packages/chiplet_ring/lib/src/models.dart` — export/use typed ring file models.
- `mobile/packages/chiplet_ring/lib/src/ring_platform.dart` — expose typed file events and command results.
- `mobile/packages/chiplet_ring/lib/chiplet_ring.dart` — public typed file/capability API.
- `mobile/packages/chiplet_ring/android/src/main/kotlin/com/eureka/chiplet_ring/ChipletRingPlugin.kt` — tag file operations, expose memory and recording acknowledgements, and preserve operation identity.
- `mobile/packages/chiplet_ring/test/ring_platform_test.dart` — native method-channel contract.
- `mobile/lib/pages/ring_debug_page.dart` — developer-only capability probe controls and measured results.
- `mobile/lib/ring/ring_capture_controller.dart` — hybrid start/stop and live-frame quality tracking.
- `mobile/lib/ring/ring_capture_service.dart` — production workflow composition and startup recovery.
- `mobile/lib/ring/ring_reconnect.dart` — trigger ring-file scan after a successful reconnect.
- `mobile/lib/ring/ring_asr.dart` — accept a stable output path and clean up acknowledged local files.
- `mobile/lib/flash/flash.dart` — send trusted ring transport provenance.
- `mobile/lib/capture_activity/capture_activity_event.dart` — retain truthful realtime/offline source metadata.
- `mobile/lib/theme_v2/capture/capture_activity_models.dart` — offline-sync copy.
- `mobile/lib/main.dart` and `mobile/lib/auth/auth_controller.dart` — start/stop durable ring recovery with the authenticated lifecycle.
- `mobile/test/ring/ring_capture_controller_test.dart` — dual-path/local-first/fallback behavior.
- `mobile/test/ring/ring_reconnect_test.dart` — reconnect-to-file-scan behavior.
- `mobile/test/flash_file_task_test.dart` — card realtime/offline presentation parity.
- `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart` — monotonic identity merge with recovered ring tasks.
- `mobile/test/theme_v2/capture/capture_activity_top_bar_test.dart` — online listening and offline-sync copy.

### New backend files

- `theme_v2_service/migrations/versions/0021_capture_device_identity.py` — owner-scoped stable device-capture identity and ring provenance columns.

### Modified backend files

- `theme_v2_service/app/domains/capture/models.py` — persist `device_capture_key`, device identity, and ring audio provenance.
- `theme_v2_service/app/domains/capture/schemas.py` — optional trusted provenance on `FlashRequest`.
- `theme_v2_service/app/domains/capture/service.py` — idempotent lookup/conflict checks and original capture timestamps.
- `theme_v2_service/tests/contract/test_capture_api.py` — duplicate, conflict, provenance, and delayed-reconnect contracts.

### Conditional Android files

Create these files only if Task 1 proves that the existing vendor
`com.lm.sdk.BLEService` does not keep the required Flutter callbacks/task writes
alive with the screen off:

- `mobile/android/app/src/main/kotlin/com/eureka/mindapp/CaptureKeepAliveService.kt` — minimal connected-device foreground keep-alive.
- `mobile/lib/capture_activity/capture_background_keep_alive.dart` — typed MethodChannel lifecycle wrapper.
- `mobile/test/capture_background_keep_alive_test.dart` — start/stop/auth lifecycle contract.

---

### Task 1: Prove the physical ring capability matrix

**Files:**
- Create: `mobile/packages/chiplet_ring/lib/src/ring_file_event.dart`
- Create: `mobile/lib/ring/ring_capability_probe.dart`
- Create: `mobile/test/ring/ring_capability_probe_test.dart`
- Modify: `mobile/packages/chiplet_ring/lib/src/ring_platform.dart`
- Modify: `mobile/packages/chiplet_ring/lib/chiplet_ring.dart`
- Modify: `mobile/packages/chiplet_ring/android/src/main/kotlin/com/eureka/chiplet_ring/ChipletRingPlugin.kt`
- Modify: `mobile/packages/chiplet_ring/test/ring_platform_test.dart`
- Modify: `mobile/lib/pages/ring_debug_page.dart`
- Modify after measurement: `docs/superpowers/specs/2026-08-11-theme-v2-hybrid-hardware-capture-transport-design.md`

**Interfaces:**
- Produces `RingFileEvent.fromMap(Map<Object?, Object?>)` with typed `item`, `audio`, `done`, `deleted`, `memory`, `memoryFull`, and `recordingAck` variants.
- Produces `RingCapabilityProbe.runConnectedProbe()` returning `RingCapabilityReport`.
- Produces measured `connectedMode` equal to `dualPath` only when live PCM and the downloaded local file are both valid.
- Produces a recorded `autonomousOfflineCapture` physical result; it is evidence, not a guessed runtime flag.

- [ ] **Step 1: Write failing typed-event and measurement tests**

```dart
test('file item retains the SDK id needed for download and delete', () {
  final event = RingFileEvent.fromMap({
    'kind': 'item',
    'name': 'R0001.bin',
    'size': 245760,
    'id': [1, 2, 3, 4],
  });

  expect(event, isA<RingFileItemEvent>());
  final item = (event as RingFileItemEvent).file;
  expect(item.name, 'R0001.bin');
  expect(item.sizeBytes, 245760);
  expect(item.id, [1, 2, 3, 4]);
});

test('capacity report uses measurements rather than a codec constant', () {
  final report = RingCapabilityReport.fromSamples(
    usableBytes: 8 * 1024 * 1024,
    samples: const [
      RingStorageSample(duration: Duration(seconds: 30), bytes: 120000),
      RingStorageSample(duration: Duration(seconds: 60), bytes: 240000),
      RingStorageSample(duration: Duration(seconds: 120), bytes: 480000),
    ],
    livePcmValid: true,
    localFileValid: true,
  );

  expect(report.bytesPerSecond, 4000);
  expect(report.connectedMode, RingConnectedCaptureMode.dualPath);
});
```

- [ ] **Step 2: Run the tests and confirm they fail before the typed API exists**

Run:

```bash
cd mobile
flutter test packages/chiplet_ring/test/ring_platform_test.dart test/ring/ring_capability_probe_test.dart
```

Expected: FAIL because `RingFileEvent`, `RingCapabilityReport`, and typed file-event APIs do not exist.

- [ ] **Step 3: Add the typed Dart file-event contract**

```dart
enum RingFileEventKind {
  item,
  audio,
  done,
  deleted,
  memory,
  memoryFull,
  recordingAck,
  empty,
}

@immutable
class RingFileRef {
  const RingFileRef({
    required this.name,
    required this.id,
    required this.sizeBytes,
  });

  final String name;
  final List<int> id;
  final int sizeBytes;

  String get identityMaterial => '$name:$sizeBytes:${id.join("-")}';
}

sealed class RingFileEvent {
  const RingFileEvent(this.operationId);
  final String operationId;

  factory RingFileEvent.fromMap(Map<Object?, Object?> raw) {
    final operationId = raw['operationId']?.toString() ?? '';
    return switch (raw['kind']) {
      'item' => RingFileItemEvent(
          operationId,
          RingFileRef(
            name: raw['name']?.toString() ?? '',
            id: List<int>.from(raw['id'] as List? ?? const []),
            sizeBytes: (raw['size'] as num?)?.toInt() ?? 0,
          ),
        ),
      'audio' => RingFileAudioEvent(
          operationId,
          Uint8List.fromList(List<int>.from(raw['pcm'] as List? ?? const [])),
        ),
      'done' => RingFileDoneEvent(operationId),
      'deleted' => RingFileDeletedEvent(operationId, raw['ok'] == true),
      'memory' => RingMemoryEvent(
          operationId,
          (raw['state'] as num?)?.toInt() ?? -1,
        ),
      'memoryFull' => RingMemoryFullEvent(operationId),
      'recordingAck' => RingRecordingAckEvent(
          operationId,
          raw['active'] == true,
          raw['ok'] == true,
        ),
      _ => RingFileEmptyEvent(operationId),
    };
  }
}
```

Export the types from `chiplet_ring.dart`, change `fileEvents` to
`Stream<RingFileEvent>`, and retain one broadcast EventChannel subscription.

- [ ] **Step 4: Tag every native file operation and recording acknowledgement**

Pass an `operationId` from Dart on `getFileList`, `downloadFile`, `deleteFile`,
`startLocalRecording`, and `stopLocalRecording`. Echo it on every native event
for that operation. Serialize native SDK callbacks through one active operation
so a late `done` from a previous download cannot complete a later request.

```kotlin
private var activeFileOperationId: String = ""

private fun fileEvent(kind: String, values: Map<String, Any?> = emptyMap()) {
    val payload = HashMap<String, Any?>()
    payload["kind"] = kind
    payload["operationId"] = activeFileOperationId
    payload.putAll(values)
    main.post { fileSink?.success(payload) }
}
```

Do not log PCM, file bytes, or transcript content.

- [ ] **Step 5: Implement the connected probe and debug controls**

`RingCapabilityProbe.runConnectedProbe()` must:

1. snapshot the file list and memory state;
2. start local recording;
3. start live streaming;
4. collect live frames and sequence gaps for a fixed 30-second spoken sample;
5. stop live and local recording;
6. identify exactly one newly created file;
7. download it and validate non-empty PCM;
8. return measured file bytes, live bytes, frame-gap count, and selected mode;
9. leave the probe file on the ring until the operator explicitly deletes it.

Expose buttons in `RingDebugPage` for `30 秒双通道测试`, `读取存储`, and
`扫描本地文件`. Do not expose formatting as part of the probe.

- [ ] **Step 6: Run the automated probe tests**

Run:

```bash
cd mobile
dart format packages/chiplet_ring/lib lib/ring/ring_capability_probe.dart test/ring/ring_capability_probe_test.dart
flutter test packages/chiplet_ring/test/ring_platform_test.dart test/ring/ring_capability_probe_test.dart
flutter analyze packages/chiplet_ring/lib lib/ring/ring_capability_probe.dart lib/pages/ring_debug_page.dart
```

Expected: PASS with no analyzer issues.

- [ ] **Step 7: Execute and record the physical matrix**

Run the Theme V2 build on the known Android target:

```bash
cd mobile
flutter run -d RFCY71B21YK
```

Measure 30-, 60-, and 120-second local recordings. Then perform the simultaneous
probe. Finally power the phone fully off, use the ring’s intended start/stop
gesture, power the phone on, reconnect, and inspect whether exactly one complete
new file exists.

Append a `Physical Capability Results` section to the design spec containing:

```text
device firmware/hardware version
usable bytes
30/60/120 second file sizes
measured bytes per second
live + local coexistence: pass/fail
screen-off callback/task persistence: pass/fail
powered-off-phone autonomous file creation: pass/fail
selected connected mode: dualPath/localFirst
firmware blocker required: yes/no
```

The implementation must use `localFirst` when simultaneous mode fails. The
phone-off acceptance gate remains open when autonomous file creation fails.

- [ ] **Step 8: Commit the capability foundation and measured decision**

```bash
git add mobile/packages/chiplet_ring mobile/lib/ring/ring_capability_probe.dart mobile/lib/pages/ring_debug_page.dart mobile/test/ring/ring_capability_probe_test.dart docs/superpowers/specs/2026-08-11-theme-v2-hybrid-hardware-capture-transport-design.md
git commit -m "test: characterize ring capture transport"
```

---

### Task 2: Add backend stable device-capture identity

**Files:**
- Create: `theme_v2_service/migrations/versions/0021_capture_device_identity.py`
- Modify: `theme_v2_service/app/domains/capture/models.py`
- Modify: `theme_v2_service/app/domains/capture/schemas.py`
- Modify: `theme_v2_service/app/domains/capture/service.py`
- Modify: `theme_v2_service/tests/contract/test_capture_api.py`

**Interfaces:**
- Extends `FlashRequest` with optional `device_capture_key`, `device_kind`, `device_id`, `device_file_name`, `capture_started_at`, `capture_ended_at`, `local_audio_sha256`, and `local_audio_size_bytes`.
- Produces owner-scoped uniqueness on `(user_id, device_capture_key)` when the key is non-null.
- Preserves the existing `/api/flash` response and Agent execution contract.

- [ ] **Step 1: Write failing duplicate/provenance contract tests**

```python
async def test_ring_reconnect_reuses_device_capture_key(client):
    token = await _register(client, "ring-idempotency@example.com")
    payload = {
        "text": "明天下午去跑步",
        "source": "voice",
        "client_task_id": "ring-online-provisional-1",
        "device_capture_key": "ring:AA-BB:R0001.bin:240000:01-02",
        "device_kind": "ring",
        "device_id": "AA:BB",
        "device_file_name": "R0001.bin",
        "capture_started_at": "2026-08-11T08:30:00+08:00",
        "capture_ended_at": "2026-08-11T08:30:12+08:00",
        "local_audio_sha256": "a" * 64,
        "local_audio_size_bytes": 240000,
    }

    first = await client.post("/api/flash", headers=_headers(token), json=payload)
    duplicate = await client.post(
        "/api/flash",
        headers=_headers(token),
        json={**payload, "client_task_id": "ring-recovered-1"},
    )

    assert first.status_code == 200
    assert duplicate.status_code == 200
    assert duplicate.json()["recording_id"] == first.json()["recording_id"]


async def test_ring_device_capture_key_rejects_different_transcript(client):
    token = await _register(client, "ring-conflict@example.com")
    payload = {
        "text": "喝了五百毫升水",
        "source": "voice",
        "client_task_id": "ring-first",
        "device_capture_key": "ring:AA-BB:R0002.bin:200000:03-04",
        "device_kind": "ring",
        "device_id": "AA:BB",
        "device_file_name": "R0002.bin",
    }
    assert (await client.post("/api/flash", headers=_headers(token), json=payload)).status_code == 200
    conflict = await client.post(
        "/api/flash",
        headers=_headers(token),
        json={**payload, "client_task_id": "ring-second", "text": "完全不同的内容"},
    )
    assert conflict.status_code == 409
```

Also assert `capture_started_at`, device identity, hash, and size are persisted.

- [ ] **Step 2: Run the focused backend tests and verify failure**

Run:

```bash
cd theme_v2_service
python -m pytest -q tests/contract/test_capture_api.py -k "device_capture_key or ring_reconnect"
```

Expected: FAIL because `FlashRequest` ignores/rejects the new contract and the
recording model has no stable device key.

- [ ] **Step 3: Add the migration and model fields**

```python
device_capture_key: Mapped[str | None] = mapped_column(String(255))
device_kind: Mapped[str | None] = mapped_column(String(32))
device_id: Mapped[str | None] = mapped_column(String(160))
```

Add this constraint to `CaptureRecording.__table_args__` and migration `0021`:

```python
sa.UniqueConstraint(
    "user_id",
    "device_capture_key",
    name="uq_capture_recordings_user_device_capture",
)
```

The migration only adds nullable columns and the unique constraint; it does not
backfill test recordings or rewrite card identity.

- [ ] **Step 4: Extend and validate `FlashRequest`**

```python
class FlashRequest(BaseModel):
    text: str = Field(min_length=1)
    session_id: str = ""
    source: Literal["voice", "typed", "imported"] = "voice"
    capture_session_type: str = ""
    file_id: str = ""
    client_task_id: str = Field(default="", max_length=160)
    device_capture_key: str = Field(default="", max_length=255)
    device_kind: Literal["", "ring", "card", "phone"] = ""
    device_id: str = Field(default="", max_length=160)
    device_file_name: str = Field(default="", max_length=255)
    capture_started_at: TimestampInput = None
    capture_ended_at: TimestampInput = None
    local_audio_sha256: str | None = Field(
        default=None,
        pattern=r"^[0-9a-fA-F]{64}$",
    )
    local_audio_size_bytes: int | None = Field(default=None, gt=0)
```

Strip all optional string fields. Do not accept a model-selected user id,
Session id, or backend recording id.

- [ ] **Step 5: Make text-capture acceptance idempotent by either trusted key**

Look up the authenticated user’s existing record by `client_task_id` first, then
by non-empty `device_capture_key`. If either resolves, require the same text,
device identity, and audio hash when supplied; return the existing recording.

```python
identity_conditions = [CaptureRecording.client_task_id == client_task_id]
if device_capture_key is not None:
    identity_conditions.append(
        CaptureRecording.device_capture_key == device_capture_key
    )
existing = await session.scalar(
    select(CaptureRecording).where(
        CaptureRecording.user_id == user_id,
        or_(*identity_conditions),
    )
)
```

For a new recording, persist `_parse_timestamp(command.capture_started_at)`,
`_parse_timestamp(command.capture_ended_at)`, the stable device fields, and
audio hash/size. Preserve `audio_format="text"` and `asr_mode="text_client"` so
this change does not create a second ASR path.

- [ ] **Step 6: Run migration, contract, and capture-job tests**

Run:

```bash
cd theme_v2_service
python -m pytest -q tests/contract/test_capture_api.py tests/integration/test_capture_jobs.py
alembic upgrade head
alembic downgrade 0020_capture_root_mutation_key
alembic upgrade head
```

Expected: all tests PASS and the migration round-trip succeeds.

- [ ] **Step 7: Commit the backend identity boundary**

```bash
git add theme_v2_service/app/domains/capture theme_v2_service/migrations/versions/0021_capture_device_identity.py theme_v2_service/tests/contract/test_capture_api.py
git commit -m "feat: make hardware captures idempotent by device file"
```

---

### Task 3: Persist recoverable ring capture tasks

**Files:**
- Create: `mobile/lib/ring/ring_capture_task.dart`
- Create: `mobile/lib/ring/ring_capture_store.dart`
- Create: `mobile/test/ring/ring_capture_task_test.dart`
- Create: `mobile/test/ring/ring_capture_store_test.dart`

**Interfaces:**
- Produces `RingCaptureStage`, `RingCaptureTask`, and `ringDeviceCaptureKey(...)`.
- Produces `RingCaptureStore.load(userId)`, `upsert(userId, task)`, and `remove(userId, taskId)`.
- Stores metadata and local paths, never PCM bytes in SharedPreferences.

- [ ] **Step 1: Write failing serialization, identity, and user-scope tests**

```dart
test('ring device key is stable across reconnect attempts', () {
  final first = ringDeviceCaptureKey(
    deviceId: 'AA:BB',
    fileName: 'R0001.bin',
    fileId: const [1, 2, 3],
    sizeBytes: 240000,
  );
  final second = ringDeviceCaptureKey(
    deviceId: 'AA:BB',
    fileName: 'R0001.bin',
    fileId: const [1, 2, 3],
    sizeBytes: 240000,
  );
  expect(second, first);
});

test('store restores only the authenticated users tasks', () async {
  SharedPreferences.setMockInitialValues({});
  final store = SharedPreferencesRingCaptureStore();
  await store.upsert('user-a', ringTask(id: 'a'));
  await store.upsert('user-b', ringTask(id: 'b'));

  expect((await store.load('user-a')).map((e) => e.id), ['a']);
  expect((await store.load('user-b')).map((e) => e.id), ['b']);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd mobile
flutter test test/ring/ring_capture_task_test.dart test/ring/ring_capture_store_test.dart
```

Expected: FAIL because the task and store types do not exist.

- [ ] **Step 3: Implement the durable task model**

```dart
enum RingCaptureStage {
  provisional,
  recording,
  fileAssociated,
  downloading,
  downloaded,
  transcribing,
  submitting,
  accepted,
  deletingDeviceFile,
  done,
  failed,
}

@immutable
class RingCaptureTask {
  const RingCaptureTask({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.stage,
    required this.startedAt,
    required this.updatedAt,
    this.endedAt,
    this.fileName,
    this.fileId = const [],
    this.deviceSizeBytes,
    this.deviceCaptureKey,
    this.localWavPath,
    this.localAudioSha256,
    this.localAudioSizeBytes,
    this.transcript,
    this.recordingId,
    this.sessionId,
    this.inputTurnId,
    this.deletePending = false,
    this.lastErrorCode,
  });

  final String id;
  final String userId;
  final String deviceId;
  final RingCaptureStage stage;
  final DateTime startedAt;
  final DateTime updatedAt;
  final DateTime? endedAt;
  final String? fileName;
  final List<int> fileId;
  final int? deviceSizeBytes;
  final String? deviceCaptureKey;
  final String? localWavPath;
  final String? localAudioSha256;
  final int? localAudioSizeBytes;
  final String? transcript;
  final String? recordingId;
  final String? sessionId;
  final String? inputTurnId;
  final bool deletePending;
  final String? lastErrorCode;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'deviceId': deviceId,
    'stage': stage.name,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'fileName': fileName,
    'fileId': fileId,
    'deviceSizeBytes': deviceSizeBytes,
    'deviceCaptureKey': deviceCaptureKey,
    'localWavPath': localWavPath,
    'localAudioSha256': localAudioSha256,
    'localAudioSizeBytes': localAudioSizeBytes,
    'transcript': transcript,
    'recordingId': recordingId,
    'sessionId': sessionId,
    'inputTurnId': inputTurnId,
    'deletePending': deletePending,
    'lastErrorCode': lastErrorCode,
  };
}
```

Use SHA-256 of normalized device kind/id/file name/file id/size for
`device_capture_key`; never include transcript text.

`fromJson` must require non-empty `id`, `userId`, and `deviceId`; parse the
stage with `RingCaptureStage.values.byName`; parse all timestamps as UTC; copy
the integer file-id list; and reject an entry whose stage or required timestamp
cannot be parsed. `copyWith` must expose every field above and use an explicit
sentinel for nullable fields so recovery can clear `lastErrorCode` after a
successful retry.

- [ ] **Step 4: Implement authenticated, atomic SharedPreferences persistence**

Use key `ring_capture_tasks_v1:<trimmed user id>`. Serialize the whole immutable
task list only after updating an in-memory map, and reject an empty user id.
`load` must ignore malformed individual entries but must not erase them until a
subsequent successful write.

- [ ] **Step 5: Run tests, format, and analyze**

Run:

```bash
cd mobile
dart format lib/ring/ring_capture_task.dart lib/ring/ring_capture_store.dart test/ring/ring_capture_task_test.dart test/ring/ring_capture_store_test.dart
flutter test test/ring/ring_capture_task_test.dart test/ring/ring_capture_store_test.dart
flutter analyze lib/ring/ring_capture_task.dart lib/ring/ring_capture_store.dart
```

Expected: PASS.

- [ ] **Step 6: Commit the durable task store**

```bash
git add mobile/lib/ring/ring_capture_task.dart mobile/lib/ring/ring_capture_store.dart mobile/test/ring/ring_capture_task_test.dart mobile/test/ring/ring_capture_store_test.dart
git commit -m "feat: persist recoverable ring capture tasks"
```

---

### Task 4: Build the serial ring file recovery workflow

**Files:**
- Create: `mobile/lib/ring/ring_file_gateway.dart`
- Create: `mobile/lib/ring/ring_file_workflow.dart`
- Create: `mobile/test/ring/ring_file_gateway_test.dart`
- Create: `mobile/test/ring/ring_file_workflow_test.dart`
- Modify: `mobile/lib/ring/ring_asr.dart`
- Modify: `mobile/lib/flash/flash.dart`

**Interfaces:**
- Produces `RingFileGateway.listFiles()`, `download(file)`, and `delete(file)` with one operation in flight.
- Produces `RingFileWorkflow.start(userId, deviceId)`, `scanAndRecover()`, `associateNewFile(taskId, baseline)`, and `stop()`.
- Extends `sendFlash` with a `FlashCaptureProvenance` value object.

- [ ] **Step 1: Write failing gateway correlation and workflow recovery tests**

```dart
test('late done from an old download cannot complete the active download', () async {
  final native = FakeRingFileNative();
  final gateway = RingFileGateway(native: native);
  final first = gateway.download(fileRef(name: 'R1.bin', id: [1]));
  native.emit(RingFileAudioEvent(native.activeOperationId, Uint8List(8)));
  native.emit(RingFileDoneEvent(native.activeOperationId));
  expect((await first).length, 8);

  final second = gateway.download(fileRef(name: 'R2.bin', id: [2]));
  native.emit(RingFileDoneEvent('old-operation'));
  expect(second, doesNotComplete);
  native.emit(RingFileAudioEvent(native.activeOperationId, Uint8List(16)));
  native.emit(RingFileDoneEvent(native.activeOperationId));
  expect((await second).length, 16);
});

test('backend acceptance precedes ring file deletion', () async {
  final log = <String>[];
  final workflow = ringWorkflow(
    transcribe: (_) async { log.add('asr'); return '喝了五百毫升水'; },
    submit: (_) async { log.add('accepted'); return acceptedFlash(); },
    delete: (_) async { log.add('deleted'); return true; },
  );
  await workflow.recover(fileRef(name: 'R1.bin', id: [1]));
  expect(log, ['asr', 'accepted', 'deleted']);
});
```

Add tests for network failure retaining the file, ASR failure retaining the
file, `deletePending` after disconnect, empty PCM, memory-full, and duplicate
scan callbacks.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd mobile
flutter test test/ring/ring_file_gateway_test.dart test/ring/ring_file_workflow_test.dart
```

Expected: FAIL because no ring file workflow exists.

- [ ] **Step 3: Implement the serial file gateway**

The gateway subscribes once to typed `fileEvents`, generates a UUID-like local
operation id, ignores events with other ids, uses a 15-second list timeout and a
60-second download timeout, and refuses a second concurrent operation.

```dart
abstract interface class RingFileNative {
  Stream<RingFileEvent> get fileEvents;
  Future<void> getFileList(String operationId);
  Future<void> downloadFile(String operationId, RingFileRef file);
  Future<void> deleteFile(String operationId, RingFileRef file);
}

class RingFileGateway {
  Future<List<RingFileRef>> listFiles();
  Future<Uint8List> download(RingFileRef file);
  Future<bool> delete(RingFileRef file);
}
```

File listing completes when the SDK-reported item count is reached, on a typed
empty event, or on the matching `done`; it deduplicates by `identityMaterial`.

- [ ] **Step 4: Extend `sendFlash` with trusted transport provenance**

```dart
@immutable
class FlashCaptureProvenance {
  const FlashCaptureProvenance({
    required this.deviceCaptureKey,
    required this.deviceKind,
    required this.deviceId,
    required this.deviceFileName,
    required this.localAudioSha256,
    required this.localAudioSizeBytes,
    this.captureStartedAt,
    this.captureEndedAt,
  });

  final String deviceCaptureKey;
  final String deviceKind;
  final String deviceId;
  final String deviceFileName;
  final DateTime? captureStartedAt;
  final DateTime? captureEndedAt;
  final String localAudioSha256;
  final int localAudioSizeBytes;
}
```

Serialize UTC ISO-8601 timestamps and lowercase SHA-256. Existing typed/manual
callers omit provenance and retain their current request shape.

- [ ] **Step 5: Implement recovery from one ring file**

For every newly discovered, unacknowledged file:

1. derive the stable device key;
2. upsert a `fileAssociated` task;
3. publish offline `receiving` activity;
4. download decoded 8 kHz mono PCM;
5. write a stable WAV under application support, not the temporary directory;
6. hash the WAV and persist path/hash/size before ASR;
7. run `RingAsr` and persist transcript before HTTP;
8. call `sendFlash` with provenance and deterministic client task id;
9. persist returned recording/Session/turn ids;
10. delete the ring file only after `FlashResult.ok == true`;
11. keep `deletePending` and retry deletion without resubmission when needed.

All tasks run serially because the SDK exposes one untagged hardware file
channel. Workflow errors are classified into stable local codes and never log
audio or transcript bodies.

- [ ] **Step 6: Implement baseline/new-file association**

`associateNewFile` compares a pre-recording file snapshot to a post-stop
snapshot. Exactly one added identity is associated with the provisional online
task. Zero additions leaves the task recoverable and schedules another scan.
Multiple additions are processed independently as offline files; none is
deleted based on timing guesses.

- [ ] **Step 7: Run all ring file tests**

Run:

```bash
cd mobile
dart format lib/ring lib/flash/flash.dart test/ring
flutter test test/ring/ring_asr_test.dart test/ring/ring_capture_task_test.dart test/ring/ring_capture_store_test.dart test/ring/ring_file_gateway_test.dart test/ring/ring_file_workflow_test.dart
flutter analyze lib/ring lib/flash/flash.dart
```

Expected: PASS with no analyzer issues.

- [ ] **Step 8: Commit the ring file recovery workflow**

```bash
git add mobile/lib/ring mobile/lib/flash/flash.dart mobile/test/ring
git commit -m "feat: recover ring captures from device files"
```

---

### Task 5: Make connected ring capture hybrid and failure-safe

**Files:**
- Modify: `mobile/lib/ring/ring_capture_controller.dart`
- Modify: `mobile/lib/ring/ring_capture_service.dart`
- Modify: `mobile/lib/ring/ring_reconnect.dart`
- Modify: `mobile/lib/main.dart`
- Modify: `mobile/lib/auth/auth_controller.dart`
- Modify: `mobile/test/ring/ring_capture_controller_test.dart`
- Modify: `mobile/test/ring/ring_reconnect_test.dart`

**Interfaces:**
- `RingCaptureController` consumes the measured `RingConnectedCaptureMode`.
- `RingFileWorkflow.beginOnlineCapture` persists before issuing hardware commands.
- `RingFileWorkflow.finishOnlineCapture` associates the safety file, validates live PCM, and chooses fast path or file fallback.
- A successful reconnect invokes `scanAndRecover()` once after connection stabilization.

- [ ] **Step 1: Write failing dual-path, local-first, frame-gap, and start-error tests**

```dart
test('dual path persists and starts local before live streaming', () async {
  final order = <String>[];
  final controller = ringController(
    mode: RingConnectedCaptureMode.dualPath,
    persistBegin: () async => order.add('persist'),
    startLocal: () async => order.add('local'),
    startLive: () async => order.add('live'),
  );
  await controller.debugBegin();
  expect(order, ['persist', 'local', 'live']);
});

test('a live sequence gap falls back to the associated local file', () async {
  final sources = <String>[];
  final controller = ringController(
    finishWithLive: (_) async => sources.add('live'),
    finishWithFile: (_) async => sources.add('file'),
  );
  await controller.debugBegin();
  controller.debugAddFrame(frame(seq: 1));
  controller.debugAddFrame(frame(seq: 3));
  await controller.debugStop();
  expect(sources, ['file']);
});
```

Also cover: local start failure aborts safely; live start failure in dual mode
continues local-first; empty live buffer falls back to file; second click during
finish is ignored; a later capture still works after a failed attempt.

- [ ] **Step 2: Run the controller and reconnect tests and verify failure**

Run:

```bash
cd mobile
flutter test test/ring/ring_capture_controller_test.dart test/ring/ring_reconnect_test.dart
```

Expected: FAIL against the current memory-only controller.

- [ ] **Step 3: Refactor start into a durable ordered handshake**

The first double-click must execute:

```text
persist provisional task
-> snapshot device files
-> start local safety recording
-> start live stream only in measured dualPath mode
-> publish listening
```

Do not swallow `_startRecording` errors. If local start fails, publish a
turn-local recoverable failure and reset the controller. If live start fails
after local succeeds, retain the task and continue in local-first mode.

- [ ] **Step 4: Refactor stop into one idempotent finalization**

The second double-click must stop whichever modes started, drain live frames,
persist end time, associate a new device file, and then call
`finishOnlineCapture`. Track the first frame sequence and every gap. Live PCM is
eligible only when it is non-empty and has zero sequence gaps; otherwise use the
downloaded file.

Both routes submit with the associated stable device key. A live-path ASR result
does not delete the safety file until backend acceptance.

- [ ] **Step 5: Start and stop workflow ownership with authentication**

`startRingCapture(ApiClient, userId)` starts reconnect plus durable file
workflow exactly once for that user. Logout calls `stopRingCapture`, cancels
subscriptions, closes the workflow, and clears only in-memory state; persisted
unacknowledged tasks remain user-scoped for the next login.

- [ ] **Step 6: Trigger recovery after reconnect**

Add an `onConnected` callback to `RingReconnect` that fires only on a transition
from not-connected to connected, after the token handshake reports success.
Wire it to `RingFileWorkflow.scanAndRecover()`. Coalesce repeated connected
events so they do not create parallel scans.

- [ ] **Step 7: Run focused mobile tests**

Run:

```bash
cd mobile
dart format lib/ring lib/main.dart lib/auth/auth_controller.dart test/ring
flutter test test/ring/ring_capture_controller_test.dart test/ring/ring_reconnect_test.dart test/ring/ring_file_workflow_test.dart
flutter analyze lib/ring lib/main.dart lib/auth/auth_controller.dart
```

Expected: PASS.

- [ ] **Step 8: Commit the connected hybrid path**

```bash
git add mobile/lib/ring mobile/lib/main.dart mobile/lib/auth/auth_controller.dart mobile/test/ring
git commit -m "feat: make ring capture hybrid and recoverable"
```

---

### Task 6: Align card/ring presentation and restart recovery

**Files:**
- Modify: `mobile/lib/capture_activity/capture_activity_event.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_activity_models.dart`
- Modify: `mobile/lib/ring/ring_file_workflow.dart`
- Modify: `mobile/lib/ble_flash/flash_file_workflow.dart` only if a failing parity test requires it
- Modify: `mobile/test/flash_file_task_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_activity_top_bar_test.dart`
- Modify: `mobile/test/theme_v2/capture/capture_session_realtime_test.dart`

**Interfaces:**
- Online ring/card uses `isRealtime=true` and begins at `listening`.
- Recovered ring/card uses `isRealtime=false` and `receiving` renders as `正在同步离线闪念`.
- Local task aliases merge into backend recording aliases without duplicate top bars or Session transient rows.

- [ ] **Step 1: Write failing online/offline copy and merge tests**

```dart
test('offline hardware receiving uses truthful recovery copy', () {
  final item = CaptureActivityItem(
    aliases: const {'device-file:R0001.bin'},
    source: CaptureActivitySource.ring,
    phase: CaptureActivityPhase.receiving,
    isRealtime: false,
    occurredAt: DateTime.utc(2026, 8, 11),
  );
  expect(item.statusLabel, '正在同步离线闪念');
});

test('connected recording still begins with listening', () {
  final item = CaptureActivityItem(
    aliases: const {'client:ring-online'},
    source: CaptureActivitySource.ring,
    phase: CaptureActivityPhase.listening,
    isRealtime: true,
    occurredAt: DateTime.utc(2026, 8, 11),
  );
  expect(item.statusLabel, '正在聆听');
});
```

Add a coordinator test that merges provisional, device-file, client-task, and
recording aliases into one activity and never regresses from terminal state.

- [ ] **Step 2: Run the presentation tests and verify the offline copy fails**

Run:

```bash
cd mobile
flutter test test/flash_file_task_test.dart test/theme_v2/capture/capture_activity_coordinator_test.dart test/theme_v2/capture/capture_activity_top_bar_test.dart test/theme_v2/capture/capture_session_realtime_test.dart
```

Expected: at least the offline-copy assertion FAILS with `正在接收`.

- [ ] **Step 3: Implement source-aware copy without a new workflow phase**

```dart
String get statusLabel {
  if (phase == CaptureActivityPhase.done && resultCount != null) {
    return '已整理 · $resultCount 项';
  }
  if (phase == CaptureActivityPhase.receiving &&
      !isRealtime &&
      source != CaptureActivitySource.audioUpload) {
    return '正在同步离线闪念';
  }
  return phase.label;
}
```

Keep the existing five product phases. Do not add S3, conversion, download
percentage, or hardware filenames to product copy.

- [ ] **Step 4: Restore persisted ring activities at startup**

After authentication and local task load, publish each non-terminal ring task
through `CaptureActivityBus` using stable local/device/client/recording aliases.
Use original capture time for ordering. Terminal tasks are not replayed as new
success banners.

- [ ] **Step 5: Verify the card needs no workflow rewrite**

Keep `BleFlashManager` start events as realtime `listening`; keep the existing
end-event file task and reconnect scan. Add assertions that a card file
discovered after reconnect is non-realtime, sorts by original filename time,
and uses offline-sync copy. Modify `FlashFileWorkflow` only if these tests expose
a mismatch.

- [ ] **Step 6: Run presentation and Session tests**

Run:

```bash
cd mobile
dart format lib/capture_activity lib/theme_v2/capture lib/ring/ring_file_workflow.dart test/theme_v2/capture test/flash_file_task_test.dart
flutter test test/flash_file_task_test.dart test/theme_v2/capture/capture_activity_coordinator_test.dart test/theme_v2/capture/capture_activity_top_bar_test.dart test/theme_v2/capture/capture_session_realtime_test.dart
```

Expected: PASS; one transient capture state is replaced by one final user turn.

- [ ] **Step 7: Commit presentation and recovery projection**

```bash
git add mobile/lib/capture_activity mobile/lib/theme_v2/capture mobile/lib/ring/ring_file_workflow.dart mobile/lib/ble_flash/flash_file_workflow.dart mobile/test/flash_file_task_test.dart mobile/test/theme_v2/capture
git commit -m "feat: unify online and recovered capture status"
```

---

### Task 7: Close the Android screen-off lifecycle gap only if proven

**Files:**
- Inspect/Test: `mobile/packages/chiplet_ring/android/src/main/AndroidManifest.xml`
- Inspect/Test: `mobile/android/app/src/main/AndroidManifest.xml`
- Conditional Create: `mobile/android/app/src/main/kotlin/com/eureka/mindapp/CaptureKeepAliveService.kt`
- Conditional Create: `mobile/lib/capture_activity/capture_background_keep_alive.dart`
- Conditional Create: `mobile/test/capture_background_keep_alive_test.dart`
- Conditional Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Conditional Modify: `mobile/android/app/src/main/kotlin/com/eureka/mindapp/MainActivity.kt`
- Conditional Modify: `mobile/android/app/src/main/res/values/strings.xml`
- Conditional Modify: `mobile/lib/ring/ring_capture_service.dart`
- Conditional Modify: `mobile/lib/ble_flash/ble_flash_manager.dart`

**Interfaces:**
- Reuses vendor `BLEService` when it passes the physical screen-off test.
- If required, produces `CaptureBackgroundKeepAlive.setEnabled(bool)` and an App-owned `connectedDevice` foreground service containing no ASR/network/Agent code.

- [ ] **Step 1: Test the existing vendor service before changing architecture**

With the Task 1 probe build installed and the ring/card connected:

```bash
adb -s RFCY71B21YK shell input keyevent 26
adb -s RFCY71B21YK shell dumpsys activity services com.eureka.mindapp
adb -s RFCY71B21YK shell dumpsys deviceidle force-idle
```

Record one ring Flash and one card Flash while the screen is off. Restore:

```bash
adb -s RFCY71B21YK shell dumpsys deviceidle unforce
adb -s RFCY71B21YK shell input keyevent 26
```

Pass condition: start/end events are received, a durable local task or already
accepted recording exists, and no audio is lost. If this passes, do not create
the conditional service files; proceed to Step 6.

- [ ] **Step 2: If the vendor service fails, write a failing MethodChannel lifecycle test**

```dart
test('authenticated hardware connection starts and logout stops keep-alive', () async {
  final calls = <MethodCall>[];
  installCaptureKeepAliveMock(calls.add);
  await CaptureBackgroundKeepAlive.instance.setEnabled(true);
  await CaptureBackgroundKeepAlive.instance.setEnabled(false);
  expect(calls.map((call) => call.method), ['start', 'stop']);
});
```

Run:

```bash
cd mobile
flutter test test/capture_background_keep_alive_test.dart
```

Expected: FAIL because the wrapper does not exist.

- [ ] **Step 3: If required, implement the minimal native service**

Declare permissions `FOREGROUND_SERVICE` and
`FOREGROUND_SERVICE_CONNECTED_DEVICE`; declare a non-exported service with
`android:foregroundServiceType="connectedDevice"`.

```kotlin
class CaptureKeepAliveService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(
            4102,
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("UREKA 设备已连接")
                .setContentText("正在保持闪念设备连接")
                .setOngoing(true)
                .build(),
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
```

The service must not own BLE commands, audio buffers, ASR, HTTP requests, task
state, or Agent work.

- [ ] **Step 4: If required, wire start/stop to authenticated connection state**

Expose MethodChannel `eureka/capture_keep_alive` in `MainActivity`. Start the
service when either supported hardware device is bound and connected; stop it
only when both are disconnected, the user explicitly unbinds, or logout occurs.
Repeated start/stop calls are idempotent.

- [ ] **Step 5: If required, run tests and rebuild**

Run:

```bash
cd mobile
dart format lib/capture_activity/capture_background_keep_alive.dart test/capture_background_keep_alive_test.dart
flutter test test/capture_background_keep_alive_test.dart test/ring/ring_capture_controller_test.dart test/flash_file_task_test.dart
flutter analyze lib/capture_activity/capture_background_keep_alive.dart lib/ring/ring_capture_service.dart lib/ble_flash/ble_flash_manager.dart
flutter build apk --debug
```

Expected: PASS and APK builds.

- [ ] **Step 6: Repeat the screen-off/Doze acceptance**

Repeat Step 1. The task passes only when the capture is either processed online
or durably recoverable from the hardware file. A visible persistent Android
notification is expected only when the conditional App-owned service was
required.

- [ ] **Step 7: Commit only the lifecycle changes actually required by evidence**

If the vendor service passes and no source change is needed, record the pass in
the design spec and include it with the final verification commit. If it fails,
commit the conditional implementation:

```bash
git add mobile/android/app/src/main mobile/lib/capture_activity/capture_background_keep_alive.dart mobile/lib/ring/ring_capture_service.dart mobile/lib/ble_flash/ble_flash_manager.dart mobile/test/capture_background_keep_alive_test.dart docs/superpowers/specs/2026-08-11-theme-v2-hybrid-hardware-capture-transport-design.md
git commit -m "fix: keep hardware capture alive with screen off"
```

---

### Task 8: Run destructive-boundary, Docker, and physical-device acceptance

**Files:**
- Modify: `docs/superpowers/specs/2026-08-11-theme-v2-hybrid-hardware-capture-transport-design.md` with final measured acceptance results.
- Modify tests only when a real defect is reproduced first; do not weaken an assertion to make acceptance pass.

**Interfaces:**
- Produces a verified release decision for `dualPath` or `localFirst`.
- Produces a separate firmware blocker when autonomous phone-off ring recording is unavailable.

- [ ] **Step 1: Run the complete focused automated suite**

Run:

```bash
cd theme_v2_service
python -m pytest -q tests/contract/test_capture_api.py tests/contract/test_capture_sse.py tests/integration/test_capture_jobs.py tests/integration/test_capture_session_materialization.py
```

Run:

```bash
cd mobile
flutter test packages/chiplet_ring/test/ring_platform_test.dart test/ring test/flash_file_task_test.dart test/theme_v2/capture test/theme_v2/shell/theme_v2_app_shell_capture_test.dart
flutter analyze lib/ring lib/ble_flash lib/capture_activity lib/theme_v2/capture lib/flash/flash.dart
flutter build apk --debug
```

Expected: all tests PASS, analyzer reports no issues, and the Theme V2 APK builds.

- [ ] **Step 2: Start only the independent Theme V2 backend and smoke identity**

Run from the repository root:

```bash
docker compose -p eureka-theme-v2 -f docker-compose.theme-v2.yml up -d --build mysql api worker
docker compose -p eureka-theme-v2 -f docker-compose.theme-v2.yml ps
```

Expected: Theme V2 `mysql`, `api`, and `worker` are healthy/running; the
legacy backend is not required.

- [ ] **Step 3: Install the Theme V2 build on the physical device**

Run:

```bash
cd mobile
adb -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s RFCY71B21YK reverse tcp:8000 tcp:8000
adb -s RFCY71B21YK shell am force-stop com.eureka.mindapp
adb -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Confirm the Theme V2 Today shell is visible before hardware validation.

- [ ] **Step 4: Verify connected ring and card happy paths**

For each device:

1. start recording and confirm the full top bar immediately shows `正在聆听`;
2. stop and confirm `正在接收` then `正在转写`;
3. confirm final text appears in the correct daily Flash Session without refresh;
4. confirm one Agent running state becomes one result;
5. confirm Assets, notification, and Flash count are created once;
6. confirm the hardware file is deleted only after backend acceptance;
7. leave/reopen the Session and confirm no duplicate turn or cards.

- [ ] **Step 5: Verify recovery and exactly-once behavior**

Run these scenarios for both devices where supported:

- screen off before capture start;
- App process killed after file close but before HTTP submission;
- network disabled through ASR/submission and restored later;
- BLE disconnected during file download and reconnected;
- App restarted while backend Agent processing is pending;
- the same file discovered repeatedly.

For every scenario, query the authenticated test account and verify one
`CaptureRecording`, one input turn, and no duplicate Assets/notifications.

- [ ] **Step 6: Verify phone-off hardware behavior**

Power the phone fully off. Record one Flash on W1/W2 and one on the ring. Power
the phone on, launch Theme V2, reconnect, and scan files.

- Card pass: the file transfers, preserves capture time, and processes once.
- Ring pass: a complete ring-local file exists and processes once.
- Ring fail: append a clearly named firmware blocker to the design spec. Do not
  mark phone-off ring capture complete and do not add an App hotfix.

- [ ] **Step 7: Verify the 8 MB safety policy**

Use measured codec rates from Task 1. Retain at least one deliberately
unacknowledged test file, approach the calculated low-space threshold without
formatting, and confirm:

- acknowledged files are cleaned first;
- the unacknowledged file remains;
- memory-full/low-space is visible as a controlled warning;
- reconnect continues processing the retained file;
- no oldest-unacknowledged overwrite occurs.

Delete only acknowledged test files after verification and state what was
removed in the acceptance record.

- [ ] **Step 8: Run final regression and inspect the diff**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Confirm unrelated pre-existing mobile edits were neither staged nor rewritten.

- [ ] **Step 9: Commit final acceptance evidence**

```bash
git add docs/superpowers/specs/2026-08-11-theme-v2-hybrid-hardware-capture-transport-design.md
git commit -m "test: verify hybrid hardware capture on device"
```

Do not merge to `main`. Push `codex/theme-v2-ui-refactor` only after the full
screen-off and exactly-once gates pass; if phone-off ring autonomy fails, push
with the firmware blocker explicitly recorded rather than claiming completion.

---

## Final Acceptance Checklist

- [ ] Ring capability mode is selected from physical evidence, not assumption.
- [ ] Online ring and card retain `正在聆听`.
- [ ] Screen-off capture is online or durably recoverable.
- [ ] Card phone-off recording recovers once.
- [ ] Ring phone-off support is either proven or recorded as a firmware blocker.
- [ ] Ring safety files survive ASR/network/App failures.
- [ ] Hardware files delete only after durable backend acceptance.
- [ ] Original capture time survives delayed reconnect.
- [ ] Offline recovery displays `正在同步离线闪念`.
- [ ] Duplicate callbacks/retries create no duplicate turn, Assets, or notifications.
- [ ] The existing Theme V2 Agent, MCP, Session, outbox, and notification architecture remains intact.
- [ ] Focused backend/mobile tests, Docker smoke, APK build, and physical-device acceptance pass.
