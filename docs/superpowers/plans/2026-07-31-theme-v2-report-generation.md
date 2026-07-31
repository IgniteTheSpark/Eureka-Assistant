# Theme V2 Report Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the complete Theme V2 Report Generation workflow from user/Trigger launch through planning, evidence selection, durable pipeline execution, official rendering, private reports, public shares, protected media, and deterministic share cards.

**Architecture:** Every report starts as a durable `ReportGenerationRun`; Planner and Pipeline execute as leased WorkflowJobs and write checkpoints back to the Run. Versioned repository templates, capability-profile providers, deterministic renderers, and snapshot-based public shares preserve clear trust and authorization boundaries.

**Tech Stack:** FastAPI, SQLAlchemy 2 async, MySQL 8, WorkflowJob Worker, Notification Outbox, Pydantic, LiteLLM-compatible provider interface, httpx, markdown-it-py, Bleach, Jinja2, Pillow, qrcode, local/S3-compatible storage adapter, pytest.

## Global Constraints

- Requires Service Foundation, Notification, and Trigger plans.
- Product truth is `spec/design/theme-v2-report-generation.md`; runtime truth is the isolated service design.
- Every Report comes from exactly one `ReportGenerationRun`; each Run produces at most one Report.
- Trigger and user-initiated origins use the same Run API but manual runs never read or mutate Trigger cooldown.
- Every source passes through Planner; Pipeline accepts only immutable `ReportExecutionPlan`, never Wish, Genre, or Dispatcher output.
- Planner has read-only tools and cannot use Web Search, image generation, or write user data.
- Pipeline cannot select a new Template or expand Asset IDs.
- Asset IDs are references; Pipeline loads the latest authorized content at execution time.
- Page progress is polled from Run detail; do not add report-progress SSE.
- Optional Web or illustration failure degrades; required/authoritative Web failure is fatal and retryable.
- Charts are deterministic SVG/HTML; image models never generate numbers, axes, tables, or statistical claims.
- Public URLs contain only a random share token; the database stores only its hash.
- Public share reads immutable snapshots and never call private Report APIs.
- Trusted instructions are system policy, official Template Skill, and Execution Plan. Asset/Event/Web text is untrusted data.
- Tests use fake planner/generator/search/image providers unless a separate manual eval command is explicitly run.

---

## File Structure

### Create

- `theme_v2_service/app/domains/reports/models.py`
- `theme_v2_service/app/domains/reports/schemas.py`
- `theme_v2_service/app/domains/reports/state_machine.py`
- `theme_v2_service/app/domains/reports/service.py`
- `theme_v2_service/app/domains/reports/api_runs.py`
- `theme_v2_service/app/domains/reports/api_reports.py`
- `theme_v2_service/app/domains/reports/planner.py`
- `theme_v2_service/app/domains/reports/planner_tools.py`
- `theme_v2_service/app/domains/reports/templates.py`
- `theme_v2_service/app/domains/reports/pipeline.py`
- `theme_v2_service/app/domains/reports/evidence.py`
- `theme_v2_service/app/domains/reports/providers.py`
- `theme_v2_service/app/domains/reports/providers_litellm.py`
- `theme_v2_service/app/domains/reports/providers_web.py`
- `theme_v2_service/app/domains/reports/providers_image.py`
- `theme_v2_service/app/domains/reports/web_search.py`
- `theme_v2_service/app/domains/reports/charts.py`
- `theme_v2_service/app/domains/reports/rendering.py`
- `theme_v2_service/app/domains/reports/storage.py`
- `theme_v2_service/app/domains/reports/shares.py`
- `theme_v2_service/app/domains/reports/share_cards.py`
- `theme_v2_service/app/domains/reports/maintenance.py`
- `theme_v2_service/report-templates/<template>/template.json`
- `theme_v2_service/report-templates/<template>/SKILL.md`
- `theme_v2_service/app/static/report-v1.css`
- `theme_v2_service/app/templates/report.html.j2`
- `theme_v2_service/app/templates/public_report.html.j2`
- `theme_v2_service/migrations/versions/0004_report_workflow.py`
- `theme_v2_service/migrations/versions/0005_report_share.py`
- `theme_v2_service/tests/unit/test_report_state_machine.py`
- `theme_v2_service/tests/unit/test_template_registry.py`
- `theme_v2_service/tests/unit/test_report_pipeline.py`
- `theme_v2_service/tests/unit/test_chart_validation.py`
- `theme_v2_service/tests/unit/test_share_tokens.py`
- `theme_v2_service/tests/integration/test_report_run_service.py`
- `theme_v2_service/tests/integration/test_report_jobs.py`
- `theme_v2_service/tests/integration/test_report_persist.py`
- `theme_v2_service/tests/integration/test_report_shares.py`
- `theme_v2_service/tests/contract/test_report_run_api.py`
- `theme_v2_service/tests/contract/test_report_api.py`
- `theme_v2_service/tests/contract/test_public_report_api.py`
- `theme_v2_service/tests/e2e/test_report_workflow.py`
- `theme_v2_service/evals/report_scenarios.py`
- `theme_v2_service/evals/run_report_evals.py`

### Modify

- `theme_v2_service/app/config.py` — provider profiles, context limits, public base URL.
- `theme_v2_service/app/main.py` — private/public routes and static assets.
- `theme_v2_service/app/worker.py` and `app/jobs/registry.py` — Planner/Pipeline/maintenance handlers.
- `theme_v2_service/requirements.txt` — render/share/provider dependencies.
- `docker-compose.theme-v2.yml` and `.env.theme-v2.example` — provider/storage settings.

---

### Task 1: Add Report workflow persistence and pure state machine

**Files:**

- Create: `theme_v2_service/app/domains/reports/models.py`
- Create: `theme_v2_service/app/domains/reports/schemas.py`
- Create: `theme_v2_service/app/domains/reports/state_machine.py`
- Create: `theme_v2_service/migrations/versions/0004_report_workflow.py`
- Create: `theme_v2_service/tests/unit/test_report_state_machine.py`
- Create: `theme_v2_service/tests/integration/test_report_run_service.py`

**Interfaces:**

- Consumes: foundation Base and WorkflowJob.
- Produces: `ReportGenerationRun`, `Report`, `File`, state enums, `transition_run`, and API schemas.

- [ ] **Step 1: Write the failing state transition matrix**

```python
@pytest.mark.parametrize(("source", "target"), [
    ("planning", "awaiting_selection"),
    ("awaiting_selection", "planning"),
    ("awaiting_selection", "generating"),
    ("generating", "completed"),
    ("planning", "failed"),
    ("generating", "failed"),
    ("planning", "cancelled"),
    ("awaiting_selection", "expired"),
])
def test_allowed_transitions(source, target):
    assert transition_run(make_run(source), target).state == target


@pytest.mark.parametrize(("source", "target"), [
    ("completed", "generating"),
    ("cancelled", "planning"),
    ("expired", "generating"),
    ("planning", "completed"),
])
def test_forbidden_transitions(source, target):
    with pytest.raises(InvalidRunTransition): transition_run(make_run(source), target)
```

- [ ] **Step 2: Add ORM rows and constraints**

Implement all fields from spec sections 4 and 16. MySQL replaces the partial unique Trigger index with a nullable `trigger_execution_id` plus normal unique constraint; MySQL permits multiple `NULL` values. Add `UNIQUE(generation_run_id)` on Report. File fields are `id`, `user_id`, `purpose`, `mime_type`, `size_bytes`, `sha256`, `storage_key`, `created_at`.

- [ ] **Step 3: Define validated JSON schemas**

Create strict Pydantic models for `PendingDecision`, `ReportPlanOption`, `EvidenceScope`, `ReportExecutionPlan`, `GenerationContext`, `ReportSpec`, and `ShareCardSpec`. Configure `extra="forbid"` for Agent-produced structures.

- [ ] **Step 4: Implement state invariants**

`completed` requires `report_id` and `completed_at`; `failed` requires `failure_stage`, `error_code`, `error_message`, and `retry_from`; `awaiting_selection` requires a pending decision; `generating` requires `execution_plan` and `generation_job_id`. Terminal runs reject further writes.

- [ ] **Step 5: Apply migration and run tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm api alembic upgrade head`

Expected: current revision is `0004_report_workflow`.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_report_state_machine.py tests/integration/test_report_run_service.py -q`

Expected: state and constraint tests PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/reports/models.py theme_v2_service/app/domains/reports/schemas.py theme_v2_service/app/domains/reports/state_machine.py theme_v2_service/migrations/versions/0004_report_workflow.py theme_v2_service/tests/unit/test_report_state_machine.py theme_v2_service/tests/integration/test_report_run_service.py
git commit -m "feat(theme-v2): add report workflow state"
```

---

### Task 2: Create Runs atomically and expose the R1 API

**Files:**

- Create: `theme_v2_service/app/domains/reports/service.py`
- Create: `theme_v2_service/app/domains/reports/api_runs.py`
- Modify: `theme_v2_service/app/main.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Create: `theme_v2_service/tests/integration/test_report_jobs.py`
- Create: `theme_v2_service/tests/contract/test_report_run_api.py`

**Interfaces:**

- Consumes: `consume_execution`, `enqueue_job`, current user, Run models.
- Produces: create/list/detail/decision/generate/retry/cancel endpoints and current-job guards.

- [ ] **Step 1: Write failing origin and idempotency tests**

Cover user-initiated creation, available Trigger consumption, duplicate Trigger consumption returning the same Run, expired `410`, cross-user `404`, no Run on unclicked execution, duplicate Generate returning current job, and completed/cancelled mutation rejection.

- [ ] **Step 2: Implement user-initiated creation**

```python
async def create_user_run(session, *, user_id: str, command: UserRunCreate) -> ReportGenerationRun:
    scope = command.evidence_scope or EvidenceScope()
    run = ReportGenerationRun(user_id=user_id, origin="user_initiated", state="planning", intent=command.intent, evidence_scope=scope.model_dump(), launch_context={})
    session.add(run)
    await session.flush()
    job = await enqueue_job(session, run_id=run.id, job_type="report_planner", dedupe_key=f"planner:{run.id}:initial")
    run.planner_job_id = job.id
    return run
```

- [ ] **Step 3: Implement Trigger creation in one transaction**

Lock the owned TriggerExecution, create the Run, copy current execution payload into `launch_context`, call `consume_execution(session, user_id=user_id, execution_id=command.trigger_execution_id, workflow_run_id=run.id, now=utc_now())`, enqueue Planner, and commit once. If already consumed, return the linked Run.

- [ ] **Step 4: Implement current-job guarded decisions**

Submitting answers/evidence clears old `pending_decision` and `plan_options`, sets state `planning`, creates a uniquely keyed new Planner Job, and replaces `planner_job_id`. Generate resolves the selected option into `ReportExecutionPlan`, sets state `generating`, creates Pipeline Job, and replaces `generation_job_id`. Only a job whose ID equals the Run's current job ID may write back. Run-detail serialization exposes user-facing title, summary, goal, time range, Skill labels/counts, and Web/illustration intent; it must not expose template ID/version, base family, field-binding keys, model profile, Job lease, or raw launch context.

- [ ] **Step 5: Expose Run APIs**

```text
POST /api/report-generation-runs
GET  /api/report-generation-runs?active=true
GET  /api/report-generation-runs/{run_id}
POST /api/report-generation-runs/{run_id}/decision
POST /api/report-generation-runs/{run_id}/generate
POST /api/report-generation-runs/{run_id}/retry
POST /api/report-generation-runs/{run_id}/cancel
```

Return only current user data. Active list includes planning, awaiting_selection, generating, and failed; it excludes completed, cancelled, expired, and all Trigger-only state.

- [ ] **Step 6: Register fake handlers for R1**

Use deterministic handlers that move Planner to one fixed plan option and Pipeline to a minimal persisted report. They exist only in tests through dependency injection; production startup fails clearly when a required provider profile is missing rather than silently using demo content.

- [ ] **Step 7: Run API and job tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_report_jobs.py tests/contract/test_report_run_api.py -q`

Expected: origin, state, ownership, idempotency, cancellation, and stale-job tests PASS.

- [ ] **Step 8: Commit**

```bash
git add theme_v2_service/app/domains/reports/service.py theme_v2_service/app/domains/reports/api_runs.py theme_v2_service/app/main.py theme_v2_service/app/jobs/registry.py theme_v2_service/tests/integration/test_report_jobs.py theme_v2_service/tests/contract/test_report_run_api.py
git commit -m "feat(theme-v2): add report run api and jobs"
```

---

### Task 3: Implement Template Registry and bounded Report Planner

**Files:**

- Create: `theme_v2_service/app/domains/reports/templates.py`
- Create: `theme_v2_service/app/domains/reports/planner_tools.py`
- Create: `theme_v2_service/app/domains/reports/planner.py`
- Create: eight directories under `theme_v2_service/report-templates/`
- Create: `theme_v2_service/tests/unit/test_template_registry.py`
- Create: `theme_v2_service/tests/integration/test_report_planner.py`

**Interfaces:**

- Consumes: current Run, read-only UserSkill/Asset/Event tools, and `ReportPlannerProvider`.
- Produces: clarification or 1–3 validated `ReportPlanOption` values and `report_plan_ready` Notification.

- [ ] **Step 1: Write failing registry and planner tests**

Test duplicate template IDs, invalid semver, missing SKILL.md, unsupported policies, custom Skill names, primary-only baseline, bounded related discovery, clarification, one valid option, three-option maximum, and stale Planner write rejection.

- [ ] **Step 2: Add exact Phase 1 templates**

Create `child-growth-review`, `finance-review`, `idea-synthesis`, `work-monthly-review`, `tennis-monthly-review`, `learning-review`, `pre-event-briefing`, and `general-period-review`. Every `template.json` contains the spec's fields and a semver version; every SKILL.md defines evidence interpretation, analysis method, minimum data, sections, chart rules, citation rules, disclaimers, and share-card output.

- [ ] **Step 3: Implement repository-only Registry loading**

Use these exact public signatures:

```text
TemplateRegistry.load(root: Path) -> TemplateRegistry
TemplateRegistry.get(template_id: str, version: str | None = None) -> TemplatePackage
TemplateRegistry.candidates_for(capabilities: set[str]) -> list[TemplatePackage]
```

`load` recursively finds `template.json`, validates its sibling `SKILL.md`,
indexes packages by `(id, version)`, and raises `TemplateRegistryError` on a
duplicate. `get` returns the requested version or the highest semantic version.
`candidates_for` returns packages whose `data_fit` intersects the supplied
capabilities, sorted by ID and descending version.

Startup validates all manifests and fails on duplicates or malformed packages. No template table is created.

- [ ] **Step 4: Implement read-only bounded tools**

The Planner toolset exposes only the exact methods in the spec. Enforce configurable ceilings: at most 20 candidate Skills, 20 summaries per Skill, 100 total summaries, and a serialized context limit. The tools filter by current `user_id` on every query.

- [ ] **Step 5: Implement two-stage planning**

Build primary-only evidence first, then bounded related discovery. Validate provider output with `extra="forbid"`, require a primary-only option when evidence is sufficient, reject more than three options, and never call Web/image providers.

- [ ] **Step 6: Persist Planner result with stale-job guard**

Clarification sets `pending_decision.type=clarification`; sufficient planning stores options, sets `pending_decision.type=plan_selection`, transitions to `awaiting_selection`, and creates one deduplicated `report_plan_ready` Notification plus Outbox in the same transaction.

- [ ] **Step 7: Run Planner tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_template_registry.py tests/integration/test_report_planner.py -q`

Expected: registry, security, bounds, options, clarification, notification, and stale-job cases PASS.

- [ ] **Step 8: Commit**

```bash
git add theme_v2_service/app/domains/reports/templates.py theme_v2_service/app/domains/reports/planner_tools.py theme_v2_service/app/domains/reports/planner.py theme_v2_service/report-templates theme_v2_service/tests/unit/test_template_registry.py theme_v2_service/tests/integration/test_report_planner.py
git commit -m "feat(theme-v2): add report planner and templates"
```

---

### Task 4: Build the checkpointed Pipeline and evidence loader

**Files:**

- Create: `theme_v2_service/app/domains/reports/providers.py`
- Create: `theme_v2_service/app/domains/reports/evidence.py`
- Create: `theme_v2_service/app/domains/reports/pipeline.py`
- Create: `theme_v2_service/tests/unit/test_report_pipeline.py`
- Create: `theme_v2_service/tests/integration/test_report_evidence.py`

**Interfaces:**

- Consumes: immutable `ReportExecutionPlan`, latest owned Assets, provider protocols, and Run checkpoint.
- Produces: resumable stage results for load_evidence → web_search → content_generation → illustration → html_render → persist.

- [ ] **Step 1: Write the failing resume matrix**

Test fresh execution, deleted Asset, cross-user Asset, sufficient remainder, insufficient remainder, crash after content, crash after render, cancellation before writeback, and a superseded generation job.

- [ ] **Step 2: Define provider protocols**

Use these exact async protocol signatures:

```text
ReportPlannerProvider.plan(request: PlannerRequest) -> PlannerResult
ReportGeneratorProvider.generate(request: GeneratorRequest) -> GeneratorResult
WebSearchProvider.search(queries: list[str]) -> list[WebSource]
IllustrationProvider.generate(prompt: str) -> GeneratedImage
```

Each implementation is an async method. Production adapters convert provider
responses into the strict Pydantic result before returning; fake adapters
return constructor-injected results and count calls for resume assertions.

Add deterministic fakes under `tests/fakes/`, not production modules.

- [ ] **Step 3: Implement latest-evidence loading**

Query only `resolved_asset_ids` owned by Run user, preserve requested order, mark missing/cross-user IDs unavailable without distinguishing them, bind current payload fields, and evaluate Template minimum data before any paid call.

- [ ] **Step 4: Implement a stage runner with checkpoints**

```python
STAGES = ("load_evidence", "web_search", "content_generation", "illustration", "html_render", "persist")

async def execute_report_job(context: PipelineContext) -> None:
    for stage in STAGES[context.resume_index:]:
        await context.assert_current_and_not_cancelled()
        result = await context.handlers[stage](context)
        await context.save_checkpoint(stage, result)
```

Checkpoint writes update `active_stage`, `generation_context`, draft/file/HTML references, usage, and guarded Job lease in a short transaction. External calls happen outside transactions.

- [ ] **Step 5: Run pipeline and evidence tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_report_pipeline.py tests/integration/test_report_evidence.py -q`

Expected: resume, ownership, latest-content, cancellation, and stale-job cases PASS.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/reports/providers.py theme_v2_service/app/domains/reports/evidence.py theme_v2_service/app/domains/reports/pipeline.py theme_v2_service/tests/fakes theme_v2_service/tests/unit/test_report_pipeline.py theme_v2_service/tests/integration/test_report_evidence.py
git commit -m "feat(theme-v2): add checkpointed report pipeline"
```

---

### Task 5: Add privacy-safe Web Search and structured generation

**Files:**

- Create: `theme_v2_service/app/domains/reports/web_search.py`
- Create: `theme_v2_service/app/domains/reports/providers_litellm.py`
- Create: `theme_v2_service/app/domains/reports/providers_web.py`
- Create: `theme_v2_service/app/domains/reports/providers_image.py`
- Modify: `theme_v2_service/app/domains/reports/providers.py`
- Modify: `theme_v2_service/app/config.py`
- Modify: `theme_v2_service/requirements.txt`
- Modify: `.env.theme-v2.example`
- Create: `theme_v2_service/tests/unit/test_report_web_search.py`
- Create: `theme_v2_service/tests/unit/test_report_generation_security.py`

**Interfaces:**

- Consumes: Execution Plan web policy, abstracted evidence, Template Skill, capability profile settings.
- Produces: qualified `WebSource` rows and validated `GeneratorResult`.

- [ ] **Step 1: Write policy and privacy tests**

Test `none`, optional failure degradation, required retryable failure, authoritative-only rejection, query removal of names/addresses/raw text, source title/URL/access time, and prompt-injection text remaining quoted data.

- [ ] **Step 2: Implement query abstraction and source qualification**

`build_web_queries` receives only report goal, capability names, date range, and non-sensitive aggregate terms. It rejects any query token found in configured sensitive values. `authoritative_only` accepts configured government, university, standards, and recognized professional organization domains; it does not silently fall back.

- [ ] **Step 3: Implement capability-profile provider configuration**

Add `REPORT_PLANNER_MODEL`, `REPORT_GENERATOR_MODEL`, `REPORT_ILLUSTRATION_MODEL`, provider API keys, timeouts, and maximum attempts. Templates never contain model names. Missing profiles fail readiness only when the corresponding production handler is enabled.

Add `litellm>=1.53.0` to `requirements.txt`; use the already approved
`httpx>=0.28.0` for Web and image HTTP adapters.

- [ ] **Step 4: Validate structured generator output**

`GeneratorResult` contains `content_md`, `chart_directives`, optional `illustration_prompt`, `share_card_spec`, and usage. Reject unknown fields, unreferenced numeric claims, scripts/HTML supplied by the model, more than three highlights, or Asset/Skill/Run IDs in share-card copy.

- [ ] **Step 5: Implement production provider adapters**

`LiteLLMPlannerProvider` and `LiteLLMGeneratorProvider` call
`litellm.acompletion` with the configured capability profile, JSON-schema
response format, timeout, and no implicit tool access. They validate the parsed
object before returning and report token usage. `ConfiguredWebSearchProvider`
uses an injected `httpx.AsyncClient`, selects configured Bocha first and Tavily
second, normalizes URL/title/snippet/access time, and never retries a rejected
authoritative source as ordinary search. `OpenAICompatibleIllustrationProvider`
sends only the sanitized illustration prompt, rejects non-image MIME types, and
returns bytes plus MIME type. All adapters raise typed retryable/permanent
errors without logging request bodies or secrets.

- [ ] **Step 6: Run tests**

Run: `docker compose -f docker-compose.theme-v2.yml build api worker test`

Expected: image rebuild completes with the configured provider dependencies.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_report_web_search.py tests/unit/test_report_generation_security.py -q`

Expected: policy, privacy, validation, and injection tests PASS without network access.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/domains/reports/web_search.py theme_v2_service/app/domains/reports/providers.py theme_v2_service/app/domains/reports/providers_litellm.py theme_v2_service/app/domains/reports/providers_web.py theme_v2_service/app/domains/reports/providers_image.py theme_v2_service/app/config.py theme_v2_service/requirements.txt .env.theme-v2.example theme_v2_service/tests/unit/test_report_web_search.py theme_v2_service/tests/unit/test_report_generation_security.py
git commit -m "feat(theme-v2): add report provider policies"
```

---

### Task 6: Implement charts, media storage, illustration degradation, and official rendering

**Files:**

- Create: `theme_v2_service/app/domains/reports/charts.py`
- Create: `theme_v2_service/app/domains/reports/storage.py`
- Create: `theme_v2_service/app/domains/reports/rendering.py`
- Create: `theme_v2_service/app/static/report-v1.css`
- Create: `theme_v2_service/app/templates/report.html.j2`
- Modify: `theme_v2_service/requirements.txt`
- Create: `theme_v2_service/tests/unit/test_chart_validation.py`
- Create: `theme_v2_service/tests/unit/test_report_rendering.py`
- Create: `theme_v2_service/tests/integration/test_report_storage.py`

**Interfaces:**

- Consumes: evidence-derived directives, Markdown, illustration prompt, media root.
- Produces: deterministic SVG, owned File rows, sanitized HTML cache, and warning/checkpoint data.

- [ ] **Step 1: Write failing deterministic and safety tests**

Test chart values trace to evidence, invalid chart removal, no image-model chart path, illustration failure degradation, no Base64 image HTML, script stripping, fixed asset URLs, local storage path traversal rejection, and identical render input producing identical HTML.

- [ ] **Step 2: Implement chart validation and SVG rendering**

Allow only `line`, `bar`, and `summary` directives with explicit source paths. Resolve every value from Evidence or a registered pure reducer. Invalid directives return a warning and no SVG; they never alter narrative text.

- [ ] **Step 3: Implement storage adapter**

Use these exact async interfaces:

```text
Storage.put(key: str, content: bytes, mime_type: str) -> StoredObject
Storage.get(key: str) -> bytes
```

`LocalStorage.__init__(root: Path)` stores `root.resolve()`. `put` resolves the
candidate path, rejects it unless `candidate.is_relative_to(root)`, creates
parent directories, writes bytes in a worker thread, and returns key, byte
length, MIME type, and SHA-256. `get` applies the same containment check and
returns bytes from a worker thread.

Resolve every key under `media_root`, reject `..` or absolute paths, calculate SHA-256, and persist a user-owned File row. Keep an S3-compatible interface but do not add a MinIO service.

- [ ] **Step 4: Implement illustration degradation**

Send only the sanitized scene prompt. On any illustration failure, store `failed_degraded`, add a warning, skip the file, and continue to render. Reject generated content claiming text/chart output.

- [ ] **Step 5: Implement official HTML rendering**

Parse Markdown, sanitize with a strict tag/attribute allowlist, inject deterministic chart SVG and controlled media URLs, apply official CSS and fixed JS only, add lazy loading, and prohibit model-supplied script/style/event attributes. `content_md + spec_json` remain canonical; HTML is cache.

Add `markdown-it-py>=3.0.0`, `bleach>=6.2.0`, and `jinja2>=3.1.0` to
`requirements.txt`.

- [ ] **Step 6: Run tests**

Run: `docker compose -f docker-compose.theme-v2.yml build api worker test`

Expected: image rebuild completes with Markdown, sanitizing, template, and storage dependencies.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_chart_validation.py tests/unit/test_report_rendering.py tests/integration/test_report_storage.py -q`

Expected: all deterministic, security, storage, and degradation tests PASS.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/domains/reports/charts.py theme_v2_service/app/domains/reports/storage.py theme_v2_service/app/domains/reports/rendering.py theme_v2_service/app/static/report-v1.css theme_v2_service/app/templates/report.html.j2 theme_v2_service/requirements.txt theme_v2_service/tests/unit/test_chart_validation.py theme_v2_service/tests/unit/test_report_rendering.py theme_v2_service/tests/integration/test_report_storage.py
git commit -m "feat(theme-v2): render reports with protected media"
```

---

### Task 7: Persist Reports, expose private reads, and close the workflow

**Files:**

- Create: `theme_v2_service/app/domains/reports/api_reports.py`
- Modify: `theme_v2_service/app/domains/reports/pipeline.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Modify: `theme_v2_service/app/main.py`
- Create: `theme_v2_service/tests/integration/test_report_persist.py`
- Create: `theme_v2_service/tests/contract/test_report_api.py`

**Interfaces:**

- Consumes: completed render checkpoint and Notification service.
- Produces: exactly one Report per Run, private list/detail/viewer APIs, `report_done`/`report_failed` notifications.

- [ ] **Step 1: Write failure-window tests**

Test Worker retry at persist, unique Report, duplicate `report_done` prevention, stale lease, cancelled Run, private ownership `404`, active Run exclusion after completion, and fatal pipeline failure with retry metadata.

- [ ] **Step 2: Persist atomically**

In one guarded transaction create Report, set `run.report_id`, transition Run completed, mark Job succeeded, and create `report_done` Notification/Outbox. `UNIQUE(generation_run_id)` makes retry return the existing Report. Fatal failure stores failure fields, marks the active Job failed, and creates one `report_failed` Notification keyed by `report-run:<run_id>`.

- [ ] **Step 3: Expose private APIs**

```text
GET /api/reports
GET /api/reports/{report_id}
GET /app/reports/{report_id}
GET /api/files/{file_id}
```

All use current user ownership; missing and cross-user IDs return `404`. Report JSON includes content/spec needed by the private app but does not expose internal Job lease data.

- [ ] **Step 4: Run persistence and contract tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/integration/test_report_persist.py tests/contract/test_report_api.py -q`

Expected: retry, uniqueness, notification, ownership, list, detail, viewer, and file auth cases PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/api_reports.py theme_v2_service/app/domains/reports/pipeline.py theme_v2_service/app/domains/reports/service.py theme_v2_service/app/main.py theme_v2_service/tests/integration/test_report_persist.py theme_v2_service/tests/contract/test_report_api.py
git commit -m "feat(theme-v2): persist and serve private reports"
```

---

### Task 8: Add immutable public shares and protected media

**Files:**

- Create: `theme_v2_service/app/domains/reports/shares.py`
- Create: `theme_v2_service/app/templates/public_report.html.j2`
- Create: `theme_v2_service/migrations/versions/0005_report_share.py`
- Modify: `theme_v2_service/app/domains/reports/api_reports.py`
- Create: `theme_v2_service/tests/unit/test_share_tokens.py`
- Create: `theme_v2_service/tests/integration/test_report_shares.py`
- Create: `theme_v2_service/tests/contract/test_public_report_api.py`

**Interfaces:**

- Consumes: owned completed Report and referenced Files.
- Produces: `ReportShare`, create/revoke/public read/public media endpoints.

- [ ] **Step 1: Write token, snapshot, and authorization tests**

Test random token length, SHA-256-only persistence, 30-day default expiry, immutable snapshot, revoke, expired `404`, public payload without internal IDs, media-key isolation, and immediate media revocation.

- [ ] **Step 2: Add ReportShare migration**

Implement all spec fields, unique `token_hash`, index `(user_id, created_at)`, and status/expiry index. `media_map_json` maps random media keys to File IDs; public serialization never returns this map or any File ID.

- [ ] **Step 3: Implement token helpers**

```python
def issue_share_token() -> str:
    return secrets.token_urlsafe(32)


def hash_share_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
```

Never log or persist the raw token after the create response is formed.

- [ ] **Step 4: Implement snapshot creation and public lookup**

Create copies of report Markdown, public-safe spec, sanitized HTML, and media map. Public lookup hashes the token, requires active/unexpired status, renders from snapshot only, sets `X-Robots-Tag: noindex`, and never calls private Report retrieval.

- [ ] **Step 5: Expose share routes**

```text
POST   /api/reports/{report_id}/shares
DELETE /api/report-shares/{share_id}
GET    /api/public/report-shares/{share_token}
GET    /r/{share_token}
GET    /r/{share_token}/media/{media_key}
```

- [ ] **Step 6: Run tests**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm api alembic upgrade head`

Expected: current revision is `0005_report_share`.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_share_tokens.py tests/integration/test_report_shares.py tests/contract/test_public_report_api.py -q`

Expected: all share and media authorization tests PASS.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/domains/reports/shares.py theme_v2_service/app/templates/public_report.html.j2 theme_v2_service/migrations/versions/0005_report_share.py theme_v2_service/app/domains/reports/api_reports.py theme_v2_service/tests/unit/test_share_tokens.py theme_v2_service/tests/integration/test_report_shares.py theme_v2_service/tests/contract/test_public_report_api.py
git commit -m "feat(theme-v2): add secure report sharing"
```

---

### Task 9: Generate deterministic 1080 × 1440 share cards

**Files:**

- Create: `theme_v2_service/app/domains/reports/share_cards.py`
- Modify: `theme_v2_service/app/domains/reports/shares.py`
- Modify: `theme_v2_service/requirements.txt`
- Modify: `theme_v2_service/Dockerfile`
- Create: `theme_v2_service/tests/unit/test_share_cards.py`
- Create: `theme_v2_service/tests/integration/test_share_card_storage.py`

**Interfaces:**

- Consumes: validated `ShareCardSpec`, optional illustration File, and public share URL.
- Produces: deterministic PNG File and Open Graph image reference.

- [ ] **Step 1: Write failing card-contract tests**

Assert exact 1080 × 1440 PNG, no more than three highlights, stable layout without illustration, QR points to current share URL, internal IDs absent from rendered metadata, and generation failure not changing Report completion.

- [ ] **Step 2: Implement a deterministic Pillow renderer**

Install `fonts-noto-cjk` in the Theme V2 Docker image and resolve it by a fixed
container path for Chinese fallback while Geist remains the Latin display face.
Use fixed margins, controlled text wrapping, a no-illustration fallback block,
and qrcode generated locally from the public URL. Assert both resolved font
paths during API/Worker readiness. Do not invoke another summary Agent.

Add `pillow>=10.4.0` and `qrcode>=7.4.2` to `requirements.txt`.

- [ ] **Step 3: Store and authorize the card**

Persist as File purpose `report_share_card`; set `share_card_file_id`; expose it only through the active Share token path. On failure record a warning and allow the user to retry card generation without regenerating Report content.

- [ ] **Step 4: Run tests**

Run: `docker compose -f docker-compose.theme-v2.yml build api worker test`

Expected: the image contains Pillow, qrcode, Geist assets, and `fonts-noto-cjk`.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_share_cards.py tests/integration/test_share_card_storage.py -q`

Expected: geometry, content, QR, storage, fallback, and retry cases PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/share_cards.py theme_v2_service/app/domains/reports/shares.py theme_v2_service/requirements.txt theme_v2_service/Dockerfile theme_v2_service/tests/unit/test_share_cards.py theme_v2_service/tests/integration/test_share_card_storage.py
git commit -m "feat(theme-v2): add deterministic report share cards"
```

---

### Task 10: Add expiry, observability, evals, and the full workflow gate

**Files:**

- Create: `theme_v2_service/app/domains/reports/maintenance.py`
- Create: `theme_v2_service/app/observability.py`
- Modify: `theme_v2_service/app/worker.py`
- Create: `theme_v2_service/evals/report_scenarios.py`
- Create: `theme_v2_service/evals/run_report_evals.py`
- Create: `theme_v2_service/tests/integration/test_report_maintenance.py`
- Create: `theme_v2_service/tests/e2e/test_report_workflow.py`

**Interfaces:**

- Consumes: awaiting Runs, Shares, WorkflowJobs, fake providers, metrics sink.
- Produces: expiry/cleanup ticks, required metrics, offline eval harness, and end-to-end acceptance proof.

- [ ] **Step 1: Write failing maintenance tests**

Test awaiting selection expires after 7 days, planning/generating timeout becomes failed rather than expired, expired/revoked share media immediately fails, completed Run stays immutable, and repeated maintenance is idempotent.

- [ ] **Step 2: Add structured metrics and sanitized logging**

Emit the exact Planner, Pipeline, Workflow, Share, Job lease, and Outbox metrics from the spec/runtime design. Structured logs may contain run/job/report/share IDs and error codes; they must redact Asset payload, Event description, full Web query, prompts, credentials, and raw share tokens.

- [ ] **Step 3: Add offline eval scenarios**

Create deterministic fixtures for custom baby Skills, combined evidence, tennis review, idea synthesis, manual-report isolation, deleted Assets, Web policy matrix, illustration degradation, Worker recovery, public share, and prompt injection. `run_report_evals.py` accepts injected providers and outputs JSON summary; default execution uses fakes and no network.

- [ ] **Step 4: Write the end-to-end workflow**

The test runs:

```text
Asset threshold → report_available SSE/history
Trigger click → Run.planning + Planner Job
fake Planner → awaiting_selection + report_plan_ready
decision/generate → Pipeline Job
fake Pipeline → Report + report_done
private read → create Share → public read/media/card
revoke → public page/media/card all return 404
```

- [ ] **Step 5: Run the complete Report gate**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_report_state_machine.py tests/unit/test_template_registry.py tests/unit/test_report_pipeline.py tests/unit/test_report_web_search.py tests/unit/test_report_generation_security.py tests/unit/test_chart_validation.py tests/unit/test_report_rendering.py tests/unit/test_share_tokens.py tests/unit/test_share_cards.py tests/integration/test_report_run_service.py tests/integration/test_report_jobs.py tests/integration/test_report_planner.py tests/integration/test_report_evidence.py tests/integration/test_report_storage.py tests/integration/test_report_persist.py tests/integration/test_report_shares.py tests/integration/test_share_card_storage.py tests/integration/test_report_maintenance.py tests/contract/test_report_run_api.py tests/contract/test_report_api.py tests/contract/test_public_report_api.py tests/e2e/test_report_workflow.py -q`

Expected: all Report tests PASS without real external providers.

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test python -m evals.run_report_evals --provider fake`

Expected: every required scenario reports `passed: true`.

- [ ] **Step 6: Commit**

```bash
git add theme_v2_service/app/domains/reports/maintenance.py theme_v2_service/app/observability.py theme_v2_service/app/worker.py theme_v2_service/evals theme_v2_service/tests/integration/test_report_maintenance.py theme_v2_service/tests/e2e/test_report_workflow.py
git commit -m "test(theme-v2): complete report workflow gate"
```

---

## Completion Gate

- R1–R10 are implemented with durable, inspectable state and no legacy Report path.
- Planner and Pipeline never bypass Run/WorkflowJob; stale jobs and leases cannot overwrite current state.
- Every acceptance scenario in spec section 25 has a named test or eval.
- Private reports, public snapshots, media, and share cards obey separate authorization boundaries.
- Failure and resume behavior avoids duplicate Reports, duplicate terminal notifications, repeated paid stages, and leaked content.
- No production code uses Wish, Genre-first routing, Report Dispatcher, Redis, Kafka, or a synchronous bypass endpoint.
