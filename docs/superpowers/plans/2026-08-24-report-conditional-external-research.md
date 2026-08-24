# Report Conditional External Research Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let every data-backed Report add a grounded, source-backed external-reference module when the user explicitly requests it or generation discovers a credible anomaly, while keeping the core Report immediately readable and limiting loading, completion, failure, and retry to the related inline module.

**Architecture:** Extend the existing Planner and Generator structured contracts with a server-owned external-research policy and at most two grounded candidates. The main Report pipeline validates those candidates, injects trusted pending slots after their cited findings, persists the Report as normally readable, and enqueues idempotent `WorkflowJob`s. Each child job performs bounded Web Search plus typed synthesis, patches only its trusted HTML slot and the stable source slot, increments the existing Report revision, and leaves the Report Run state unchanged. Flutter generalizes the current illustration revision poll into a Report-enrichment poll that patches trusted external-reference slots in place and routes retry through an owner-scoped API.

**Tech Stack:** Python 3.12, FastAPI, Pydantic v2, SQLAlchemy async, existing WorkflowJob queue, LiteLLM structured output, existing DeepSeek Web Search provider, Jinja2 trusted Report renderer, Flutter/Dart, `webview_flutter`.

## Global Constraints

- External research is an evidence module; it must not choose or replace the Report content template or presentation family.
- Explicit external needs must appear in the confirmed plan before generation.
- Conditional research may start without another user confirmation only when grounded owned evidence passes the trigger gate.
- Conditional research may add public evidence but must never add unselected owned Assets.
- `pending` is a module status, never a new Report or Report Run state.
- A readable core Report must not wait for conditional external research.
- Loading, ready, failed, insufficient, and retry states remain local to the triggering module.
- External claims require accepted HTTPS sources; failed or source-insufficient work must never fall back to uncited model memory.
- Health, finance, legal, and safety modules use authoritative-only search and qualified, non-diagnostic language.
- Missing age, weight, geography, currency, or other decisive context must not be inferred and must not pause generation.
- Public shares created while a module is pending are immutable snapshots and must not contain a permanently animated loading state.
- Do not add a Report-completion notification or Reka signal for external-module completion.
- Verification follows repository `AGENTS.md`: focused regression tests, directly affected tests, a small number of credible adjacent cases, targeted analysis, and diff checks only. Do not run full backend or Flutter suites without new user confirmation.

---

## File Structure

### New backend files

- `theme_v2_service/app/domains/reports/external_research.py` — pure candidate grounding, trigger gating, pending-module construction, slot injection, pending-count helpers, and result validation.
- `theme_v2_service/app/domains/reports/external_research_jobs.py` — enqueue, execute, retry, terminal failure, Report/spec/HTML patching, and job handler.
- `theme_v2_service/tests/unit/test_report_external_research.py` — pure trigger, grounding, injection, source, and safety contracts.
- `theme_v2_service/tests/integration/test_report_external_research_jobs.py` — durable job, idempotency, patching, retry, ownership, and failure contracts.
- `theme_v2_service/tests/e2e/test_report_conditional_research_flow.py` — one focused core-ready → pending-module → ready-module workflow.

### New mobile files

- `mobile/lib/theme_v2/report/report_enrichment.dart` — pure pending-count parsing, trusted slot extraction, retry-URI parsing, and revision-response modeling.
- `mobile/test/theme_v2/report/report_enrichment_test.dart` — pure mobile enrichment and safe-slot contracts.

### Existing files changed

- `theme_v2_service/app/domains/reports/schemas.py` — plan policy and persisted module types.
- `theme_v2_service/app/domains/reports/providers.py` — Generator candidate and external-research provider request/result contracts.
- `theme_v2_service/app/domains/reports/providers_litellm.py` — Planner/Generator instructions and typed module-synthesis provider.
- `theme_v2_service/app/domains/reports/planner.py` — validate/persist external-research policy without changing template policy.
- `theme_v2_service/app/domains/reports/security.py` — candidate and module claim/source validation.
- `theme_v2_service/app/domains/reports/pipeline.py` — pending module stage, immediate child enqueue, render, spec persistence, and no Report-level wait.
- `theme_v2_service/app/domains/reports/presentation/blocks.py` — trusted external-research marker rendering.
- `theme_v2_service/app/domains/reports/presentation/renderer.py` — typed pending/ready/failed/insufficient modules and stable source slot.
- `theme_v2_service/app/domains/reports/presentation/styles.py` — local module status visuals with reduced-motion behavior.
- `theme_v2_service/app/domains/reports/rendering.py` — trusted private HTML slot replacement/removal helpers.
- `theme_v2_service/app/domains/reports/api_reports.py` — pending count and owner-scoped module retry.
- `theme_v2_service/app/domains/reports/shares.py` — remove pending animation from immutable public snapshots.
- `theme_v2_service/app/jobs/registry.py` — configured external-research handler.
- `theme_v2_service/app/worker.py` — report-enrichment lane includes illustration and external-research jobs.
- `theme_v2_service/tests/unit/test_report_schemas.py`
- `theme_v2_service/tests/unit/test_report_generation_security.py`
- `theme_v2_service/tests/unit/test_report_presentation.py`
- `theme_v2_service/tests/unit/test_report_rendering.py`
- `theme_v2_service/tests/unit/test_report_pipeline.py`
- `theme_v2_service/tests/unit/test_worker_runtime.py`
- `theme_v2_service/tests/contract/test_report_api.py`
- `theme_v2_service/tests/integration/test_report_shares.py`
- `mobile/lib/pages/report_viewer_page.dart` — generalized revision polling, local patching, and retry routing.
- `mobile/lib/theme_v2/report/report_models.dart` — pending count on completed Report summaries.
- `mobile/lib/theme_v2/report/report_notification_target.dart` — pass initial module state into Viewer.
- `mobile/lib/theme_v2/report/report_container_page.dart` — pass initial module state into Viewer.
- `mobile/lib/theme_v2/report/report_run_page.dart` — display plan authorization and pass module state into Viewer.
- `mobile/test/theme_v2/report/report_viewer_theme_test.dart`
- `mobile/test/theme_v2/report/report_repository_test.dart`
- `mobile/test/theme_v2/report/report_notification_target_test.dart`
- `mobile/test/theme_v2/report/report_run_page_test.dart`

---

### Task 1: Add explicit and conditional research contracts to planning and generation

**Files:**
- Modify: `theme_v2_service/app/domains/reports/schemas.py:260-390`
- Modify: `theme_v2_service/app/domains/reports/providers.py:15-100`
- Modify: `theme_v2_service/app/domains/reports/providers_litellm.py:23-175`
- Modify: `theme_v2_service/app/domains/reports/planner.py:260-470`
- Modify: `theme_v2_service/app/domains/reports/service.py:800-870`
- Test: `theme_v2_service/tests/unit/test_report_schemas.py`
- Test: `theme_v2_service/tests/integration/test_report_planner.py`
- Test: `theme_v2_service/tests/unit/test_report_generation_security.py`

**Interfaces:**
- Produces: `ExternalResearchPolicy`, `ReportExternalResearchModule`, `ResearchEvidenceQuote`, `GeneratedExternalResearchCandidate`, `ExternalResearchRequest`, `ExternalResearchResult`, and `ReportExternalResearchProvider.synthesize()`.
- Produces: `ReportPlanOption.external_research`, `ReportExecutionPlan.external_research`, `GeneratorResult.external_research_candidates`, and `ReportSpec.external_research_modules`.
- Consumes: existing `EvidenceReference`, `PublicResearchBrief`, `GeneratorRequest`, `GeneratorResult`, and LiteLLM structured-output helpers.

- [ ] **Step 1: Write failing schema and Planner tests**

Add exact tests proving backward-compatible conditional defaults, explicit questions, strict candidate limits, and persisted plan round-tripping:

```python
def test_report_plan_defaults_to_conditional_external_research():
    option = ReportPlanOption.model_validate(_option_json())
    assert option.external_research.mode == "conditional"
    assert option.external_research.explicit_questions == []


def test_execution_plan_preserves_explicit_and_conditional_research():
    plan = ReportExecutionPlan.model_validate({
        **_execution_plan_json(),
        "external_research": {
            "mode": "explicit_and_conditional",
            "explicit_questions": ["与适用的权威喂养参考相比如何？"],
            "reason": "用户明确要求外部对比",
        },
    })
    assert plan.external_research.mode == "explicit_and_conditional"
    assert plan.external_research.explicit_questions == [
        "与适用的权威喂养参考相比如何？"
    ]


def test_generator_rejects_more_than_two_external_research_candidates():
    request = _request()
    raw = _result(external_research_candidates=[
        _research_candidate(f"candidate-{index}") for index in range(3)
    ])
    with pytest.raises(ValidationError):
        GeneratorResult.model_validate(raw)
```

- [ ] **Step 2: Run the focused RED tests**

Run:

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q \
  tests/unit/test_report_schemas.py \
  tests/integration/test_report_planner.py \
  tests/unit/test_report_generation_security.py
```

Expected: FAIL because the external-research policy, module, candidate, and provider models do not exist.

- [ ] **Step 3: Add the exact schema and provider contracts**

Add these bounded types; keep defaults so existing stored plans and fake provider fixtures remain readable:

```python
ExternalResearchMode = Literal["conditional", "explicit_and_conditional"]
ExternalResearchDomain = Literal[
    "general", "health", "finance", "legal", "safety"
]
ExternalResearchStatus = Literal[
    "pending", "ready", "failed", "insufficient"
]


class ExternalResearchPolicy(StrictModel):
    mode: ExternalResearchMode = "conditional"
    explicit_questions: list[str] = Field(default_factory=list, max_length=4)
    reason: str | None = Field(default=None, max_length=240)


class ReportExternalResearchModule(StrictModel):
    id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,80}$")
    trigger_kind: Literal["explicit", "conditional"]
    domain: ExternalResearchDomain = "general"
    freshness: Literal[
        "current", "recent_year", "historical", "not_applicable"
    ] = "current"
    title: str = Field(min_length=1, max_length=160)
    evidence_ids: list[str] = Field(default_factory=list, max_length=12)
    owned_fact: str = Field(min_length=1, max_length=600)
    questions: list[str] = Field(default_factory=list, min_length=1, max_length=4)
    status: ExternalResearchStatus = "pending"
    job_id: str | None = None
    source_urls: list[str] = Field(default_factory=list, max_length=8)
    reference_summary: str = Field(default="", max_length=1600)
    interpretation: str = Field(default="", max_length=1600)
    applicability: str = Field(default="", max_length=800)
    uncertainty: str = Field(default="", max_length=800)
    escalation_guidance: str = Field(default="", max_length=800)
    error_code: str | None = Field(default=None, max_length=100)
    revision: int = Field(default=1, ge=1)
```

Add `external_research: ExternalResearchPolicy = Field(default_factory=ExternalResearchPolicy)` to both plan types and `external_research_modules: list[ReportExternalResearchModule] = Field(default_factory=list, max_length=2)` to `ReportSpec`.

Add the provider-owned types:

```python
class ResearchEvidenceQuote(ProviderModel):
    evidence_id: str = Field(min_length=1)
    quote: str = Field(min_length=2, max_length=240)


class GeneratedExternalResearchCandidate(ProviderModel):
    id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,80}$")
    trigger_kind: Literal["explicit", "conditional"]
    domain: ExternalResearchDomain = "general"
    freshness: Literal[
        "current", "recent_year", "historical", "not_applicable"
    ] = "current"
    title: str = Field(min_length=1, max_length=160)
    evidence_ids: list[str] = Field(min_length=1, max_length=12)
    evidence_quotes: list[ResearchEvidenceQuote] = Field(
        default_factory=list, max_length=12
    )
    owned_fact: str = Field(min_length=1, max_length=600)
    questions: list[str] = Field(min_length=1, max_length=4)


class ExternalResearchRequest(ProviderModel):
    module: ReportExternalResearchModule
    evidence_context: dict
    sources: list[dict] = Field(default_factory=list)


class ExternalResearchResult(ProviderModel):
    status: Literal["ready", "insufficient"]
    source_urls: list[str] = Field(default_factory=list, max_length=8)
    reference_summary: str = Field(default="", max_length=1600)
    interpretation: str = Field(default="", max_length=1600)
    applicability: str = Field(default="", max_length=800)
    uncertainty: str = Field(default="", max_length=800)
    escalation_guidance: str = Field(default="", max_length=800)


class ReportExternalResearchProvider(Protocol):
    async def synthesize(
        self, request: ExternalResearchRequest
    ) -> ExternalResearchResult:
        raise NotImplementedError
```

Add `external_research_candidates: list[GeneratedExternalResearchCandidate] = Field(default_factory=list, max_length=2)` to `GeneratorResult`.

- [ ] **Step 4: Teach Planner and Generator prompts the approved behavior**

Update Planner instructions so `external_research` is independent of immutable template `web_policy`:

```python
"Always include external_research. Use mode=explicit_and_conditional only "
"when the user's intent or confirmed additional_focus explicitly asks for "
"comparison, verification, standards, current external facts, or professional "
"reference; copy the concrete need into explicit_questions. Otherwise use "
"mode=conditional with no explicit_questions. This policy does not change the "
"official template web_policy."
```

Update Generator trusted config with `external_research_contract` and require at most two candidates. Explicit candidates must answer an exact plan question. Conditional candidates must cite exact owned evidence, identify a material anomaly, and avoid medical or financial conclusions before research.

In `validate_planner_result_against_request`, keep template `web_search` validation unchanged and separately enforce:

```python
if option.external_research.mode == "explicit_and_conditional":
    if not option.external_research.explicit_questions:
        raise InvalidPlannerResult("explicit external research requires questions")
elif option.external_research.explicit_questions:
    raise InvalidPlannerResult("conditional external research cannot carry explicit questions")
```

Copy the selected option policy into `ReportExecutionPlan` in `service.py` when the immutable execution plan is frozen.

- [ ] **Step 5: Run focused GREEN tests and commit**

Run the Step 2 command. Expected: PASS.

Commit:

```bash
git add theme_v2_service/app/domains/reports/schemas.py \
  theme_v2_service/app/domains/reports/providers.py \
  theme_v2_service/app/domains/reports/providers_litellm.py \
  theme_v2_service/app/domains/reports/planner.py \
  theme_v2_service/app/domains/reports/service.py \
  theme_v2_service/tests/unit/test_report_schemas.py \
  theme_v2_service/tests/integration/test_report_planner.py \
  theme_v2_service/tests/unit/test_report_generation_security.py
git commit -m "feat: define conditional report research contracts"
```

---

### Task 2: Ground candidates and build trusted pending modules

**Files:**
- Create: `theme_v2_service/app/domains/reports/external_research.py`
- Create: `theme_v2_service/tests/unit/test_report_external_research.py`
- Modify: `theme_v2_service/app/domains/reports/security.py:1-330`
- Modify: `theme_v2_service/app/domains/reports/providers_litellm.py:80-175`

**Interfaces:**
- Consumes: `GeneratorRequest`, `GeneratorResult`, `GeneratedExternalResearchCandidate`, and `ExternalResearchPolicy` from Task 1.
- Produces: `ground_research_candidates(result, request)`, `build_pending_modules(candidates, policy)`, `inject_research_slots(content_md, modules)`, `pending_external_research_count(modules)`, and `validate_external_research_result(request, result)`.

- [ ] **Step 1: Write RED tests for explicit, conditional, false-positive, and privacy cases**

```python
def test_explicit_candidate_must_match_confirmed_plan_question():
    request = _request(mode="explicit_and_conditional", questions=["与标准相比如何？"])
    result = _result(candidate=_candidate(
        trigger_kind="explicit",
        questions=["给出完全无关的市场预测"],
    ))
    assert ground_research_candidates(result, request) == []


def test_conditional_candidate_requires_three_grounded_owned_records():
    request = _feeding_request(values=[140, 135, 20])
    result = _result(candidate=_candidate(
        trigger_kind="conditional",
        evidence_ids=["feed-1", "feed-2", "feed-3"],
        evidence_quotes=[
            {"evidence_id": "feed-1", "quote": "140"},
            {"evidence_id": "feed-2", "quote": "135"},
            {"evidence_id": "feed-3", "quote": "20"},
        ],
        owned_fact="8月16日的20ml低于另外两次记录",
    ))
    grounded = ground_research_candidates(result, request)
    assert [item.id for item in grounded] == ["feeding-drop"]


def test_conditional_candidate_rejects_missing_quote_duplicate_and_unit_mismatch():
    request = _feeding_request(values=[140, 135, 20])
    assert ground_research_candidates(
        _result(candidate=_candidate(evidence_quotes=[
            {"evidence_id": "feed-3", "quote": "200ml"}
        ])),
        request,
    ) == []


def test_slot_is_inserted_after_the_cited_finding_only():
    content = "异常记录。[evidence:feed-3]\n\n后续节律分析。"
    module = _pending_module(evidence_ids=["feed-3"])
    injected = inject_research_slots(content, [module])
    assert injected.index("[evidence:feed-3]") < injected.index(
        "[[external-research:feeding-drop]]"
    ) < injected.index("后续节律分析")
```

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q tests/unit/test_report_external_research.py \
  tests/unit/test_report_generation_security.py
```

Expected: FAIL because the grounding and slot functions do not exist.

- [ ] **Step 3: Implement exact grounding and gate rules**

Implement pure helpers with these enforced rules:

```python
MAX_RESEARCH_MODULES = 2
HIGH_RISK_DOMAINS = {"health", "finance", "legal", "safety"}
RESEARCH_MARKER_RE = re.compile(
    r"\[\[external-research:([A-Za-z0-9_-]{1,80})\]\]"
)


def ground_research_candidates(
    result: GeneratorResult,
    request: GeneratorRequest,
) -> list[GeneratedExternalResearchCandidate]:
    allowed_ids = {
        item.get("reference_id") or item.get("asset_id")
        for item in request.evidence_bundle.get("user_evidence", [])
        if isinstance(item, dict)
    }
    policy = request.execution_plan.external_research
    accepted = []
    for candidate in result.external_research_candidates:
        evidence_ids = list(dict.fromkeys(candidate.evidence_ids))
        if not evidence_ids or not set(evidence_ids).issubset(allowed_ids):
            continue
        if not _all_quotes_are_exact(candidate, request.evidence_bundle):
            continue
        if candidate.trigger_kind == "explicit":
            if policy.mode != "explicit_and_conditional":
                continue
            if not set(candidate.questions).intersection(policy.explicit_questions):
                continue
        elif len(evidence_ids) < 3 or len(candidate.evidence_quotes) < 3:
            continue
        if not _candidate_is_cited_in_content(candidate, result.content_md):
            continue
        accepted.append(candidate)
    return accepted[:MAX_RESEARCH_MODULES]
```

`_all_quotes_are_exact` serializes only the referenced evidence item's payload, bound fields, and temporal facts; it never searches another user's or an unselected record. Reject model-supplied `[[external-research:<id>]]` markers inside `validate_generator_result` before server injection.

Build pending modules with `status="pending"`, empty public content, and no inferred context. Insert one marker immediately after the first paragraph containing a cited evidence ID. If no cited paragraph exists, omit that module instead of appending it at the end.

- [ ] **Step 4: Validate synthesized modules against owned numbers and accepted sources**

Implement:

```python
def validate_external_research_result(
    request: ExternalResearchRequest,
    raw: ExternalResearchResult | dict,
) -> ExternalResearchResult:
    result = ExternalResearchResult.model_validate(raw)
    allowed_urls = {
        source["url"] for source in request.sources
        if isinstance(source, dict) and str(source.get("url", "")).startswith("https://")
    }
    if not set(result.source_urls).issubset(allowed_urls):
        raise ValueError("external research cites an unavailable source")
    if result.status == "ready" and not result.source_urls:
        raise ValueError("ready external research requires a source")
    if request.module.domain in HIGH_RISK_DOMAINS:
        authoritative = {
            source["url"] for source in request.sources
            if source.get("authoritative") is True
        }
        if not set(result.source_urls).issubset(authoritative):
            raise ValueError("high-risk research requires authoritative sources")
        if not result.uncertainty.strip():
            raise ValueError("high-risk research requires uncertainty")
    _reject_html_and_ungrounded_numbers(request, result)
    return result
```

Use the existing numeric-claim extraction helpers against the selected evidence plus accepted source snippets. Do not add keyword-only diagnosis heuristics as the primary safety boundary; typed output, authoritative source enforcement, exact citations, and uncertainty are the enforceable contract.

- [ ] **Step 5: Run GREEN and commit**

Run the Step 2 command. Expected: PASS.

Commit:

```bash
git add theme_v2_service/app/domains/reports/external_research.py \
  theme_v2_service/app/domains/reports/security.py \
  theme_v2_service/app/domains/reports/providers_litellm.py \
  theme_v2_service/tests/unit/test_report_external_research.py \
  theme_v2_service/tests/unit/test_report_generation_security.py
git commit -m "feat: ground conditional report research"
```

---

### Task 3: Render local pending, ready, failed, and insufficient states safely

**Files:**
- Modify: `theme_v2_service/app/domains/reports/presentation/blocks.py:1-280`
- Modify: `theme_v2_service/app/domains/reports/presentation/renderer.py:1-196`
- Modify: `theme_v2_service/app/domains/reports/presentation/styles.py:1-92`
- Modify: `theme_v2_service/app/domains/reports/rendering.py:1-110`
- Modify: `theme_v2_service/app/domains/reports/shares.py:45-180`
- Test: `theme_v2_service/tests/unit/test_report_presentation.py`
- Test: `theme_v2_service/tests/unit/test_report_rendering.py`
- Test: `theme_v2_service/tests/integration/test_report_shares.py`

**Interfaces:**
- Consumes: `ReportExternalResearchModule` and injected `[[external-research:<id>]]` markers.
- Produces: stable HTML IDs `reka-report-research-<id>` and `reka-report-sources`, `replace_external_research_slot()`, `replace_report_sources_slot()`, and `strip_pending_external_research_slots()`.

- [ ] **Step 1: Write rendering RED tests**

```python
def test_pending_research_renders_only_at_its_trusted_marker():
    module = _module(status="pending")
    rendered = render_report_presentation(
        title="喂养报告",
        content_md="异常。\n\n[[external-research:feeding-drop]]\n\n后续内容。",
        chart_svgs={}, media_urls={}, external_research_modules=[module],
    )
    assert 'id="reka-report-research-feeding-drop"' in rendered.html
    assert 'data-research-status="pending"' in rendered.html
    assert "外部参照正在生成" in rendered.html
    assert "报告主体正在生成" not in rendered.html


def test_ready_health_module_has_distinct_label_and_escaped_content():
    module = _module(
        domain="health", status="ready",
        reference_summary="权威参考 <script>alert(1)</script>",
        interpretation="仅表示需要继续观察",
        applicability="适用于已说明的人群",
        uncertainty="不能据此诊断",
        escalation_guidance="若同时出现权威来源列出的危险信号，请及时就医",
    )
    html = render_external_research_module(module)
    assert "健康参考" in html
    assert html.index("及时就医") < html.index("仅表示需要继续观察")
    assert "<script>" not in html
    assert "&lt;script&gt;" in html


def test_share_snapshot_removes_pending_animation_but_keeps_core_report(session):
    report = _report_with_pending_research_html(session)
    created = await create_report_share(session, user_id=report.user_id, report_id=report.id)
    assert "外部参照正在生成" not in created.share.snapshot_html
    assert "报告正文" in created.share.snapshot_html
```

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q \
  tests/unit/test_report_presentation.py \
  tests/unit/test_report_rendering.py \
  tests/integration/test_report_shares.py
```

Expected: FAIL because the renderer has no external-research block or stable source slot.

- [ ] **Step 3: Render typed modules, never model HTML**

Extend `render_blocks` to accept a module map and recognize only exact markers:

```python
EXTERNAL_RESEARCH_RE = re.compile(
    r"^\[\[external-research:([A-Za-z0-9_-]{1,80})\]\]$"
)


def render_blocks(
    content_md: str,
    *,
    chart_svgs: dict[str, str],
    external_research_modules: dict[str, ReportExternalResearchModule] | None = None,
) -> str:
    modules = external_research_modules or {}
    # Before ordinary directives, resolve an exact marker against a server-owned module.
```

`render_external_research_module` must build all HTML from escaped typed fields. Use:

```html
<aside id="reka-report-research-{id}"
       class="r-research r-research--{status}"
       data-research-status="{status}">
  <div class="r-research-label">外部参照</div>
  <div class="r-research-content">escaped typed module content</div>
</aside>
```

Pending shows the approved copy `外部参照正在生成` and local progress treatment. Ready shows `外部参照`, or `健康参考` for health. A non-empty `escalation_guidance` appears before comparison prose in the high-risk visual tone. Failed shows `资料核对失败` plus `<a href="reka-report-retry://{id}">重试</a>`. Insufficient shows `暂时无法完成有效对照` and no retry.

Add reduced-motion-safe shimmer CSS scoped to `.r-research--pending`. Do not add a top banner, overlay, or Report-level status class.

- [ ] **Step 4: Add exact private HTML patch helpers and stable source slot**

Implement helpers that require exactly one trusted slot:

```python
REPORT_SOURCES_SLOT_RE = re.compile(
    r'<section id="reka-report-sources" class="r-sources" '
    r'aria-labelledby="report-sources-title">.*?</section>',
    re.DOTALL,
)
PENDING_EXTERNAL_RESEARCH_SLOT_RE = re.compile(
    r'<aside id="reka-report-research-[A-Za-z0-9_-]{1,80}" '
    r'class="r-research r-research--pending" '
    r'data-research-status="pending">.*?</aside>',
    re.DOTALL,
)


def replace_external_research_slot(
    html: str,
    module_id: str,
    replacement_html: str,
) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]{1,80}", module_id) is None:
        raise ValueError("invalid external research module id")
    pattern = re.compile(
        rf'<aside id="reka-report-research-{re.escape(module_id)}" '
        r'class="r-research r-research--(?:pending|ready|failed|insufficient)" '
        r'data-research-status="(?:pending|ready|failed|insufficient)">.*?</aside>',
        re.DOTALL,
    )
    matches = list(pattern.finditer(html))
    if len(matches) != 1:
        raise ValueError("external research slot must appear exactly once")
    return pattern.sub(replacement_html, html, count=1)


def replace_report_sources_slot(html: str, sources_html: str) -> str:
    matches = list(REPORT_SOURCES_SLOT_RE.finditer(html))
    if len(matches) != 1:
        raise ValueError("report sources slot must appear exactly once")
    return REPORT_SOURCES_SLOT_RE.sub(sources_html, html, count=1)


def strip_pending_external_research_slots(html: str) -> str:
    return PENDING_EXTERNAL_RESEARCH_SLOT_RE.sub("", html)
```

The renderer must always emit `<section id="reka-report-sources" class="r-sources" aria-labelledby="report-sources-title">`; it is empty and hidden when no sources exist. This gives the job and mobile viewer a stable patch target without rerendering charts. Share creation calls `strip_pending_external_research_slots` before snapshot persistence, matching the existing rule that optional work completed after sharing does not mutate the public snapshot.

- [ ] **Step 5: Run GREEN and commit**

Run the Step 2 command. Expected: PASS.

Commit:

```bash
git add theme_v2_service/app/domains/reports/presentation/blocks.py \
  theme_v2_service/app/domains/reports/presentation/renderer.py \
  theme_v2_service/app/domains/reports/presentation/styles.py \
  theme_v2_service/app/domains/reports/rendering.py \
  theme_v2_service/app/domains/reports/shares.py \
  theme_v2_service/tests/unit/test_report_presentation.py \
  theme_v2_service/tests/unit/test_report_rendering.py \
  theme_v2_service/tests/integration/test_report_shares.py
git commit -m "feat: render inline report research states"
```

---

### Task 4: Persist a readable Report and enqueue research without waiting

**Files:**
- Modify: `theme_v2_service/app/domains/reports/pipeline.py:1-710`
- Create: `theme_v2_service/app/domains/reports/external_research_jobs.py`
- Modify: `theme_v2_service/app/domains/reports/service.py:800-1100`
- Modify: `theme_v2_service/tests/unit/test_report_pipeline.py`
- Modify: `theme_v2_service/tests/integration/test_report_persist.py`
- Modify: `theme_v2_service/tests/fakes/report_providers.py`

**Interfaces:**
- Consumes: grounding, module construction, slot injection, and rendering from Tasks 2–3.
- Produces: pipeline stage `external_research`, `enqueue_report_external_research()`, pending module job IDs in `ReportSpec`, and a completed/readable Report independent of module jobs.

- [ ] **Step 1: Write pipeline RED tests**

```python
def test_external_research_stage_follows_content_and_precedes_render():
    assert STAGES == (
        "load_evidence", "web_search", "content_generation",
        "external_research", "chart_validation", "illustration",
        "html_render", "persist",
    )


async def test_pipeline_persists_core_report_without_waiting_for_research(session):
    generator = FakeGeneratorProvider(_generator_result_with_feeding_candidate())
    await _execute_pipeline(session, generator=generator)
    report = await session.scalar(select(Report))
    run = await session.get(ReportGenerationRun, report.generation_run_id)
    modules = ReportSpec.model_validate(report.spec_json).external_research_modules
    assert run.state in {"completed", "illustration_pending"}
    assert modules[0].status == "pending"
    assert modules[0].job_id
    assert 'data-research-status="pending"' in report.html
```

Also assert no candidate means no job, an invalid candidate creates no job, and resume from an `external_research` checkpoint reuses the same dedupe key.

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q \
  tests/unit/test_report_pipeline.py \
  tests/integration/test_report_persist.py
```

Expected: FAIL because the stage and enqueue function do not exist.

- [ ] **Step 3: Implement idempotent enqueue**

In `external_research_jobs.py`:

```python
REPORT_EXTERNAL_RESEARCH_JOB_TYPE = "report_external_research"


async def enqueue_report_external_research(
    session: AsyncSession,
    *,
    run: ReportGenerationRun,
    parent_job_id: str,
    module: ReportExternalResearchModule,
    research_context: dict,
) -> WorkflowJob:
    job = await enqueue_job(
        session,
        run_id=run.id,
        job_type=REPORT_EXTERNAL_RESEARCH_JOB_TYPE,
        dedupe_key=f"report-external-research:{run.id}:{module.id}",
        max_attempts=get_settings().report_provider_max_attempts,
    )
    if not job.checkpoint_json:
        job.checkpoint_json = {
            "phase": "queued",
            "module": module.model_dump(mode="json"),
            "research_context": research_context,
            "parent_job_id": parent_job_id,
        }
    await session.flush()
    return job
```

Keep the checkpoint bounded: `research_context` contains only the candidate's exact evidence quotes, grounded owned fact, selected record IDs, and any already-confirmed applicability values required by that module. It must serialize to at most 16 KiB. Do not copy full Asset payloads, the full evidence bundle, or an unbounded provider response into the child checkpoint.

- [ ] **Step 4: Add the non-blocking pipeline stage**

After content generation:

1. call `ground_research_candidates`;
2. build pending modules;
3. insert trusted markers into a copy of `content_md`;
4. enqueue one child per module inside a short transaction;
5. record each returned job ID;
6. return immediately without polling the child.

The stage result shape is:

```python
{
    "content_md": injected_content,
    "modules": [module.model_dump(mode="json") for module in modules],
    "warnings": [],
}
```

`html_render_stage` normalizes the injected content, passes typed modules to the renderer, and returns them. `persist_stage` writes them to `ReportSpec.external_research_modules`. `persist_completed_report` keeps the existing state decision based only on illustration status; pending research modules never produce a new Run state.

- [ ] **Step 5: Run GREEN and commit**

Run the Step 2 command. Expected: PASS.

Commit:

```bash
git add theme_v2_service/app/domains/reports/pipeline.py \
  theme_v2_service/app/domains/reports/external_research_jobs.py \
  theme_v2_service/app/domains/reports/service.py \
  theme_v2_service/tests/unit/test_report_pipeline.py \
  theme_v2_service/tests/integration/test_report_persist.py \
  theme_v2_service/tests/fakes/report_providers.py
git commit -m "feat: queue report research after core generation"
```

---

### Task 5: Complete durable research, patch the Report, and expose local retry

**Files:**
- Modify: `theme_v2_service/app/domains/reports/external_research_jobs.py`
- Modify: `theme_v2_service/app/domains/reports/providers_litellm.py:175-395`
- Modify: `theme_v2_service/app/domains/reports/api_reports.py:1-180`
- Modify: `theme_v2_service/app/jobs/registry.py:1-190`
- Modify: `theme_v2_service/app/worker.py:1-70`
- Create: `theme_v2_service/tests/integration/test_report_external_research_jobs.py`
- Modify: `theme_v2_service/tests/contract/test_report_api.py`
- Modify: `theme_v2_service/tests/unit/test_worker_runtime.py`

**Interfaces:**
- Consumes: `ExternalResearchRequest`, `ExternalResearchResult`, Web Search, trusted patch helpers, and pending modules.
- Produces: `execute_report_external_research_job()`, `mark_external_research_failed()`, `retry_report_external_research()`, `report_external_research_handler()`, API field `pending_external_research_count`, and `POST /api/reports/{report_id}/external-research/{module_id}/retry`.

- [ ] **Step 1: Write durable job and API RED tests**

Cover success, source insufficiency, high-risk source filtering, provider retry, stale Report, exact owner, and idempotent retry:

```python
async def test_research_job_patches_only_module_and_sources_and_increments_revision(session):
    report, job = await _seed_pending_health_module(session)
    await execute_report_external_research_job(
        job,
        web_search=_authoritative_search(),
        synthesizer=_ready_synthesizer(),
        now=NOW,
    )
    await session.refresh(report)
    module = ReportSpec.model_validate(report.spec_json).external_research_modules[0]
    assert module.status == "ready"
    assert module.source_urls == ["https://authority.example/feeding"]
    assert report.revision == 2
    assert 'data-research-status="ready"' in report.html
    assert 'id="reka-report-sources"' in report.html


async def test_retry_is_owner_scoped_and_requeues_same_module(client, auth_headers):
    response = await client.post(
        f"/api/reports/{REPORT_ID}/external-research/{MODULE_ID}/retry",
        headers=auth_headers,
    )
    assert response.status_code == 200
    assert response.json()["status"] == "pending"
    assert response.json()["pending_external_research_count"] == 1
```

- [ ] **Step 2: Run RED**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q \
  tests/integration/test_report_external_research_jobs.py \
  tests/contract/test_report_api.py \
  tests/unit/test_worker_runtime.py
```

Expected: FAIL because execution, API retry, and worker registration are absent.

- [ ] **Step 3: Add typed LiteLLM synthesis**

Implement `LiteLLMExternalResearchProvider` with a separate schema response. Its trusted prompt must include the typed module, accepted sources, exact allowed source URLs, applicable numeric claims, and these rules:

```text
Return ready only when at least one accepted source directly supports the module.
Use only source_urls from allowed_source_urls.
Do not infer missing demographic, geographic, medical, financial, or legal context.
For health, finance, legal, and safety, state applicability and uncertainty.
Preserve material disagreement between sources instead of inventing one consensus.
When authoritative evidence supports an urgent risk, put the bounded escalation in escalation_guidance.
Do not diagnose, prescribe, guarantee, or turn general references into personal facts.
Return insufficient when the supplied context cannot support a valid comparison.
```

Validate the returned object with `validate_external_research_result` before persistence.

- [ ] **Step 4: Implement durable execution and terminal degradation**

The handler performs these exact phases, checkpointing after search and synthesis so retries do not repeat completed paid work:

```python
async def execute_report_external_research_job(
    job: WorkflowJob,
    *,
    web_search: WebSearchProvider,
    synthesizer: ReportExternalResearchProvider,
    now: datetime | None = None,
    session_factory: async_sessionmaker[AsyncSession] = AsyncSessionFactory,
) -> None:
    current_time = now or utc_now()
    checkpoint = await _load_current_job_checkpoint(
        session_factory,
        job=job,
    )
    module = ReportExternalResearchModule.model_validate(checkpoint["module"])
    policy = "authoritative_only" if module.domain in HIGH_RISK_DOMAINS else "optional"
    if "sources" not in checkpoint:
        queries = build_module_web_queries(module, freshness=module.freshness)
        execution = await execute_web_search(policy=policy, provider=web_search, queries=queries)
        checkpoint = await _save_sources_checkpoint(
            session_factory,
            job=job,
            checkpoint=checkpoint,
            sources=execution.sources,
        )
    if "result" not in checkpoint:
        request = ExternalResearchRequest(
            module=module,
            evidence_context=checkpoint["research_context"],
            sources=checkpoint["sources"],
        )
        result = validate_external_research_result(
            request,
            await synthesizer.synthesize(request),
        )
        checkpoint = await _save_result_checkpoint(
            session_factory,
            job=job,
            checkpoint=checkpoint,
            result=result,
        )
    await _attach_module_result(
        session_factory,
        job=job,
        checkpoint=checkpoint,
        now=current_time,
    )
```

Define `_load_current_job_checkpoint`, `_save_sources_checkpoint`, and `_save_result_checkpoint` in the same file with the exact signatures used above. Each function verifies job ID, Run ID, running status, and lease owner before reading or writing a bounded `checkpoint_json`; save functions use a short `with_for_update()` transaction and return the committed checkpoint dictionary.

`_attach_module_result` locks the owned Report, verifies the exact pending module/job pair, merges only sources cited by this result, patches the trusted module and source slots, increments both module and Report revisions, and leaves `ReportGenerationRun.state` unchanged.

If the enrichment worker runs before the parent pipeline has persisted the Report, defer the child for one second while the matching generation job is still active. Treat a missing Report as permanent only after the parent is terminal or the Run/owner no longer matches. Emit bounded metrics for accepted/rejected triggers, query count, source outcome, synthesis duration, terminal degradation, and Report revision attachment; logs include IDs and categories but never full Asset payloads or provider responses.

On terminal provider failure, `mark_external_research_failed` patches only that module to `failed`, stores a bounded error category, increments revision, and leaves the Report readable. No-source success becomes `insufficient`, not `failed`.

- [ ] **Step 5: Add owner-scoped serialization and retry**

Serialize:

```python
def _pending_external_research_count(report: Report) -> int:
    spec = ReportSpec.model_validate(report.spec_json)
    return pending_external_research_count(spec.external_research_modules)
```

Return `pending_external_research_count` from both list and detail endpoints. Retry must lock the Report, locate one failed module, set it to pending, clear public result/error fields, requeue the same dedupe identity through `enqueue_or_requeue_job`, rerender the trusted local slot, increment revision, and commit. Insufficient modules remain non-retryable because the available context or sources cannot support the comparison; pending or ready modules return their existing state instead of creating a duplicate job. Cross-owner Report/module access returns 404.

- [ ] **Step 6: Register a bounded enrichment worker lane**

Register `REPORT_EXTERNAL_RESEARCH_JOB_TYPE` with the configured Web Search and `LiteLLMExternalResearchProvider`. Replace the illustration-only lane set with:

```python
REPORT_ENRICHMENT_JOB_TYPES = {
    REPORT_ILLUSTRATION_JOB_TYPE,
    REPORT_EXTERNAL_RESEARCH_JOB_TYPE,
}
```

Primary excludes that set; enrichment includes that set. Update `test_worker_runtime.py` to assert exactly those filters and no change to capture/planner/pipeline routing.

- [ ] **Step 7: Run GREEN and commit**

Run the Step 2 command. Expected: PASS.

Commit:

```bash
git add theme_v2_service/app/domains/reports/external_research_jobs.py \
  theme_v2_service/app/domains/reports/providers_litellm.py \
  theme_v2_service/app/domains/reports/api_reports.py \
  theme_v2_service/app/jobs/registry.py \
  theme_v2_service/app/worker.py \
  theme_v2_service/tests/integration/test_report_external_research_jobs.py \
  theme_v2_service/tests/contract/test_report_api.py \
  theme_v2_service/tests/unit/test_worker_runtime.py
git commit -m "feat: complete durable report research modules"
```

---

### Task 6: Patch only the inline module in Flutter and route retry

**Files:**
- Create: `mobile/lib/theme_v2/report/report_enrichment.dart`
- Create: `mobile/test/theme_v2/report/report_enrichment_test.dart`
- Modify: `mobile/lib/pages/report_viewer_page.dart:1-430`
- Modify: `mobile/lib/theme_v2/report/report_models.dart:85-150`
- Modify: `mobile/lib/theme_v2/report/report_notification_target.dart:120-150`
- Modify: `mobile/lib/theme_v2/report/report_container_page.dart:155-180`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart:100-140,820-930`
- Modify: `mobile/test/theme_v2/report/report_viewer_theme_test.dart`
- Modify: `mobile/test/theme_v2/report/report_repository_test.dart`
- Modify: `mobile/test/theme_v2/report/report_notification_target_test.dart`
- Modify: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Interfaces:**
- Consumes: API `pending_external_research_count`, Report `revision`, trusted module/source IDs, and retry endpoint from Task 5.
- Produces: `ReportEnrichmentSnapshot`, `extractTrustedExternalResearchSlots()`, `extractTrustedReportSourcesSlot()`, `externalResearchRetryModuleId()`, and generalized Viewer revision polling.

- [ ] **Step 1: Write pure Dart RED tests**

```dart
test('parses pending count without synthesizing malformed values', () {
  expect(ReportEnrichmentSnapshot.fromJson({
    'revision': 3,
    'illustration_status': 'ready',
    'pending_external_research_count': 1,
    'html': '<html>ready</html>',
  }).hasPendingWork, isTrue);
  expect(ReportEnrichmentSnapshot.fromJson({
    'pending_external_research_count': '1',
  }).pendingExternalResearchCount, 0);
});

test('extracts only uniquely identified trusted research slots', () {
  const trusted = '<aside id="reka-report-research-feed-1" '
      'class="r-research r-research--ready" '
      'data-research-status="ready">result</aside>';
  expect(extractTrustedExternalResearchSlots('<main>$trusted</main>'), {
    'feed-1': trusted,
  });
  expect(extractTrustedExternalResearchSlots('$trusted$trusted'), isEmpty);
});

test('retry URI accepts only a canonical bounded module id', () {
  expect(externalResearchRetryModuleId(
    'reka-report-retry://feeding-drop'), 'feeding-drop');
  expect(externalResearchRetryModuleId(
    'reka-report-retry://../feeding-drop'), isNull);
});
```

- [ ] **Step 2: Run RED**

```bash
cd mobile && flutter test \
  test/theme_v2/report/report_enrichment_test.dart \
  test/theme_v2/report/report_viewer_theme_test.dart \
  test/theme_v2/report/report_repository_test.dart \
  test/theme_v2/report/report_notification_target_test.dart \
  test/theme_v2/report/report_run_page_test.dart
```

Expected: FAIL because the enrichment model and Viewer arguments do not exist.

- [ ] **Step 3: Add pure parsing and trusted extraction**

Implement:

```dart
@immutable
class ReportEnrichmentSnapshot {
  const ReportEnrichmentSnapshot({
    required this.revision,
    required this.illustrationStatus,
    required this.pendingExternalResearchCount,
    required this.html,
  });

  final int revision;
  final String illustrationStatus;
  final int pendingExternalResearchCount;
  final String html;

  bool get hasPendingWork =>
      illustrationStatus == 'pending' || pendingExternalResearchCount > 0;

  factory ReportEnrichmentSnapshot.fromJson(Map<dynamic, dynamic> json) =>
      ReportEnrichmentSnapshot(
        revision: (json['revision'] as num?)?.toInt() ?? 1,
        illustrationStatus:
            json['illustration_status'] is String
                ? json['illustration_status'] as String
                : 'not_required',
        pendingExternalResearchCount:
            (json['pending_external_research_count'] as num?)?.toInt() ?? 0,
        html: json['html'] is String ? json['html'] as String : '',
      );
}
```

Use bounded regular expressions for exactly one `<aside id="reka-report-research-<id>">` per module and exactly one `<section id="reka-report-sources">`. Reject duplicates, external IDs, unexpected tags, and malformed schemes.

- [ ] **Step 4: Generalize Viewer polling without a Report-level state**

Replace illustration-specific scheduling with `_hasPendingEnrichment`:

```dart
bool get _hasPendingEnrichment =>
    _illustrationStatus == 'pending' || _pendingExternalResearchCount > 0;
```

Poll `/api/reports/{id}` only while visible and pending. On a newer revision:

1. patch the illustration slot if its status changed;
2. patch every changed trusted external-research slot;
3. patch the stable source slot;
4. update revision/status/count;
5. use `_reloadPreservingScroll` only when a required trusted slot cannot be patched.

Do not show a native banner, dialog, spinner, or AppBar status. Loading remains inside renderer-owned HTML.

Intercept `reka-report-retry://<module-id>` before ordinary external links. POST the retry endpoint once, immediately fetch the returned/current Report, patch the failed slot to pending, and restart bounded polling. Network failure leaves the failed module visible and shows the existing concise toast.

- [ ] **Step 5: Pass the pending count through every Theme V2 entry**

Add `initialPendingExternalResearchCount` to `ReportViewerPage`. Parse it in `CompletedReportSummary` and pass it from:

- Report container;
- completed Report notification;
- Report Run completion route;
- existing Theme V2 Asset-to-Report route if it builds the Viewer directly.

In the plan confirmation card, add exactly one line:

```dart
Text(
  externalMode == 'explicit_and_conditional'
      ? '外部参照：已纳入明确需求，并在显著异常时自动补充'
      : '外部参照：发现显著异常时自动补充',
),
```

Do not add a new step, confirmation control, or Report-level loading state.

- [ ] **Step 6: Run GREEN and targeted analysis**

Run the Step 2 Flutter command. Expected: PASS.

Run:

```bash
cd mobile && flutter analyze \
  lib/pages/report_viewer_page.dart \
  lib/theme_v2/report/report_enrichment.dart \
  lib/theme_v2/report/report_models.dart \
  lib/theme_v2/report/report_notification_target.dart \
  lib/theme_v2/report/report_container_page.dart \
  lib/theme_v2/report/report_run_page.dart \
  test/theme_v2/report/report_enrichment_test.dart \
  test/theme_v2/report/report_viewer_theme_test.dart \
  test/theme_v2/report/report_repository_test.dart \
  test/theme_v2/report/report_notification_target_test.dart \
  test/theme_v2/report/report_run_page_test.dart
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/pages/report_viewer_page.dart \
  mobile/lib/theme_v2/report/report_enrichment.dart \
  mobile/lib/theme_v2/report/report_models.dart \
  mobile/lib/theme_v2/report/report_notification_target.dart \
  mobile/lib/theme_v2/report/report_container_page.dart \
  mobile/lib/theme_v2/report/report_run_page.dart \
  mobile/test/theme_v2/report/report_enrichment_test.dart \
  mobile/test/theme_v2/report/report_viewer_theme_test.dart \
  mobile/test/theme_v2/report/report_repository_test.dart \
  mobile/test/theme_v2/report/report_notification_target_test.dart \
  mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "feat: update report research modules in place"
```

---

### Task 7: Prove the focused end-to-end contract and adjacent failure cases

**Files:**
- Create: `theme_v2_service/tests/e2e/test_report_conditional_research_flow.py`
- Modify: `theme_v2_service/tests/fakes/report_providers.py`
- Modify: `theme_v2_service/tests/contract/test_report_api.py`
- Modify: `mobile/test/theme_v2/report/report_enrichment_test.dart`

**Interfaces:**
- Consumes: all Tasks 1–6.
- Produces: one deterministic vertical-slice acceptance fixture and the final focused verification evidence.

- [ ] **Step 1: Write the deterministic vertical-slice test**

Use fake Planner, Generator, Web Search, and synthesis providers. Seed five owned feeding Assets with one grounded low record. The test must prove:

```python
async def test_core_report_opens_while_conditional_reference_completes(
    session,
    conditional_research_flow,
):
    # The fixture seeds five owned feeding records, runs the parent pipeline,
    # and returns the exact child job plus fake providers for that Run.
    run, report, child, providers = await conditional_research_flow.generate_parent()
    assert run.state in {"completed", "illustration_pending"}
    assert pending_count(report) == 1
    assert "外部参照正在生成" in report.html

    # Complete the child without changing selected owned evidence.
    original_asset_ids = list(ReportSpec.model_validate(report.spec_json).source_asset_ids)
    await execute_report_external_research_job(
        child,
        web_search=providers.web_search,
        synthesizer=providers.synthesizer,
    )
    session.expire_all()
    ready = await session.get(Report, report.id)
    assert pending_count(ready) == 0
    assert ready.revision == report.revision + 1
    assert ReportSpec.model_validate(ready.spec_json).source_asset_ids == original_asset_ids
    assert "健康参考" in ready.html
    assert "https://authority.example/feeding" in ready.html
```

Add adjacent cases in the same file:

- normal feeding records produce no candidate/job;
- one malformed or partial 20ml record does not pass the gate;
- missing age/weight returns `insufficient` without another user decision;
- Web Search failure leaves the Report readable and patches only the module to failed;
- repeating the child or retry does not duplicate modules or sources;
- a share created while pending has core content and no animated pending module.
- module completion creates no additional `report_done` Notification or Reka signal.

- [ ] **Step 2: Run the exact backend focused slice**

```bash
docker compose -f docker-compose.theme-v2.yml --profile test run --rm test \
  python -m pytest -q \
  tests/unit/test_report_schemas.py \
  tests/unit/test_report_generation_security.py \
  tests/unit/test_report_external_research.py \
  tests/unit/test_report_presentation.py \
  tests/unit/test_report_rendering.py \
  tests/unit/test_report_pipeline.py \
  tests/unit/test_worker_runtime.py \
  tests/integration/test_report_planner.py \
  tests/integration/test_report_persist.py \
  tests/integration/test_report_external_research_jobs.py \
  tests/integration/test_report_shares.py \
  tests/contract/test_report_api.py \
  tests/e2e/test_report_conditional_research_flow.py
```

Expected: all selected tests PASS. Do not expand to the full backend suite.

- [ ] **Step 3: Run the exact Flutter focused slice**

```bash
cd mobile && flutter test \
  test/theme_v2/report/report_enrichment_test.dart \
  test/theme_v2/report/report_viewer_theme_test.dart \
  test/theme_v2/report/report_repository_test.dart \
  test/theme_v2/report/report_notification_target_test.dart \
  test/theme_v2/report/report_run_page_test.dart
```

Expected: all selected tests PASS. Do not expand to the full Flutter suite.

- [ ] **Step 4: Run targeted analysis and diff checks**

```bash
cd mobile && flutter analyze \
  lib/pages/report_viewer_page.dart \
  lib/theme_v2/report/report_enrichment.dart \
  lib/theme_v2/report/report_models.dart \
  lib/theme_v2/report/report_notification_target.dart \
  lib/theme_v2/report/report_container_page.dart \
  lib/theme_v2/report/report_run_page.dart \
  test/theme_v2/report/report_enrichment_test.dart \
  test/theme_v2/report/report_viewer_theme_test.dart \
  test/theme_v2/report/report_repository_test.dart \
  test/theme_v2/report/report_notification_target_test.dart \
  test/theme_v2/report/report_run_page_test.dart
cd .. && git diff --check
```

Expected: `No issues found!` and no diff-check output.

- [ ] **Step 5: Commit the focused acceptance fixture**

```bash
git add theme_v2_service/tests/e2e/test_report_conditional_research_flow.py \
  theme_v2_service/tests/fakes/report_providers.py \
  theme_v2_service/tests/contract/test_report_api.py \
  mobile/test/theme_v2/report/report_enrichment_test.dart
git commit -m "test: verify conditional report research flow"
```

---

## Execution Notes

- Implement tasks in order. Later tasks depend on exact interfaces created earlier.
- Use RED → GREEN for every task. Do not write production code before the stated failing test demonstrates the missing behavior.
- Keep commits scoped to one task. Do not include unrelated root-worktree or preview files.
- Do not modify the existing selected-Asset scope contract, Report template catalog, chart renderer, Report-to-Todo behavior, or notification model outside the explicit changes above.
- Do not rebuild or install a device APK during implementation. A device pass is a separate user-approved step after focused automated verification.
- If implementation reveals that a full suite is genuinely required by a cross-cutting change, stop first, explain the specific unbounded risk and estimated cost, and obtain user confirmation as required by `AGENTS.md`.
