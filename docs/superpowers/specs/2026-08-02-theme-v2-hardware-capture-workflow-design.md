# Theme V2 Hardware Capture Workflow Design

> Date: 2026-08-02
>
> Status: Approved for implementation. The user requested direct execution after
> the independent Theme V2 runtime and full physical-device workflow goal were
> confirmed.

## 1. Goal

Reproduce the legacy hardware capture workflow inside the independent Theme V2
runtime so a real W1/W2 recorder card or Chiplet Ring can complete this path:

```text
discover and bind
→ reconnect
→ capture hardware audio
→ transfer audio to the phone
→ Tencent ASR
→ Theme V2 capture agent
→ persist Theme V2 Asset/Event records
→ publish progress and completion
→ refresh Today/Library
```

The result must run with the old backend and old MySQL stopped. The mobile
client keeps the mature BLE, audio-transfer, retry, and Tencent speech client
code. Theme V2 owns all server-side code, tables, migrations, jobs, and data.

## 2. Fixed Constraints

- Keep the independent `eureka-theme-v2` Docker Compose project, network,
  MySQL database, and volumes.
- Do not proxy to the old backend, query its database, import its runtime code,
  or dual-write.
- Do not add Redis, Kafka, Celery, or another broker. Use the existing MySQL
  `WorkflowJob` queue and Transactional Outbox.
- Preserve the mobile contracts required by `DeviceController`,
  `DeviceSilentReconnect`, `FlashFileWorkflow`, and ring capture.
- Keep FastAPI, SQLAlchemy 2, Alembic, MySQL 8, LiteLLM, Flutter, and the existing
  native BLE plugins.
- All device bindings, recordings, jobs, assets, events, and status reads are
  owner-scoped by the authenticated Theme V2 user.
- Do not expose bearer tokens, audio URLs with query strings, transcripts, or
  model prompts in logs.
- The implementation is successful only after automated tests and a real-device
  end-to-end capture pass.

## 3. Considered Approaches

### A. Mobile dual-backend routing

Send Theme V2 CRUD to port 8100 and hardware requests to the old service. This
is the fastest demonstration but requires the old Docker, old database, and
cross-runtime identity synchronization. It cannot satisfy standalone Theme V2
acceptance and is rejected.

### B. Import or mount legacy backend modules

Change the Theme V2 image build context and import `backend/api/cards.py`,
`backend/api/flash.py`, and the old agent stack. This preserves more code but
couples migrations, global settings, models, process-local queues, and both
services' dependency graphs. It violates the approved code boundary and is
rejected.

### C. Contract-preserving Theme V2 port

Keep the mature mobile contracts, reimplement their server behavior as focused
Theme V2 domains, and use Theme V2's database job queue and outbox. Stable
validation and state-machine behavior from the old service are used as a
reference, but the new runtime owns the implementation. This is the selected
approach.

## 4. Scope Boundary

This design reproduces the complete hardware-initiated capture workflow. It
includes the old Flash intent family needed to turn a transcript into user
records: todo, event, expense, contact, idea, notes, miscellaneous note, and
short question/answer. User-defined Theme V2 skills can also receive a capture
when their schema and description match.

It does not migrate unrelated legacy Pet, Goal, Nudge, Offer, OAuth connector,
Report Dispatcher, or old chat-history data. Theme V2 startup must stop calling
unsupported legacy endpoints so those omissions do not produce API exceptions.
Interactive Theme V2 Session/Chat remains a separate UI surface, but the
capture agent and its provider abstractions are reusable by that future work.

## 5. Components

### 5.1 Device domain

Create `theme_v2_service/app/domains/devices/` with models, schemas, service,
and API modules. It owns `Card` and `CardBinding` and exposes:

```http
POST /api/cards/binding-info
POST /api/cards/bindings
GET  /api/cards/bindings
POST /api/cards/{binding_id}/unbind
```

Responses retain the legacy field names because they are a hardware transport
contract, not an old database contract. One card can have only one active
binding globally. Rebinding by the same user refreshes UUID and display metadata;
binding by another user returns 409. Unbind preserves history and clears the
active uniqueness key.

### 5.2 Capture persistence domain

Create `theme_v2_service/app/domains/capture/` and add:

- `CaptureFile`: owner, storage reference, file type, duration, source, ASR state.
- `CaptureRecording`: client task identity, card/file metadata, S3 metadata,
  Tencent task metadata, transcript, agent state, result summary, result record
  references, retry/error fields, and timestamps.
- `CaptureTurn`: normalized transcript and provenance used by the agent and
  record creation.

Uniqueness is enforced on `(user_id, client_task_id)` and on the device file
identity used by offline recovery. Duplicate submissions with the same content
return the existing recording; conflicting duplicates return 409.

The mobile compatibility API is:

```http
POST /api/flash
POST /api/flash/listening
POST /api/flash/tencent-asr-s3-uploads
POST /api/flash/tencent-asr-sync-results
GET  /api/flash/recordings/{recording_id}
POST /api/flash/recordings/{recording_id}/retry
```

### 5.3 Tencent ASR provider

The phone remains responsible for the current short-file `sync_client` path:
it sends Opus to the configured Tencent speech service and posts the result to
Theme V2. The server validates, stores, and queues the completed transcript.

For larger recordings, the phone keeps the established S3 upload flow. The V2
worker creates and polls the Tencent S3 ASR task through a focused `AsrProvider`
interface. Provider calls happen outside database transactions. Job checkpoints
store the external task ID and polling state so worker restarts do not duplicate
the ASR task.

The provider base URL is configured by `TENCENT_ASR_SERVICE_BASE_URL`; defaults
match the existing mobile service. Tests use a fake provider and never call a
real external service.

### 5.4 Capture agent

The capture agent is a V2-owned application service with a provider interface:

```python
class CaptureAgentProvider(Protocol):
    async def organize(
        self,
        *,
        transcript: str,
        local_date: date,
        skills: list[CaptureSkill],
    ) -> CaptureAgentResult: ...
```

The production provider uses the existing LiteLLM dependency and a strict JSON
schema. Its instruction is derived from the canonical legacy Flash dispatcher
and sub-skill rules, but it returns one normalized result containing a warm
summary plus zero or more record commands. A deterministic validator rejects
unknown skills, invalid payload shapes, malformed dates, and unsupported
operations before any write.

Record commands are persisted in one short transaction:

- event intent → V2 `Event`.
- all other record-producing intents → V2 `Asset` linked to a `UserSkill`.
- QA intent → summary only, with no Asset.
- multiple intents → multiple records, preserving transcript provenance.

New users receive idempotent baseline V2 skills before the first capture. The
baseline includes todo, expense, contact, idea, notes, and miscellaneous. Custom
skills are included only when enabled.

Agent execution uses a `capture_process` `WorkflowJob`. Text Flash from the
ring also creates a recording and job. To preserve the ring's synchronous
`POST /api/flash` contract, the API waits for the database-backed job for a
bounded period; the worker still owns the external model call and the request
does not create an in-process business task.

### 5.5 Progress, notifications, and refresh

Capture state transitions publish generic Outbox events named
`flash_file_status`. The existing outbox dispatcher is generalized so
notification events still reload their Notification row while capture events
publish their stored payload directly. SSE preserves the event name expected by
`AppEvents`.

Terminal success also creates one persisted `flash_done` Notification in the
same transaction as recording completion. The payload contains recording ID,
client task ID, status, summary, and created record references. The mobile app
uses the existing data-revision path to refresh Today and Library.

### 5.6 Mobile Theme V2 integration

The native card and ring implementations remain shared. Theme V2 adds a live
device-status adapter that listens to `DeviceController` and `RingConnection`
and maps them into `DeviceStatusSummary`. Device Center continues to host the
mature pairing and connected-device pages until their P6 visual replacement is
implemented; this preserves working hardware behavior now.

Theme V2 startup is separated from legacy product startup:

- keep BLE managers, reconnect, hardware capture, app events, and data revision;
- do not start Pet, Nudge, Offer, old Timeline, old Contacts, or old Skill list
  requests solely because the user authenticated;
- Theme V2 repositories use `/api/user-skills`, `/api/assets`, and `/api/events`;
- compatibility aliases are added only when a still-supported hardware flow
  truly needs one.

## 6. State Machines

### 6.1 Card recording

```text
accepted
→ asr_processing
→ asr_done
→ agent_processing
→ done
```

Terminal alternatives are `empty` and `failed`. Retry resumes from the last
durable checkpoint: ASR is retried when no transcript exists; agent processing
is retried when a transcript exists. A terminal failed client-side ASR result is
stored but does not delete the source audio from the device.

### 6.2 Job behavior

`capture_asr` and `capture_process` are separate job types. Both use dedupe keys
derived from the recording ID, lease ownership, bounded exponential retry, and
idempotent handlers. Only the current lease owner can write a terminal result.
Permanent validation/provider errors fail without retry; transport and provider
availability errors retry up to the configured maximum.

## 7. Error Handling

- Missing or foreign card binding: 403.
- Card already actively bound by another user: 409.
- Conflicting duplicate capture: 409.
- Invalid ASR payload or state transition: 422.
- Foreign recording read/retry: 404.
- Provider temporarily unavailable: recording remains recoverable and the job
  retries.
- Agent output invalid after bounded attempts: recording becomes failed, source
  audio remains recoverable, and the user receives a failure notification.
- App startup API failures must be represented by controlled feature state, not
  raw `ApiException(...)` text.

## 8. Database and Migration Strategy

One new Alembic revision creates device and capture tables and indexes. It does
not copy old migrations or data. Existing `WorkflowJob` is extended only with a
generic JSON input/checkpoint field if the recording ID cannot be represented by
the existing `run_id`; no parallel queue table is introduced.

All timestamps are UTC `DATETIME(6)`, IDs are `CHAR(36)`, and JSON fields use
native MySQL JSON. Audio bytes stay in Tencent/S3 or on the phone; the Theme V2
database stores metadata and authorized references only.

## 9. Test Strategy

Every production behavior is introduced test-first.

1. Contract tests cover all card and Flash endpoints, auth, ownership, exact
   mobile response shapes, duplicates, and invalid state transitions.
2. MySQL integration tests cover active-binding concurrency, recording
   idempotency, job dedupe/lease recovery, atomic record creation, notification,
   and outbox publication.
3. Provider unit tests cover Tencent status parsing, safe URL logging, capture
   agent schema validation, baseline skill routing, multi-intent output, QA, and
   invalid model output.
4. Flutter tests cover live device status mapping, Theme V2 startup gating, and
   compatibility with the current device and Flash workflow clients.
5. Docker smoke starts only Theme V2 MySQL/API/Worker and exercises register,
   bind, submit a fake transcript, run the fake capture job, read the resulting
   Asset/Event, and receive completion through SSE/list recovery.
6. Real-device acceptance uses the connected Android device and physical
   hardware: bind, reconnect, record a short phrase, verify ASR text, verify
   agent-created record, verify Today/Library refresh, restart the app, and
   verify reconnect. A larger recording also verifies the async S3 ASR path.

## 10. Acceptance Criteria

- Old backend and old database can be stopped throughout the test.
- Device pairing and automatic reconnect complete without 404 or raw
  `ApiException` UI.
- Theme V2 displays real connected/disconnected state wherever the device entry
  is visible.
- Short recorder-card audio completes the client-sync ASR path.
- Large recorder-card audio completes the S3 async ASR path.
- Ring audio completes Ring ASR and `POST /api/flash` processing.
- One transcript can create multiple correct V2 records through the capture
  agent, including an Event and generic Assets.
- Duplicate mobile retries create neither duplicate recordings nor duplicate
  records.
- Worker or API restart does not lose an accepted recording.
- Progress and completion are recoverable through recording state and persisted
  Notification history even if an SSE frame is missed.
- Full automated suite, Docker smoke, Flutter analyze, APK build, and physical
  device workflow pass before completion is reported.

## 11. Delivery Slices

1. Device binding domain and mobile live-state bridge.
2. Capture persistence and sync-client ASR ingress.
3. Async Tencent ASR worker job and recovery.
4. Capture agent provider, baseline skills, and V2 record writes.
5. Generic outbox progress, notification completion, and startup cleanup.
6. Docker smoke, APK deployment, and physical-device acceptance.

Each slice is independently tested and committed. The final branch is pushed to
its existing remote branch and is not merged into `main`.
