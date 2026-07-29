# Theme V2 Assets + Skill Builder Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Theme V2 asset containers, details, editors, Skill Builder, and Card Display Settings as one compatible system while removing the Asset Detail goal action.

**Architecture:** Normalize every record into an `AssetRecordViewModel`, keep container/detail state in dedicated controllers, and render all list/editor/builder previews through shared Theme V2 card primitives. Skill creation and existing-skill configuration share `CardFieldSelectionController`, while `CardDisplayConfig` remains the only render-spec serializer.

**Tech Stack:** Flutter, Dart, Riverpod, existing `ApiClient`, Flutter unit/widget/golden tests, Android debug build and ADB device verification.

## Global Constraints

- Visual source of truth is `spec/design/redesignureka.pen`, Library/Assets section `WLBLn`.
- Behavioral source of truth is `spec/design/theme-v2-library-assets-handoff.md`.
- The four system containers are exactly Todo, Notes, Events, and Contacts.
- Asset detail always enters as a bottom sheet and can expand in place to a full page without refetching.
- `CardDisplayConfig` has exactly one primary field and at most three ordered secondary fields.
- Skill Builder has exactly three visible steps: Describe, Fields, Card.
- Existing-skill configuration edits presentation only and opens directly at Card.
- System preset records keep their dedicated edit pages.
- “设为目标” is removed from Asset Detail and from its public callback/result plumbing.
- Preserve unrelated render-spec and payload keys.
- Do not migrate backend data and do not change the production default of `THEME_V2`.
- Every behavior change follows red-green-refactor and lands in a focused commit.

---

## File Structure

### Shared asset presentation

- Create `mobile/lib/theme_v2/library/asset/asset_record.dart`: normalized record kind, source, fields, card projection, adapters, Todo classification.
- Create `mobile/lib/theme_v2/library/asset/asset_container_controller.dart`: filter-specific pages, counts, scroll offsets, refresh, pagination, Todo optimistic state.
- Create `mobile/lib/theme_v2/library/asset/asset_detail_content.dart`: domain-aware detail bodies and source/action footer inputs.
- Create `mobile/lib/theme_v2/library/asset/asset_long_text.dart`: overflow-aware half/full selectable text region.
- Create `mobile/lib/theme_v2/library/asset/asset_editors.dart`: Todo, Notes, Event, Contact, and custom editor routing and shared preview shell.
- Modify `mobile/lib/theme_v2/library/asset/asset_list_page.dart`: render controllers, tabs, groups, shared cards, and preserved page chrome.
- Modify `mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart`: expose normalized record state and operation errors.
- Modify `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`: exact half/full geometry and sticky chrome.
- Modify `mobile/lib/theme_v2/library/asset/asset_detail_page.dart`: full-state host.
- Modify `mobile/lib/theme_v2/library/asset/asset_editor.dart`: schema draft validation and preview projection.
- Delete `mobile/lib/theme_v2/library/asset/set_goal_action.dart`.

### Shared card configuration

- Create `mobile/lib/theme_v2/asset/card_field_selection.dart`: reusable reducer and selector widget.
- Modify `mobile/lib/theme_v2/asset/asset_card_display.dart`: safe construction helpers and compatible serialization used by the reducer.
- Modify `mobile/lib/theme_v2/asset/asset_card.dart`: preview/list keys and content handling required by Asset and Builder screens.

### Skill Builder and existing-skill configuration

- Rewrite `mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart`: exact three-step controller, editable field drafts, shared card selection.
- Rewrite `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`: Pen-aligned Steps 1–3 and configuration mode.
- Create `mobile/lib/theme_v2/library/create_skill/skill_configuration_repository.dart`: load/save existing-skill presentation.
- Modify `mobile/lib/theme_v2/library/create_skill_action.dart`: route creation and configuration to the shared wizard.
- Modify `mobile/lib/theme_v2/library/theme_v2_library_page.dart`: open configuration from custom containers and remove goal plumbing.

### Tests

- Create `mobile/test/theme_v2/library/asset/asset_record_test.dart`.
- Create `mobile/test/theme_v2/library/asset/asset_container_controller_test.dart`.
- Create `mobile/test/theme_v2/library/asset/asset_long_text_test.dart`.
- Create `mobile/test/theme_v2/asset/card_field_selection_test.dart`.
- Create `mobile/test/theme_v2/library/create_skill/skill_configuration_repository_test.dart`.
- Modify existing Asset, Skill Builder, component, navigation, and golden tests under `mobile/test/theme_v2/`.

---

### Task 1: Normalize Asset Records and Todo Ordering

**Files:**
- Create: `mobile/lib/theme_v2/library/asset/asset_record.dart`
- Create: `mobile/test/theme_v2/library/asset/asset_record_test.dart`

**Interfaces:**
- Consumes: existing `AssetItem`, Event/Contact response maps, `RenderSpec`, `CardDisplayConfig`, and `AssetCardViewData`.
- Produces: `AssetRecordKind`, `AssetRecordField`, `AssetSource`, `AssetRecordViewModel`, `AssetRecordAdapter`, `TodoAssetFilter`, and `sortTodoRecords`.

- [ ] **Step 1: Write failing adapter and ordering tests**

```dart
test('todo without due date sorts after scheduled todo', () {
  final records = [
    record(id: 'open', dueAt: null),
    record(id: 'late', dueAt: DateTime(2026, 7, 29, 9)),
  ];
  expect(sortTodoRecords(records).map((item) => item.id), ['late', 'open']);
});

test('custom adapter derives card through CardDisplayConfig', () {
  final result = AssetRecordAdapter.custom(
    asset: asset(payload: {'title': 'Trip', 'city': 'Osaka'}),
    skillLabel: 'Travel',
    renderSpec: {'primary_field': 'title', 'secondary_field': 'city'},
    schema: schema,
  );
  expect(result.card.primaryValue, 'Trip');
  expect(result.card.secondaryValues, ['Osaka']);
});
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_record_test.dart`

Expected: FAIL because `asset_record.dart` and its types do not exist.

- [ ] **Step 3: Implement immutable record models and adapters**

```dart
enum AssetRecordKind { todo, note, event, contact, custom }
enum TodoAssetFilter { all, today, completed, unscheduled }

@immutable
class AssetRecordViewModel {
  const AssetRecordViewModel({
    required this.id,
    required this.containerId,
    required this.kind,
    required this.card,
    required this.fields,
    required this.payload,
    required this.createdAt,
    this.source,
    this.dueAt,
    this.completed = false,
    this.userSkillId,
    this.sessionId,
  });

  final String id;
  final String containerId;
  final AssetRecordKind kind;
  final AssetCardViewData card;
  final List<AssetRecordField> fields;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final AssetSource? source;
  final DateTime? dueAt;
  final bool completed;
  final String? userSkillId;
  final String? sessionId;

  AssetRecordViewModel copyWith({bool? completed});
}
```

Implement typed `todo`, `note`, `event`, `contact`, and `custom` factories. Parse due date/time once, classify records through `matchesTodoFilter`, and sort scheduled records chronologically before unscheduled records.

- [ ] **Step 4: Run focused tests**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_record_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_record.dart mobile/test/theme_v2/library/asset/asset_record_test.dart
git commit -m "feat(assets): normalize library records"
```

### Task 2: Build Filter-Preserving Container State

**Files:**
- Create: `mobile/lib/theme_v2/library/asset/asset_container_controller.dart`
- Create: `mobile/test/theme_v2/library/asset/asset_container_controller_test.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`

**Interfaces:**
- Consumes: `AssetRecordViewModel`, `TodoAssetFilter`, existing typed API loaders.
- Produces: `AssetContainerRepository`, `AssetContainerSnapshot`, and `AssetContainerController`.

- [ ] **Step 1: Write failing state tests**

```dart
test('each todo filter preserves its own offset and records', () async {
  final controller = AssetContainerController(repository: fake, container: todo);
  await controller.load();
  controller.rememberOffset(120);
  await controller.selectTodoFilter(TodoAssetFilter.today);
  controller.rememberOffset(48);
  await controller.selectTodoFilter(TodoAssetFilter.all);
  expect(controller.current.scrollOffset, 120);
});

test('failed optimistic completion restores prior record', () async {
  fake.completeError = StateError('offline');
  await expectLater(controller.toggleTodo('a'), throwsStateError);
  expect(controller.record('a').completed, isFalse);
});
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_container_controller_test.dart`

Expected: FAIL because the controller does not exist.

- [ ] **Step 3: Implement the controller**

```dart
class AssetContainerController extends ChangeNotifier {
  final AssetContainerRepository repository;
  final LibraryContainerSummary container;
  final Map<TodoAssetFilter, AssetContainerSnapshot> _todoSnapshots = {};

  Future<void> load({bool refresh = false});
  Future<void> loadMore();
  Future<void> selectTodoFilter(TodoAssetFilter filter);
  void rememberOffset(double value);
  Future<void> toggleTodo(String id);
}
```

Keep visible records during refresh, preserve loaded records during pagination errors, store one offset per Todo filter, and roll back only the mutated Todo record when completion fails.

- [ ] **Step 4: Replace list-local loading with the controller**

Render:

- four count-bearing Todo pill tabs;
- shared rows from normalized card data;
- unscheduled records after scheduled rows;
- domain empty states;
- retryable initial/pagination errors;
- persistent top navigation and dock.

- [ ] **Step 5: Run controller and list tests**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_container_controller_test.dart test/theme_v2/library/asset/asset_list_page_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_container_controller.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/test/theme_v2/library/asset/asset_container_controller_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart
git commit -m "feat(assets): rebuild container lists"
```

### Task 3: Remove Asset Goal Plumbing

**Files:**
- Delete: `mobile/lib/theme_v2/library/asset/set_goal_action.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`

**Interfaces:**
- Produces: `Future<void> showThemeV2AssetDetail(...)` with no goal callback or route result.

- [ ] **Step 1: Change tests to compile against the goal-free API**

```dart
await showThemeV2AssetDetail(
  context,
  data: data,
  payload: payload,
  cardType: 'todo',
  assetId: 'a1',
  userSkillId: 'todo',
  spec: spec,
);
expect(find.text('设为目标'), findsNothing);
```

Remove test fixtures that pass `onSetGoal` or assert `SetGoalIntent`.

- [ ] **Step 2: Run the focused tests and verify compile failure**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_detail_test.dart test/theme_v2/library/asset/asset_list_page_test.dart`

Expected: FAIL while production constructors still require or expose goal plumbing.

- [ ] **Step 3: Remove the complete dependency chain**

```dart
Future<void> showThemeV2AssetDetail(
  BuildContext context, {
  required CardData data,
  required Map<String, dynamic> payload,
  required String cardType,
  required String? assetId,
  required String? userSkillId,
  required RenderSpec? spec,
  String? sessionId,
}) async {
  await showModalBottomSheet<void>(/* existing route */);
}
```

Delete `SetGoalIntent`, the action widget, list/page callbacks, result propagation, and all imports.

- [ ] **Step 4: Verify no production references remain**

Run: `rg -n "SetGoalIntent|onSetGoal|设为目标|set_goal_action" mobile/lib/theme_v2/library`

Expected: no matches.

- [ ] **Step 5: Run focused tests**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_detail_test.dart test/theme_v2/library/asset/asset_list_page_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/test/theme_v2/library/asset/asset_detail_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart
git add -u mobile/lib/theme_v2/library/asset/set_goal_action.dart
git commit -m "refactor(assets): remove goal action"
```

### Task 4: Rebuild Detail Geometry, Domain Content, and Long Text

**Files:**
- Create: `mobile/lib/theme_v2/library/asset/asset_detail_content.dart`
- Create: `mobile/lib/theme_v2/library/asset/asset_long_text.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_page.dart`
- Create: `mobile/test/theme_v2/library/asset/asset_long_text_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_detail_presentation_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`

**Interfaces:**
- Consumes: `AssetRecordViewModel` from Task 1.
- Produces: `AssetLongText`, five domain detail bodies, and detail footer/source view data.

- [ ] **Step 1: Write failing geometry and long-text tests**

```dart
testWidgets('half detail is 576 high at 411x960', (tester) async {
  await tester.binding.setSurfaceSize(const Size(411, 960));
  await pumpDetail(tester, record: noteRecord(longBody));
  expect(tester.getSize(find.byKey(const Key('asset-detail-surface'))).height, 576);
});

testWidgets('expand preserves hydration and exposes selectable local scroll', (tester) async {
  await pumpDetail(tester, record: noteRecord(longBody));
  await tester.tap(find.byKey(const Key('asset-detail-expand')));
  await tester.pumpAndSettle();
  expect(find.byType(SelectableText), findsOneWidget);
  expect(fake.detailRequestCount, 1);
});
```

- [ ] **Step 2: Run tests and verify failures**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_long_text_test.dart test/theme_v2/library/asset/asset_detail_test.dart`

Expected: FAIL because the exact geometry and long-text widget are absent.

- [ ] **Step 3: Implement `AssetLongText`**

Use `TextPainter.didExceedMaxLines` to decide whether half state gets a fade and “查看全部”. Use a constrained `SingleChildScrollView` containing `SelectableText` in full state; keep the parent detail footer outside this scroller.

- [ ] **Step 4: Implement domain detail bodies**

Create explicit bodies for Todo, Note, Event, Contact, and custom schema records. Each receives immutable record data and callbacks; none owns route geometry or calls the API.

- [ ] **Step 5: Rebuild the route shell**

Use:

```dart
final halfHeight = math.min(576.0, media.size.height - media.padding.top);
```

Keep one controller instance, animate half/full geometry, make content the only flexible scroll region, place source 8 pixels above the sticky action footer, and keep delete confirmation explicit.

- [ ] **Step 6: Run detail tests**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_detail_presentation_test.dart test/theme_v2/library/asset/asset_detail_test.dart test/theme_v2/library/asset/asset_long_text_test.dart`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_detail_content.dart mobile/lib/theme_v2/library/asset/asset_long_text.dart mobile/lib/theme_v2/library/asset/asset_detail_presentation.dart mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart mobile/lib/theme_v2/library/asset/asset_detail_page.dart mobile/test/theme_v2/library/asset/asset_long_text_test.dart mobile/test/theme_v2/library/asset/asset_detail_presentation_test.dart mobile/test/theme_v2/library/asset/asset_detail_test.dart
git commit -m "feat(assets): rebuild detail presentation"
```

### Task 5: Rebuild Dedicated Editors with Live Shared Preview

**Files:**
- Create: `mobile/lib/theme_v2/library/asset/asset_editors.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_editor.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_editor_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_detail_test.dart`

**Interfaces:**
- Consumes: `AssetRecordKind`, `AssetRecordViewModel`, `AssetEditorDraft`, shared `ThemeV2AssetCard`.
- Produces: `AssetEditorRouter` and domain editor widgets.

- [ ] **Step 1: Write failing editor routing and preview tests**

```dart
testWidgets('system kinds route to dedicated editor forms', (tester) async {
  await pumpEditor(tester, kind: AssetRecordKind.event);
  expect(find.byKey(const Key('event-start-field')), findsOneWidget);
  expect(find.byKey(const Key('event-end-field')), findsOneWidget);
});

testWidgets('editing title updates sticky shared preview', (tester) async {
  await pumpEditor(tester, kind: AssetRecordKind.note);
  await tester.enterText(find.byKey(const Key('note-title-field')), 'New title');
  expect(find.descendant(
    of: find.byKey(const Key('asset-editor-preview')),
    matching: find.text('New title'),
  ), findsOneWidget);
});
```

- [ ] **Step 2: Run tests and verify failures**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_editor_test.dart`

Expected: FAIL because dedicated Theme V2 editor routing and preview keys are absent.

- [ ] **Step 3: Implement explicit editor routing**

```dart
Widget buildAssetEditor(AssetEditorContext context) => switch (context.record.kind) {
  AssetRecordKind.todo => TodoAssetEditor(context),
  AssetRecordKind.note => NoteAssetEditor(context),
  AssetRecordKind.event => EventAssetEditor(context),
  AssetRecordKind.contact => ContactAssetEditor(context),
  AssetRecordKind.custom => SchemaAssetEditor(context),
};
```

Keep Event and Contact typed endpoints, add Todo/Notes field models, preserve custom required/type validation, and keep the draft in memory after failed save.

- [ ] **Step 4: Add sticky live preview**

Project the draft through `AssetRecordAdapter` and render `ThemeV2AssetCard.richCard` above the scrollable form. Rebuild from local draft notifications only.

- [ ] **Step 5: Run editor and detail tests**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_editor_test.dart test/theme_v2/library/asset/asset_detail_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_editors.dart mobile/lib/theme_v2/library/asset/asset_editor.dart mobile/lib/theme_v2/library/asset/asset_detail_sheet.dart mobile/test/theme_v2/library/asset/asset_editor_test.dart mobile/test/theme_v2/library/asset/asset_detail_test.dart
git commit -m "feat(assets): add dedicated live-preview editors"
```

### Task 6: Share Card Field Selection and Compatible Serialization

**Files:**
- Create: `mobile/lib/theme_v2/asset/card_field_selection.dart`
- Modify: `mobile/lib/theme_v2/asset/asset_card_display.dart`
- Modify: `mobile/lib/theme_v2/asset/asset_card.dart`
- Create: `mobile/test/theme_v2/asset/card_field_selection_test.dart`
- Modify: `mobile/test/theme_v2/asset/asset_card_display_test.dart`

**Interfaces:**
- Produces: `CardSelectableField`, `CardFieldSelectionController`, and `CardFieldSelector`.

- [ ] **Step 1: Write failing reducer tests**

```dart
test('changing primary removes it from secondary order', () {
  final controller = selection(primary: 'title', secondary: ['city', 'date']);
  controller.selectPrimary('city');
  expect(controller.config.primaryFieldId, 'city');
  expect(controller.config.secondaryFieldIds, ['date']);
});

test('secondary activation order caps at three', () {
  final controller = selection(primary: 'title');
  for (final id in ['a', 'b', 'c', 'd']) controller.toggleSecondary(id);
  expect(controller.config.secondaryFieldIds, ['a', 'b', 'c']);
  expect(controller.errorMessage, '次要字段最多选择 3 个');
});
```

- [ ] **Step 2: Run tests and verify failures**

Run: `cd mobile && flutter test test/theme_v2/asset/card_field_selection_test.dart`

Expected: FAIL because the reducer does not exist.

- [ ] **Step 3: Implement reducer and selector**

```dart
class CardFieldSelectionController extends ChangeNotifier {
  CardFieldSelectionController({
    required List<CardSelectableField> fields,
    required CardDisplayConfig config,
  });

  CardDisplayConfig get config;
  void selectPrimary(String fieldId);
  bool toggleSecondary(String fieldId);
  int? secondaryOrder(String fieldId);
}
```

The selector renders each field once, a primary radio, a secondary toggle, and an activation-order badge. It disables the primary field's secondary toggle.

- [ ] **Step 4: Verify compatible serialization**

Assert `applyToRenderSpec` writes canonical `card_display`, legacy primary/secondary/meta fields, retains field formats, and preserves unrelated keys.

- [ ] **Step 5: Run card tests**

Run: `cd mobile && flutter test test/theme_v2/asset/card_field_selection_test.dart test/theme_v2/asset/asset_card_display_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/asset/card_field_selection.dart mobile/lib/theme_v2/asset/asset_card_display.dart mobile/lib/theme_v2/asset/asset_card.dart mobile/test/theme_v2/asset/card_field_selection_test.dart mobile/test/theme_v2/asset/asset_card_display_test.dart
git commit -m "feat(theme-v2): share card field selection"
```

### Task 7: Rebuild Skill Builder's Three-Step State Machine

**Files:**
- Rewrite: `mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart`
- Modify: `mobile/test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`

**Interfaces:**
- Consumes: `CardFieldSelectionController` from Task 6 and existing draft/confirm endpoints.
- Produces: `SkillWizardStage.describe`, `.fields`, `.card`; `SkillDraftField`; editable schema reducer; compatible confirm payload.

- [ ] **Step 1: Replace old-stage tests with exact three-step tests**

```dart
test('clarification remains inside Describe and generated draft enters Fields', () async {
  fake.responses.add({'questions': [questionJson]});
  await controller.generate();
  expect(controller.stage, SkillWizardStage.describe);
  expect(controller.questions, isNotEmpty);
  fake.responses.add({'draft': draftJson});
  await controller.generate();
  expect(controller.stage, SkillWizardStage.fields);
});

test('field draft supports edit add remove and reorder', () {
  controller.renameField('city', label: '城市', meaning: '目的地');
  controller.addField(type: 'string');
  controller.moveField(2, 0);
  controller.removeField('budget');
  expect(controller.payloadSchema.keys.first, controller.fields.first.key);
});
```

- [ ] **Step 2: Run controller tests and verify failures**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`

Expected: FAIL because the old controller exposes Describe/Questions/Preview/Complete.

- [ ] **Step 3: Implement the three visible stages**

```dart
enum SkillWizardStage { describe, fields, card }

@immutable
class SkillDraftField {
  const SkillDraftField({
    required this.id,
    required this.key,
    required this.label,
    required this.type,
    required this.meaning,
    required this.required,
  });
}
```

Keep clarification questions in Describe. Add validation for non-empty unique keys/labels and supported types. Create the selection controller after schema generation and keep it synchronized when fields are renamed or removed.

- [ ] **Step 4: Compose final create payload**

Serialize edited field order into `payload_schema`, apply the selection config to the original render spec, preserve chat starters, and send through `/api/skills/confirm`.

- [ ] **Step 5: Run controller tests**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart mobile/test/theme_v2/library/create_skill/skill_wizard_controller_test.dart
git commit -m "feat(skills): rebuild three-step builder state"
```

### Task 8: Rebuild Skill Builder UI and Existing-Skill Card Settings

**Files:**
- Create: `mobile/lib/theme_v2/library/create_skill/skill_configuration_repository.dart`
- Rewrite: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill_action.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Create: `mobile/test/theme_v2/library/create_skill/skill_configuration_repository_test.dart`
- Modify: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

**Interfaces:**
- Consumes: three-step controller from Task 7 and shared selector from Task 6.
- Produces: `ThemeV2SkillWizard.create(...)`, `ThemeV2SkillWizard.configure(...)`, `SkillConfigurationRepository`.

- [ ] **Step 1: Write failing create/configuration widget tests**

```dart
testWidgets('builder renders exact Describe Fields Card rails', (tester) async {
  await pumpBuilder(tester);
  expect(find.text('Describe'), findsOneWidget);
  expect(find.text('Fields'), findsOneWidget);
  expect(find.text('Card'), findsOneWidget);
  expect(find.text('Questions'), findsNothing);
  expect(find.text('Preview'), findsNothing);
});

testWidgets('configuration opens directly at Card and omits schema editing', (tester) async {
  await pumpConfiguration(tester, skill: storedSkill);
  expect(find.byKey(const Key('skill-card-step')), findsOneWidget);
  expect(find.byKey(const Key('skill-fields-step')), findsNothing);
});
```

- [ ] **Step 2: Run widget/repository tests and verify failures**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart test/theme_v2/library/create_skill/skill_configuration_repository_test.dart`

Expected: FAIL because configuration mode and Pen-aligned three-step UI are absent.

- [ ] **Step 3: Implement configuration repository**

```dart
abstract interface class SkillConfigurationRepository {
  Future<ConfigurableSkill> load(String userSkillId);
  Future<void> saveCardDisplay(
    String userSkillId,
    CardDisplayConfig config,
    Map<String, dynamic> originalRenderSpec,
  );
}
```

Load from the existing skills API and PATCH only `render_spec` plus permitted presentation values. Do not send `payload_schema`.

- [ ] **Step 4: Build Step 1 Describe**

Match the Pen progress rails, description field, examples, AI guidance, inline clarification questions, and bottom primary action.

- [ ] **Step 5: Build Step 2 Fields**

Render reorderable rows with editable label/key/type/meaning/required controls and explicit add/remove actions. Continue only when controller validation succeeds.

- [ ] **Step 6: Build shared Step 3 Card**

Render `ThemeV2AssetCard.richCard` above `CardFieldSelector`. Creation uses “创建 Skill”; configuration uses “保存展示设置”. Both use the same controller/reducer.

- [ ] **Step 7: Wire navigation**

Creation enters Describe. A custom container's “Card Display Settings” passes `userSkillId` and enters Card configuration mode. Back navigation steps from Card to Fields and Fields to Describe only in creation mode.

- [ ] **Step 8: Run Skill Builder tests**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_wizard_controller_test.dart test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart test/theme_v2/library/create_skill/skill_configuration_repository_test.dart`

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add mobile/lib/theme_v2/library/create_skill/skill_configuration_repository.dart mobile/lib/theme_v2/library/create_skill/skill_wizard_controller.dart mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart mobile/lib/theme_v2/library/create_skill_action.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/test/theme_v2/library/create_skill/skill_configuration_repository_test.dart mobile/test/theme_v2/library/create_skill/skill_wizard_controller_test.dart mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart
git commit -m "feat(skills): add builder and card settings UI"
```

### Task 9: Add Pen-Aligned Golden Coverage

**Files:**
- Create: `mobile/test/theme_v2/library/asset/theme_v2_asset_golden_test.dart`
- Create: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_builder_golden_test.dart`
- Create: golden PNGs under `mobile/test/theme_v2/library/asset/goldens/`
- Create: golden PNGs under `mobile/test/theme_v2/library/create_skill/goldens/`

**Interfaces:**
- Consumes: completed Asset and Skill Builder widgets.
- Produces: light/dark 411×960 visual regression baselines.

- [ ] **Step 1: Add deterministic golden harnesses**

```dart
await tester.binding.setSurfaceSize(const Size(411, 960));
await tester.pumpWidget(buildThemeV2Golden(
  brightness: Brightness.light,
  child: seededTodoList(),
));
await expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/todo-list-411-light.png'),
);
```

Cover list, half detail, full detail, and edit for system/custom records, plus Builder Steps 1–3 and configuration mode in light and dark themes.

- [ ] **Step 2: Generate baselines**

Run: `cd mobile && flutter test --update-goldens test/theme_v2/library/asset/theme_v2_asset_golden_test.dart test/theme_v2/library/create_skill/theme_v2_skill_builder_golden_test.dart`

Expected: PASS and deterministic PNG baselines are written.

- [ ] **Step 3: Inspect every baseline against the corresponding Pen node**

Verify geometry, typography, sticky chrome, card fields, progress rails, half-sheet height, and dark/light surfaces. Correct widget code before accepting mismatched baselines.

- [ ] **Step 4: Run goldens without update**

Run: `cd mobile && flutter test test/theme_v2/library/asset/theme_v2_asset_golden_test.dart test/theme_v2/library/create_skill/theme_v2_skill_builder_golden_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/test/theme_v2/library/asset/theme_v2_asset_golden_test.dart mobile/test/theme_v2/library/asset/goldens mobile/test/theme_v2/library/create_skill/theme_v2_skill_builder_golden_test.dart mobile/test/theme_v2/library/create_skill/goldens
git commit -m "test(theme-v2): cover asset and skill builder visuals"
```

### Task 10: Regression, Android Build, and Real-Device Acceptance

**Files:**
- Modify only code/tests that fail the acceptance checks.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified Android Theme V2 flow with no production-default change.

- [ ] **Step 1: Format touched Dart files**

Run: `cd mobile && dart format lib/theme_v2/asset lib/theme_v2/library test/theme_v2/asset test/theme_v2/library`

Expected: formatter exits 0.

- [ ] **Step 2: Run focused test suites**

Run: `cd mobile && flutter test test/theme_v2/asset test/theme_v2/library`

Expected: PASS.

- [ ] **Step 3: Run Calendar and shared Theme V2 regressions**

Run: `cd mobile && flutter test test/theme_v2/calendar test/theme_v2/navigation`

Expected: PASS.

- [ ] **Step 4: Analyze touched implementation**

Run: `cd mobile && flutter analyze lib/theme_v2/asset lib/theme_v2/library test/theme_v2/asset test/theme_v2/library`

Expected: no errors or warnings introduced by this tranche.

- [ ] **Step 5: Build the Theme V2 Android debug APK**

Run: `cd mobile && flutter build apk --debug --dart-define=THEME_V2=true`

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced.

- [ ] **Step 6: Install and launch on the connected device**

Run:

```bash
ADB="/Users/admin/Library/Android/sdk/platform-tools/adb"
"$ADB" -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
"$ADB" -s RFCY71B21YK reverse tcp:8000 tcp:8000
"$ADB" -s RFCY71B21YK shell am force-stop com.eureka.mindapp
"$ADB" -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: install succeeds and the app launches with Theme V2.

- [ ] **Step 7: Perform real-device acceptance**

Verify:

- persistent Library navigation and dock;
- all four system containers and one custom container;
- Todo tabs, counts, scheduled/unscheduled ordering, and completion rollback behavior;
- half/full detail transition without duplicate loading or state loss;
- long note expansion and local text scrolling;
- source placement and sticky actions;
- every dedicated system editor and custom editor live preview;
- Skill Builder Describe → Fields → Card;
- schema add/edit/remove/reorder;
- existing custom-skill Card Display Settings opening directly at Card;
- saved display config reflected in list/detail/editor preview;
- no “设为目标” action.

- [ ] **Step 8: Capture device screenshots**

Capture Todo list/detail, long Notes detail, Builder Fields/Card, and existing-skill configuration for final comparison.

- [ ] **Step 9: Run final diff and cleanliness checks**

Run:

```bash
git diff --check
git status --short
rg -n "SetGoalIntent|onSetGoal|设为目标|set_goal_action" mobile/lib/theme_v2/library
```

Expected: no whitespace errors, only intended files are modified, and the goal-action search returns no matches.

- [ ] **Step 10: Commit verification fixes if any**

```bash
git add mobile/lib/theme_v2/asset mobile/lib/theme_v2/library mobile/test/theme_v2/asset mobile/test/theme_v2/library
git commit -m "fix(theme-v2): close asset device regressions"
```

Skip this commit when verification requires no code changes.
