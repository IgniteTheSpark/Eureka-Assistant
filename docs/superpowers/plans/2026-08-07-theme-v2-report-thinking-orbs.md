# Theme V2 Unified Report and Thinking Orbs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Preserve unrelated working-tree changes and commit only files owned by each task.

**Goal:** Make every Report entry use one understandable plan-and-scope workflow with useful public research, while giving hardware/offline capture one consistent Thinking Orbs work-state language in the global header and matching Session.

**Architecture:** Deliver two independently testable vertical slices. Report stores an editable, revisioned `ReportPlanDraft`, resolves private references into a typed internal evidence bundle, emits only a minimal `PublicResearchBrief` to Web Search, and freezes both into an immutable execution plan. Capture sources publish neutral typed activity events; a Theme V2 coordinator merges local and server identities, chooses one visible task, and renders the same normalized phase in the global header and Session transcript.

**Tech Stack:** FastAPI, Pydantic v2, SQLAlchemy/Alembic, MySQL JSON, existing Workflow Jobs/SSE, LiteLLM/DeepSeek, pytest; Flutter/Dart, `CustomPainter`, `http`, `webview_flutter`, `url_launcher`, flutter_test.

**Design sources:**

- `docs/superpowers/specs/2026-08-07-theme-v2-unified-report-planning-research-design.md`
- `docs/superpowers/specs/2026-08-07-theme-v2-thinking-orbs-capture-status-design.md`

## Global constraints

- Keep the current service topology, Workflow Job registry, Report renderer, Session model, and BLE/ring SDK integrations. This is an app-layer migration, not an architecture rewrite.
- “资产” in product copy includes generic/custom assets, Events, and Contacts. Persistence and service code use `EvidenceReference(kind, id)` because Events and Contacts are first-class tables.
- User-selected assets and descriptions remain private/internal evidence. Only a typed, bounded `PublicResearchBrief` reaches Web Search.
- “时间范围” is not a generic Report-plan control. Use a contextual report period for retrospective/data reports and research freshness for public research.
- Quick generate applies the recommended plan with recommended evidence and research defaults in one action. It is the same execution path as manual confirmation, not a second generator.
- Report and Thinking Orbs share no persistence or controller state. Failure in one slice must not disable the other.
- Do not add a new audio-file picker. Integrate the existing ring/card realtime and offline-upload paths; expose a typed `audioUpload` source adapter for an existing/future UI entry.
- Thinking Orbs uses Flutter-native drawing, not a WebView, npm package, or copied repository asset.
- Reduced-motion refinements and additional accessibility motion settings remain explicitly pending, per product decision. Existing semantics and tap targets must not regress.
- Every backend read is owner-scoped. Every mutable Report-plan request uses optimistic `expected_revision`.
- Preserve legacy API fields (`asset_ids`, `resolved_asset_ids`) as projections during migration so existing clients and stored runs remain readable.

## File structure

### Report backend

- Modify `theme_v2_service/app/domains/reports/schemas.py`: typed references, research brief, blockers, editable draft, frozen execution plan.
- Modify `theme_v2_service/app/domains/reports/models.py`: persist `plan_draft`, `plan_revision`, and scope-resolution job id.
- Create `theme_v2_service/migrations/versions/0018_report_plan_draft.py`: additive nullable/defaulted migration.
- Modify `theme_v2_service/app/domains/reports/planner.py`: produce recommended focus, references, and public entities from complete event context.
- Modify `theme_v2_service/app/domains/reports/evidence.py`: resolve typed owned Asset/Event/Contact references.
- Create `theme_v2_service/app/domains/reports/evidence_options.py`: unified picker query projection.
- Create `theme_v2_service/app/domains/reports/scope_resolution.py`: deterministic/LLM bounded-focus-to-public-brief resolver.
- Modify `theme_v2_service/app/domains/reports/service.py`: draft lifecycle, revision checks, freeze-at-generate.
- Modify `theme_v2_service/app/domains/reports/api_runs.py`: draft and evidence-options endpoints.
- Modify `theme_v2_service/app/jobs/registry.py`: register `report_scope_resolution`.
- Modify `theme_v2_service/app/domains/reports/web_search.py`: typed query construction and source qualification.
- Modify `theme_v2_service/app/domains/reports/providers.py`: query/source provenance types.
- Modify `theme_v2_service/app/domains/reports/providers_deepseek_web.py`: reject URL-only tool results.
- Modify `theme_v2_service/app/domains/reports/pipeline.py`: search only from frozen public brief.
- Modify `theme_v2_service/app/domains/reports/presentation/blocks.py`: safe Markdown link rendering.

### Report mobile

- Create `mobile/lib/theme_v2/report/report_plan_models.dart`: typed plan draft and evidence option models.
- Modify `mobile/lib/theme_v2/report/report_run_controller.dart`: revisioned draft updates and quick/manual generation.
- Modify `mobile/lib/theme_v2/report/report_run_page.dart`: compact recommended card plus three-step adjustment flow.
- Create `mobile/lib/theme_v2/report/report_evidence_picker_page.dart`: full-screen grouped/searchable picker.
- Modify `mobile/lib/pages/report_viewer_page.dart`: open qualified external links outside the WebView.
- Modify `mobile/pubspec.yaml`: add `url_launcher`.

### Thinking Orbs backend/mobile

- Modify `theme_v2_service/app/domains/capture/schemas.py`, `service.py`, and `jobs.py`: stable task/recording/session identity plus normalized display phase.
- Create `mobile/lib/capture_activity/capture_activity_event.dart` and `capture_activity_bus.dart`: product-neutral event contract.
- Modify `mobile/lib/ble_flash/ble_flash_manager.dart`, `mobile/lib/flash_file_workflow.dart`, `mobile/lib/ring/ring_capture_controller.dart`, `mobile/lib/ring/ring_capture_service.dart`, and `mobile/lib/flash/flash.dart`: publish stable source events and correlate backend IDs.
- Create `mobile/lib/theme_v2/capture/capture_activity_models.dart`, `capture_activity_coordinator.dart`, `thinking_orb.dart`, and `capture_activity_top_bar.dart`.
- Modify `mobile/lib/app_events.dart`, `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`, and `theme_v2_global_top_nav.dart`: coordinator lifecycle and full-header takeover.
- Modify `mobile/lib/theme_v2/chat/chat_models.dart`, `chat_controller.dart`, `mobile/lib/theme_v2/capture/capture_session_controller.dart`, `mobile/lib/theme_v2/session/session_analysis_block.dart`, `session_transcript.dart`, and `theme_v2_session_page.dart`: normalized inline work state and live capture text.

---

## Task 1: Introduce the revisioned Report plan contract

**Files:**

- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/app/domains/reports/models.py`
- Create: `theme_v2_service/migrations/versions/0018_report_plan_draft.py`
- Test: `theme_v2_service/tests/unit/test_report_schemas.py`
- Test: `theme_v2_service/tests/integration/test_report_run_service.py`

**Step 1: Write failing schema tests**

Add tests for these invariants:

```python
def test_plan_draft_accepts_typed_event_contact_and_asset_references():
    draft = ReportPlanDraft.model_validate({
        "selected_option_id": "recommended",
        "attention_questions": ["球队建设的当前短板是什么？"],
        "additional_focus": "补充 Kevin 的公开职业背景",
        "evidence_scope": {"references": [
            {"kind": "event", "id": "event-1"},
            {"kind": "contact", "id": "contact-1"},
            {"kind": "asset", "id": "asset-1"},
        ]},
        "public_research_scope": {"entities": [], "questions": [], "freshness": "current"},
        "blockers": [],
    })
    assert [ref.kind for ref in draft.evidence_scope.references] == ["event", "contact", "asset"]


def test_generate_request_requires_matching_plan_revision():
    request = RunGenerateRequest(
        selected_option_id="recommended",
        expected_plan_revision=3,
    )
    assert request.expected_plan_revision == 3
```

Run: `cd theme_v2_service && .venv/bin/pytest tests/unit/test_report_schemas.py -q`

Expected: FAIL because the new types do not exist.

**Step 2: Implement additive schemas**

Implement:

```python
EvidenceKind = Literal["asset", "event", "contact"]

class EvidenceReference(StrictModel):
    kind: EvidenceKind
    id: str = Field(min_length=1)

class ResearchEntity(StrictModel):
    id: str
    kind: Literal["organization", "person", "topic", "product", "place"]
    name: str
    qualifier: str | None = None
    enabled: bool = True

class PublicResearchBrief(StrictModel):
    entities: list[ResearchEntity] = Field(default_factory=list)
    questions: list[str] = Field(default_factory=list, max_length=8)
    freshness: Literal["current", "recent_year", "historical", "not_applicable"] = "current"

class PlanBlocker(StrictModel):
    code: Literal["ambiguous_person", "missing_public_entity", "empty_scope"]
    message: str
    entity_id: str | None = None

class ReportPlanDraft(StrictModel):
    selected_option_id: str
    attention_questions: list[str] = Field(default_factory=list, max_length=8)
    additional_focus: str = Field(default="", max_length=500)
    evidence_scope: EvidenceScope
    public_research_scope: PublicResearchBrief
    blockers: list[PlanBlocker] = Field(default_factory=list)
```

Extend `EvidenceScope` with `references`; normalize legacy `asset_ids` into asset-kind references and keep the projection. Extend `ReportExecutionPlan` with frozen `resolved_references`, `attention_questions`, and `public_research_brief`. Extend `RunGenerateRequest` with `expected_plan_revision`.

**Step 3: Add model columns and migration**

Add:

```python
plan_draft: Mapped[dict | None] = mapped_column(mysql.JSON)
plan_revision: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
scope_resolution_job_id: Mapped[str | None] = mapped_column(CHAR(36))
```

Migration `0018_report_plan_draft` must have `down_revision = "0017_legacy_agent_data_backfill"`, use additive columns, set server default `0` for `plan_revision`, and downgrade only these columns.

**Step 4: Run focused tests and migration import check**

Run:

```bash
cd theme_v2_service
.venv/bin/pytest tests/unit/test_report_schemas.py tests/integration/test_report_run_service.py -q
.venv/bin/python -m compileall app/domains/reports migrations/versions/0018_report_plan_draft.py
```

Expected: PASS.

**Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/schemas.py theme_v2_service/app/domains/reports/models.py theme_v2_service/migrations/versions/0018_report_plan_draft.py theme_v2_service/tests/unit/test_report_schemas.py theme_v2_service/tests/integration/test_report_run_service.py
git commit -m "feat(report): add revisioned planning contract"
```

## Task 2: Preserve complete private event/contact/asset evidence

**Files:**

- Modify: `theme_v2_service/app/domains/reports/planner.py`
- Modify: `theme_v2_service/app/domains/reports/evidence.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Test: `theme_v2_service/tests/integration/test_report_planner.py`
- Test: `theme_v2_service/tests/integration/test_report_evidence.py`
- Test: `theme_v2_service/tests/e2e/test_report_generation_flow.py`

**Step 1: Add the exact event regression**

Create an owned Event whose title is `球队建设情况讨论`, description requests comparison with 皇家马德里 and 巴塞罗那, and linked contact Kevin. Assert that the planned draft references the Event/Contact, retains the full private description in internal evidence, and proposes organization entities `皇家马德里` and `巴塞罗那` without placing the full description into the public brief.

Run: `cd theme_v2_service && .venv/bin/pytest tests/integration/test_report_planner.py tests/integration/test_report_evidence.py -q`

Expected: FAIL because the current execution scope loses the Event description.

**Step 2: Resolve typed owned evidence**

Add one owner-scoped resolver:

```python
async def resolve_evidence_references(
    session: AsyncSession,
    *,
    user_id: str,
    references: list[EvidenceReference],
) -> ResolvedEvidence:
    """Return ordered Asset/Event/Contact snapshots and unavailable refs."""
```

The returned bundle must keep `kind`, `id`, canonical title, complete internal fields, and effective time. It must never silently resolve another user's record. Legacy asset IDs become asset references.

**Step 3: Seed the initial editable draft from the recommended plan**

When planning reaches `awaiting_selection`, populate `run.plan_draft` from the recommended option. Include recommended attention questions, typed references, entity suggestions, freshness, and blockers. Increment `plan_revision` exactly once per persisted semantic change.

**Step 4: Verify the end-to-end planning boundary**

Assert the generator request receives full internal Event evidence, while the fake Web Search provider receives only typed public entities/questions.

Run: `cd theme_v2_service && .venv/bin/pytest tests/integration/test_report_planner.py tests/integration/test_report_evidence.py tests/e2e/test_report_generation_flow.py -q`

Expected: PASS.

**Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/planner.py theme_v2_service/app/domains/reports/evidence.py theme_v2_service/app/domains/reports/service.py theme_v2_service/tests/integration/test_report_planner.py theme_v2_service/tests/integration/test_report_evidence.py theme_v2_service/tests/e2e/test_report_generation_flow.py
git commit -m "fix(report): preserve typed private evidence"
```

## Task 3: Add unified evidence options and editable plan-draft APIs

**Files:**

- Create: `theme_v2_service/app/domains/reports/evidence_options.py`
- Create: `theme_v2_service/app/domains/reports/scope_resolution.py`
- Modify: `theme_v2_service/app/domains/reports/api_runs.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Modify: `theme_v2_service/app/jobs/registry.py`
- Test: `theme_v2_service/tests/contract/test_report_run_api.py`
- Test: `theme_v2_service/tests/integration/test_report_run_service.py`
- Test: `theme_v2_service/tests/integration/test_report_jobs.py`

**Step 1: Write failing contract tests**

Cover:

- `GET /api/report-generation-runs/evidence-options?q=Kevin&type=contact` returns only owned results.
- The endpoint supports `type=all|asset|event|contact`, cursor, limit, canonical icon/title/subtitle/effective time, and dynamic skill label.
- `PUT /{run_id}/plan-draft` rejects stale `expected_revision` with 409.
- Removing references is synchronous and immediately visible.
- Changing only toggles/attention questions is synchronous.
- Changing `additional_focus` schedules one `report_scope_resolution` job and sets `state=planning`, `active_stage=scope_resolution` until resolved.
- An ambiguous person without company/role/profile emits `ambiguous_person` and prevents generation.

Run: `cd theme_v2_service && .venv/bin/pytest tests/contract/test_report_run_api.py tests/integration/test_report_jobs.py -q`

Expected: FAIL with 404/422 and missing job type.

**Step 2: Implement the evidence options projection**

Create:

```python
class EvidenceOption(StrictModel):
    reference: EvidenceReference
    type_label: str
    filter_id: str
    filter_label: str
    title: str
    subtitle: str | None = None
    icon: str
    effective_at: datetime | None = None

async def list_evidence_options(..., query: str, type_filter: str, cursor: str | None, limit: int) -> EvidenceOptionPage:
    ...
```

Use existing canonical asset icon mapping. `全部` means no filter; it never means select all.

**Step 3: Implement optimistic draft updates**

The service signature is:

```python
async def update_plan_draft(
    session: AsyncSession,
    *,
    user_id: str,
    run_id: str,
    expected_revision: int,
    command: ReportPlanDraftUpdate,
) -> tuple[ReportGenerationRun, WorkflowJob | None]:
    ...
```

Lock the owned run, compare revision, validate selected option, normalize references, persist semantic change, and increment revision. No-op updates do not increment. Existing `decision` remains for clarification compatibility.

**Step 4: Implement bounded scope resolution**

`report_scope_resolution` receives only the private focus text plus already-known entity candidates. It uses the configured planner model without Web Search and returns a typed public brief. It never copies the complete Event description. Deterministic removals/toggles do not enqueue the model.

**Step 5: Freeze exactly the confirmed revision on generation**

`generate_run` must compare `expected_plan_revision`, reject blockers, resolve references, and copy the exact draft into `ReportExecutionPlan`. Quick generate simply submits the current recommended draft and its revision.

**Step 6: Run focused tests**

Run: `cd theme_v2_service && .venv/bin/pytest tests/contract/test_report_run_api.py tests/integration/test_report_run_service.py tests/integration/test_report_jobs.py -q`

Expected: PASS.

**Step 7: Commit**

```bash
git add theme_v2_service/app/domains/reports/evidence_options.py theme_v2_service/app/domains/reports/scope_resolution.py theme_v2_service/app/domains/reports/api_runs.py theme_v2_service/app/domains/reports/service.py theme_v2_service/app/jobs/registry.py theme_v2_service/tests/contract/test_report_run_api.py theme_v2_service/tests/integration/test_report_run_service.py theme_v2_service/tests/integration/test_report_jobs.py
git commit -m "feat(report): add editable scope and evidence picker api"
```

## Task 4: Make public research typed, relevant, and substantive

**Files:**

- Modify: `theme_v2_service/app/domains/reports/providers.py`
- Modify: `theme_v2_service/app/domains/reports/web_search.py`
- Modify: `theme_v2_service/app/domains/reports/providers_deepseek_web.py`
- Modify: `theme_v2_service/app/domains/reports/pipeline.py`
- Modify: `theme_v2_service/tests/fakes/report_providers.py`
- Test: `theme_v2_service/tests/unit/test_report_web_search.py`
- Test: `theme_v2_service/tests/unit/test_report_deepseek_web_provider.py`
- Test: `theme_v2_service/tests/unit/test_report_pipeline.py`

**Step 1: Write failing query/source tests**

Assert:

- The football event produces entity-specific queries about Real Madrid and FC Barcelona squad-building/current roster, not `counterparty event free_text location`.
- The full private event description and selected private asset text never appear in queries.
- A person query requires qualifier text; `Kevin` alone yields a blocker/no query.
- HTTP URLs, empty titles, empty snippets, URL-only `open_page` actions, and sources unrelated to every entity/question are rejected.
- Every accepted source records query/entity/question provenance.

Run: `cd theme_v2_service && .venv/bin/pytest tests/unit/test_report_web_search.py tests/unit/test_report_deepseek_web_provider.py -q`

Expected: FAIL under the current generic builder.

**Step 2: Change the provider contract**

```python
class WebQuery(ProviderModel):
    id: str
    text: str
    entity_ids: list[str]
    question_ids: list[str]

class WebSource(ProviderModel):
    title: str
    url: str
    snippet: str
    accessed_at: str
    authoritative: bool = False
    query_id: str
    entity_ids: list[str] = Field(default_factory=list)
    question_ids: list[str] = Field(default_factory=list)
```

Change `WebSearchProvider.search` to accept `list[WebQuery]` and update fakes/providers together.

**Step 3: Build queries only from `PublicResearchBrief`**

Generate bounded entity/question pairs, add freshness language contextually, cap query count, and deduplicate. Do not pass `report_goal`, raw evidence, or arbitrary capability names into Web Search.

**Step 4: Qualify sources before generation**

Normalize HTTPS URLs, strip tracking fragments where safe, require a substantive title/snippet, check entity/question term overlap, and preserve authoritative-domain classification. Degrade optional search with a user-readable warning when no sources qualify; fail only when policy is required.

**Step 5: Verify pipeline boundary**

Run: `cd theme_v2_service && .venv/bin/pytest tests/unit/test_report_web_search.py tests/unit/test_report_deepseek_web_provider.py tests/unit/test_report_pipeline.py -q`

Expected: PASS, including assertions that only qualified typed sources reach `GeneratorRequest.external_sources`.

**Step 6: Commit**

```bash
git add theme_v2_service/app/domains/reports/providers.py theme_v2_service/app/domains/reports/web_search.py theme_v2_service/app/domains/reports/providers_deepseek_web.py theme_v2_service/app/domains/reports/pipeline.py theme_v2_service/tests/fakes/report_providers.py theme_v2_service/tests/unit/test_report_web_search.py theme_v2_service/tests/unit/test_report_deepseek_web_provider.py theme_v2_service/tests/unit/test_report_pipeline.py
git commit -m "fix(report): make public research scoped and relevant"
```

## Task 5: Render readable evidence and clickable qualified links

**Files:**

- Modify: `theme_v2_service/app/domains/reports/presentation/blocks.py`
- Modify: `theme_v2_service/app/domains/reports/providers_litellm.py`
- Modify: `mobile/lib/pages/report_viewer_page.dart`
- Modify: `mobile/pubspec.yaml`
- Test: `theme_v2_service/tests/unit/test_report_presentation.py`
- Test: `theme_v2_service/tests/unit/test_report_litellm_provider.py`
- Test: `mobile/test/pages/report_viewer_page_test.dart`

**Step 1: Add failing safety/readability tests**

Cover safe `[label](https://example.com/path)` rendering with escaped label/URL, rejection of javascript/data/file schemes, evidence rendered as natural prose rather than raw `evidence`, `acceptance_marker`, or schema fields, and mobile external navigation only for qualified HTTP(S) URLs.

**Step 2: Implement safe Markdown links**

Extend `inline()` to recognize only HTTP(S) links, escape label and href, add `target="_blank" rel="noopener noreferrer"`, and leave unsupported schemes as plain escaped text.

**Step 3: Tighten generator instructions**

Require each section to synthesize facts into useful prose, use named links at the supporting sentence, never dump raw evidence/schema keys, and keep existing Todo extraction, report templates/styles, and Seedream illustration behavior.

**Step 4: Open external links from the viewer**

Add `url_launcher`, intercept only HTTP(S), call `launchUrl(..., mode: LaunchMode.externalApplication)`, keep report-internal navigation inside the locked-down viewer, and surface a non-blocking failure message.

**Step 5: Test**

Run:

```bash
cd theme_v2_service
.venv/bin/pytest tests/unit/test_report_presentation.py tests/unit/test_report_litellm_provider.py -q
cd ../mobile
flutter pub get
flutter test test/pages/report_viewer_page_test.dart
```

Expected: PASS.

**Step 6: Commit**

```bash
git add theme_v2_service/app/domains/reports/presentation/blocks.py theme_v2_service/app/domains/reports/providers_litellm.py theme_v2_service/tests/unit/test_report_presentation.py theme_v2_service/tests/unit/test_report_litellm_provider.py mobile/lib/pages/report_viewer_page.dart mobile/pubspec.yaml mobile/pubspec.lock mobile/test/pages/report_viewer_page_test.dart
git commit -m "fix(report): render readable citations and open links"
```

## Task 6: Build the unified mobile Report plan flow

**Files:**

- Create: `mobile/lib/theme_v2/report/report_plan_models.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_controller.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Test: `mobile/test/theme_v2/report/report_run_controller_test.dart`
- Test: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Step 1: Write failing controller/widget tests**

Assert:

- Every origin renders the same recommended plan summary.
- Primary `一键生成` sends the displayed `plan_revision` and recommended option.
- Secondary `调整方案` reveals exactly: `报告方案`, `关注范围`, `参考资产`.
- Report period appears only for applicable retrospective plans; research freshness appears inside public research scope.
- User can add bounded focus text and qualified Kevin profile intent.
- A blocker disables generation with an actionable explanation.
- Returning from scope resolution refreshes the same run instead of creating another run.

Run: `cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart test/theme_v2/report/report_run_page_test.dart`

Expected: FAIL because the current controller is map-based and page only selects a tile.

**Step 2: Add typed models and controller commands**

Provide `ReportPlanDraftView`, `EvidenceReferenceView`, `PublicResearchBriefView`, and `PlanBlockerView`, plus:

```dart
Future<void> updateDraft(ReportPlanDraftUpdate update);
Future<void> quickGenerate();
Future<void> generateConfirmedDraft();
```

Serialize `expected_revision`/`expected_plan_revision`. Preserve the existing clarification and generation polling paths.

**Step 3: Implement the compact three-step UI**

Render a real three-step Stepper inside the existing Report Run route:

1. `方案`: show the recommended type, alternatives, short rationale, included evidence count, public-research summary, and the `一键生成` shortcut.
2. `范围`: edit attention questions, additional focus, public-research entities, and reference Assets through the full-screen picker.
3. `确认`: summarize the chosen plan, focus, Asset counts/types, public-research entities, and capability policies before `确认并生成` freezes the plan.

Each step is a distinct screen state with sticky navigation controls; do not flatten the three steps into one scrolling form. Preserve the existing Reka/report container entry behavior.

**Step 4: Test and analyze**

Run:

```bash
cd mobile
flutter test test/theme_v2/report/report_run_controller_test.dart test/theme_v2/report/report_run_page_test.dart
flutter analyze lib/theme_v2/report
```

Expected: PASS with no new analyzer errors.

**Step 5: Commit**

```bash
git add mobile/lib/theme_v2/report/report_plan_models.dart mobile/lib/theme_v2/report/report_run_controller.dart mobile/lib/theme_v2/report/report_run_page.dart mobile/test/theme_v2/report/report_run_controller_test.dart mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "feat(theme-v2): unify report planning flow"
```

## Task 7: Add the full-screen Report evidence picker

**Files:**

- Create: `mobile/lib/theme_v2/report/report_evidence_picker_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Test: `mobile/test/theme_v2/report/report_evidence_picker_page_test.dart`

**Step 1: Write failing picker tests**

Cover search, `全部` plus type/dynamic-skill filters, Event/Contact/custom skill rows, selected chips with remove, cancel preserving the draft, confirm emitting ordered typed references, and cursor pagination without duplicate rows.

**Step 2: Implement a Report-specific full-screen picker**

Do not reuse `widgets/asset_picker.dart` directly because it only models generic assets. Reuse its visual vocabulary but consume the Report evidence-options endpoint and keep selected references locally until confirmation.

**Step 3: Integrate and test**

Run: `cd mobile && flutter test test/theme_v2/report/report_evidence_picker_page_test.dart test/theme_v2/report/report_run_page_test.dart`

Expected: PASS.

**Step 4: Commit**

```bash
git add mobile/lib/theme_v2/report/report_evidence_picker_page.dart mobile/lib/theme_v2/report/report_run_page.dart mobile/test/theme_v2/report/report_evidence_picker_page_test.dart
git commit -m "feat(theme-v2): add report evidence picker"
```

## Task 8: Normalize the capture status contract

**Files:**

- Modify: `theme_v2_service/app/domains/capture/schemas.py`
- Modify: `theme_v2_service/app/domains/capture/service.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Test: `theme_v2_service/tests/contract/test_capture_api.py`
- Test: `theme_v2_service/tests/contract/test_capture_sse.py`
- Test: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Test: `theme_v2_service/tests/e2e/test_hardware_capture_flow.py`

**Step 1: Write failing capture-state tests**

Assert one task can be followed through stable `client_task_id`, `recording_id`, `session_id`, and `input_turn_id`; SSE emits normalized `display_phase` values `receiving`, `transcribing`, `understanding`, `organizing`, terminal `done|empty|failed`; `done` includes result count; ring-provided `client_task_id` is not replaced by the server.

**Step 2: Extend the additive API**

Add optional `client_task_id` to `FlashRequest`, `recording_id` to `FlashResponse`, and additive capture status keys:

```json
{
  "client_task_id": "...",
  "recording_id": "...",
  "session_id": "...",
  "input_turn_id": "...",
  "display_phase": "organizing",
  "source": "ring|card|audio_upload",
  "result_count": 3
}
```

Preserve legacy `status`, `pipeline_status`, and message fields.

**Step 3: Publish stages at real boundaries**

Publish receiving when bytes/file are accepted, transcribing around ASR, understanding before the legacy capture agent, organizing after provider output and before persistence, and terminal only after transaction outcome. Do not reintroduce the removed legacy hardware animation.

**Step 4: Run tests**

Run: `cd theme_v2_service && .venv/bin/pytest tests/contract/test_capture_api.py tests/contract/test_capture_sse.py tests/integration/test_capture_jobs.py tests/e2e/test_hardware_capture_flow.py -q`

Expected: PASS.

**Step 5: Commit**

```bash
git add theme_v2_service/app/domains/capture/schemas.py theme_v2_service/app/domains/capture/service.py theme_v2_service/app/domains/capture/jobs.py theme_v2_service/tests/contract/test_capture_api.py theme_v2_service/tests/contract/test_capture_sse.py theme_v2_service/tests/integration/test_capture_jobs.py theme_v2_service/tests/e2e/test_hardware_capture_flow.py
git commit -m "feat(capture): publish normalized activity phases"
```

## Task 9: Build the mobile capture activity bus and coordinator

**Files:**

- Create: `mobile/lib/capture_activity/capture_activity_event.dart`
- Create: `mobile/lib/capture_activity/capture_activity_bus.dart`
- Create: `mobile/lib/theme_v2/capture/capture_activity_models.dart`
- Create: `mobile/lib/theme_v2/capture/capture_activity_coordinator.dart`
- Modify: `mobile/lib/app_events.dart`
- Modify: `mobile/lib/flash/flash.dart`
- Test: `mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart`

**Step 1: Write failing reducer tests**

Cover monotonic stage progression, alias merge from local task key to client task/recording/file IDs, duplicate/out-of-order SSE, realtime priority over offline upload, stable active selection, `另有 N 条`, success 1.5 seconds, failure 3 seconds, empty 2 seconds, tap disabled before session/turn identity, and task recovery from persisted upload snapshots.

**Step 2: Implement a neutral event contract**

```dart
enum CaptureActivitySource { ring, card, audioUpload }
enum CaptureActivityPhase { listening, receiving, transcribing, understanding, organizing, done, empty, failed }

@immutable
class CaptureActivityEvent {
  final Set<String> aliases;
  final CaptureActivitySource source;
  final CaptureActivityPhase phase;
  final String? sessionId;
  final String? inputTurnId;
  final int? resultCount;
  final DateTime occurredAt;
}
```

`CaptureActivityBus` is broadcast and has no Theme V2 import. `app_events.dart` translates server SSE payloads into this contract while keeping legacy listeners working.

**Step 3: Implement the coordinator**

Inject a clock/timer scheduler for deterministic tests. Merge aliases transitively, never regress phase, prioritize live ring/card over offline upload then oldest active task, keep active selection stable until terminal dwell ends, and expose one immutable `CaptureActivitySnapshot`.

**Step 4: Run tests**

Run: `cd mobile && flutter test test/theme_v2/capture/capture_activity_coordinator_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/capture_activity/capture_activity_event.dart mobile/lib/capture_activity/capture_activity_bus.dart mobile/lib/theme_v2/capture/capture_activity_models.dart mobile/lib/theme_v2/capture/capture_activity_coordinator.dart mobile/lib/app_events.dart mobile/lib/flash/flash.dart mobile/test/theme_v2/capture/capture_activity_coordinator_test.dart
git commit -m "feat(theme-v2): coordinate capture activity"
```

## Task 10: Connect ring/card/offline sources to stable activity identities

**Files:**

- Modify: `mobile/lib/ble_flash/ble_flash_manager.dart`
- Modify: `mobile/lib/flash_file_workflow.dart`
- Modify: `mobile/lib/ring/ring_capture_controller.dart`
- Modify: `mobile/lib/ring/ring_capture_service.dart`
- Test: `mobile/test/ble_flash/ble_flash_manager_test.dart`
- Test: `mobile/test/flash_file_workflow_test.dart`
- Test: `mobile/test/ring/ring_capture_service_test.dart`

**Step 1: Write failing source-adapter tests**

Verify card start publishes `listening`, file arrival merges the same task into `receiving`, upload/ASR/agent updates preserve the file/client/recording aliases, ring start/end uses one generated client task ID sent to `sendFlash`, and restored offline tasks appear as `audioUpload`/card receiving work without stealing a live task.

**Step 2: Implement adapters without SDK changes**

Generate IDs at the earliest local event, pass them through existing controllers/services, expose an immutable persisted-task snapshot from `FlashFileWorkflow`, and publish typed events. Do not alter BLE packet handling, contact binding, or ring SDK behavior.

**Step 3: Run tests**

Run: `cd mobile && flutter test test/ble_flash/ble_flash_manager_test.dart test/flash_file_workflow_test.dart test/ring/ring_capture_service_test.dart`

Expected: PASS.

**Step 4: Commit**

```bash
git add mobile/lib/ble_flash/ble_flash_manager.dart mobile/lib/flash_file_workflow.dart mobile/lib/ring/ring_capture_controller.dart mobile/lib/ring/ring_capture_service.dart mobile/test/ble_flash/ble_flash_manager_test.dart mobile/test/flash_file_workflow_test.dart mobile/test/ring/ring_capture_service_test.dart
git commit -m "feat(capture): correlate hardware activity tasks"
```

## Task 11: Render Thinking Orbs as a full-header takeover

**Files:**

- Create: `mobile/lib/theme_v2/capture/thinking_orb.dart`
- Create: `mobile/lib/theme_v2/capture/capture_activity_top_bar.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart`
- Test: `mobile/test/theme_v2/capture/thinking_orb_test.dart`
- Test: `mobile/test/theme_v2/capture/capture_activity_top_bar_test.dart`
- Test: `mobile/test/theme_v2/shell/theme_v2_app_shell_test.dart`

**Step 1: Write failing presentation tests**

Assert idle renders the existing header unchanged; active work replaces the complete 56px bar; it shows source, normalized Chinese phase, one native orb, and queue count; terminal copy/dwell is correct; tap is enabled only with a target; the light-theme bar is not black.

**Step 2: Implement the native orb**

Use `CustomPainter` with 3–5 translucent circles driven by one controller. Phase changes alter breathing speed, orbit radius, and convergence; do not use product images or external package code. Repaint only the orb subtree.

**Step 3: Implement shell takeover**

The shell owns/coalesces coordinator lifecycle and cross-fades between the unchanged global nav and `CaptureActivityTopBar`. Preserve the fixed 56px layout so pages do not jump.

**Step 4: Run tests/analyzer**

Run:

```bash
cd mobile
flutter test test/theme_v2/capture/thinking_orb_test.dart test/theme_v2/capture/capture_activity_top_bar_test.dart test/theme_v2/shell/theme_v2_app_shell_test.dart
flutter analyze lib/theme_v2/capture lib/theme_v2/shell lib/capture_activity
```

Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/theme_v2/capture/thinking_orb.dart mobile/lib/theme_v2/capture/capture_activity_top_bar.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/shell/theme_v2_global_top_nav.dart mobile/test/theme_v2/capture/thinking_orb_test.dart mobile/test/theme_v2/capture/capture_activity_top_bar_test.dart mobile/test/theme_v2/shell/theme_v2_app_shell_test.dart
git commit -m "feat(theme-v2): add thinking orbs header takeover"
```

## Task 12: Standardize Session work states and live capture turns

**Files:**

- Modify: `mobile/lib/theme_v2/chat/chat_models.dart`
- Modify: `mobile/lib/theme_v2/chat/chat_controller.dart`
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Modify: `mobile/lib/theme_v2/session/session_analysis_block.dart`
- Modify: `mobile/lib/theme_v2/session/session_transcript.dart`
- Modify: `mobile/lib/theme_v2/session/theme_v2_session_page.dart`
- Test: `mobile/test/theme_v2/chat/chat_controller_test.dart`
- Test: `mobile/test/theme_v2/session/session_transcript_test.dart`
- Test: `mobile/test/theme_v2/session/theme_v2_session_page_test.dart`

**Step 1: Write failing Session tests**

Cover:

- Hardware input creates a transient right-side `正在聆听/正在转写` turn before ASR text.
- ASR text replaces the transient content without refresh.
- Agent creates exactly one running reply and transitions `正在理解 → 检索/执行 → 组织回答` for chat, and `正在理解 → 正在整理` for capture.
- Tool call/results do not create duplicate assistant messages.
- Leaving and reopening the Session loads the real persisted turn/result.
- Failure appears on the corresponding turn, not as a session-wide bottom error.

**Step 2: Add normalized work phase to messages**

Introduce `AgentWorkPhase { understanding, executing, composing, organizing }` on the running assistant message. Map chat SSE start/meta, tool call/result, token, and terminal events monotonically. Map capture activity by session/input-turn alias.

**Step 3: Reuse the same orb visual inline**

`SessionAnalysisBlock` hosts a compact `ThinkingOrb` plus phase copy. It is present only for the current running assistant turn; it becomes normal content or a turn-level failure on completion.

**Step 4: Run focused regression tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/chat/chat_controller_test.dart test/theme_v2/session/session_transcript_test.dart test/theme_v2/session/theme_v2_session_page_test.dart
flutter analyze lib/theme_v2/chat lib/theme_v2/session lib/theme_v2/capture
```

Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/theme_v2/chat/chat_models.dart mobile/lib/theme_v2/chat/chat_controller.dart mobile/lib/theme_v2/capture/capture_session_controller.dart mobile/lib/theme_v2/session/session_analysis_block.dart mobile/lib/theme_v2/session/session_transcript.dart mobile/lib/theme_v2/session/theme_v2_session_page.dart mobile/test/theme_v2/chat/chat_controller_test.dart mobile/test/theme_v2/session/session_transcript_test.dart mobile/test/theme_v2/session/theme_v2_session_page_test.dart
git commit -m "feat(theme-v2): standardize session work states"
```

## Task 13: Combined regression, Docker, and real-device acceptance

**Files:**

- Modify tests only if a test exposes an implementation defect; do not weaken assertions.
- Record no screenshots or logs in the repository unless an existing acceptance convention requires them.

**Step 1: Run complete backend suites for touched domains**

```bash
cd theme_v2_service
.venv/bin/pytest tests/unit/test_report_*.py tests/contract/test_report_*.py tests/integration/test_report_*.py tests/e2e/test_report_generation_flow.py -q
.venv/bin/pytest tests/unit/test_capture_*.py tests/contract/test_capture_*.py tests/integration/test_capture_*.py tests/e2e/test_hardware_capture_flow.py -q
```

Expected: PASS.

**Step 2: Run complete focused Flutter suites**

```bash
cd mobile
flutter test test/theme_v2/report test/theme_v2/capture test/theme_v2/chat test/theme_v2/session
flutter test test/ble_flash test/ring test/flash_file_workflow_test.dart
flutter analyze lib/theme_v2/report lib/theme_v2/capture lib/theme_v2/chat lib/theme_v2/session lib/theme_v2/shell lib/capture_activity
```

Expected: PASS with no new analyzer errors.

**Step 3: Start only the independent Theme V2 Docker stack**

Run:

```bash
docker compose -p eureka-theme-v2 -f docker-compose.theme-v2.yml up -d --build --wait mysql redis api worker
docker compose -p eureka-theme-v2 -f docker-compose.theme-v2.yml exec -T api alembic upgrade head
theme_v2_service/scripts/smoke.sh
```

Confirm API health, Workflow worker health, migration 0018, Redis connectivity, and Report/capture provider configuration. Do not restart or reuse the legacy app stack.

**Step 4: Install the Theme V2 build on the connected device**

From `mobile/`, verify the package is `com.eureka.mindapp`, build the current branch, install the new debug APK, reverse the Theme V2 API port, force-stop, and launch. Confirm visually that the Theme V2 Today screen is open before testing.

**Step 5: Execute the Report acceptance matrix**

- User-initiated Report: quick generate from recommended plan.
- User-initiated Report: adjust focus, add/remove Event/Contact/custom asset in full-screen picker, then generate.
- Pre-event Reka flow: `球队建设情况讨论`, organizations 皇家马德里/巴塞罗那, plus qualified Kevin background.
- Verify previewed research scope matches actual generated citations.
- Verify current squad/context is substantive, citations are named/clickable, no raw evidence/schema keys appear, Todo extraction remains usable, and Seedream illustration still renders when requested.

**Step 6: Execute the Thinking Orbs acceptance matrix**

- Ring live capture.
- Card live capture.
- Existing card offline/upload recovery.
- Two overlapping tasks showing one active plus queue count.
- Open matching Flash Session mid-ASR and observe live right-side transient text then one agent running state.
- Leave/reopen Session and confirm persisted final content.
- Force empty/failure paths and confirm terminal dwell plus turn-level failure.

**Step 7: Check diff ownership and commit the verification fixes**

Run `git status --short`, `git diff --check`, and inspect every staged file. Stage only implementation/test files from this plan; preserve unrelated asset-library/bubble/Pen work already present in the working tree.

```bash
git commit -m "test(theme-v2): verify report and capture workflows"
```

## Completion criteria

- All Report origins converge on the same editable recommended plan and immutable confirmed execution plan.
- A user can one-click generate or inspect/adjust type, attention, public research, and typed reference assets.
- Private source content never becomes a Web Search query; ambiguous people are blocked until qualified.
- The exact football/Kevin scenario yields relevant, substantive, named, clickable sources and readable output.
- Existing report templates, Todo extraction, and Seedream illustration still work.
- Ring/card/offline capture produces normalized live state in the full top bar and matching Session without refresh.
- Queueing, recovery, terminal dwell, and tap target behavior match the approved Thinking Orbs spec.
- All focused backend/mobile tests pass, Theme V2 Docker is healthy, and the build is verified on the real device as Theme V2.
