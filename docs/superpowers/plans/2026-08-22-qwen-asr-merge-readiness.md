# Qwen ASR Merge Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Qwen-based mobile voice-input branch safe to merge by serving its authenticated streaming route from the production Theme V2 API and bounding every client/provider lifecycle wait.

**Architecture:** Theme V2 owns the provider-neutral `/api/asr/stream` WebSocket and its Qwen adapter, using the same JWT and production process as the rest of the app. Mobile start/cleanup operations use generation-based cancellation plus explicit deadlines, while stale report-picker requests are ignored. Existing hardware file ASR remains a separate provider interface; a later migration may replace Tencent/card.biz with Alibaba's asynchronous file transcription API without coupling it to the mobile streaming model.

**Tech Stack:** Flutter/Dart, FastAPI/Python asyncio, Alibaba Cloud Model Studio WebSocket ASR, Docker Compose, pytest/unittest.

## Global Constraints

- Production streaming model is `qwen-audio-3.0-asr-flash-streaming`.
- Provider API keys remain server-side and never enter the mobile bundle.
- Ordinary voice input is limited to 300 seconds; Reka hold-to-talk is limited to 60 seconds.
- No automatic retry of recorded audio and no runtime provider fallback.
- Existing hardware capture behavior must remain unchanged in this merge-readiness fix.

---

### Task 1: Production Theme V2 Qwen gateway

**Files:**
- Create: `theme_v2_service/app/domains/asr/{__init__,provider,qwen_streaming,session,streaming,api}.py`
- Create: `theme_v2_service/tests/unit/test_asr_stream_gateway.py`
- Modify: `theme_v2_service/app/config.py`
- Modify: `theme_v2_service/app/main.py`
- Modify: `theme_v2_service/requirements.txt`
- Modify: `deploy/docker-compose.theme-v2.prod.yml`
- Modify: `deploy/.env.theme-v2.prod.example`
- Modify: `deploy/tests/test_theme_v2_prod.py`

- [ ] Write route/auth/config/provider-timeout tests that fail because Theme V2 does not expose the ASR gateway.
- [ ] Run the focused tests and confirm the missing route/config failures.
- [ ] Port the provider-neutral Qwen gateway into Theme V2, adapt JWT validation, and add a bounded provider audio-send deadline.
- [ ] Add production environment wiring and readiness validation.
- [ ] Run the focused gateway, configuration, and deployment-contract tests.

### Task 2: Mobile lifecycle deadlines and pre-ready errors

**Files:**
- Modify: `mobile/test/voice_input/voice_input_service_test.dart`
- Modify: `mobile/test/voice_input/voice_input_coordinator_test.dart`
- Modify: `mobile/lib/voice_input/voice_input_service.dart`
- Modify: `mobile/lib/voice_input/voice_input_coordinator.dart`

- [ ] Add failing tests for pre-ready normalized errors, a never-completing connector, a late socket after cancellation, and hung cleanup.
- [ ] Run the focused Flutter tests and confirm the expected timeouts/protocol failures.
- [ ] Add connection generations, connection and cleanup deadlines, and late-resource disposal.
- [ ] Parse authenticated provider errors before enforcing the `ready` state.
- [ ] Run the focused tests and analyzer.

### Task 3: Evidence picker stale-response guard

**Files:**
- Modify: `mobile/test/theme_v2/report/report_evidence_picker_page_test.dart`
- Modify: `mobile/lib/theme_v2/report/report_evidence_picker_page.dart`

- [ ] Add failing widget tests where an older search completes after a newer search and where load-more is tapped twice.
- [ ] Run the focused widget tests and confirm stale/duplicate results are visible.
- [ ] Add a reset request generation and one in-flight pagination guard.
- [ ] Run the focused widget tests and analyzer.

### Task 4: Qwen-first design and hardware migration boundary

**Files:**
- Modify: `docs/superpowers/specs/2026-08-20-mobile-cloud-voice-input-design.md`
- Create: `docs/superpowers/specs/2026-08-22-hardware-asr-qwen-migration-note.md`

- [ ] Make Theme V2 the canonical gateway in the mobile design and remove legacy-backend production ambiguity.
- [ ] Record that the Qwen streaming model does not support batch inference, while Alibaba Paraformer file transcription accepts a public/OSS audio URL through asynchronous submit-and-poll APIs.
- [ ] Keep hardware migration pending until input formats, retention, quality, latency, cost, and rollback are verified.

### Task 5: Merge verification

**Files:**
- Verify only; no new production scope.

- [ ] Run focused Python ASR/config/deployment tests.
- [ ] Run Flutter voice-input and evidence-picker tests plus analyzer.
- [ ] Run `git diff --check`, inspect the feature diff against local and remote `main`, and confirm user-owned files are untouched.
- [ ] Commit the scoped fixes and report whether the branch is ready to merge.
