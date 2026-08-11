# Theme V2 Report Async Illustration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a Report wait up to 30 seconds for Seedream, then open as a readable text Report while one durable image job continues and backfills the illustration without a visible page refresh.

**Architecture:** The Report pipeline enqueues one idempotent `report_illustration` child job and waits only for its durable checkpoint. The worker runs a filtered illustration lane concurrently with the primary lane. Pending Reports reserve one trusted HTML slot; the child job later patches the stored HTML and increments a Report revision, which the Flutter viewer observes and replaces in place.

**Tech Stack:** Python 3.12 asyncio, SQLAlchemy 2 async, MySQL/Alembic, existing WorkflowJob lease queue, FastAPI, trusted Jinja Report renderer, Flutter `webview_flutter`, widget tests.

## Global Constraints

- The foreground illustration wait is exactly 30 seconds by default.
- Crossing 30 seconds must not cancel the Seedream request or fail Report content.
- At most one paid illustration is generated per Report generation attempt.
- Worker restart and lease recovery must resume from a durable checkpoint.
- A pending Report is readable and has a fixed-height subtle placeholder in light and dark palettes.
- The open mobile Report patches only the trusted illustration slot and preserves scroll position.
- Existing public share snapshots are immutable; a share created after image completion includes the image.
- Illustration failure is non-fatal and separately retryable.
- Do not merge or push during this plan.

---

### Task 1: Persist Report Illustration State and Revision

**Files:**
- Create: `theme_v2_service/migrations/versions/0023_report_async_illustration.py`
- Modify: `theme_v2_service/app/domains/reports/models.py`
- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/app/domains/reports/state_machine.py`
- Modify: `theme_v2_service/tests/integration/test_migrations.py`
- Test: `theme_v2_service/tests/unit/test_report_state_machine.py`

**Interfaces:**
- Produces: `Report.illustration_status`, `Report.illustration_job_id`, `Report.revision`, `Report.updated_at`, and Run state `illustration_pending`.
- Consumes: existing Report and Run state machines.

- [ ] **Step 1: Write failing state tests**

```python
def test_generating_can_publish_a_readable_pending_report(run):
    run.state = "generating"
    run.report_id = "report-1"
    run.completed_at = NOW
    transition_run(run, "illustration_pending", now=NOW)
    assert run.state == "illustration_pending"


def test_pending_illustration_can_complete(run):
    run.state = "illustration_pending"
    run.report_id = "report-1"
    run.completed_at = NOW
    transition_run(run, "completed", now=NOW)
    assert run.state == "completed"
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd theme_v2_service && pytest tests/unit/test_report_state_machine.py -q`

Expected: FAIL because `illustration_pending` is not an allowed state.

- [ ] **Step 3: Add migration and ORM fields**

```python
revision = "0023_report_async_illustration"
down_revision = "0022_report_scope_draft"


def upgrade() -> None:
    op.add_column("reports", sa.Column("illustration_status", sa.String(24), nullable=False, server_default="not_required"))
    op.add_column("reports", sa.Column("illustration_job_id", sa.CHAR(36), nullable=True))
    op.add_column("reports", sa.Column("revision", sa.Integer(), nullable=False, server_default=sa.text("1")))
    op.add_column("reports", sa.Column("updated_at", mysql.DATETIME(fsp=6), nullable=True))
    op.drop_constraint("ck_report_generation_runs_state", "report_generation_runs", type_="check")
    op.create_check_constraint("ck_report_generation_runs_state", "report_generation_runs", "state IN ('planning','awaiting_selection','generating','illustration_pending','completed','failed','cancelled','expired')")
```

Backfill `reports.updated_at = reports.created_at`, then make it non-null. Add an illustration-status check constraint.

- [ ] **Step 4: Extend state transitions**

Allow `generating -> illustration_pending -> completed`; `illustration_pending` requires `report_id` and `completed_at` and is treated as readable but non-editable. Add it to active/readable serialization where required.

- [ ] **Step 5: Run migration and state tests**

Run: `cd theme_v2_service && pytest tests/unit/test_report_state_machine.py tests/integration/test_migrations.py -q`

Expected: PASS with migration head `0023_report_async_illustration`.

- [ ] **Step 6: Commit state persistence**

```bash
git add theme_v2_service/migrations/versions/0023_report_async_illustration.py theme_v2_service/app/domains/reports/models.py theme_v2_service/app/domains/reports/schemas.py theme_v2_service/app/domains/reports/state_machine.py theme_v2_service/tests/unit/test_report_state_machine.py theme_v2_service/tests/integration/test_migrations.py
git commit -m "feat: persist pending report illustrations"
```

### Task 2: Add Filtered Concurrent Worker Lanes

**Files:**
- Modify: `theme_v2_service/app/jobs/queue.py`
- Modify: `theme_v2_service/app/jobs/runner.py`
- Modify: `theme_v2_service/app/worker.py`
- Test: `theme_v2_service/tests/integration/test_jobs.py`
- Test: `theme_v2_service/tests/unit/test_worker_runtime.py`

**Interfaces:**
- Produces: `claim_next_job(session: AsyncSession, *, owner: str, now: datetime, lease_seconds: int, include_job_types: set[str] | None = None, exclude_job_types: set[str] | None = None) -> WorkflowJob | None` and filtered `run_worker` lanes.
- Consumes: existing WorkflowJob status/lease behavior.

- [ ] **Step 1: Write failing queue-filter tests**

```python
async def test_worker_lane_claims_only_included_types(session):
    await enqueue_job(session, job_type="report_pipeline", dedupe_key="p")
    illustration = await enqueue_job(session, job_type="report_illustration", dedupe_key="i")
    claimed = await claim_next_job(
        session,
        owner="illustration-worker",
        now=NOW,
        lease_seconds=60,
        include_job_types={"report_illustration"},
    )
    assert claimed.id == illustration.id
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_jobs.py -q`

Expected: FAIL because claim filtering is unsupported.

- [ ] **Step 3: Implement SQL-level filtering**

Add `WorkflowJob.job_type.in_(include_job_types)` or `WorkflowJob.job_type.not_in(exclude_job_types)` to the claim query. Reject simultaneous include/exclude sets with `ValueError`.

- [ ] **Step 4: Run primary and illustration loops concurrently**

```python
await asyncio.gather(
    run_worker(registry, stop_event=stop_event, owner=f"{owner}:primary", exclude_job_types={REPORT_ILLUSTRATION_JOB_TYPE}),
    run_worker(registry, stop_event=stop_event, owner=f"{owner}:illustration", include_job_types={REPORT_ILLUSTRATION_JOB_TYPE}),
)
```

Only the primary process owns maintenance schedulers. Both loops share the same stop event.

- [ ] **Step 5: Run worker tests**

Run: `cd theme_v2_service && pytest tests/integration/test_jobs.py tests/unit/test_worker_runtime.py -q`

Expected: PASS and no cross-lane claims.

- [ ] **Step 6: Commit worker lanes**

```bash
git add theme_v2_service/app/jobs/queue.py theme_v2_service/app/jobs/runner.py theme_v2_service/app/worker.py theme_v2_service/tests/integration/test_jobs.py theme_v2_service/tests/unit/test_worker_runtime.py
git commit -m "feat: add dedicated illustration worker lane"
```

### Task 3: Implement the Durable Illustration Job

**Files:**
- Create: `theme_v2_service/app/domains/reports/illustration_jobs.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Test: `theme_v2_service/tests/integration/test_report_illustration_jobs.py`

**Interfaces:**
- Produces: `REPORT_ILLUSTRATION_JOB_TYPE`, `enqueue_report_illustration`, `report_illustration_handler`, and `attach_ready_illustration`.
- Consumes: existing `IllustrationProvider`, `persist_owned_file`, WorkflowJob checkpoints, and Report presentation metadata.

- [ ] **Step 1: Write failing idempotency and resume tests**

```python
async def test_illustration_job_persists_file_before_attach(session, fake_provider):
    job = await enqueue_report_illustration(session, run=run, prompt="abstract football systems")
    await execute_report_illustration_job(job, provider=fake_provider, storage=storage)
    stored = await session.get(WorkflowJob, job.id)
    assert stored.checkpoint_json["file_id"]
    assert fake_provider.calls == 1


async def test_retry_with_file_checkpoint_does_not_call_provider_again(session, fake_provider):
    job.checkpoint_json = {"prompt": "safe", "file_id": "file-1", "phase": "stored"}
    await execute_report_illustration_job(job, provider=fake_provider, storage=storage)
    assert fake_provider.calls == 0
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_illustration_jobs.py -q`

Expected: FAIL because the durable job module does not exist.

- [ ] **Step 3: Enqueue one child job per generation attempt**

```python
async def enqueue_report_illustration(session, *, run, parent_job_id, prompt, policy):
    job = await enqueue_job(
        session,
        run_id=run.id,
        job_type=REPORT_ILLUSTRATION_JOB_TYPE,
        dedupe_key=f"report-illustration:{run.id}:{parent_job_id}",
        max_attempts=get_settings().report_provider_max_attempts,
    )
    if job.checkpoint_json is None:
        job.checkpoint_json = {"phase": "queued", "prompt": prompt, "policy": policy, "parent_job_id": parent_job_id}
    return job
```

- [ ] **Step 4: Persist provider output before Report attachment**

The handler checks `checkpoint_json.file_id` first. If absent, it calls Seedream, validates the MIME type, stores one owned file using the child job ID, and commits `phase=stored` plus `file_id`. Only then does it attempt Report attachment.

- [ ] **Step 5: Defer safely until the parent Report exists**

If no Report row exists yet, call `defer_job(session, job_id=job.id, owner=job.lease_owner, now=now, available_at=now + timedelta(seconds=1), checkpoint=current_checkpoint)` and raise `JobDeferred`. The next lease resumes from `file_id` without another provider call.

- [ ] **Step 6: Register the configured handler**

Build the Seedream provider once per job with the existing settings and register `report_illustration` independently from `report_pipeline`.

- [ ] **Step 7: Run durable job tests**

Run: `cd theme_v2_service && pytest tests/integration/test_report_illustration_jobs.py tests/integration/test_jobs.py -q`

Expected: PASS with one provider call across retry/recovery.

- [ ] **Step 8: Commit the durable job**

```bash
git add theme_v2_service/app/domains/reports/illustration_jobs.py theme_v2_service/app/jobs/registry.py theme_v2_service/tests/integration/test_report_illustration_jobs.py
git commit -m "feat: generate report illustrations durably"
```

### Task 4: Enqueue, Wait 30 Seconds, and Persist a Pending Report

**Files:**
- Modify: `theme_v2_service/app/domains/reports/pipeline.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Modify: `theme_v2_service/app/domains/reports/rendering.py`
- Modify: `theme_v2_service/app/domains/reports/presentation/renderer.py`
- Modify: `theme_v2_service/app/domains/reports/presentation/styles.py`
- Test: `theme_v2_service/tests/unit/test_report_pipeline.py`
- Test: `theme_v2_service/tests/unit/test_report_rendering.py`
- Test: `theme_v2_service/tests/integration/test_report_jobs.py`

**Interfaces:**
- Produces: pending illustration checkpoint, fixed trusted slot, and `persist_completed_report(session, *, run_id, job_id, lease_owner, data, illustration_status, illustration_job_id)`.
- Consumes: Task 3 durable child job and Task 1 Report fields.

- [ ] **Step 1: Write failing under/over-30-second tests**

```python
async def test_image_ready_inside_budget_is_rendered(fake_clock):
    result = await wait_for_illustration_result(job_id="image-1", timeout_seconds=30, poll_seconds=0.1)
    assert result == {"status": "ready", "file_id": "file-1"}


async def test_timeout_returns_pending_without_cancelling_child(fake_clock):
    result = await wait_for_illustration_result(job_id="image-1", timeout_seconds=30, poll_seconds=0.1)
    assert result == {"status": "pending", "job_id": "image-1"}
    assert child_job.status in {"queued", "running"}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/unit/test_report_pipeline.py tests/unit/test_report_rendering.py -q`

Expected: FAIL because the synchronous timeout still cancels provider generation.

- [ ] **Step 3: Replace the synchronous illustration stage**

The pipeline stage resolves and sanitizes the prompt, enqueues Task 3's child job, and polls only durable job status/checkpoint for up to `REPORT_OPTIONAL_ILLUSTRATION_TIMEOUT_SECONDS`. It never awaits or cancels the provider coroutine directly.

- [ ] **Step 4: Render a stable pending slot**

```html
<figure id="reka-report-illustration" class="r-illustration r-illustration--pending" data-illustration-status="pending" aria-label="报告配图生成中">
  <div class="r-illustration-placeholder"></div>
</figure>
```

The stylesheet reserves a responsive fixed height and uses palette-derived low-contrast surfaces in both light and dark modes.

- [ ] **Step 5: Persist readable pending state**

`CompletedReportData` carries `illustration_status` and `illustration_job_id`. If pending, `persist_completed_report` transitions the Run to `illustration_pending`, creates the normal `report_done` notification immediately, and makes `report_id` readable. If ready/not-required/failed, it transitions directly to `completed`.

- [ ] **Step 6: Run pipeline and renderer tests**

Run: `cd theme_v2_service && pytest tests/unit/test_report_pipeline.py tests/unit/test_report_rendering.py tests/integration/test_report_jobs.py -q`

Expected: PASS; the child remains active after the 30-second result.

- [ ] **Step 7: Commit the parent pipeline change**

```bash
git add theme_v2_service/app/domains/reports/pipeline.py theme_v2_service/app/domains/reports/service.py theme_v2_service/app/domains/reports/rendering.py theme_v2_service/app/domains/reports/presentation/renderer.py theme_v2_service/app/domains/reports/presentation/styles.py theme_v2_service/tests/unit/test_report_pipeline.py theme_v2_service/tests/unit/test_report_rendering.py theme_v2_service/tests/integration/test_report_jobs.py
git commit -m "feat: publish reports while illustrations continue"
```

### Task 5: Atomically Attach the Later Image

**Files:**
- Modify: `theme_v2_service/app/domains/reports/illustration_jobs.py`
- Modify: `theme_v2_service/app/domains/reports/rendering.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Test: `theme_v2_service/tests/integration/test_report_illustration_jobs.py`
- Test: `theme_v2_service/tests/contract/test_public_report_api.py`

**Interfaces:**
- Produces: `replace_pending_illustration_slot(html, file_url) -> str` and atomic Report revision update.
- Consumes: Task 4 trusted placeholder and Task 3 stored file checkpoint.

- [ ] **Step 1: Write failing attach tests**

```python
async def test_attach_patches_only_slot_and_increments_revision(session, pending_report, stored_job):
    original_body = extract_report_body_without_slot(pending_report.html)
    await attach_ready_illustration(session, job=stored_job, file_id="file-1")
    await session.refresh(pending_report)
    assert pending_report.illustration_status == "ready"
    assert pending_report.revision == 2
    assert extract_report_body_without_slot(pending_report.html) == original_body
    assert '/api/files/file-1' in pending_report.html


async def test_existing_share_snapshot_does_not_change(session, share, pending_report, stored_job):
    before = share.snapshot_html
    await attach_ready_illustration(session, job=stored_job, file_id="file-1")
    assert share.snapshot_html == before
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_illustration_jobs.py tests/contract/test_public_report_api.py -q`

Expected: FAIL because late attachment does not exist.

- [ ] **Step 3: Implement exact trusted-slot replacement**

Use one strict regex matching only the renderer-owned `figure` ID and pending status. Reject HTML with zero or multiple slots. Generate the replacement figure using the same owned-URL validator as initial rendering.

- [ ] **Step 4: Update Report, Run, and generation context atomically**

Lock the Report and matching Run. Verify `illustration_job_id`, `illustration_status=pending`, and child job ownership. Patch HTML; append the file ID exactly once to `spec_json.generated_file_ids`; set `share_card_spec.illustration_file_id`; store bounded illustration metadata; increment `revision`; set `updated_at`; transition Run `illustration_pending -> completed`.

- [ ] **Step 5: Implement terminal failure completion**

When child retries are exhausted, mark Report illustration `failed`, remove/replace the pending slot with no gap, record a safe error category, increment revision, and transition the readable Run to `completed`.

- [ ] **Step 6: Run attach and sharing tests**

Run: `cd theme_v2_service && pytest tests/integration/test_report_illustration_jobs.py tests/contract/test_public_report_api.py tests/contract/test_report_api.py -q`

Expected: PASS with immutable existing shares.

- [ ] **Step 7: Commit late attachment**

```bash
git add theme_v2_service/app/domains/reports/illustration_jobs.py theme_v2_service/app/domains/reports/rendering.py theme_v2_service/app/domains/reports/service.py theme_v2_service/tests/integration/test_report_illustration_jobs.py theme_v2_service/tests/contract/test_public_report_api.py theme_v2_service/tests/contract/test_report_api.py
git commit -m "feat: backfill completed report illustrations"
```

### Task 6: Expose Revision State and Auto-patch the Open Flutter Report

**Files:**
- Modify: `theme_v2_service/app/domains/reports/api_reports.py`
- Modify: `mobile/lib/theme_v2/report/report_models.dart`
- Modify: `mobile/lib/pages/report_viewer_page.dart`
- Test: `theme_v2_service/tests/contract/test_report_api.py`
- Test: `mobile/test/theme_v2/report/report_viewer_refresh_test.dart`

**Interfaces:**
- Produces: API fields `revision`, `updated_at`, `illustration_status`; Flutter pending poll and DOM patch.
- Consumes: Task 5 Report revision and trusted slot.

- [ ] **Step 1: Write failing API and Flutter tests**

```python
async def test_report_api_exposes_pending_revision(client, pending_report, auth):
    response = await client.get(f"/api/reports/{pending_report.id}", headers=auth)
    assert response.json()["revision"] == 1
    assert response.json()["illustration_status"] == "pending"
```

```dart
testWidgets('pending report polls and patches illustration without reload', (tester) async {
  await tester.pumpWidget(viewer(initialStatus: 'pending', initialRevision: 1));
  await tester.pump(const Duration(seconds: 3));
  expect(fakeWebView.slotPatchCalls, 1);
  expect(fakeWebView.fullReloadCalls, 0);
});
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/contract/test_report_api.py -q`

Run: `cd mobile && flutter test test/theme_v2/report/report_viewer_refresh_test.dart`

Expected: FAIL because revision fields and viewer polling do not exist.

- [ ] **Step 3: Serialize Report revision state**

Add `illustration_status`, `revision`, and `updated_at` to list/detail serialization. Keep existing response fields stable.

- [ ] **Step 4: Poll only while visible and pending**

The viewer owns a three-second timer only when `enableThemeV2Actions`, `reportId != null`, and status is pending. It implements `WidgetsBindingObserver` to pause on background and resume with one immediate fetch on foreground.

- [ ] **Step 5: Patch the trusted slot and preserve scroll**

Fetch the newer HTML, extract the renderer-owned slot, and call one bounded JavaScript function that replaces `document.getElementById('reka-report-illustration').outerHTML`. Do not execute arbitrary server-provided JavaScript. On patch failure only, read `window.scrollY`, reload trusted HTML, and restore the scroll position.

- [ ] **Step 6: Stop on terminal state and update local HTML**

After `ready` or `failed`, cancel polling, update `_html` so Share uses the newest private Report HTML, and leave Report actions state untouched.

- [ ] **Step 7: Run API, Flutter, and analyzer checks**

Run: `cd theme_v2_service && pytest tests/contract/test_report_api.py -q`

Run: `cd mobile && flutter test test/theme_v2/report/report_viewer_refresh_test.dart test/theme_v2/report/report_viewer_theme_test.dart`

Run: `cd mobile && flutter analyze lib/pages/report_viewer_page.dart test/theme_v2/report/report_viewer_refresh_test.dart`

Expected: PASS and no analyzer issues.

- [ ] **Step 8: Commit viewer refresh**

```bash
git add theme_v2_service/app/domains/reports/api_reports.py theme_v2_service/tests/contract/test_report_api.py mobile/lib/theme_v2/report/report_models.dart mobile/lib/pages/report_viewer_page.dart mobile/test/theme_v2/report/report_viewer_refresh_test.dart
git commit -m "feat: refresh pending report illustrations in place"
```

### Task 7: Configure and Verify the Full Async Illustration Loop

**Files:**
- Modify: `docker-compose.theme-v2.yml`
- Modify: `deploy/docker-compose.theme-v2.prod.yml`
- Modify: `theme_v2_service/tests/e2e/test_report_generation_flow.py`
- Modify: `theme_v2_service/tests/unit/test_config.py`

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: a containerized 30-second continuation path ready for bounded real-device acceptance.

- [ ] **Step 1: Assert the exact default configuration**

```python
def test_optional_illustration_foreground_budget_is_30_seconds(monkeypatch):
    monkeypatch.delenv("REPORT_OPTIONAL_ILLUSTRATION_TIMEOUT_SECONDS", raising=False)
    get_settings.cache_clear()
    assert get_settings().report_optional_illustration_timeout_seconds == 30
```

- [ ] **Step 2: Ensure both Compose files pass illustration settings**

Pass the existing Seedream enabled/model/API URL/key/provider timeout and `REPORT_OPTIONAL_ILLUSTRATION_TIMEOUT_SECONDS=30` to the single worker process. No second Docker image or shared old-service worker is introduced.

- [ ] **Step 3: Add a deterministic delayed-image E2E**

The fake image provider blocks past the parent wait, writes its durable checkpoint, then completes. Assert the Report is readable with revision 1 before release and ready with revision 2 afterward.

- [ ] **Step 4: Run the complete Report backend suite**

Run: `cd theme_v2_service && pytest tests/unit/test_config.py tests/unit/test_report_pipeline.py tests/unit/test_report_rendering.py tests/integration/test_jobs.py tests/integration/test_report_jobs.py tests/integration/test_report_illustration_jobs.py tests/contract/test_report_api.py tests/contract/test_public_report_api.py tests/e2e/test_report_generation_flow.py -q`

Expected: PASS.

- [ ] **Step 5: Run the complete Flutter Report suite**

Run: `cd mobile && flutter test test/theme_v2/report`

Run: `cd mobile && flutter analyze lib/theme_v2/report lib/pages/report_viewer_page.dart test/theme_v2/report`

Expected: PASS and no analyzer issues.

- [ ] **Step 6: Run local Docker migration and readiness checks**

Run: `docker compose -f docker-compose.theme-v2.yml up -d --build migrate api worker`

Run: `curl -fsS http://127.0.0.1:8100/ready`

Expected: `{"status":"ready"}` and both worker lanes remain healthy.

- [ ] **Step 7: Commit the end-to-end gate**

```bash
git add docker-compose.theme-v2.yml deploy/docker-compose.theme-v2.prod.yml theme_v2_service/tests/e2e/test_report_generation_flow.py theme_v2_service/tests/unit/test_config.py
git commit -m "test: verify delayed report illustration backfill"
```
