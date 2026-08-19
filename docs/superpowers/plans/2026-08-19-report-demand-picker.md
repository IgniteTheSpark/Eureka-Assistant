# Report Demand Confirmation and Full-screen Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make vague period-summary requests preselect relevant assets, collect the complete report brief on one page, and provide one full-screen asset picker with configured two-line cards.

**Architecture:** The report scope adapter returns a provisional 30-day scope plus exact matching references for vague “最近” requests. Flutter keeps explicit additions/exclusions while refetching filters, renders grouped selection summaries, and opens a single full-screen picker for manual add and group review. Evidence-option formatting is driven by each Skill render spec so picker cards match Asset Library configuration.

**Tech Stack:** Python 3.12, FastAPI/Pydantic, SQLAlchemy async, pytest, Flutter/Dart, Material 3.

## Global Constraints

- Report demand confirmation is one page; do not add a stepper.
- Time choices are exactly 最近 7 天、最近 14 天、最近 30 天、其他.
- Presentation form and additional information remain on the same page.
- The main picker has no “全部 / 已选” tab; type pills wrap to multiple rows.
- Custom asset rows use configured primary and secondary display fields and never substitute the Skill label for missing content.
- Follow `/AGENTS.md`: run only reproducing tests, directly affected cases, targeted analysis, and diff checks.

---

### Task 1: Return a provisional 30-day selection for vague report periods

**Files:**
- Modify: `theme_v2_service/app/domains/reports/scope_adapters.py`
- Test: `theme_v2_service/tests/integration/test_report_scope_adapters.py`

**Interfaces:**
- Consumes: `initial_scope(intent, now, timezone_name)` and `_filter_record_groups_for_intent(groups, intent)`.
- Produces: `time_range_options()` with `last_7_days`, `last_14_days`, `last_30_days`, `custom`; `ReportScopeCandidateResponse.default_scope` with provisional 30-day references and unresolved `time_range` dimension.

- [ ] **Step 1: Replace the stale zero-selection assertion with a failing dance regression**

```python
async def test_vague_recent_dance_previews_thirty_days_and_selects_dance(session):
    await _seed_report_record_types(session)
    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结最近的跳舞情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    assert [option.id for option in response.time_range_options] == [
        "last_7_days", "last_14_days", "last_30_days", "custom"
    ]
    assert [group.machine_name for group in response.record_groups] == ["dance_log"]
    assert response.default_scope.missing_dimensions == ["time_range"]
    assert response.default_scope.time_range == response.time_range_options[2].time_range
    assert [ref.id for ref in response.default_scope.selection.auto_references] == [
        "asset-3"
    ]
```

- [ ] **Step 2: Run the focused backend test and verify RED**

Run from repository root:

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/integration/test_report_scope_adapters.py \
  -q -k 'vague_recent_dance or explicit_period_selects_only_matching'
```

Expected: the new dance test fails because the current response has no 14-day option, no provisional time range, and zero automatic references.

- [ ] **Step 3: Implement stable 7/14/30/custom options and provisional selection**

```python
def time_range_options(*, now: datetime, timezone_name: str) -> list[TimeRangeOption]:
    zone = ZoneInfo(timezone_name)
    local_now = _aware_utc(now).astimezone(zone)
    return [
        TimeRangeOption(
            id=f"last_{days}_days",
            label=f"最近 {days} 天",
            time_range=TimeRange(
                from_at=local_now - timedelta(days=days),
                to_at=local_now,
            ),
        )
        for days in (7, 14, 30)
    ] + [TimeRangeOption(id="custom", label="其他")]
```

In `list_scope_candidates`, select `last_30_days` by ID instead of list position, query that period when the parsed time is absent, always build `auto_references`, and copy the provisional period into `default_scope.time_range` while retaining `missing_dimensions == ["time_range"]`.

Change intent filtering to return whether a semantic type match was found. When no type matched and more than one record group is available, append `asset_type` to `missing_dimensions`; do not append it for an explicit dance match.

- [ ] **Step 4: Run the directly affected scope-adapter cases**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/integration/test_report_scope_adapters.py -q \
  -k 'vague_recent or explicit_period or time_range'
```

Expected: all selected scope-period tests pass.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/scope_adapters.py \
  theme_v2_service/tests/integration/test_report_scope_adapters.py
git commit -m "fix: preselect vague report scope assets"
```

### Task 2: Format Report evidence from configured card fields

**Files:**
- Modify: `theme_v2_service/app/domains/reports/evidence_options.py`
- Test: `theme_v2_service/tests/integration/test_report_evidence.py`

**Interfaces:**
- Consumes: `UserSkill.render_spec_json`, `Asset.payload_json`.
- Produces: `EvidenceOption.title`, `subtitle`, and filter labels with counts.

- [ ] **Step 1: Add failing configured-field and missing-field tests**

```python
async def test_asset_options_use_configured_card_fields(session):
    skill = await _skill(session, user_id="user-1", name="dance_log")
    skill.display_name = "跳舞记录"
    skill.render_spec_json = {
        "primary_field": "practice_name",
        "card_display": {
            "primary_field_id": "practice_name",
            "secondary_field_ids": ["location", "duration"],
        },
    }
    session.add(Asset(
        id="dance-1", user_id="user-1", user_skill_id=skill.id,
        payload_json={
            "practice_name": "Urban 编舞", "location": "网球中心", "duration": 48,
        },
    ))
    await session.commit()
    page = await list_evidence_options(session, user_id="user-1")
    option = next(item for item in page.items if item.reference.id == "dance-1")
    assert option.title == "Urban 编舞"
    assert option.subtitle == "网球中心 · 48"
```

Add a sibling asset with only `location`; assert `option.title == ""` and that neither title nor subtitle falls back to `跳舞记录`.

- [ ] **Step 2: Run the two focused evidence tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/integration/test_report_evidence.py -q \
  -k 'configured_card_fields or missing_configured_field'
```

Expected: current heuristic title/subtitle selection fails both assertions.

- [ ] **Step 3: Implement render-spec field extraction**

```python
def _card_fields(skill: UserSkill) -> tuple[str, list[str]]:
    render = skill.render_spec_json or {}
    card = render.get("card_display") if isinstance(render.get("card_display"), dict) else {}
    primary = str(card.get("primary_field_id") or render.get("primary_field") or "")
    secondary = card.get("secondary_field_ids")
    if not isinstance(secondary, list):
        secondary = [render.get("secondary_field"), *(row.get("field") for row in render.get("meta_fields", []) if isinstance(row, dict))]
    return primary, [str(field) for field in secondary if field and field != primary][:3]

def _asset_card_text(asset: Asset, skill: UserSkill) -> tuple[str, str | None]:
    primary, secondary = _card_fields(skill)
    payload = asset.payload_json or {}
    title = _text(payload.get(primary)) if primary else ""
    values = [_text(payload.get(field)) for field in secondary]
    subtitle = " · ".join(value for value in values if value)
    return title, subtitle or None
```

Use this pair for search and response construction. Build filters only for kinds present in the unpaginated candidate result and include their counts in the label, for example `跳舞记录 8`.

- [ ] **Step 4: Run the focused evidence file**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/integration/test_report_evidence.py -q
```

Expected: all Report evidence-option tests pass.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/reports/evidence_options.py \
  theme_v2_service/tests/integration/test_report_evidence.py
git commit -m "fix: honor configured fields in report evidence"
```

### Task 3: Make the Report scope page an adaptive complete brief

**Files:**
- Modify: `mobile/lib/theme_v2/report/report_run_controller.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Test: `mobile/test/theme_v2/report/report_run_controller_test.dart`
- Test: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Interfaces:**
- Consumes: provisional `ReportScopeDraftView`, `ReportScopeCandidateResponseView.recordGroups`.
- Produces: grouped selected summaries; `openEvidencePicker(initialFilterId:)`; exact brief submitted to plan generation.

- [ ] **Step 1: Add failing controller regressions**

```dart
test('provisional scope keeps matching auto selection while time is unresolved', () async {
  final controller = ReportRunController(api: fakeApi);
  await controller.loadScopeCandidates();
  expect(controller.scopeDraft!.missingDimensions, contains('time_range'));
  expect(
    controller.scopeDraft!.selection.autoReferences,
    const [EvidenceReferenceView(kind: 'asset', id: 'dance-1')],
  );
});

test('refetch preserves manual additions and exclusions', () async {
  controller.replaceScopeSupportingReferences(const [
    EvidenceReferenceView(kind: 'asset', id: 'manual-1'),
  ]);
  await controller.selectScopeTimeRange(last14Days);
  expect(controller.scopeDraft!.selection.manualReferences.single.id, 'manual-1');
  expect(controller.scopeDraft!.selection.excludedReferenceIds, contains('dance-1'));
});
```

Use the existing fake API queue to return 30-day and 14-day candidate payloads. Add a third assertion that `toggleScopeGroup('skill-dance', true)` removes `asset_type` from `missingDimensions` without clearing `manualReferences`.

- [ ] **Step 2: Run controller tests and verify RED**

```bash
cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart
```

Expected: new provisional/type-selection expectations fail.

- [ ] **Step 3: Implement controller helpers**

Add `selectedCountForGroup(String skillId)`, preserve manual/excluded state in `_mergeRefetchedCandidates`, and remove the resolved dimension when a time or type choice is confirmed. Do not introduce a separate page-stage state.

- [ ] **Step 4: Add failing page regressions**

```dart
expect(find.byKey(const ValueKey('report-step-scope')), findsOneWidget);
expect(find.text('最近 7 天'), findsOneWidget);
expect(find.text('最近 14 天'), findsOneWidget);
expect(find.text('最近 30 天'), findsOneWidget);
expect(find.text('其他'), findsWidgets);
expect(find.byKey(const ValueKey('report-selected-group-skill-dance')), findsOneWidget);
expect(find.text('跳舞记录 × 8'), findsOneWidget);
expect(find.byKey(const ValueKey('report-open-evidence-picker')), findsOneWidget);
expect(find.byKey(const ValueKey('report-additional-focus')), findsOneWidget);
expect(find.byKey(const ValueKey('report-presentation-data_trend')), findsOneWidget);
expect(find.byKey(const ValueKey('report-scope-record-dance-1')), findsNothing);
```

- [ ] **Step 5: Implement the adaptive page**

Replace the current generic “已选择 n 项资产” and inline `_recordScopeGroup` list with clarification cards and grouped summary buttons. The group button calls `_openEvidencePicker(initialFilterId: group.skillId)`; manual add passes no filter. Keep existing presentation and additional-focus controls in this same scroll view. The bottom action contains only `生成报告方案`.

- [ ] **Step 6: Run focused Report controller/page tests**

```bash
cd mobile && flutter test \
  test/theme_v2/report/report_run_controller_test.dart \
  test/theme_v2/report/report_run_page_test.dart
```

Expected: both files pass.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/theme_v2/report/report_run_controller.dart \
  mobile/lib/theme_v2/report/report_run_page.dart \
  mobile/test/theme_v2/report/report_run_controller_test.dart \
  mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "feat: confirm complete report demand inline"
```

### Task 4: Convert Report evidence selection into one full-screen picker

**Files:**
- Modify: `mobile/lib/theme_v2/report/report_evidence_picker_page.dart`
- Modify: `mobile/lib/theme_v2/report/report_plan_models.dart`
- Modify: `mobile/lib/theme_v2/report/report_run_page.dart`
- Test: `mobile/test/theme_v2/report/report_evidence_picker_page_test.dart`

**Interfaces:**
- Consumes: `ReportEvidenceLoader`, `initialSelected`, optional `initialFilterId`.
- Produces: `Future<List<EvidenceReferenceView>?> showReportEvidencePicker(...)`.

- [ ] **Step 1: Add failing full-screen interaction tests**

```dart
await tester.tap(find.text('打开'));
await tester.pumpAndSettle();
expect(find.byType(ReportEvidencePickerPage), findsOneWidget);
expect(find.byKey(const ValueKey('report-evidence-filter-wrap')), findsOneWidget);
expect(find.text('已选'), findsNothing);
expect(
  tester.widget<ChoiceChip>(
    find.byKey(const ValueKey('report-evidence-filter-skill-dance')),
  ).selected,
  isTrue,
);
await tester.tap(find.byKey(const ValueKey('report-evidence-selected-summary')));
await tester.pumpAndSettle();
expect(find.text('已选资产'), findsOneWidget);
await tester.tap(find.byKey(const ValueKey('selected-remove-asset:dance-1')));
await tester.tap(find.text('返回'));
await tester.pumpAndSettle();
expect(find.text('已选择 0 项'), findsOneWidget);
```

- [ ] **Step 2: Run the picker test and verify RED**

```bash
cd mobile && flutter test test/theme_v2/report/report_evidence_picker_page_test.dart
```

Expected: failures for sheet host, horizontal filters, missing initial filter, and missing review page.

- [ ] **Step 3: Replace the sheet launcher with a full-screen route**

```dart
Future<List<EvidenceReferenceView>?> showReportEvidencePicker(
  BuildContext context, {
  required ReportEvidenceLoader loadPage,
  List<EvidenceReferenceView> initialSelected = const [],
  String? initialFilterId,
}) => Navigator.of(context).push<List<EvidenceReferenceView>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ReportEvidencePickerPage(
      loadPage: loadPage,
      initialSelected: initialSelected,
      initialFilterId: initialFilterId,
    ),
  ),
);
```

- [ ] **Step 4: Build the main and selected-review surfaces**

Use `Wrap` for all filter pills. Render asset options with `ThemeV2AssetCard(variant: AssetCardVariant.richCard, height: 78)` using `AssetCardViewData(skillLabel: option.typeLabel, primaryValue: option.title, secondaryValues: [if (option.subtitle case final value?) value], mark: option.icon)`. Put `已选择 n 项 ›` and `完成` in separate hit targets. Push a private `_SelectedEvidencePage` that removes from the shared selected map and returns without recreating picker state.

- [ ] **Step 5: Run picker plus Report page regressions**

```bash
cd mobile && flutter test \
  test/theme_v2/report/report_evidence_picker_page_test.dart \
  test/theme_v2/report/report_run_page_test.dart
```

Expected: both files pass.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/report/report_evidence_picker_page.dart \
  mobile/lib/theme_v2/report/report_plan_models.dart \
  mobile/lib/theme_v2/report/report_run_page.dart \
  mobile/test/theme_v2/report/report_evidence_picker_page_test.dart \
  mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "feat: add full-screen report asset picker"
```

### Task 5: Focused Report verification

**Files:** No production changes expected.

- [ ] **Step 1: Run the affected backend slice**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest \
  tests/integration/test_report_scope_adapters.py \
  tests/integration/test_report_evidence.py -q
```

- [ ] **Step 2: Run the affected Flutter slice**

```bash
cd mobile && flutter test \
  test/theme_v2/report/report_run_controller_test.dart \
  test/theme_v2/report/report_run_page_test.dart \
  test/theme_v2/report/report_evidence_picker_page_test.dart
```

- [ ] **Step 3: Run targeted analysis and diff checks**

```bash
cd mobile && flutter analyze \
  lib/theme_v2/report/report_run_controller.dart \
  lib/theme_v2/report/report_run_page.dart \
  lib/theme_v2/report/report_evidence_picker_page.dart \
  lib/theme_v2/report/report_plan_models.dart
git diff --check
```

Expected: all focused tests pass, targeted analysis reports no issues, and diff check is clean. Do not run full backend or Flutter suites.
