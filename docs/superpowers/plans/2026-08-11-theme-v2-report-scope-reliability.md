# Theme V2 Report Scope Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make manual and Reka-initiated Reports confirm a type-specific scope before planning, use future meetings and Event notes correctly, support multi-select period summaries, and ground Event time in the user's local timezone.

**Architecture:** Extend the existing `ReportGenerationRun` rather than creating a second workflow. A focused scope-adapter module owns pre-event, period-summary, and generic candidate selection; confirmed scope is revisioned and then passed into the existing Planner. Reka aggregates available pre-event trigger executions, while evidence normalization exposes typed local temporal facts and generic evidence citations.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2 async, Alembic/MySQL 8, Pydantic v2, pytest/pytest-asyncio, Flutter/Dart, `ChangeNotifier`, widget tests.

## Global Constraints

- Manual `会前调研` must not ask for Report purpose again.
- Manual pre-event scope returns only the next three future active Events, ordered by local start time; the primary Event is single-select.
- Supporting Events, Contacts, Assets, and custom-skill records remain multi-select.
- Event Notes means the product remarks field stored as `Event.description`; it participates in Planner, scope resolution, Web Search query derivation, and Generator context.
- Period-summary Skill groups and individual records are both multi-select and default to all aggregatable records inside the explicit period.
- Period-summary Web Search defaults to off unless the user requests external comparison.
- Reka and Notifications expose the same trigger execution and must not create duplicate Runs.
- Event times shown to Report providers and validators use `DEFAULT_USER_TIMEZONE`, currently `Asia/Shanghai`.
- Do not merge or push during this plan.

---

### Task 1: Persist a Revisioned Scope Draft

**Files:**
- Create: `theme_v2_service/migrations/versions/0022_report_scope_draft.py`
- Modify: `theme_v2_service/app/domains/reports/models.py`
- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/tests/integration/test_migrations.py`
- Test: `theme_v2_service/tests/unit/test_report_schemas.py`

**Interfaces:**
- Produces: `ReportScopeDraft`, `ReportScopeDraftUpdate`, `ReportScopePrepareRequest`, and `ReportGenerationRun.scope_*` columns used by all later tasks.
- Consumes: existing `EvidenceReference`, `EvidenceScope`, and `TimeRange`.

- [ ] **Step 1: Write failing schema tests**

```python
def test_pre_event_scope_requires_one_primary_event():
    draft = ReportScopeDraft(
        adapter_kind="pre_event_briefing",
        primary_reference=EvidenceReference(kind="event", id="event-1"),
        supporting_references=[EvidenceReference(kind="contact", id="contact-1")],
    )
    assert draft.to_evidence_scope().references == [
        EvidenceReference(kind="event", id="event-1"),
        EvidenceReference(kind="contact", id="contact-1"),
    ]


def test_period_summary_scope_accepts_multiple_skills_and_records():
    draft = ReportScopeDraft(
        adapter_kind="period_summary",
        skill_ids=["water", "running"],
        supporting_references=[
            EvidenceReference(kind="asset", id="water-1"),
            EvidenceReference(kind="asset", id="run-1"),
        ],
        time_range={"from": "2026-08-10T00:00:00+08:00", "to": "2026-08-17T00:00:00+08:00"},
    )
    assert set(draft.skill_ids) == {"water", "running"}
    assert len(draft.to_evidence_scope().references) == 2
```

- [ ] **Step 2: Run the schema tests and verify failure**

Run: `cd theme_v2_service && pytest tests/unit/test_report_schemas.py -q`

Expected: FAIL because the scope draft types do not exist.

- [ ] **Step 3: Add strict scope models**

```python
ScopeAdapterKind = Literal["pre_event_briefing", "period_summary", "generic"]


class ReportScopeDraft(StrictModel):
    adapter_kind: ScopeAdapterKind
    primary_reference: EvidenceReference | None = None
    supporting_references: list[EvidenceReference] = Field(default_factory=list)
    skill_ids: list[str] = Field(default_factory=list)
    time_range: TimeRange | None = None
    attention_focus: list[str] = Field(default_factory=list, max_length=8)
    additional_focus: str = Field(default="", max_length=500)

    def to_evidence_scope(self) -> EvidenceScope:
        references = ([self.primary_reference] if self.primary_reference else []) + self.supporting_references
        return EvidenceScope(
            time_range=self.time_range,
            skill_ids=list(dict.fromkeys(self.skill_ids)),
            references=references,
        )


class ReportScopeDraftUpdate(StrictModel):
    expected_revision: int = Field(ge=0)
    draft: ReportScopeDraft


class ReportScopePrepareRequest(StrictModel):
    expected_revision: int = Field(ge=0)
```

- [ ] **Step 4: Add the migration and ORM columns**

```python
revision = "0022_report_scope_draft"
down_revision = "0021_capture_device_identity"


def upgrade() -> None:
    op.add_column("report_generation_runs", sa.Column("scope_adapter", sa.String(32), nullable=True))
    op.add_column("report_generation_runs", sa.Column("scope_draft", mysql.JSON(), nullable=True))
    op.add_column("report_generation_runs", sa.Column("scope_revision", sa.Integer(), nullable=False, server_default=sa.text("0")))
    op.add_column("report_generation_runs", sa.Column("scope_hash", sa.CHAR(64), nullable=True))
    op.add_column("report_generation_runs", sa.Column("plan_scope_hash", sa.CHAR(64), nullable=True))
```

Mirror these columns in `ReportGenerationRun` and update migration-head assertions to `0022_report_scope_draft`.

- [ ] **Step 5: Run focused tests**

Run: `cd theme_v2_service && pytest tests/unit/test_report_schemas.py tests/integration/test_migrations.py -q`

Expected: PASS.

- [ ] **Step 6: Commit the data contract**

```bash
git add theme_v2_service/migrations/versions/0022_report_scope_draft.py theme_v2_service/app/domains/reports/models.py theme_v2_service/app/domains/reports/schemas.py theme_v2_service/tests/unit/test_report_schemas.py theme_v2_service/tests/integration/test_migrations.py
git commit -m "feat: add report scope draft contract"
```

### Task 2: Build Pre-event and Period-summary Scope Adapters

**Files:**
- Create: `theme_v2_service/app/domains/reports/scope_adapters.py`
- Test: `theme_v2_service/tests/integration/test_report_scope_adapters.py`

**Interfaces:**
- Produces: `infer_scope_adapter(intent: str) -> ScopeAdapterKind`, `initial_scope(intent: str, *, now: datetime, timezone_name: str, trigger_event_id: str | None = None) -> ReportScopeDraft`, `list_scope_candidates(session: AsyncSession, *, user_id: str, adapter_kind: ScopeAdapterKind, intent: str, now: datetime, timezone_name: str) -> ReportScopeCandidateResponse`, and `scope_digest(draft: ReportScopeDraft, *, primary_version: str | None) -> str`.
- Consumes: Task 1 scope types, `Event`, `Asset`, `UserSkill`, `DEFAULT_USER_TIMEZONE`.

- [ ] **Step 1: Write failing adapter tests**

```python
async def test_pre_event_candidates_are_only_the_next_three(session, user_id):
    await seed_events(session, user_id=user_id, starts=[-60, 30, 60, 90, 120], cancelled_index=2)
    response = await list_scope_candidates(
        session,
        user_id=user_id,
        adapter_kind="pre_event_briefing",
        now=datetime(2026, 8, 11, 12, tzinfo=timezone.utc),
        timezone_name="Asia/Shanghai",
    )
    assert [item.local_start for item in response.events] == ["20:30", "21:30", "22:00"]


async def test_period_summary_defaults_all_in_period_records(session, user_id):
    response = await list_scope_candidates(
        session,
        user_id=user_id,
        adapter_kind="period_summary",
        intent="汇总这周我的记录",
        now=datetime(2026, 8, 11, 12, tzinfo=timezone.utc),
        timezone_name="Asia/Shanghai",
    )
    assert all(group.default_selected for group in response.record_groups)
    assert {item.reference.id for group in response.record_groups for item in group.records} == {"water-1", "run-1"}
```

- [ ] **Step 2: Run the adapter tests and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_scope_adapters.py -q`

Expected: FAIL because `scope_adapters` does not exist.

- [ ] **Step 3: Implement semantic category routing and local period resolution**

```python
def infer_scope_adapter(intent: str) -> ScopeAdapterKind:
    normalized = intent.casefold()
    if any(word in normalized for word in ("会前", "会议准备", "meeting brief")):
        return "pre_event_briefing"
    if any(word in normalized for word in ("汇总", "总结", "复盘")) and any(
        word in normalized for word in ("这周", "本周", "本月", "最近")
    ):
        return "period_summary"
    return "generic"


def resolve_report_period(intent: str, *, now: datetime, timezone_name: str) -> TimeRange:
    zone = ZoneInfo(timezone_name)
    local_now = now.astimezone(zone)
    monday = local_now.date() - timedelta(days=local_now.weekday())
    start = datetime.combine(monday, time.min, tzinfo=zone)
    return TimeRange(from_at=start, to_at=start + timedelta(days=7))
```

The router uses category markers rather than an exact full-sentence match. `resolve_report_period` also implements the accepted month/recent forms covered by tests.

- [ ] **Step 4: Implement future Event candidates and grouped record candidates**

Use `Event.start_at > utc_now`, exclude `status IN ('cancelled', 'deleted', 'completed')`, order ascending, and limit three. For period summaries, use `coalesce(Asset.effective_at, Asset.created_at)` inside the resolved UTC bounds, join `UserSkill`, group by Skill, and return each selected Asset reference plus safe display fields.

- [ ] **Step 5: Implement a canonical scope digest**

```python
def scope_digest(draft: ReportScopeDraft, *, primary_version: str | None) -> str:
    canonical = draft.model_dump(mode="json", by_alias=True)
    canonical["primary_version"] = primary_version
    encoded = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()
```

- [ ] **Step 6: Run adapter tests**

Run: `cd theme_v2_service && pytest tests/integration/test_report_scope_adapters.py -q`

Expected: PASS.

- [ ] **Step 7: Commit the adapters**

```bash
git add theme_v2_service/app/domains/reports/scope_adapters.py theme_v2_service/tests/integration/test_report_scope_adapters.py
git commit -m "feat: add report scope adapters"
```

### Task 3: Change Run Creation to Scope-first Planning

**Files:**
- Modify: `theme_v2_service/app/domains/reports/api_runs.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Modify: `theme_v2_service/app/domains/reports/planner.py`
- Modify: `theme_v2_service/app/domains/reports/state_machine.py`
- Test: `theme_v2_service/tests/contract/test_report_run_api.py`
- Test: `theme_v2_service/tests/integration/test_report_planner.py`

**Interfaces:**
- Produces: `GET /{run_id}/scope-candidates`, `PUT /{run_id}/scope-draft`, and `POST /{run_id}/prepare-plan`.
- Consumes: Task 2 adapter functions and existing Planner job.

- [ ] **Step 1: Write failing API tests**

```python
async def test_manual_pre_event_run_waits_for_scope_before_planner(client, session, auth):
    created = await client.post(
        "/api/report-generation-runs",
        headers=auth,
        json={"origin": "user_initiated", "intent": "会前调研"},
    )
    assert created.json()["state"] == "awaiting_selection"
    assert created.json()["pending_decision"]["type"] == "scope_confirmation"
    assert await session.scalar(select(func.count()).select_from(WorkflowJob)) == 0


async def test_prepare_plan_sets_event_before_planner(client, session, auth, event):
    run_id = await create_scope_run(client, auth)
    await client.put(
        f"/api/report-generation-runs/{run_id}/scope-draft",
        headers=auth,
        json={"expected_revision": 0, "draft": {"adapter_kind": "pre_event_briefing", "primary_reference": {"kind": "event", "id": event.id}}},
    )
    prepared = await client.post(
        f"/api/report-generation-runs/{run_id}/prepare-plan",
        headers=auth,
        json={"expected_revision": 1},
    )
    assert prepared.json()["state"] == "planning"
    assert prepared.json()["active_stage"] == "intake"
```

- [ ] **Step 2: Run the contract tests and verify failure**

Run: `cd theme_v2_service && pytest tests/contract/test_report_run_api.py -q`

Expected: FAIL because create still enqueues Planner and the scope endpoints do not exist.

- [ ] **Step 3: Create Runs in scope-confirmation state**

`create_user_run` now infers an adapter, writes an initial scope draft, sets `pending_decision={"type":"scope_confirmation","adapter_kind": adapter_kind}`, and leaves `planner_job_id=None`. Trigger Runs select `pre_event_briefing`, prefill their Event reference, and still consume the same trigger execution exactly once.

- [ ] **Step 4: Add owner-scoped scope service methods and endpoints**

```python
async def prepare_scope_plan(session, *, user_id: str, run_id: str, expected_revision: int):
    run = await owned_run_for_update(session, user_id=user_id, run_id=run_id)
    if run.scope_revision != expected_revision:
        raise RunConflict("scope revision is stale")
    draft = ReportScopeDraft.model_validate(run.scope_draft)
    await validate_scope_draft(session, run=run, draft=draft)
    run.evidence_scope = draft.to_evidence_scope().model_dump(mode="json", by_alias=True)
    if draft.primary_reference and draft.primary_reference.kind == "event":
        run.launch_context = {**run.launch_context, "event_id": draft.primary_reference.id}
    run.plan_scope_hash = run.scope_hash
    run.pending_decision = None
    await _enqueue_planner(session, run, reason=f"scope:{run.scope_hash}")
    transition_run(run, "planning")
    return run
```

- [ ] **Step 5: Bind Planner results and generation to the current scope hash**

When Planner persists options, it copies `scope_hash` into `plan_scope_hash`. `generate_run` rejects a Run when `scope_hash != plan_scope_hash`. Editing scope clears old options, draft, and selected option.

- [ ] **Step 6: Ensure Planner reads selected Event Notes before generating options**

The confirmed primary Event ID must be in `launch_context.event_id` and `EvidenceScope.references`; `build_planner_request` must load it through `PlannerTools.get_event`, whose `PlannerEvent.description` carries Event Notes.

- [ ] **Step 7: Run Run and Planner tests**

Run: `cd theme_v2_service && pytest tests/contract/test_report_run_api.py tests/integration/test_report_planner.py tests/integration/test_report_run_service.py -q`

Expected: PASS.

- [ ] **Step 8: Commit the scope-first service flow**

```bash
git add theme_v2_service/app/domains/reports/api_runs.py theme_v2_service/app/domains/reports/service.py theme_v2_service/app/domains/reports/planner.py theme_v2_service/app/domains/reports/state_machine.py theme_v2_service/tests/contract/test_report_run_api.py theme_v2_service/tests/integration/test_report_planner.py theme_v2_service/tests/integration/test_report_run_service.py
git commit -m "feat: plan reports after scope confirmation"
```

### Task 4: Re-resolve Public Research from Event Notes and Evidence Changes

**Files:**
- Modify: `theme_v2_service/app/domains/reports/scope_resolution.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Test: `theme_v2_service/tests/unit/test_report_generation_security.py`
- Test: `theme_v2_service/tests/integration/test_report_jobs.py`

**Interfaces:**
- Produces: `ScopeResolutionRequest.selected_evidence` and evidence-change-triggered resolution.
- Consumes: confirmed scope references and safe owned summaries.

- [ ] **Step 1: Write failing resolver tests**

```python
async def test_event_notes_shape_public_scope(session, configured_run, event):
    event.description = "讨论中国足球建设，主要对比欧美足球体系"
    request = await build_scope_resolution_request(session, configured_run)
    assert request.selected_evidence[0]["notes"] == event.description


async def test_reference_change_enqueues_scope_resolution(session, configured_run):
    command = ReportPlanDraftUpdate(
        expected_revision=configured_run.plan_revision,
        selected_option_id="option-1",
        evidence_scope=EvidenceScope(
            references=[EvidenceReference(kind="event", id="event-2")]
        ),
    )
    updated, job = await update_plan_draft(
        session,
        user_id=configured_run.user_id,
        run_id=configured_run.id,
        command=command,
    )
    assert job.job_type == "report_scope_resolution"
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_jobs.py -q`

Expected: FAIL because resolver input currently contains only free-form focus and current public scope.

- [ ] **Step 3: Extend the resolver request**

```python
class ScopeResolutionRequest(ScopeResolutionModel):
    additional_focus: str
    current_public_scope: PublicResearchBrief
    selected_evidence: list[dict[str, Any]] = Field(default_factory=list, max_length=20)
```

Load bounded owned Event/Asset/Contact summaries. Event summaries include title, Notes/description, location, local time, and attendees. The resolver prompt instructs the model to turn relevant Notes into public entities and research questions.

- [ ] **Step 4: Trigger resolution for meaningful evidence changes**

`update_plan_draft` compares normalized evidence references as well as additional focus. A changed reference set enqueues one deduplicated scope-resolution job for the new plan revision.

- [ ] **Step 5: Run resolver and security tests**

Run: `cd theme_v2_service && pytest tests/integration/test_report_jobs.py tests/unit/test_report_generation_security.py -q`

Expected: PASS.

- [ ] **Step 6: Commit scope enrichment**

```bash
git add theme_v2_service/app/domains/reports/scope_resolution.py theme_v2_service/app/domains/reports/service.py theme_v2_service/tests/integration/test_report_jobs.py theme_v2_service/tests/unit/test_report_generation_security.py
git commit -m "fix: enrich report research from selected evidence"
```

### Task 5: Add Pre-event Report Offers to Reka

**Files:**
- Modify: `theme_v2_service/app/domains/reka/service.py`
- Modify: `theme_v2_service/app/domains/reka/schemas.py`
- Modify: `mobile/lib/theme_v2/reka/reka_signal_models.dart`
- Modify: `mobile/lib/theme_v2/reka/reka_signal_repository.dart`
- Modify: `mobile/lib/theme_v2/reka/reka_signal_controller.dart`
- Test: `theme_v2_service/tests/integration/test_reka_signal_service.py`
- Test: `mobile/test/theme_v2/reka/reka_signal_controller_test.dart`

**Interfaces:**
- Produces: Reka signal `kind=report`, target `type=trigger_execution`.
- Consumes: existing available `TriggerExecution` rows and existing trigger Report route.

- [ ] **Step 1: Write failing Reka aggregation test**

```python
async def test_available_pre_event_execution_is_a_reka_report_signal(session, user_id):
    execution = TriggerExecution(
        user_id=user_id,
        trigger_type="pre_event_report",
        workflow_type="report_generation",
        scope_type="event",
        scope_id="event-1",
        status="available",
        dedupe_key="pre-event:event-1",
        revision=1,
        payload_json={"event_id": "event-1", "event_title": "球队建设会议"},
        first_fired_at=NOW,
        last_fired_at=NOW,
        expires_at=NOW + timedelta(hours=1),
    )
    session.add(execution)
    result = await list_signals(session, user_id=user_id, now=NOW, timezone_name="Asia/Shanghai")
    signal = next(item for item in result["signals"] if item["kind"] == "report")
    assert signal["natural_key"] == f"report:{execution.id}"
    assert signal["target"] == {"type": "trigger_execution", "id": execution.id}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_reka_signal_service.py -q`

Expected: FAIL because the Report source is not collected and the response schema rejects it.

- [ ] **Step 3: Collect and rank Report trigger candidates**

Query owned, `available`, unexpired `pre_event_report` executions. Validate that the target Event still exists and is future/active. Create `_SignalCandidate(rank=(0, -execution.first_fired_at.timestamp(), execution.id), actions=("open", "dismiss"))` with the stable natural key `report:<execution_id>`.

- [ ] **Step 4: Extend backend and Flutter discriminated values**

Add `report` to the signal kind and `trigger_execution` to the target type. Tapping the card calls the same `ReportRunController.startFromTrigger(executionId)` path used by Notifications.

- [ ] **Step 5: Verify one execution creates one Run across both surfaces**

Run: `cd theme_v2_service && pytest tests/integration/test_reka_signal_service.py tests/contract/test_report_run_api.py -q`

Run: `cd mobile && flutter test test/theme_v2/reka/reka_signal_controller_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit Reka Report signals**

```bash
git add theme_v2_service/app/domains/reka/service.py theme_v2_service/app/domains/reka/schemas.py theme_v2_service/tests/integration/test_reka_signal_service.py mobile/lib/theme_v2/reka mobile/test/theme_v2/reka/reka_signal_controller_test.dart
git commit -m "feat: surface pre-event reports in reka"
```

### Task 6: Ground Event Citations and Local Temporal Facts

**Files:**
- Modify: `theme_v2_service/app/domains/reports/evidence.py`
- Modify: `theme_v2_service/app/domains/reports/security.py`
- Modify: `theme_v2_service/app/domains/reports/normalization.py`
- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/app/domains/reports/pipeline.py`
- Test: `theme_v2_service/tests/integration/test_report_evidence.py`
- Test: `theme_v2_service/tests/unit/test_report_generation_security.py`
- Test: `theme_v2_service/tests/unit/test_report_normalization.py`

**Interfaces:**
- Produces: `EvidenceItem.temporal_facts`, generic `evidence_ids` citations, and typed temporal numeric allowlisting.
- Consumes: `ReportExecutionPlan.resolved_references` and `DEFAULT_USER_TIMEZONE`.

- [ ] **Step 1: Write the 21:00 regression test**

```python
async def test_event_evidence_is_local_and_citable(session, run, event):
    event.start_at = datetime(2026, 8, 11, 13, 0)  # stored UTC
    event.end_at = datetime(2026, 8, 11, 14, 0)
    bundle = await load_latest_evidence(
        session,
        run=run,
        execution_plan=ReportExecutionPlan.model_validate(run.execution_plan),
        registry=get_template_registry(),
        timezone_name="Asia/Shanghai",
    )
    item = bundle.user_evidence[0]
    assert item.temporal_facts.local_start_time == "21:00"
    assert item.temporal_facts.local_interval_text == "21:00–22:00"


def test_local_event_time_passes_numeric_validation(generator_request):
    result = generator_result("会议时间为 21:00。[evidence:event-1]")
    assert validate_generator_result(result, request=generator_request)
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_evidence.py tests/unit/test_report_generation_security.py -q`

Expected: FAIL because Event evidence is UTC-naive and event references are not allowed citation IDs.

- [ ] **Step 3: Add typed local temporal facts**

```python
class EvidenceTemporalFacts(EvidenceModel):
    timezone: str
    local_date: str
    local_start_time: str
    local_end_time: str
    local_interval_text: str
    duration_minutes: int
```

Convert stored UTC-naive Event times to aware UTC and then to `ZoneInfo(timezone_name)`. Generator-facing `effective_at`, `start_at`, and `end_at` use the local aware values.

- [ ] **Step 4: Generalize evidence citations**

`allowed_citation_tags` includes every `resolved_references` ID. `normalize_report_content` accepts `allowed_evidence_ids` plus the Asset-only subset and records `ReportCitation.evidence_ids`; `asset_ids` remains only the compatibility projection.

- [ ] **Step 5: Allow only typed temporal numbers**

Walk `temporal_facts` and explicitly add year, month, day, hour, minute, and duration strings. Do not weaken `NUMBER_RE` globally or allow arbitrary numbers from unrelated text.

- [ ] **Step 6: Run the Report correctness suite**

Run: `cd theme_v2_service && pytest tests/unit/test_report_generation_security.py tests/unit/test_report_normalization.py tests/integration/test_report_evidence.py tests/integration/test_report_pipeline.py -q`

Expected: PASS, including the 21:00 regression.

- [ ] **Step 7: Commit temporal grounding**

```bash
git add theme_v2_service/app/domains/reports/evidence.py theme_v2_service/app/domains/reports/security.py theme_v2_service/app/domains/reports/normalization.py theme_v2_service/app/domains/reports/schemas.py theme_v2_service/app/domains/reports/pipeline.py theme_v2_service/tests/integration/test_report_evidence.py theme_v2_service/tests/unit/test_report_generation_security.py theme_v2_service/tests/unit/test_report_normalization.py
git commit -m "fix: ground report event time and citations"
```

### Task 7: Build the Scope-first Flutter Stepper

**Files:**
- Modify: `mobile/lib/theme_v2/report/report_plan_models.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_controller.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_create_sheet.dart`
- Test: `mobile/test/theme_v2/report/report_run_controller_test.dart`
- Test: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Interfaces:**
- Produces: mobile states `范围 -> 方案 -> 生成`, future-Event single selection, and period-summary group/record multi-select.
- Consumes: Task 3 scope APIs and current evidence picker.

- [ ] **Step 1: Write failing controller tests**

```dart
test('manual pre-event loads candidates before planning', () async {
  await controller.startUserInitiated('会前调研');
  expect(controller.needsScopeConfirmation, isTrue);
  await controller.loadScopeCandidates();
  expect(controller.scopeCandidates.events.length, 3);
});

test('period summary preserves group and record multi-selection', () async {
  controller.toggleScopeGroup('water', false);
  controller.toggleScopeRecord(const EvidenceReferenceView(kind: 'asset', id: 'run-1'), true);
  expect(controller.scopeDraft.references.map((e) => e.id), ['run-1']);
});
```

- [ ] **Step 2: Run controller tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart`

Expected: FAIL because scope state and APIs do not exist.

- [ ] **Step 3: Add scope view models and controller methods**

Implement `ReportScopeDraftView`, `ReportScopeCandidateResponseView`, `loadScopeCandidates`, `saveScopeDraft`, and `preparePlan`. Scope mutations use optimistic `scope_revision` and preserve selection on retry.

- [ ] **Step 4: Reorder the stepper and render adapter-specific scope UI**

Change labels from `方案 / 范围 / 确认` to `范围 / 方案 / 生成`. Pre-event renders up to three large tappable Event cards with radio semantics. Period summary renders Skill group checkboxes and expandable record checkboxes. Supporting evidence opens the existing bottom-sheet picker and remains multi-select.

- [ ] **Step 5: Keep the quick path**

After Planner returns, the recommended option is selected. `按推荐方案生成` freezes the current revision in one tap; `调整范围` returns to Step 1 and invalidates the stale plan through the scope API.

- [ ] **Step 6: Run Flutter Report tests and analyze**

Run: `cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart test/theme_v2/report/report_run_page_test.dart test/theme_v2/report/report_evidence_picker_page_test.dart`

Run: `cd mobile && flutter analyze lib/theme_v2/report test/theme_v2/report`

Expected: all tests PASS and analyze reports no issues.

- [ ] **Step 7: Commit the scope-first UI**

```bash
git add mobile/lib/theme_v2/report mobile/test/theme_v2/report
git commit -m "feat: confirm report scope before planning"
```

### Task 8: End-to-end Scope Reliability Verification

**Files:**
- Modify: `theme_v2_service/tests/e2e/test_report_generation_flow.py`
- Modify: `docs/superpowers/specs/2026-08-11-theme-v2-report-reliability-scope-and-async-illustration-design.md` only if implementation reveals a factual mismatch.

**Interfaces:**
- Consumes: Tasks 1-7.
- Produces: one deterministic backend E2E and a ready-to-run real-device acceptance checklist.

- [ ] **Step 1: Add deterministic E2E coverage**

The fake Planner must assert it receives the selected Event and Notes. The fake Generator must return a citable 21:00 claim. The test must verify one Reka signal, one Run, one completed Report, and no `unreferenced numeric claim` failure.

- [ ] **Step 2: Run the complete backend Report/Reka suite**

Run: `cd theme_v2_service && pytest tests/unit/test_report_schemas.py tests/unit/test_report_generation_security.py tests/unit/test_report_normalization.py tests/contract/test_report_run_api.py tests/integration/test_report_scope_adapters.py tests/integration/test_report_planner.py tests/integration/test_report_evidence.py tests/integration/test_report_jobs.py tests/integration/test_reka_signal_service.py tests/e2e/test_report_generation_flow.py -q`

Expected: PASS.

- [ ] **Step 3: Run the complete Flutter Report/Reka suite**

Run: `cd mobile && flutter test test/theme_v2/report test/theme_v2/reka`

Run: `cd mobile && flutter analyze lib/theme_v2/report lib/theme_v2/reka test/theme_v2/report test/theme_v2/reka`

Expected: PASS and no analyzer issues.

- [ ] **Step 4: Commit the E2E gate**

```bash
git add theme_v2_service/tests/e2e/test_report_generation_flow.py
git commit -m "test: cover scope-first report reliability"
```
