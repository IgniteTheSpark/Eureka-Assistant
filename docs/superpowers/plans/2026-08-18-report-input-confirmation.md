# Report Input Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make report step one explicitly confirm Assets, an optional presentation preference, and optional supplemental text before plan generation.

**Architecture:** Extend the report scope draft with unresolved filter dimensions and presentation preference, make scope-candidate generation progressive, and keep one authoritative selection set. The Flutter controller renders only missing filters, supports manual Asset additions, and passes the confirmed input to the existing bounded Planner.

**Tech Stack:** Python 3.12, FastAPI, Pydantic, SQLAlchemy, pytest, Flutter/Dart, flutter_test.

## Global Constraints

- Time range and Skill type are Asset filters, not report types.
- Type-only requests ask only for time; type-plus-time requests immediately select all matching Assets.
- Specific-Asset requests select it and offer additional Asset association.
- Manual Asset addition is always available.
- Presentation preference is nullable and single-select: data review, theme synthesis, professional evaluation, research briefing, or custom.
- Supplemental report text is stored separately from custom-presentation text.
- User-selected standard presentation family is a hard Planner constraint.
- Use TDD and commit each independently passing task.

---

### Task 1: Model progressive report input on the service

**Files:**
- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/app/domains/reports/scope_adapters.py`
- Test: `theme_v2_service/tests/unit/test_report_schemas.py`
- Test: `theme_v2_service/tests/integration/test_report_scope_adapters.py`

**Interfaces:**
- Produces: `PresentationPreference(family, custom_text)`.
- Extends: `ReportScopeDraft.presentation_preference` and `ReportScopeDraft.missing_dimensions`.
- Extends: `ReportScopeCandidateResponse.time_range_options`.

- [ ] **Step 1: Write failing schema and adapter tests**

```python
def test_recent_expense_scope_keeps_time_unresolved():
    draft = initial_scope("总结最近的消费", now=NOW, timezone_name="Asia/Shanghai")
    assert draft.adapter_kind == "period_summary"
    assert draft.time_range is None
    assert draft.missing_dimensions == ["time_range"]

async def test_explicit_month_selects_all_matching_expenses(session):
    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结本月的消费",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    assert response.time_range_options == []
    assert {ref.id for ref in response.default_scope.supporting_references} == {
        "expense-1", "expense-2"
    }
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd theme_v2_service && pytest tests/unit/test_report_schemas.py tests/integration/test_report_scope_adapters.py -q`

Expected: FAIL because vague `最近` is immediately resolved to seven days and preference fields do not exist.

- [ ] **Step 3: Implement progressive input models**

```python
PresentationFamily = Literal[
    "data_trend",
    "theme_synthesis",
    "professional_evaluation",
    "briefing_research",
]

class PresentationPreference(StrictModel):
    family: PresentationFamily | None = None
    custom_text: str = Field(default="", max_length=500)

class TimeRangeOption(StrictModel):
    id: Literal["last_7_days", "last_30_days", "current_month", "custom"]
    label: str
    time_range: TimeRange | None = None
```

Treat `最近`/`近期` without a number as unresolved. Emit 7-day, 30-day, current-month, and custom options. Explicit `本月`, `近7天`, `过去30天`, or a submitted time range remains resolved. Keep backward-compatible defaults when reading existing drafts.

- [ ] **Step 4: Run schema/adapter tests**

Run: `cd theme_v2_service && pytest tests/unit/test_report_schemas.py tests/integration/test_report_scope_adapters.py -q`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/schemas.py theme_v2_service/app/domains/reports/scope_adapters.py theme_v2_service/tests/unit/test_report_schemas.py theme_v2_service/tests/integration/test_report_scope_adapters.py
git commit -m "feat: model progressive report input"
```

### Task 2: Recompute one authoritative Asset selection set

**Files:**
- Modify: `theme_v2_service/app/domains/reports/schemas.py`
- Modify: `theme_v2_service/app/domains/reports/scope_adapters.py`
- Modify: `theme_v2_service/app/domains/reports/service.py`
- Modify: `theme_v2_service/app/domains/reports/api_runs.py`
- Test: `theme_v2_service/tests/integration/test_report_scope_adapters.py`
- Test: `theme_v2_service/tests/contract/test_report_run_api.py`

**Interfaces:**
- Produces: `ReportAssetSelection(auto_references, manual_references, excluded_reference_ids)`.
- Produces: scope-draft recomputation semantics used by `PUT /api/report-generation-runs/{id}/scope-draft`.

- [ ] **Step 1: Write failing selection-provenance tests**

```python
async def test_time_selection_autoselects_all_and_preserves_manual_assets(session, report_run):
    updated = await update_scope_draft(
        session,
        user_id="user-1",
        run_id=report_run.id,
        command=ReportScopeDraftUpdate(expected_revision=0, draft={
            "time_range": LAST_30_DAYS,
            "skill_ids": ["expense-skill"],
            "selection": {
                "manual_references": [{"kind": "asset", "id": "note-1"}]
            },
        }),
    )
    ids = {ref["id"] for ref in updated.scope_draft["supporting_references"]}
    assert ids == {"expense-1", "expense-2", "note-1"}
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_scope_adapters.py tests/contract/test_report_run_api.py -k 'selection or scope' -q`

Expected: FAIL because auto/manual/excluded selection is not modeled.

- [ ] **Step 3: Implement selection recomputation**

Define the final set as:

```python
auto = await references_for_filters(
    session,
    user_id=user_id,
    skill_ids=draft.skill_ids,
    time_range=draft.time_range,
)
final = (
    set(auto) - set(draft.selection.excluded_reference_ids)
) | set(draft.selection.manual_references)
draft = draft.model_copy(update={
    "supporting_references": sorted(final, key=lambda ref: (ref.kind, ref.id)),
    "selection": draft.selection.model_copy(update={"auto_references": auto}),
})
```

Do not recompute for a specific-Asset-only draft with no Skill/time filters. Validate ownership for auto and manual references. Save and return the same resolved draft used by Planner preparation.

- [ ] **Step 4: Run report scope contract tests**

Run: `cd theme_v2_service && pytest tests/contract/test_report_run_api.py tests/integration/test_report_scope_adapters.py -q`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/schemas.py theme_v2_service/app/domains/reports/scope_adapters.py theme_v2_service/app/domains/reports/service.py theme_v2_service/app/domains/reports/api_runs.py theme_v2_service/tests/integration/test_report_scope_adapters.py theme_v2_service/tests/contract/test_report_run_api.py
git commit -m "fix: keep one report asset selection set"
```

### Task 3: Constrain Planner options with presentation preference

**Files:**
- Modify: `theme_v2_service/app/domains/reports/planner.py`
- Modify: `theme_v2_service/app/domains/reports/providers_litellm.py`
- Test: `theme_v2_service/tests/integration/test_report_planner.py`
- Test: `theme_v2_service/tests/unit/test_report_schemas.py`

**Interfaces:**
- Consumes: `ReportScopeDraft.presentation_preference`.
- Guarantees: a standard selected family is present on every returned option; an unset family remains Planner-owned.

- [ ] **Step 1: Write failing Planner constraint tests**

```python
def test_selected_presentation_family_rejects_other_option_family(planner_request):
    request = planner_request.model_copy(update={
        "scope_draft": planner_request.scope_draft.model_copy(update={
            "presentation_preference": {"family": "theme_synthesis"}
        })
    })
    result = PlannerResult(options=[option(base_family="data_trend")])
    with pytest.raises(InvalidPlannerResult, match="presentation family"):
        validate_planner_result_against_request(request=request, result=result)
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_planner.py -k 'presentation' -q`

Expected: FAIL because Planner validation ignores presentation preference.

- [ ] **Step 3: Implement catalog filtering and validation**

When a standard family is selected, filter `registry.candidates_for(capabilities)` to that `base_family`. Include the preference and custom text in trusted Planner configuration. Reject any returned option that violates the selected family. If filtering leaves no official template, return a plan blocker instead of silently using another family. With no selection, preserve existing candidate/recommendation behavior.

- [ ] **Step 4: Run Planner tests**

Run: `cd theme_v2_service && pytest tests/integration/test_report_planner.py tests/unit/test_report_schemas.py -q`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/planner.py theme_v2_service/app/domains/reports/providers_litellm.py theme_v2_service/tests/integration/test_report_planner.py theme_v2_service/tests/unit/test_report_schemas.py
git commit -m "feat: honor report presentation preference"
```

### Task 4: Decode progressive report input in Flutter state

**Files:**
- Modify: `mobile/lib/theme_v2/report/report_plan_models.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_controller.dart`
- Test: `mobile/test/theme_v2/report/report_run_controller_test.dart`

**Interfaces:**
- Produces Dart views for time options, selection provenance, and presentation preference.
- Produces controller methods `selectTimeRange`, `setPresentationFamily`, `setCustomPresentation`, `addManualReferences`, and `removeReference`.

- [ ] **Step 1: Write failing controller tests**

```dart
test('selecting 30 days loads default all-selected expense scope', () async {
  final controller = ReportRunController(api: fakeApi);
  await controller.loadRun('run-1');
  await controller.loadScopeCandidates();
  await controller.selectTimeRange('last_30_days');
  expect(
    controller.scopeDraft!.supportingReferences.map((item) => item.id),
    containsAll(<String>['expense-1', 'expense-2']),
  );
});

test('presentation text stays separate from supplemental focus', () {
  controller.setCustomPresentation('一页式图表');
  controller.updateScopeAdditionalFocus('比较餐饮和交通');
  expect(controller.scopeDraft!.presentationPreference.customText, '一页式图表');
  expect(controller.scopeDraft!.additionalFocus, '比较餐饮和交通');
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart`

Expected: FAIL because progressive input types and methods do not exist.

- [ ] **Step 3: Implement immutable models and controller transitions**

Add JSON-compatible view models and ensure `copyWith` can explicitly clear nullable family/time values. `selectTimeRange` updates the draft and saves it through the service, then replaces local scope with the returned authoritative selection. Manual picker changes update manual/excluded provenance rather than maintaining a second untracked list.

- [ ] **Step 4: Run controller tests**

Run: `cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/report/report_plan_models.dart mobile/lib/theme_v2/report/report_run_controller.dart mobile/test/theme_v2/report/report_run_controller_test.dart
git commit -m "feat: manage progressive report input state"
```

### Task 5: Build the `确认报告输入` screen

**Files:**
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_evidence_picker_page.dart`
- Test: `mobile/test/theme_v2/report/report_run_page_test.dart`
- Test: `mobile/test/theme_v2/report/report_evidence_picker_page_test.dart`

**Interfaces:**
- Consumes: controller APIs from Task 4.
- Produces: three independent sections: Asset scope, optional presentation, optional supplemental text.

- [ ] **Step 1: Write failing progressive UI tests**

```dart
testWidgets('type-only request shows time pills and manual Asset entry', (tester) async {
  await tester.pumpWidget(reportRunHarness(typeKnown: true, timeMissing: true));
  expect(find.byKey(const ValueKey('report-time-last-7-days')), findsOneWidget);
  expect(find.byKey(const ValueKey('report-time-last-30-days')), findsOneWidget);
  expect(find.byKey(const ValueKey('report-add-assets')), findsOneWidget);
});

testWidgets('presentation is nullable and other has a separate input', (tester) async {
  await tester.pumpWidget(reportRunHarness());
  expect(
    find.text('不选择时，Reka 会根据本次素材推荐合适的呈现方式。'),
    findsOneWidget,
  );
  await tester.tap(find.text('其他'));
  await tester.pump();
  expect(find.byKey(const ValueKey('report-custom-presentation')), findsOneWidget);
  expect(find.byKey(const ValueKey('report-additional-focus')), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/report/report_run_page_test.dart test/theme_v2/report/report_evidence_picker_page_test.dart`

Expected: FAIL because the current scope step has no progressive pills/presentation section and hides manual add for period summaries.

- [ ] **Step 3: Implement the three-section input screen**

Replace the step-zero title with `确认报告输入`.

- Asset scope: render only missing filter pills, then selected grouped Assets with count/select-all and per-record removal. Always render `手动添加资产`; for a specific primary Asset use copy `还要关联其他资产吗？`.
- Presentation: nullable ChoiceChips for `数据复盘`, `主题综合`, `专业评估`, `调研简报`, `其他`; tapping the selected standard pill again clears it. `其他` reveals its own text field.
- Supplemental text: retain a separate multiline field for focus/background/use.

Keep the primary CTA disabled until at least one final reference is selected. CTA copy becomes `确认输入，生成方案`.

- [ ] **Step 4: Run report tests and analysis**

Run: `cd mobile && flutter test test/theme_v2/report`

Run: `cd mobile && flutter analyze lib/theme_v2/report test/theme_v2/report`

Expected: PASS and no analyzer issues.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/report/report_run_page.dart mobile/lib/theme_v2/report/report_evidence_picker_page.dart mobile/test/theme_v2/report/report_run_page_test.dart mobile/test/theme_v2/report/report_evidence_picker_page_test.dart
git commit -m "feat: confirm report assets and presentation input"
```

### Task 6: Verify the end-to-end report flow

**Files:**
- Modify: `theme_v2_service/tests/e2e/test_report_generation_flow.py`
- Modify: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Interfaces:**
- Verifies all service/mobile contracts produced by Tasks 1–5.

- [ ] **Step 1: Add an end-to-end recent-expense case**

```python
async def test_recent_expense_requires_time_then_plans_with_every_selected_expense(client, seeded_expenses):
    run = await create_run(client, "总结最近的消费")
    assert run["scope_draft"]["missing_dimensions"] == ["time_range"]
    run = await choose_time_range(client, run, "last_30_days")
    assert {ref["id"] for ref in run["scope_draft"]["supporting_references"]} == {
        expense.id for expense in seeded_expenses
    }
    planned = await prepare_plan(client, run)
    assert planned["state"] == "planning"
```

- [ ] **Step 2: Run the end-to-end service test**

Run: `cd theme_v2_service && pytest tests/e2e/test_report_generation_flow.py -k 'recent_expense' -q`

Expected: PASS.

- [ ] **Step 3: Run the complete affected service and Flutter suites**

Run: `cd theme_v2_service && pytest tests/contract/test_report_run_api.py tests/integration/test_report_scope_adapters.py tests/integration/test_report_planner.py tests/e2e/test_report_generation_flow.py -q`

Run: `cd mobile && flutter test test/theme_v2/report`

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add theme_v2_service/tests/e2e/test_report_generation_flow.py mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "test: cover progressive report input flow"
```
