# Mobile Cloud Voice Input Design

- **Date:** 2026-08-20
- **Status:** Approved design; awaiting written-spec review
- **Scope:** Eureka mobile app voice input, authenticated ASR gateway, and Tencent streaming ASR integration

## 1. Summary

Eureka will provide one shared voice-to-text capability for every user-authored free-text input in the mobile app. The first release supports Mandarin, English, and mixed Mandarin-English speech through a cloud streaming ASR service.

The app will not bundle a local ASR model or provide an offline fallback. When the device has no network, voice input does not start and the user receives a clear error. This matches the product's dependency on online Agent processing after transcription and avoids shipping the slow, large bundled Whisper implementation explored previously.

The app connects only to an authenticated Eureka streaming ASR gateway. The gateway owns provider integration and credentials. Tencent Cloud real-time ASR is the production provider; the final server-side route through `card.biz` remains an explicit release-gated decision.

This design supersedes `2026-08-18-mobile-bundled-offline-asr-design.md` for app voice input. That document and the `offline-asr` branch remain historical exploration and must not be merged as the implementation basis for this feature. Existing hardware ASR integrations remain unchanged.

## 2. Goals and Non-goals

### Goals

- Let users dictate into all free-text authoring surfaces, including Session Chat, report generation, Skill creation, notes, and future content editors.
- Provide low-latency provisional text while the user is speaking.
- Preserve the existing edit-and-submit workflow for ordinary text fields.
- Provide a WeChat-style long-press gesture on the Reka head for immediately creating a text Flash.
- Support Mandarin, English, and Mandarin-English code-switching in the first release.
- Keep ASR provider credentials and provider-specific protocol details out of the app.
- Avoid retaining raw audio and transcript contents outside the business records the user intentionally creates.

### Non-goals

- Offline transcription or a bundled on-device ASR model.
- Speaker recognition, voiceprint identification, denoising, or audio enhancement.
- Reliable language identification or a language selector.
- First-release support guarantees for languages other than Mandarin and English.
- Voice input for search, login, verification codes, dates, amounts, or other structured fields.
- A user-accessible audio library, recording archive, or original-audio retry.
- Changing the existing hardware file-upload or S3 asynchronous ASR paths.

## 3. Product Experience

### 3.1 Eligible input surfaces

Voice input belongs to the shared free-text input component, not to individual pages. Any surface where the user authors natural-language content should adopt that component, including:

- Session Chat messages.
- Report-generation prompts and supporting text.
- Skill names, instructions, descriptions, and other free-text Skill fields where dictation is appropriate.
- Notes and other content editors.

Structured inputs remain keyboard-only unless separately designed. The implementation plan must inventory current free-text fields so adoption is explicit and testable.

### 3.2 Ordinary free-text fields

Ordinary fields use a microphone button embedded inside the input while retaining the field's existing send, save, or submit control.

1. The user taps the microphone once.
2. The app requests microphone permission if needed, connects, and begins streaming.
3. Provisional text appears with visually weaker styling at the cursor captured when recording began.
4. Stable segments replace their provisional predecessors without duplicating text.
5. The user taps the microphone again to stop.
6. The final transcript replaces provisional text at the captured insertion point. Text that existed before recording is preserved.
7. The user may edit the result and invokes the field's existing action when ready.

The microphone interaction never auto-submits an ordinary field. While a voice session is active, that field pauses keyboard editing and its existing submit action; this keeps the captured insertion point deterministic. A visible cancel action ends the session and restores the exact pre-recording text and selection. An error has the same restoration behavior.

Ordinary dictation is limited to five minutes. The UI warns the user 30 seconds before the limit, stops automatically at the limit, and requests the final transcript.

### 3.3 Reka long-press shortcut

Only the Reka shortcut uses the long-press, release-to-send gesture.

1. A long press on the Reka head starts recording and gives haptic confirmation.
2. Provisional transcript text appears next to Reka while the press is held.
3. Sliding upward enters a clear “release to cancel” state.
4. Releasing in the cancel state discards the session and creates nothing.
5. Releasing normally stops transcription.
6. A non-empty final transcript immediately creates a text Flash through the existing `POST /api/flash` business flow, with no intermediate editor or confirmation screen.

Reka recording is limited to 60 seconds. The UI warns at 30 seconds remaining; reaching the limit automatically stops transcription and submits the non-empty final text. Empty speech or any ASR failure creates nothing.

### 3.4 Language behavior

The production Tencent engine is `16k_zh_en`, which supports Mandarin, English, and code-switching without a user-facing selector.

Language detection is not part of the product contract. The app does not need to display or depend on a detected-language field, and the gateway must not claim reliable identification of unsupported languages. Other languages are best effort only. If the provider produces no useful text, the app shows the generic message:

> 没有识别到清晰语音，请重试

First-release acceptance testing covers Mandarin, English, and mixed Mandarin-English speech only.

## 4. Architecture

### 4.1 End-to-end flow

```text
Mobile app
  -> authenticated Eureka streaming ASR gateway
      -> provider adapter
          -> card.biz streaming endpoint, if PENDING-ASR-01 resolves to that route
          -> otherwise Tencent Cloud real-time ASR directly
```

The mobile app never connects directly to Tencent or `card.biz`, never receives Tencent credentials, and does not know which provider route is active. The Eureka gateway exposes one stable application protocol and maps provider-specific events and failures into it.

The ASR gateway only transcribes. It does not create messages, reports, Skills, notes, or Flashes. Business actions remain in the app and existing business APIs.

### 4.2 Mobile components

The shared implementation lives under `mobile/lib/voice_input/`:

- `voice_input_models.dart`: session states, transcript events, errors, and completion result.
- `voice_input_service.dart`: microphone capture, authenticated WebSocket connection, audio framing, and gateway protocol.
- `voice_input_controller.dart`: one-session lifecycle, text snapshot/restore, time limits, and exactly-once completion.
- `voice_input_field.dart`: reusable ordinary-field microphone UI and provisional transcript presentation.

Reka uses the same service and controller but provides its own press/slide/release presentation and completion action.

There is one app-wide active voice session. A second entry point cannot acquire the microphone until the current session completes or is cancelled. The public API has no separate `initialize()` step: starting a session performs permission, connection, and resource setup as needed.

### 4.3 Backend components

The gateway is organized under the backend ASR boundary:

- `backend/api/asr_stream.py`: authenticated WebSocket endpoint and application protocol.
- `backend/core/asr/streaming.py`: session orchestration, frame forwarding, cancellation, and normalized events.
- `backend/core/asr/provider.py`: provider interface and normalized provider errors.
- A route-specific adapter for either `card.biz` streaming or direct Tencent streaming.

The gateway enforces authentication, per-user concurrency, maximum duration, input format, frame-size bounds, and rate limits before or while forwarding audio.

### 4.4 Provider route release gate

`PENDING-ASR-01` must be resolved before claiming live production transcription is complete.

The product owner must confirm:

- Whether the `card.biz` backend can add a streaming WebSocket endpoint.
- Where Tencent production credentials and account configuration will live.
- That the selected Tencent account and service configuration meet the no-retention requirement, including provider-side processing and diagnostic settings.

Resolution is deterministic:

- If `card.biz` is modifiable, add its streaming endpoint and let it connect to Tencent `16k_zh_en`; the Eureka gateway connects to and normalizes that endpoint.
- If `card.biz` is not modifiable, the Eureka backend connects directly to Tencent `16k_zh_en` through the same provider interface.

Until this item is resolved, the mobile contracts, UI components, gateway protocol, provider interface, and fake-provider tests may proceed. Production credentials must not be placed in the app, and the feature must not be declared live against the current non-streaming `card.biz` API.

### 4.5 Existing ASR compatibility

The current `https://pre.card.biz/api/platform/speech/asr` path accepts a completed WAV file via multipart upload and returns final text. It is not the streaming path required by this design. Existing hardware callers and the existing Tencent S3 asynchronous flow remain unchanged.

## 5. Streaming Protocol

### 5.1 Connection and audio format

The app opens an authenticated WebSocket to the Eureka gateway and sends:

- A `start` control message with a unique `voiceSessionId` and the entry-point time limit.
- Binary 16 kHz, mono, 16-bit PCM frames while listening.
- A `stop` control message for normal finalization.
- A `cancel` control message when the result must be discarded.

The app emits approximately 200 ms PCM frames, matching Tencent's recommended 6,400-byte packet size for this format. The server validates but does not reinterpret the client-selected duration limit; server-side limits are authoritative.

### 5.2 Server events

The gateway returns normalized events:

- `ready`: the provider stream is ready to receive audio.
- `partial`: replaceable provisional text with a monotonically increasing sequence number.
- `stable`: a finalized segment that will no longer be revised.
- `final`: complete transcript and audio duration in milliseconds.
- `error`: stable application error code, user-safe message category, and `retryable` metadata.

`final` does not require a detected-language value. If an adapter provides one, it is diagnostic metadata only and must not drive first-release behavior.

The controller ignores stale or duplicate sequence numbers and emits one terminal outcome at most. Provider error bodies and credentials never cross the gateway boundary.

### 5.3 Provider mapping

For Tencent real-time ASR, replaceable slice results map to `partial`, stable slice results map to `stable`, and the completed sentence/session maps to `final`. Tencent voice activity detection and forced segmentation may divide long dictation internally without ending the app session.

The integration uses production `16k_zh_en`, not the preview `Hy-ASR-3.0-preview` engine, because the preview engine's short request-duration limit is incompatible with five-minute dictation.

## 6. State and Lifecycle

Each session follows this state machine:

```text
idle
  -> requestingPermission
  -> connecting
  -> listening
  -> finalizing
  -> completed
  -> idle

requestingPermission | connecting | listening | finalizing
  -> cancelled | failed
  -> idle
```

Lifecycle rules:

- Starting captures the active field's text and selection before any provisional mutation.
- Permission denial ends the session; permanent denial offers an operating-system settings action.
- No network prevents connection and recording from starting.
- Network loss, app backgrounding, calls, and audio-session interruptions cancel the session, discard provisional text, and create no business entity.
- Cancel closes capture and the WebSocket, ignores later events, and restores the ordinary field snapshot.
- A stop waits for exactly one `final` or terminal error. If neither arrives within 10 seconds, the session fails, cleans up, and submits nothing.
- No-speech or empty-final outcomes leave ordinary fields unchanged and create no Reka Flash.
- Dispose and route changes perform the same cleanup as cancel.
- All callbacks are scoped by `voiceSessionId`; events from an older session cannot mutate a newer one.

No original audio is retained for retry. If ASR fails, provisional text is discarded and the user records again. This deliberately removes local temporary WAV management, upload fallback, retry queues, and their privacy/lifecycle complexity.

If Reka receives a valid final transcript but `POST /api/flash` times out, the app may automatically retry the text request using `voiceSessionId` as an idempotency key. This is a business-request retry only; it does not retain or retransmit audio and must not create duplicate Flashes.

## 7. Privacy, Security, and Observability

- The app bundle contains no ASR model and no Tencent credential.
- The app does not save microphone audio to a file, database, cache, or user library.
- The Eureka gateway forwards frames in memory and does not write raw audio to logs, databases, object storage, or diagnostic artifacts.
- Transcript bodies are not written to ASR infrastructure logs. Text is persisted only through an explicit existing business action, such as sending a message or creating a Flash.
- Operational logs may contain session ID, user/account identifier appropriate for access control, duration, latency, provider route, outcome, and stable error code, but not audio or transcript content.
- Authentication is required before provider resources are allocated.
- Rate limits and one-active-session enforcement protect both account cost and service capacity.
- Secrets remain server-side and must use the repository's established secret-management mechanism.
- Provider retention and diagnostic behavior is a production release gate in `PENDING-ASR-01`.

## 8. Error Model and User Feedback

The gateway uses stable errors such as:

- `permission_denied` — produced locally before connection.
- `network_unavailable` — no usable network before start.
- `connection_failed` — gateway or provider connection could not be established.
- `connection_lost` — an active stream was interrupted.
- `no_speech` — no useful final transcript.
- `duration_exceeded` — the server ended a stream at its hard limit.
- `rate_limited` — account or user rate limit reached.
- `service_unavailable` — provider unavailable or internal transient failure.
- `unsupported_audio` — client audio violates the negotiated format.
- `unauthorized` — authentication expired or invalid.

The UI maps these codes to concise localized messages. No error path auto-submits partial text. Although `retryable` helps presentation and telemetry, the first release provides no in-place ASR retry button; the user starts a new recording.

## 9. Testing Strategy

### 9.1 Mobile unit and widget tests

- Microphone permission granted, denied, and permanently denied.
- Global mutual exclusion across two voice entry points.
- Ordinary tap-to-start and tap-to-stop behavior.
- Reka long press, slide-to-cancel, normal release, and haptic state changes.
- Provisional replacement and stable-segment ordering.
- Insertion at a captured cursor while preserving surrounding text.
- Exact field restoration on cancel, failure, lifecycle interruption, and dispose.
- 60-second Reka and five-minute ordinary limits, including warnings and automatic stop.
- Stale session events and duplicate terminal events are ignored.
- No final text means no business action.

### 9.2 Gateway and adapter tests

- Authentication occurs before stream allocation.
- Valid audio frames are forwarded in order without persistence.
- Oversized, malformed, or wrong-format input is rejected.
- `partial`, `stable`, `final`, cancellation, disconnect, timeout, and provider errors map to the normalized protocol.
- Sequence numbers are monotonic and duplicate/stale events do not regress text.
- Per-user concurrency, rate limits, and both duration caps are enforced server-side.
- Fake adapters run all protocol tests before the production route is selected.
- The chosen production adapter has a live sandbox smoke test after `PENDING-ASR-01` is resolved.

### 9.3 Business-flow tests

- Ordinary field transcription never invokes that field's submit action.
- Reka creates exactly one non-empty text Flash after a successful final transcript.
- Reka cancel, empty speech, ASR error, and interruption create nothing.
- Text-request timeout retry uses `voiceSessionId` idempotency and cannot duplicate a Flash.

### 9.4 Physical-device acceptance

Run on representative physical iOS and Android devices using normal Wi-Fi and 4G/5G conditions:

- Mandarin, English, and mixed Mandarin-English speech.
- Short phrases, multi-minute dictation, silence, and background noise representative of ordinary use.
- Weak network, connection loss, backgrounding, calls, and permission changes.
- Every intended content-authoring entry point plus the Reka gesture.

First-release experience objectives are:

- First provisional text P95 at or below one second after speech begins.
- Final transcript P95 at or below two seconds after stop or normal Reka release.
- Reka creates its Flash immediately after the final transcript is received.
- No failure creates an empty business entity.
- No test or production artifact contains raw audio, transcript logs, an app-bundled model, or provider credentials.

These are end-to-end objectives, not claims about the current file-upload endpoint. They must be measured after the streaming provider route is live.

## 10. Delivery Sequence

1. Resolve `PENDING-ASR-01`, or proceed only with fake-provider contracts while the release gate remains open.
2. Implement the provider interface and authenticated Eureka WebSocket gateway.
3. Implement `VoiceInputService`, the shared controller, session state, and audio capture.
4. Build the reusable ordinary free-text input component.
5. Inventory and migrate Session Chat, report, Skill, note, and other eligible authoring surfaces.
6. Add the Reka long-press, slide-to-cancel, and idempotent text-Flash flow.
7. Run physical-device Mandarin/English/mixed-language latency and failure validation.
8. Roll out behind a feature flag, observe content-free operational metrics, then broaden availability.

## 11. Acceptance Criteria

The design is implemented when:

- Every identified user-authored free-text surface can invoke the same voice service.
- Ordinary dictation inserts editable final text and never auto-submits.
- Reka long press shows provisional text; normal release creates one text Flash; slide-up release cancels.
- Mandarin, English, and mixed speech pass physical-device acceptance.
- The app connects only to Eureka and contains neither Tencent credentials nor a local ASR model.
- Audio is streamed in memory and is not retained by Eureka-controlled systems; provider retention requirements are verified.
- Offline, cancelled, interrupted, empty, and failed sessions create no business entity.
- The one-minute and five-minute caps are enforced by both app and gateway.
- The streaming provider route is resolved and documented under `PENDING-ASR-01`.
- Existing hardware ASR paths continue to behave as before.

## 12. References

- [Tencent Cloud real-time speech recognition WebSocket API](https://cloud.tencent.com/document/product/1093/48982)
- Existing hardware client: `ring-desktop/ring_desktop/asr.py`
- Existing hardware protocol: `ring-desktop/SPEC.md`
- Existing mobile completed-file client: `mobile/lib/api/tencent_asr_s3_client.dart`
- Existing backend asynchronous adapter: `backend/core/asr/tencent_s3_async.py`
