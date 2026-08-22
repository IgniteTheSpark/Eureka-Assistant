# Custom Skill Field Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one field-configuration icon beside the existing card-display icon and provide a field-only editor that changes future capture schema without touching historical assets.

**Architecture:** The existing card-display entry and page remain unchanged. A sibling icon in the custom Skill asset-list header opens a focused field configuration page backed by the existing optimistic-concurrency repository. Backend schema validation permits field deletion; the mobile renderer treats deleted display references as empty instead of substituting the Skill label.

**Tech Stack:** Python 3.12, FastAPI/Pydantic, pytest, Flutter/Dart, Material 3.

## Global Constraints

- Add only one sibling field-configuration icon; do not redesign the Skill detail page.
- The field page contains fields only: add, edit, delete, save.
- Do not expose required/optional, hide/disable, sorting, or basic information.
- Field changes affect future captures only; historical asset payloads are not migrated.
- Deleting a display-referenced field is allowed and its card slot renders nothing.
- Follow `/AGENTS.md`; no full-suite verification for this scoped change.

---

### Task 1: Permit custom Skill field deletion on the backend

**Files:**
- Modify: `theme_v2_service/app/domains/assets/skill_schema.py`
- Test: `theme_v2_service/tests/unit/test_custom_skill_schema.py`
- Test: `theme_v2_service/tests/integration/test_asset_service.py`

**Interfaces:**
- Consumes: `UserSkillUpdate.schema_definition`, existing revision contract.
- Produces: `validate_custom_skill_update()` accepting removed custom fields while retaining schema-shape/type validation for remaining and new fields.

- [ ] **Step 1: Add failing deletion tests**

```python
def test_custom_skill_schema_allows_field_deletion_without_hiding():
    skill = _skill(schema={
        "type": "object",
        "properties": {
            "duration": {"type": "number"},
            "location": {"type": "string"},
        },
        "required": [],
    })
    validate_custom_skill_update(
        skill,
        UserSkillUpdate(schema={
            "type": "object",
            "properties": {"duration": {"type": "number"}},
            "required": [],
        }),
    )
```

Add this integration assertion after patching the Skill through the service:

```python
await update_user_skill(
    session,
    owner_id,
    skill.id,
    UserSkillUpdate(
        schema={"type": "object", "properties": {"duration": {"type": "number"}}},
        expected_updated_at=skill.updated_at,
    ),
)
await session.refresh(asset)
assert asset.payload_json == {"duration": 60, "location": "网球中心"}
```

- [ ] **Step 2: Run focused backend tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/unit/test_custom_skill_schema.py \
  tests/integration/test_asset_service.py -q \
  -k 'field_deletion or historical_asset'
```

Expected: deletion fails with `field_removed`.

- [ ] **Step 3: Remove compatibility rules that contradict future-only schema editing**

Delete the `field_removed` and `no_visible_fields` rejection branches. Continue validating field IDs, supported types/formats, array items, empty `required`, protected system Skills, and optimistic revision. Do not update or delete any Asset rows in the service.

- [ ] **Step 4: Run the focused schema/service files**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/unit/test_custom_skill_schema.py \
  tests/integration/test_asset_service.py -q
```

Expected: both files pass.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/assets/skill_schema.py \
  theme_v2_service/tests/unit/test_custom_skill_schema.py \
  theme_v2_service/tests/integration/test_asset_service.py
git commit -m "feat: allow custom skill field deletion"
```

### Task 2: Make Skill management controller field-only

**Files:**
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart`
- Test: `mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart`

**Interfaces:**
- Consumes: `SkillManagementRepository.load/save/delete` and immutable `ConfigurableSkill.renderSpec`.
- Produces: `removeField(String key)`, add/edit field draft, save preserving display name, description, and render spec.

- [ ] **Step 1: Add failing controller tests**

```dart
test('field-only save deletes schema field and preserves render spec', () async {
  final repository = _FakeRepository(_multiFieldSkill());
  final controller = SkillManagementController(
    repository: repository,
    userSkillId: 'tennis-id',
  );
  await controller.load();
  expect(controller.removeField('surface'), isTrue);
  expect(await controller.save(), isTrue);
  final properties = repository.saved!.schema['properties'] as Map;
  expect(properties.containsKey('surface'), isFalse);
  expect(repository.saved!.schema['required'], isEmpty);
  expect(repository.saved!.renderSpec, _multiFieldSkill().renderSpec);
});
```

Retain the existing rapid save/delete tests and change their UI trigger only in Task 3.

- [ ] **Step 2: Run controller test and verify RED**

```bash
cd mobile && flutter test \
  test/theme_v2/library/create_skill/skill_management_controller_test.dart
```

Expected: failures because `removeField` does not exist and save currently normalizes card selection/hidden state.

- [ ] **Step 3: Implement field-only mutations**

```dart
bool removeField(String key) {
  final next = _fields.where((field) => field.key != key).toList();
  if (next.length == _fields.length) return false;
  _fields = List.unmodifiable(next);
  _errorMessage = null;
  _notify();
  return true;
}
```

Stop rebuilding `CardFieldSelectionController` after field mutations. In `save()`, send `current.renderSpec` unchanged, and serialize only current fields with `required: <String>[]` and no `x-hidden`. Keep existing display name/description values in the request because the API contract requires a complete draft, but remove their public setters from the field-page interaction.

- [ ] **Step 4: Run controller tests**

```bash
cd mobile && flutter test \
  test/theme_v2/library/create_skill/skill_management_controller_test.dart
```

Expected: all controller tests pass after obsolete combined-page expectations are replaced with field-only behavior.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart \
  mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart
git commit -m "refactor: focus custom skill management on fields"
```

### Task 3: Add the sibling field icon and field-only page

**Files:**
- Create: `mobile/lib/theme_v2/library/create_skill/skill_field_configuration_page.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill_action.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Delete: `mobile/lib/theme_v2/library/create_skill/skill_management_sheet.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`
- Test: `mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart`

**Interfaces:**
- Consumes: `onConfigureCard`, new `onConfigureFields`, `SkillManagementController`.
- Produces: `showThemeV2SkillFieldConfigurationLaunch()` and `ThemeV2SkillFieldConfigurationPage`.

- [ ] **Step 1: Add failing header and page tests**

```dart
expect(find.byKey(const ValueKey('custom-skill-card-display')), findsOneWidget);
expect(
  find.byKey(const ValueKey('custom-skill-field-configuration')),
  findsOneWidget,
);
await tester.tap(find.byKey(const ValueKey('custom-skill-field-configuration')));
await tester.pumpAndSettle();
expect(find.text('字段配置'), findsOneWidget);
expect(find.byKey(const ValueKey('custom-skill-add-field')), findsOneWidget);
expect(find.text('基本信息'), findsNothing);
expect(find.textContaining('必填'), findsNothing);
expect(find.textContaining('停用'), findsNothing);
expect(find.text('卡片展示'), findsNothing);
expect(find.text('保存修改'), findsNothing);
```

- [ ] **Step 2: Run the focused Flutter tests and verify RED**

```bash
cd mobile && flutter test \
  test/theme_v2/library/asset/asset_list_page_test.dart \
  test/theme_v2/library/create_skill/skill_management_controller_test.dart
```

Expected: missing sibling icon and field-only page assertions fail.

- [ ] **Step 3: Expose both header actions**

Change `_ListHeader` to accept `onConfigureFields`; always show `onConfigureCard` when non-null, using key `custom-skill-card-display`, and add a sibling `ThemeV2IconButton` with key `custom-skill-field-configuration`, semantic label `字段配置`, and `Icons.data_object_rounded`.

In `_assetContainerSurface`, pass `_displayConfigurationFor(container)` for custom Skills as well as `_fieldConfigurationFor(container)`; system Skills keep card display only.

- [ ] **Step 4: Build the focused page**

Create a full-screen `Material`/`SafeArea` page with a header row: close/back, `字段配置`, top `保存`. Render stable schema order without drag handles. Each field row edits label and meaning, displays type read-only for original fields, and exposes delete. The add dialog chooses key, label, type, and meaning. Put whole-Skill deletion in a top overflow menu so the existing protected confirmation flow remains available without becoming page content.

- [ ] **Step 5: Run the focused Skill UI tests**

```bash
cd mobile && flutter test \
  test/theme_v2/library/asset/asset_list_page_test.dart \
  test/theme_v2/library/create_skill/skill_management_controller_test.dart \
  test/theme_v2/library/create_skill/skill_configuration_repository_test.dart
```

Expected: all three files pass.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/library/create_skill/skill_field_configuration_page.dart \
  mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart \
  mobile/lib/theme_v2/library/create_skill_action.dart \
  mobile/lib/theme_v2/library/asset/asset_list_page.dart \
  mobile/lib/theme_v2/library/theme_v2_library_page.dart \
  mobile/test/theme_v2/library/asset/asset_list_page_test.dart \
  mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart
git rm mobile/lib/theme_v2/library/create_skill/skill_management_sheet.dart
git commit -m "feat: add focused skill field configuration"
```

### Task 4: Render deleted or absent card fields as empty

**Files:**
- Modify: `mobile/lib/theme_v2/asset/asset_card_display.dart`
- Test: `mobile/test/theme_v2/asset/asset_card_display_test.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`

**Interfaces:**
- Consumes: `CardDisplayConfig`, payload, schema-backed `RenderSpec`.
- Produces: `AssetCardViewData` without Skill-label content fallback.

- [ ] **Step 1: Add failing missing-field regressions**

```dart
test('missing configured field stays empty without skill label fallback', () {
  final data = AssetCardViewData.fromPayload(
    payload: const {'location': '网球中心'},
    display: CardDisplayConfig(
      primaryFieldId: 'deleted_title',
      secondaryFieldIds: const ['location', 'deleted_duration'],
    ),
    spec: null,
    skillLabel: '跳舞记录',
  );
  expect(data.primaryValue, isEmpty);
  expect(data.secondaryValues, const ['网球中心']);
  expect(data.skillLabel, '跳舞记录');
});
```

- [ ] **Step 2: Run focused card tests and verify RED**

```bash
cd mobile && flutter test \
  test/theme_v2/asset/asset_card_display_test.dart \
  test/theme_v2/library/asset/asset_list_page_test.dart \
  --plain-name 'missing configured field'
```

Expected: current `primary.isEmpty ? normalizedSkillLabel : primary` fallback fails.

- [ ] **Step 3: Remove the content fallback**

```dart
return AssetCardViewData(
  skillLabel: normalizedSkillLabel,
  primaryValue: primary,
  secondaryValues: List.unmodifiable([
    for (final field in display.secondaryFieldIds)
      if (formatted(field).isNotEmpty) formatted(field),
  ]),
  mark: spec.icon,
);
```

Do not invent a replacement field. Let card variants omit an empty text slot while preserving the Skill type label and mark.

- [ ] **Step 4: Run affected card/list tests**

```bash
cd mobile && flutter test \
  test/theme_v2/asset/asset_card_display_test.dart \
  test/theme_v2/library/asset/asset_list_page_test.dart
```

Expected: both files pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/asset/asset_card_display.dart \
  mobile/test/theme_v2/asset/asset_card_display_test.dart \
  mobile/test/theme_v2/library/asset/asset_list_page_test.dart
git commit -m "fix: leave missing card fields empty"
```

### Task 5: Focused Skill verification

**Files:** No production changes expected.

- [ ] **Step 1: Run affected backend tests**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm test \
  python -m pytest tests/unit/test_custom_skill_schema.py \
  tests/integration/test_asset_service.py -q
```

- [ ] **Step 2: Run affected Flutter tests**

```bash
cd mobile && flutter test \
  test/theme_v2/library/create_skill/skill_management_controller_test.dart \
  test/theme_v2/library/create_skill/skill_configuration_repository_test.dart \
  test/theme_v2/library/asset/asset_list_page_test.dart \
  test/theme_v2/asset/asset_card_display_test.dart
```

- [ ] **Step 3: Run targeted analysis and diff checks**

```bash
cd mobile && flutter analyze \
  lib/theme_v2/library/create_skill/skill_management_controller.dart \
  lib/theme_v2/library/create_skill/skill_field_configuration_page.dart \
  lib/theme_v2/library/create_skill_action.dart \
  lib/theme_v2/library/asset/asset_list_page.dart \
  lib/theme_v2/library/theme_v2_library_page.dart \
  lib/theme_v2/asset/asset_card_display.dart
git diff --check
```

Expected: focused tests pass, targeted analysis reports no issues, and diff check is clean. Do not run full backend or Flutter suites.
