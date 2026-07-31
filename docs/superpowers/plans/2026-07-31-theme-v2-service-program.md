# Theme V2 Independent Service Program Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coordinate the independent Theme V2 runtime, Notification, Trigger, Report Generation, and Today delivery into a sequence where every checkpoint produces working, testable software and no slice depends on the legacy Docker database.

**Architecture:** One greenfield FastAPI/Worker/MySQL runtime is established first, then durable Notification/Outbox, deterministic Trigger, Report workflow, and Today read/UI are layered on it. Each subsystem has its own executable plan and completion gate; integration happens through named interfaces rather than cross-plan code duplication.

**Tech Stack:** Docker Compose, Python 3.12, FastAPI, SQLAlchemy/Alembic, MySQL 8, database Job Queue, Transactional Outbox/SSE, Flutter/Dart, pytest, flutter_test/goldens.

## Global Constraints

- Canonical architecture: `docs/superpowers/specs/2026-07-31-theme-v2-service-runtime-design.md`.
- Backend product truth: `spec/design/theme-v2-notification.md`, `spec/design/theme-v2-trigger.md`, and `spec/design/theme-v2-report-generation.md`.
- Today truth: `spec/design/theme-v2-today-handoff.md` and Pen section `PYuZt` after the Pen owner lands changes.
- New runtime lives under `theme_v2_service/` and `docker-compose.theme-v2.yml`; it does not import or connect to `backend/`.
- Phase 1 uses MySQL + Transactional Outbox + database WorkflowJob. Do not add Redis, Kafka, Celery, PostgreSQL, or a second API instance.
- Preserve old code, Compose, data volume, and migration history. Never run `docker compose down -v` against the legacy project.
- Plans use TDD, short transactions, ownership checks, fake external providers, frequent commits, and their own completion gates.
- Do not execute the old Theme V2 program's Home/Goals tasks; Goal has left current scope.
- `docs/superpowers/plans/2026-07-31-theme-v2-today.md` supersedes the code/data tasks in `spec/design/docs/superpowers/plans/2026-07-31-remove-goals-home-adjustment.md`; the Pen owner remains responsible for Pen changes.

---

## Plan Set

| Order | Plan | Independent deliverable |
|---:|---|---|
| 1 | `2026-07-31-theme-v2-service-foundation.md` | Isolated API/Worker/MySQL, auth, core records, WorkflowJob |
| 2 | `2026-07-31-theme-v2-notification.md` | Persistent notification history, MySQL Outbox, SSE recovery |
| 3 | `2026-07-31-theme-v2-trigger.md` | Proactive-summary and pre-event executions |
| 4 | `2026-07-31-theme-v2-report-generation.md` | Planner, Pipeline, Report, Renderer, Share, Share Card |
| 5 | `2026-07-31-theme-v2-today.md` | `/api/today` plus Today-only Flutter Home |

Dependency graph:

```text
Foundation
├── Notification
│   ├── Trigger
│   │   └── Report Generation
│   └── Today backend read model
└── Today Flutter models/UI with fixtures

Report Generation + Today
└── integrated Theme V2 acceptance gate
```

Today Flutter Tasks 2–6 may run after Foundation interfaces stabilize, using injected fixtures. Today Task 1 and the real integration gate wait for Notification because Reka Queue is a Notification projection.

## Spec Coverage Matrix

| Source requirement | Owning plan/tasks |
|---|---|
| Runtime isolation, MySQL types, auth, Docker, API/Worker split | Foundation Tasks 1–6 |
| WorkflowJob claim, lease, retry, recovery | Foundation Task 5; Report Tasks 2, 4, 7, 10 |
| Notification model, retention, history, read/delete | Notification Tasks 1–3, 6 |
| MySQL Outbox, SSE heartbeat, duplicate/drop recovery | Notification Tasks 4–6 |
| Proactive threshold, revision, local-day reminder, Dismiss | Trigger Tasks 1–4 |
| Pre-event T-60, cancel/reschedule/expire, compensation | Trigger Tasks 5–6 |
| Trigger consumption and manual-report isolation | Trigger Task 4; Report Task 2 |
| Run state machine, decisions, active container, retry/cancel | Report Tasks 1–2, 7, 10 |
| Planner tools, bounded discovery, options, templates | Report Task 3 |
| Execution Plan, latest evidence, checkpointed Pipeline | Report Task 4 |
| Web policy, privacy, structured generation, Agent trust | Report Task 5 |
| Charts, illustration degradation, storage, official HTML | Report Task 6 |
| Report persistence, private ownership, notifications | Report Task 7 |
| Public snapshot/token/media authorization | Report Task 8 |
| 1080 × 1440 share card | Report Task 9 |
| Observability, expiry, all report acceptance scenarios | Report Task 10 |
| Today read source and explicit non-Goal Queue | Today Tasks 1–2 |
| Today-only state, centered geometry, active lifecycle | Today Tasks 3–5 |
| Light/Dark page and real-shell Dock goldens | Today Task 6 |
| New-backend-only Today integration and Goal absence | Today Task 7 |

---

### Task 1: Execute and approve the Service Foundation plan

**Files:**

- Plan: `docs/superpowers/plans/2026-07-31-theme-v2-service-foundation.md`
- Produces: `theme_v2_service/`, `docker-compose.theme-v2.yml`, `0001_foundation`.

**Interfaces:**

- Produces: `AsyncSessionFactory`, Bearer auth, UserSkill/Asset/Event, WorkflowJob, API/Worker image, ports 8100/3307.

- [ ] **Step 1: Execute every unchecked Foundation task in order**

Use the exact test and commit cycle in the Foundation plan. Do not start Notification code until its Completion Gate passes.

- [ ] **Step 2: Run the Foundation gate**

```bash
docker compose -f docker-compose.theme-v2.yml up -d --build
docker compose -f docker-compose.theme-v2.yml run --rm api alembic current
docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit tests/integration -q
curl -fsS http://localhost:8100/health
curl -fsS http://localhost:8100/ready
```

Expected: revision `0001_foundation (head)`, all Foundation tests pass, API/Worker are healthy, and no legacy resource appears in Compose config.

- [ ] **Step 3: Record the checkpoint commit**

```bash
git rev-parse --short HEAD
```

Expected: print the reviewed Foundation commit hash in the execution handoff; do not create or push a tag.

---

### Task 2: Execute and approve Notification

**Files:**

- Plan: `docs/superpowers/plans/2026-07-31-theme-v2-notification.md`
- Produces: migration `0002_notifications_outbox` and `/api/notifications`.

**Interfaces:**

- Consumes: Foundation session/auth/jobs.
- Produces: `create_notification(session, command)`, Outbox dispatcher, SSE registry, retention maintenance.

- [ ] **Step 1: Execute every unchecked Notification task in order**

Keep the API at one instance. Do not replace the Outbox dispatcher with direct Worker→API calls or in-process Worker publishing.

- [ ] **Step 2: Run the Notification gate**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm api alembic current
docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_notification_schemas.py tests/unit/test_subscribers.py tests/integration/test_notification_service.py tests/integration/test_notification_outbox.py tests/integration/test_notification_maintenance.py tests/contract/test_notification_api.py tests/contract/test_notification_sse.py tests/e2e/test_notification_flow.py -q
```

Expected: revision `0002_notifications_outbox (head)` and all Notification tests pass.

- [ ] **Step 3: Record the checkpoint commit**

```bash
git rev-parse --short HEAD
```

Expected: print the reviewed Notification commit hash in the execution handoff; do not create or push a tag.

---

### Task 3: Execute Trigger while starting Today UI fixtures

**Files:**

- Plan A: `docs/superpowers/plans/2026-07-31-theme-v2-trigger.md`
- Plan B: `docs/superpowers/plans/2026-07-31-theme-v2-today.md`, Tasks 2–6 only.

**Interfaces:**

- Trigger consumes Notification and Asset transactions.
- Today Flutter consumes only its repository interface and fixed fixtures during this parallel window.

- [ ] **Step 1: Run Trigger Tasks 1–6 in their listed order**

The Asset transaction hook and Worker maintenance changes share backend files, so keep Trigger backend execution serial within its stream.

- [ ] **Step 2: In a separate worktree or strictly separated commit stream, run Today Tasks 2–6**

Do not run Today backend Task 1 yet and do not edit the Pen file. If worktrees are used, create them with the required `superpowers:using-git-worktrees` skill at execution time.

- [ ] **Step 3: Run the Trigger completion gate**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm api alembic current
docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_trigger_definitions.py tests/unit/test_proactive_summary_rules.py tests/unit/test_pre_event_rules.py tests/integration/test_proactive_summary.py tests/integration/test_trigger_concurrency.py tests/integration/test_trigger_consumption.py tests/integration/test_pre_event_trigger.py tests/integration/test_trigger_compensation.py tests/contract/test_trigger_dismiss_api.py tests/e2e/test_trigger_notification_flow.py -q
```

Expected: revision `0003_triggers (head)` and all Trigger tests pass.

- [ ] **Step 4: Run the fixture-only Today gate**

```bash
cd mobile
flutter test test/theme_v2/home test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_shell_test.dart
flutter analyze lib/config.dart lib/theme_v2/home lib/theme_v2/shell/theme_v2_app_shell.dart test/theme_v2/home
```

Expected: all fixture-based Today tests and analysis pass; real `/api/today` integration remains unchecked.

---

### Task 4: Execute Report Generation R1–R10

**Files:**

- Plan: `docs/superpowers/plans/2026-07-31-theme-v2-report-generation.md`
- Produces: migrations `0004_report_workflow`, `0005_report_share`, Run/Report/Share APIs, Worker handlers, templates, renderer, media, and evals.

**Interfaces:**

- Consumes: Trigger `consume_execution`, Notification Outbox, WorkflowJob lease, Asset/Event records.
- Produces: complete Report lifecycle and public snapshot boundary.

- [ ] **Step 1: Execute Report Tasks 1–4 and stop at the R1–R4 checkpoint**

Run the plan's tests after each task. Confirm manual and Trigger origins, Planner decisions, template loading, Pipeline stages, cancellation, stale jobs, and checkpoint resume using fake providers.

- [ ] **Step 2: Run the mid-plan workflow proof**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit/test_report_state_machine.py tests/unit/test_template_registry.py tests/unit/test_report_pipeline.py tests/integration/test_report_run_service.py tests/integration/test_report_jobs.py tests/integration/test_report_planner.py tests/integration/test_report_evidence.py tests/contract/test_report_run_api.py -q
```

Expected: Run→Planner→Decision→fake Pipeline passes before adding provider/render/share complexity.

- [ ] **Step 3: Execute Report Tasks 5–10**

Keep external provider tests fake/offline. Manual real-provider evals require separately supplied credentials and are not a completion dependency.

- [ ] **Step 4: Run the full Report completion gate**

Use the exact pytest and eval commands in Report Task 10.

Expected: all R1–R10 tests and fake eval scenarios pass, including Trigger click through revoked public share.

---

### Task 5: Complete Today backend and real integration

**Files:**

- Plan: `docs/superpowers/plans/2026-07-31-theme-v2-today.md`, Tasks 1 and 7 plus any unchecked UI task.
- Produces: `/api/today`, real repository integration, page/shell goldens.

**Interfaces:**

- Consumes: UserSkill/Asset/Event, Notification history, independent API at 8100.
- Produces: one Theme V2 Home read call with explicit Reka Queue semantics.

- [ ] **Step 1: Execute Today backend Task 1**

The Queue allowlist is server-owned, filters by type rather than user copy, and reads only the new database.

- [ ] **Step 2: Re-run Today Flutter Tasks 2–6 against the landed Pen source**

Fixtures and geometry must match Pen section `PYuZt`; do not edit Pen. If Pen differs from the approved handoff, stop this subproject and report the exact node/spec mismatch rather than guessing.

- [ ] **Step 3: Execute Today Task 7 integration gate**

Start the Theme V2 stack, seed only the new database, query `/api/today`, and run focused Flutter tests/analysis.

Expected: Theme V2 Home performs no legacy Today endpoint calls and all six goldens pass.

---

### Task 6: Run the cross-subsystem release-candidate gate

**Files:**

- Test only unless a named failure requires a scoped correction.

**Interfaces:**

- Consumes: all five completed plans.
- Produces: a local Theme V2 release-candidate proof; it does not deploy or delete legacy resources.

- [ ] **Step 1: Rebuild from a clean Theme V2 image and empty Theme V2 volume**

Use a disposable, explicitly named Compose project for this verification so the development V2 volume remains recoverable:

```bash
docker compose -p eureka-theme-v2-rc -f docker-compose.theme-v2.yml up -d --build
```

Expected: MySQL healthy, all migrations apply from zero, API ready, Worker running.

- [ ] **Step 2: Run all backend tests with fake external providers**

```bash
docker compose -p eureka-theme-v2-rc -f docker-compose.theme-v2.yml run --rm test python -m pytest tests/unit tests/integration tests/contract tests/e2e -q
```

Expected: all Theme V2 backend tests pass.

- [ ] **Step 3: Run all focused Flutter tests and analysis**

```bash
cd mobile
flutter test test/theme_v2/home test/theme_v2/shell test/theme_v2/inbox
flutter analyze lib/config.dart lib/theme_v2 test/theme_v2
```

Expected: all focused tests pass and analysis reports no issues.

- [ ] **Step 4: Run the acceptance journey**

```text
login/token
→ create UserSkill and 7 Assets across eligible dates
→ report_available Notification/SSE
→ consume Trigger into Run
→ Planner decision
→ generate fake-backed Report
→ private viewer
→ public Share/media/card
→ revoke and verify 404
→ load Today and verify Queue/Agenda/Assets
```

Expected: one execution, one Run, one Report, no duplicate terminal Notification, and no cross-user leakage.

- [ ] **Step 5: Confirm legacy isolation**

```bash
docker compose -p eureka-theme-v2-rc -f docker-compose.theme-v2.yml config
```

Expected: no legacy volume, network, database name, service name, or backend path.

- [ ] **Step 6: Remove only the disposable RC project after verification**

```bash
docker compose -p eureka-theme-v2-rc -f docker-compose.theme-v2.yml down
```

Expected: RC containers/network are removed; no `-v` flag is used, and development/legacy volumes remain.

- [ ] **Step 7: Record the release-candidate commit**

```bash
git rev-parse --short HEAD
```

Record the hash in the handoff. Do not tag, push, deploy, stop legacy services, or switch all mobile routes without a separate user instruction.

---

## Final Completion Gate

- The Theme V2 service starts from an empty independent MySQL volume and survives API/Worker restarts.
- Notification, Trigger, Report, and Today contracts pass their own gates and one cross-subsystem journey.
- Redis and Kafka remain absent because no Phase 1 requirement needs them.
- Today-only Home is visually correct and uses the V2 `/api/today` read model.
- Legacy code and data remain intact; current scope does not yet authorize app-wide Calendar/Library backend cutover or legacy shutdown.
