# Theme V2 Stable Shell, Skill Management, and Report Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Theme V2 root pages alive across Tab switches, restore pure global backgrounds, preserve the two Today dither containers, consolidate custom-Skill management, and correctly scope vague running reports.

**Architecture:** Give the root `IndexedStack` a stable layout slot so switching between immersive Today and standard pages never remounts root page state. Separate real data mutations from navigation-only refresh requests, merge card-display selection into custom-Skill management, and replace the expense-only report filter with deterministic Skill-term matching while keeping vague time unresolved.

**Tech Stack:** Flutter/Dart, Riverpod, WebView/WebGL, flutter_test, Python 3.12, FastAPI, SQLAlchemy, Pydantic, pytest.

## Global Constraints

- Remove visible Dither from all global page backgrounds, Calendar, Library, Report, top Nav, and bottom Dock.
- Keep exactly two local Dither fields on Today: `Reka 发现` and `Reka 生成`.
- Empty Today containers display visible, clickable zero-count watermarks without adding borders or explanatory empty copy.
- Tab switching must not recreate Today, Calendar, Library, the Reka renderer, or their controllers.
- Existing Library content must never be replaced by a blank loading surface during background refresh.
- Custom Skills have one management entry containing basic information, fields, card display, and deletion.
- Built-in Skills retain only card-display configuration.
- The `Describe / Fields / Card` stepper remains in Skill creation and is absent from existing-Skill card configuration.
- “总结最近的跑步情况” matches only running Skills and keeps time unresolved until the user confirms it.
- Use TDD: every production behavior change starts with a focused failing test and each task ends in an independently passing commit.

---

### Task 1: Keep root page state alive and remove global Dither

**Files:**
- Modify: `mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart`
- Modify: `mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart`

**Interfaces:**
- Extends: `ThemeV2PageScaffold.topNavExtent: double` with default `ThemeV2GlobalTopNav.height`.
- Guarantees: the page body always occupies the first stable child slot of one SafeArea/Stack composition.
- Guarantees: no `ThemeV2DitherSurface` or `ThemeV2DitherField.shaderSurfaceKey` is created by the page scaffold.

- [ ] **Step 1: Replace the shell-Dither expectation with a pure-background test**

```dart
testWidgets('page scaffold uses a pure background without global dither', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildThemeV2Theme(Brightness.light),
      home: const ThemeV2PageScaffold(
        body: SizedBox.expand(key: ValueKey('test-body')),
        topNav: SizedBox(height: 56, key: ValueKey('test-top-nav')),
        dock: SizedBox(height: 60, key: ValueKey('test-dock')),
      ),
    ),
  );

  expect(find.byKey(ThemeV2DitherField.shaderSurfaceKey), findsNothing);
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  expect(scaffold.backgroundColor, ThemeV2Tokens.light.background);
}
```

- [ ] **Step 2: Add a failing state-identity test across all three destinations**

```dart
testWidgets('root page states survive immersive and standard Tab switches', (
  tester,
) async {
  final keys = List.generate(3, (_) => GlobalKey<_MountedProbeState>());
  await tester.pumpWidget(
    _hostShell(
      pages: [
        ThemeV2PageScaffold(
          extendBodyBehindChrome: true,
          body: _MountedProbe(key: keys[0]),
        ),
        ThemeV2PageScaffold(body: _MountedProbe(key: keys[1])),
        ThemeV2PageScaffold(body: _MountedProbe(key: keys[2])),
      ],
    ),
  );
  final states = keys.map((key) => key.currentState).toList();

  await tester.tap(find.bySemanticsLabel('日历'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('资产'));
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('今日'));
  await tester.pump();

  expect(keys.map((key) => key.currentState), orderedEquals(states));
  expect(states.map((state) => state!.disposeCount), everyElement(0));
}
```

- [ ] **Step 3: Run the two tests and confirm the intended failures**

Run: `cd mobile && flutter test test/theme_v2/shell/theme_v2_page_scaffold_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart`

Expected: the pure-background assertion fails because a global Dither exists, and at least one probe State changes after switching between immersive and standard scaffolds.

- [ ] **Step 4: Implement one stable Stack composition**

Replace the conditional Stack/Column body with one layout shape:

```dart
final topClearance = showTopNav && !extendBodyBehindChrome
    ? topNavExtent
    : 0.0;
final bottomClearance = showDock && !extendBodyBehindChrome
    ? ThemeV2FloatingDock.contentClearance +
          MediaQuery.paddingOf(context).bottom
    : 0.0;

final composition = SafeArea(
  bottom: false,
  child: Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.only(
            top: topClearance,
            bottom: bottomClearance,
          ),
          child: body,
        ),
      ),
      if (showTopNav && topNav != null)
        Positioned(left: 0, right: 0, top: 0, child: topNav!),
      if (showDock && dock != null)
        Positioned(left: 0, right: 0, bottom: 0, child: dock!),
    ],
  ),
);

return Scaffold(
  resizeToAvoidBottomInset: resizeToAvoidBottomInset,
  backgroundColor: context.themeV2.background,
  body: composition,
);
```

Add `topNavExtent` to the constructor and `withShellChrome`. Production pages created by `_pages()` pass `ThemeV2GlobalTopNav.floatingExtent`; injected test pages keep the 56-point default. Remove the Dither imports and `ditherActive` field because the shell no longer owns a shader.

- [ ] **Step 5: Run shell and navigation tests**

Run: `cd mobile && flutter test test/theme_v2/shell/theme_v2_page_scaffold_test.dart test/theme_v2/shell/theme_v2_navigation_state_test.dart test/theme_v2/shell/theme_v2_shell_test.dart test/theme_v2/shell/theme_v2_app_shell_capture_test.dart`

Expected: PASS; root probe States retain identity and the shell has no Dither shader.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/shell/theme_v2_page_scaffold.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/test/theme_v2/shell/theme_v2_page_scaffold_test.dart mobile/test/theme_v2/shell/theme_v2_navigation_state_test.dart
git commit -m "fix: keep theme v2 root pages mounted"
```

### Task 2: Refresh Library only for real mutations

**Files:**
- Modify: `mobile/lib/data_revision.dart`
- Modify: `mobile/lib/app_shell.dart`
- Modify: `mobile/lib/theme_v2/shell/theme_v2_app_shell.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Create: `mobile/test/data_revision_test.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`

**Interfaces:**
- Produces: `dataMutationRevision: ValueNotifier<int>`.
- Preserves: `dataRevision` as the legacy aggregate refresh signal.
- Produces: `requestDataRefresh()` for navigation/resume refreshes that must not invalidate Theme V2 Library.
- Preserves: `bumpData()` as the API for confirmed mutations; it increments both revisions.

- [ ] **Step 1: Write failing revision-separation tests**

```dart
test('navigation refresh does not publish a mutation revision', () {
  final dataBefore = dataRevision.value;
  final mutationBefore = dataMutationRevision.value;

  requestDataRefresh();

  expect(dataRevision.value, dataBefore + 1);
  expect(dataMutationRevision.value, mutationBefore);
});

test('confirmed mutation publishes both revisions', () {
  final dataBefore = dataRevision.value;
  final mutationBefore = dataMutationRevision.value;

  bumpData();

  expect(dataRevision.value, dataBefore + 1);
  expect(dataMutationRevision.value, mutationBefore + 1);
});
```

- [ ] **Step 2: Write failing Library tests for route pop and mutation behavior**

```dart
testWidgets('navigation-only refresh does not reload a populated library', (
  tester,
) async {
  final repository = _CountingRepository(_overview());
  await tester.pumpWidget(_libraryHost(repository: repository));
  await tester.pumpAndSettle();
  expect(repository.loadCount, 1);

  requestDataRefresh();
  await tester.pump();
  expect(repository.loadCount, 1);

  bumpData();
  await tester.pump();
  expect(repository.loadCount, 2);
  expect(find.byType(LibraryHub), findsOneWidget);
});
```

Add this asset-container assertion in `asset_list_page_test.dart` using its existing mock HTTP client:

```dart
final beforeMutation = requestCount;
requestDataRefresh();
await tester.pump();
expect(requestCount, beforeMutation);

bumpData();
await tester.pump();
expect(requestCount, beforeMutation + 1);
expect(find.text('已有资产'), findsOneWidget);
```

- [ ] **Step 3: Run focused tests and confirm missing API / wrong reload failures**

Run: `cd mobile && flutter test test/data_revision_test.dart test/theme_v2/library/library_navigation_test.dart test/theme_v2/library/asset/asset_list_page_test.dart`

Expected: FAIL because `dataMutationRevision` and `requestDataRefresh` do not exist and Library listens to every `dataRevision` change.

- [ ] **Step 4: Implement separate revisions and switch Library listeners**

```dart
final dataRevision = ValueNotifier<int>(0);
final dataMutationRevision = ValueNotifier<int>(0);

void requestDataRefresh() => dataRevision.value++;

void bumpData() {
  dataRevision.value++;
  dataMutationRevision.value++;
}
```

Change `DataRefreshObserver.didPop` and both App-shell lifecycle `resumed` handlers to call `requestDataRefresh()`. Change `ThemeV2LibraryPage` and `ThemeV2AssetListPage` to add/remove listeners on `dataMutationRevision`. Keep their existing stale-while-revalidate rendering so cached overview/records remain mounted during the request.

- [ ] **Step 5: Run refresh, controller, and route tests**

Run: `cd mobile && flutter test test/data_revision_test.dart test/theme_v2/library/library_controller_test.dart test/theme_v2/library/asset/asset_container_controller_test.dart test/theme_v2/library/library_navigation_test.dart test/theme_v2/library/asset/asset_list_page_test.dart`

Expected: PASS; navigation-only refreshes make zero Library requests, confirmed mutations make one request, and visible content stays mounted.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/data_revision.dart mobile/lib/app_shell.dart mobile/lib/theme_v2/shell/theme_v2_app_shell.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/test/data_revision_test.dart mobile/test/theme_v2/library/library_navigation_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart
git commit -m "fix: refresh library only after data mutations"
```

### Task 3: Keep and strengthen empty Today container watermarks

**Files:**
- Modify: `mobile/lib/theme_v2/home/today_region_watermark.dart`
- Modify: `mobile/test/theme_v2/home/today_dither_material_test.dart`
- Modify: `mobile/test/theme_v2/home/today_signal_band_test.dart`
- Modify: `mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart`
- Modify: `mobile/test/theme_v2/home/today_living_surface_test.dart`

**Interfaces:**
- Preserves: `TodayRegionWatermark(count:, label:, alignment:, onPressed:)`.
- Changes: zero is a valid visible count; only negative counts are normalized to zero.
- Visual contract: label font size is at least 14, label alpha is at least `.56` in light mode and `.72` in dark mode, and the count remains visually behind foreground content.

- [ ] **Step 1: Replace the collapsing-zero test with visible/clickable empty-container tests**

```dart
testWidgets('zero-count region watermark remains visible and clickable', (
  tester,
) async {
  var taps = 0;
  await tester.pumpWidget(
    _host(
      TodayRegionWatermark(
        count: 0,
        label: 'Reka 发现',
        alignment: Alignment.bottomLeft,
        onPressed: () => taps++,
        semanticLabel: '查看全部 Reka 发现',
      ),
    ),
  );

  expect(find.text('0'), findsOneWidget);
  expect(find.text('Reka 发现'), findsOneWidget);
  await tester.tap(find.text('Reka 发现'));
  expect(taps, 1);
});
```

In `today_signal_band_test.dart` and `theme_v2_asset_bubble_field_test.dart`, render empty input and expect `Reka 发现`, `Reka 生成`, both zero counts, and their semantic actions.

- [ ] **Step 2: Add failing contrast and hierarchy assertions**

```dart
final label = tester.widget<Text>(find.text('Reka 生成'));
expect(label.style?.fontSize, greaterThanOrEqualTo(14));
expect(label.style?.fontWeight, FontWeight.w700);
expect(label.style?.color?.a, greaterThanOrEqualTo(.56));
```

Repeat in dark mode with a `.72` alpha floor, and assert the two `ThemeV2DitherField` instances still exist in `TodayLivingSurface` while no third/global field appears.

- [ ] **Step 3: Run the home tests and confirm zero-count / contrast failures**

Run: `cd mobile && flutter test test/theme_v2/home/today_dither_material_test.dart test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/today_living_surface_test.dart`

Expected: FAIL because `TodayRegionWatermark` returns `SizedBox.shrink()` for zero and the label is 12 points with lower light-mode alpha.

- [ ] **Step 4: Implement the persistent watermark hierarchy**

Remove the `count <= 0` early return, render `${count.clamp(0, 999)}`, and update the styles:

```dart
final countStyle = TextStyle(
  color: tokens.accent.withValues(alpha: dark ? .18 : .10),
  fontFamily: 'Geist',
  fontSize: 96,
  fontWeight: FontWeight.w700,
  letterSpacing: -6,
  height: .9,
);
final labelStyle = TextStyle(
  color: tokens.accent.withValues(alpha: dark ? .76 : .60),
  fontFamily: 'Geist Mono',
  fontSize: 14,
  fontWeight: FontWeight.w700,
  letterSpacing: .8,
  height: 1.15,
);
```

Do not add empty copy, borders, or a Dither field outside `TodaySignalBand` and `ThemeV2AssetBubbleField`.

- [ ] **Step 5: Run all Today container tests**

Run: `cd mobile && flutter test test/theme_v2/home/today_dither_material_test.dart test/theme_v2/home/today_signal_band_test.dart test/theme_v2/home/theme_v2_asset_bubble_field_test.dart test/theme_v2/home/today_living_surface_test.dart test/theme_v2/home/today_dot_experiment_page_test.dart`

Expected: PASS with exactly two local Dither fields and visible zero-count watermarks.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/home/today_region_watermark.dart mobile/test/theme_v2/home/today_dither_material_test.dart mobile/test/theme_v2/home/today_signal_band_test.dart mobile/test/theme_v2/home/theme_v2_asset_bubble_field_test.dart mobile/test/theme_v2/home/today_living_surface_test.dart
git commit -m "feat: keep today container watermarks visible"
```

### Task 4: Merge card-display state into custom-Skill management

**Files:**
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart`
- Modify: `mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart`

**Interfaces:**
- Extends: `SkillManagementController.cardSelection: CardFieldSelectionController?`.
- Extends: `SkillManagementController.preview: AssetCardViewData?`, derived from the current draft.
- Guarantees: `SkillManagementDraft.renderSpec` contains `cardSelection.config.applyToRenderSpec(current.renderSpec)`.

- [ ] **Step 1: Write a failing controller test for unified field and card saving**

```dart
test('management saves field edits and card display in one draft', () async {
  final repository = _Repository(skill: tennisSkill);
  final controller = SkillManagementController(
    repository: repository,
    userSkillId: 'skill-tennis',
  );
  addTearDown(controller.dispose);
  await controller.load();

  controller.addField(key: 'location', label: '地点', type: 'string');
  controller.cardSelection!.selectPrimary('location');
  expect(await controller.save(), isTrue);

  expect(
    repository.saved!.schema['properties'],
    contains('location'),
  );
  expect(
    repository.saved!.renderSpec['primary_field'],
    'location',
  );
});
```

Also assert that changing field visibility/order rebuilds selectable card fields without leaking listeners and that a failed save leaves both edits in memory.

- [ ] **Step 2: Run the controller test and confirm the missing-selection failure**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_management_controller_test.dart`

Expected: FAIL because `SkillManagementController` has no `cardSelection` and currently resends the unmodified render spec.

- [ ] **Step 3: Implement owned card-selection state**

Build selection from visible, non-UUID management fields during `_applySkill` and after field structure changes:

```dart
CardFieldSelectionController? _cardSelection;
CardFieldSelectionController? get cardSelection => _cardSelection;

void _replaceCardSelection(ConfigurableSkill skill) {
  final fields = [
    for (final field in _fields)
      if (!field.hidden && field.type != 'uuid')
        CardSelectableField(
          id: field.key,
          label: field.label,
          type: field.type,
        ),
  ];
  final previous = _cardSelection?.config;
  final oldSelection = _cardSelection;
  if (oldSelection != null) {
    oldSelection.removeListener(_selectionChanged);
    oldSelection.dispose();
  }
  CardDisplayConfig initialConfig;
  try {
    initialConfig = previous ??
        CardDisplayConfig.fromRenderSpec(skill.renderSpec);
  } on FormatException {
    initialConfig = CardDisplayConfig(primaryFieldId: fields.first.id);
  }
  _cardSelection = CardFieldSelectionController(
    fields: fields,
    config: initialConfig,
  )..addListener(_selectionChanged);
}
```

Expose a real draft preview from the same schema and render spec that will be saved:

```dart
AssetCardViewData? get preview {
  final current = _skill;
  final selection = _cardSelection;
  if (current == null || selection == null) return null;
  final schema = {
    for (final field in _fields)
      field.key: {
        ...field.metadata,
        'type': field.type,
        'label': field.label,
        if (field.meaning.isNotEmpty) 'description': field.meaning,
        if (field.hidden) 'x-hidden': true,
      },
  };
  final spec = RenderSpec.fromJson(
    selection.config.applyToRenderSpec(current.renderSpec),
  ).withSchema(schema);
  return AssetCardViewData.fromPayload(
    payload: current.samplePayload,
    display: selection.config,
    spec: spec,
    skillLabel: _displayName,
  );
}
```

In `save()`, serialize `cardSelection.config.applyToRenderSpec(current.renderSpec)`. Dispose the selection and listener in `dispose()`.

- [ ] **Step 4: Run management and existing configuration controller tests**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_management_controller_test.dart test/theme_v2/library/create_skill/skill_configuration_repository_test.dart`

Expected: PASS; custom management owns card selection while the built-in configuration controller remains unchanged.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart
git commit -m "feat: manage custom skill card display with fields"
```

### Task 5: Expose one custom-Skill entry and remove the configuration stepper

**Files:**
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_management_sheet.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Modify: `mobile/test/theme_v2/library/library_navigation_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`
- Modify: `mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart`
- Modify: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

**Interfaces:**
- Consumes: `SkillManagementController.cardSelection` from Task 4.
- Guarantees: custom list header has one `custom-skill-edit` action and no `Card Display Settings` action.
- Guarantees: built-in list header has `Card Display Settings` and no custom management action.

- [ ] **Step 1: Write failing one-entry tests**

```dart
testWidgets('custom container exposes one unified management entry', (
  tester,
) async {
  await tester.pumpWidget(_customAssetListHarness());
  expect(find.byKey(const ValueKey('custom-skill-edit')), findsOneWidget);
  expect(find.bySemanticsLabel('Card Display Settings'), findsNothing);
});

testWidgets('built-in container keeps only card display settings', (
  tester,
) async {
  await tester.pumpWidget(_builtInAssetListHarness());
  expect(find.bySemanticsLabel('Card Display Settings'), findsOneWidget);
  expect(find.byKey(const ValueKey('custom-skill-edit')), findsNothing);
});
```

- [ ] **Step 2: Write failing unified-sheet and no-stepper tests**

```dart
testWidgets('custom management contains fields card display and deletion', (
  tester,
) async {
  await tester.pumpWidget(_managementHarness());
  await tester.pumpAndSettle();
  expect(find.text('基本信息'), findsOneWidget);
  expect(find.text('记录字段'), findsOneWidget);
  expect(find.text('卡片展示'), findsOneWidget);
  expect(find.byType(CardFieldSelector), findsOneWidget);
  expect(find.byKey(const ValueKey('custom-skill-delete')), findsOneWidget);
});

testWidgets('existing skill card configuration omits creation progress', (
  tester,
) async {
  await tester.pumpWidget(_configurationHarness());
  await tester.pumpAndSettle();
  expect(find.text('Describe'), findsNothing);
  expect(find.text('Fields'), findsNothing);
  expect(find.text('Card'), findsNothing);
  expect(find.byKey(const ValueKey('skill-card-step')), findsOneWidget);
});
```

- [ ] **Step 3: Run focused widget tests and confirm duplicate-entry / stepper failures**

Run: `cd mobile && flutter test test/theme_v2/library/library_navigation_test.dart test/theme_v2/library/asset/asset_list_page_test.dart test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart test/theme_v2/library/create_skill/skill_management_controller_test.dart`

Expected: FAIL because custom containers receive both callbacks, management has no card selector, and configuration mode always renders `_WizardProgress`.

- [ ] **Step 4: Route custom and built-in containers to the correct single entry**

In `_assetContainerSurface`, use:

```dart
final custom = container.type == LibraryContainerType.custom;
final configureCard = custom ? null : _displayConfigurationFor(container);
final manageSkill = custom ? _managementFor(container) : null;
return ThemeV2AssetListPage.assets(
  meta: SkillMeta(
    container.mark,
    container.label,
    'gray',
    container.userSkillId,
  ),
  skillName: container.id,
  initialAssets: const [],
  specs: ref.read(renderSpecsProvider).valueOrNull ?? const {},
  api: _detailApi,
  coreRecordsOnly: true,
  onBack: _navigation.back,
  contentBottomPadding: ThemeV2Spacing.lg,
  onConfigureCard: configureCard,
  onManageSkill: manageSkill,
);
```

Apply the same rule to event/contact/todo/notes based on whether the container is built-in. Keep the existing callback contracts so built-in card configuration does not depend on the custom management controller.

- [ ] **Step 5: Add card display to the management sheet and hide configuration progress**

Under `记录字段`, render a `卡片展示` section with the current preview and selector:

```dart
if (controller.cardSelection case final selection?) ...[
  const SizedBox(height: 24),
  Text('卡片展示', style: sectionTitleStyle),
  const SizedBox(height: 8),
  ThemeV2AssetCard(
    variant: AssetCardVariant.richCard,
    data: controller.preview!,
    height: 98,
  ),
  const SizedBox(height: 16),
  CardFieldSelector(controller: selection),
],
```

In `ThemeV2SkillWizardSheet.build`, render `_WizardProgress(stage: stage)` and its spacing only when `!widget.isConfiguration`. Do not change the creation path.

- [ ] **Step 6: Run the complete Skill/Library test slice**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill test/theme_v2/library/asset/asset_list_page_test.dart test/theme_v2/library/library_navigation_test.dart`

Expected: PASS; custom has one entry and one save flow, built-in configuration remains available, and only creation shows the stepper.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/lib/theme_v2/library/create_skill/skill_management_sheet.dart mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart mobile/test/theme_v2/library/library_navigation_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart
git commit -m "feat: unify custom skill management entry"
```

### Task 6: Match report candidates to the requested Skill and preserve vague time

**Files:**
- Modify: `theme_v2_service/app/domains/reports/scope_adapters.py`
- Modify: `theme_v2_service/tests/integration/test_report_scope_adapters.py`
- Modify: `theme_v2_service/tests/unit/test_report_schemas.py`
- Modify: `mobile/test/theme_v2/report/report_run_page_test.dart`

**Interfaces:**
- Extends internal `ScopeRecordGroup.match_terms: list[str]` with `Field(default_factory=list, exclude=True)`.
- Preserves: `resolve_report_period("最近…") -> None` when no explicit day count is present.
- Guarantees: a successful explicit type match narrows candidates; no match retains all aggregatable candidates for manual confirmation.

- [ ] **Step 1: Add a failing integration fixture with running, expense, water, and dance**

```python
async def test_vague_recent_running_matches_only_running_and_requires_time(session):
    skills = [
        UserSkill(
            id=skill_id,
            user_id="user-1",
            machine_name=machine_name,
            display_name=display_name,
            description=description,
            schema_json={
                "type": "object",
                "properties": {"value": {"type": "number"}},
            },
        )
        for skill_id, machine_name, display_name, description in [
            ("skill-running", "running_log", "跑步记录", "记录跑步距离"),
            ("skill-expense", "expense", "消费", "记录支出金额"),
            ("skill-water", "water_log", "喝水记录", "记录饮水量"),
            ("skill-dance", "dance_log", "跳舞记录", "记录舞蹈时长"),
        ]
    ]
    session.add_all(skills)
    await session.flush()
    session.add_all([
        Asset(
            id=f"asset-{index}",
            user_id="user-1",
            user_skill_id=skill.id,
            payload_json={"value": index + 1},
            effective_at=datetime(2026, 8, 10 + index, 1, 0),
        )
        for index, skill in enumerate(skills)
    ])
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结最近的跑步情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.machine_name for group in response.record_groups] == [
        "running_log"
    ]
    assert response.default_scope.skill_ids == ["skill-running"]
    assert response.default_scope.time_range is None
    assert response.default_scope.missing_dimensions == ["time_range"]
    assert response.default_scope.supporting_references == []
    assert response.default_scope.selection.auto_references == []
```

- [ ] **Step 2: Add an explicit-period companion test**

```python
async def _seed_running_and_unrelated_records(session):
    running = UserSkill(
        id="skill-running",
        user_id="user-1",
        machine_name="running_log",
        display_name="跑步记录",
        description="记录跑步距离",
        schema_json={
            "type": "object",
            "properties": {"distance_km": {"type": "number"}},
        },
    )
    expense = UserSkill(
        id="skill-expense",
        user_id="user-1",
        machine_name="expense",
        display_name="消费",
        description="记录支出金额",
        schema_json={
            "type": "object",
            "properties": {"amount": {"type": "number"}},
        },
    )
    session.add_all([running, expense])
    await session.flush()
    session.add_all([
        Asset(
            id="run-1",
            user_id="user-1",
            user_skill_id=running.id,
            payload_json={"distance_km": 5},
            effective_at=datetime(2026, 8, 10, 1, 0),
        ),
        Asset(
            id="run-2",
            user_id="user-1",
            user_skill_id=running.id,
            payload_json={"distance_km": 8},
            effective_at=datetime(2026, 8, 11, 1, 0),
        ),
        Asset(
            id="expense-1",
            user_id="user-1",
            user_skill_id=expense.id,
            payload_json={"amount": 88},
            effective_at=datetime(2026, 8, 11, 2, 0),
        ),
    ])
    await session.commit()

async def test_explicit_30_day_running_selects_only_matching_running_assets(session):
    await _seed_running_and_unrelated_records(session)
    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="总结过去 30 天的跑步情况",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    assert response.default_scope.time_range is not None
    assert {
        reference.id
        for reference in response.default_scope.supporting_references
    } == {"run-1", "run-2"}
```

- [ ] **Step 3: Run the report adapter tests and confirm the broad-selection failure**

Run: `cd theme_v2_service && pytest tests/integration/test_report_scope_adapters.py tests/unit/test_report_schemas.py -q`

Expected: the vague-running test fails with all four record groups because the current alias map only recognizes `expense`; existing vague-time unit tests continue to pass.

- [ ] **Step 4: Implement deterministic Skill-term matching**

Populate matching text from `machine_name`, `display_name`, `description`, and `domain`, normalize case/separators, and discard generic tokens:

```python
class ScopeRecordGroup(StrictModel):
    skill_id: str
    machine_name: str = Field(default="", exclude=True)
    match_terms: list[str] = Field(default_factory=list, exclude=True)
    label: str
    count: int
    default_selected: bool = True
    records: list[ScopeRecordCandidate] = Field(default_factory=list)

_GENERIC_SKILL_TERMS = {"记录", "日志", "数据", "情况", "总结", "统计"}
_SKILL_ALIASES = {
    "expense": {"消费", "支出", "花费", "账单", "expense", "spend"},
    "running": {"跑步", "晨跑", "夜跑", "running", "run"},
    "water": {"喝水", "饮水", "water", "hydration"},
    "dance": {"跳舞", "舞蹈", "dance"},
}

def _normalize_term(value: str | None) -> str:
    return re.sub(r"[\s_\-/]+", "", (value or "").casefold())

def _skill_match_terms(skill: UserSkill) -> list[str]:
    display = _normalize_term(skill.display_name)
    bases = {display}
    for suffix in ("记录", "日志", "数据", "训练"):
        if display.endswith(suffix) and len(display) > len(suffix):
            bases.add(display[: -len(suffix)])
    machine = _normalize_term(skill.machine_name)
    description = _normalize_term(skill.description)
    domain = _normalize_term(skill.domain)
    terms = {machine, description, domain, *bases}
    searchable = "".join(terms)
    for aliases in _SKILL_ALIASES.values():
        normalized_aliases = {_normalize_term(alias) for alias in aliases}
        if any(alias in searchable for alias in normalized_aliases):
            terms.update(normalized_aliases)
    return sorted(
        term for term in terms
        if term and term not in _GENERIC_SKILL_TERMS
    )

def _filter_record_groups_for_intent(
    groups: list[ScopeRecordGroup],
    intent: str,
) -> list[ScopeRecordGroup]:
    normalized_intent = _normalize_term(intent)
    matches = [
        group
        for group in groups
        if any(
            term not in _GENERIC_SKILL_TERMS and term in normalized_intent
            for term in group.match_terms
        )
    ]
    return matches or groups
```

When `_period_records` first creates a group, assign `match_terms=_skill_match_terms(skill)`. A domain remains one complete term, so a broad health domain matches only when the user explicitly names that domain. Keep the existing 30-day candidate preview only for query purposes; when `draft.time_range is None`, keep `auto_references` and `supporting_references` empty.

- [ ] **Step 5: Add/adjust the Flutter confirmation-page assertion**

```dart
testWidgets('vague running scope requires time before selecting records', (
  tester,
) async {
  await tester.pumpWidget(_reportHarness(vagueRunningFixture));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('report-time-range-last_7_days')),
    findsOneWidget,
  );
  expect(find.text('选择时间后，Reka 会筛出对应资产'), findsOneWidget);

  await tester.tap(
    find.byKey(const ValueKey('report-time-range-last_7_days')),
  );
  await tester.pumpAndSettle();
  expect(find.text('跑步记录'), findsOneWidget);
  expect(find.text('消费'), findsNothing);
  expect(find.text('喝水记录'), findsNothing);
  expect(find.text('跳舞记录'), findsNothing);
});
```

- [ ] **Step 6: Run backend and Flutter report tests**

Run: `cd theme_v2_service && pytest tests/integration/test_report_scope_adapters.py tests/unit/test_report_schemas.py tests/contract/test_report_run_api.py -q`

Run: `cd mobile && flutter test test/theme_v2/report/report_run_controller_test.dart test/theme_v2/report/report_run_page_test.dart`

Expected: PASS; vague running has one Skill and no selected records until time confirmation, while explicit 30 days selects all matching running records.

- [ ] **Step 7: Commit**

```bash
git add theme_v2_service/app/domains/reports/scope_adapters.py theme_v2_service/tests/integration/test_report_scope_adapters.py theme_v2_service/tests/unit/test_report_schemas.py mobile/test/theme_v2/report/report_run_page_test.dart
git commit -m "fix: scope reports to requested skill type"
```

### Task 7: Full verification and correct device build

**Files:**
- No planned source changes; this task validates and installs the commits from Tasks 1–6.

**Interfaces:**
- Consumes all prior task behavior.
- Produces a Debug APK built with the Theme V2 Today experiment enabled.

- [ ] **Step 1: Run the complete affected Flutter test slice**

Run:

```bash
cd mobile && flutter test \
  test/data_revision_test.dart \
  test/theme_v2/shell \
  test/theme_v2/home \
  test/theme_v2/library \
  test/theme_v2/report
```

Expected: PASS with no exceptions, overflows, pending timers, or golden changes outside the intended pure-background/watermark surfaces.

- [ ] **Step 2: Run backend report tests**

Run:

```bash
cd theme_v2_service && pytest \
  tests/unit/test_report_schemas.py \
  tests/integration/test_report_scope_adapters.py \
  tests/contract/test_report_run_api.py \
  tests/integration/test_report_planner.py -q
```

Expected: PASS.

- [ ] **Step 3: Analyze every changed Dart file**

Run: `cd mobile && flutter analyze $(git diff --name-only main...HEAD -- 'mobile/lib/**/*.dart' 'mobile/test/**/*.dart' | sed 's#^mobile/##')`

Expected: `No issues found!`

- [ ] **Step 4: Build the correct APK**

Run:

```bash
cd mobile && flutter build apk --debug \
  --dart-define=THEME_V2=true \
  --dart-define=TODAY_DOT_EXPERIMENT=true
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced successfully.

- [ ] **Step 5: Install and verify on the connected device**

Run: `cd mobile && flutter install -d RFCY71B21YK --use-application-binary build/app/outputs/flutter-apk/app-debug.apk`

Verify manually:

1. Switch Today → Calendar → Library → Today five times; Reka never shows the flat fallback.
2. Library content and scroll position remain visible; switching Tabs and returning from an unmodified detail page makes no request-visible refresh and no white screen.
3. Calendar, Library, top Nav, and Dock use pure backgrounds; Today contains exactly two visible dither containers.
4. Empty Today shows clickable `Reka 发现 0` and `Reka 生成 0` watermarks with the stronger hierarchy.
5. A custom Skill exposes one management entry containing fields, card display, and deletion; a built-in Skill exposes only card display; existing-Skill configuration has no stepper.
6. “总结最近的跑步情况” shows only running, then asks for a time range before selecting Assets.

- [ ] **Step 6: Commit any verification-only test corrections, then confirm a clean worktree**

```bash
git status --short
```

Expected: no uncommitted files. If no correction was needed, do not create an empty commit.
