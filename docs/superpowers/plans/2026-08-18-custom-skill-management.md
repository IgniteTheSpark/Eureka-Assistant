# Custom Skill Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit compatible parts of a custom Skill and permanently delete a custom Skill together with its Assets.

**Architecture:** Add server-authoritative schema compatibility and deletion services to the Theme V2 core-records API. Extend the existing Skill configuration repository/controller into a custom-Skill management flow while keeping built-in card configuration behavior intact.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy, Pydantic, pytest, Flutter/Dart, flutter_test.

## Global Constraints

- Built-in/system Skills cannot be renamed, schema-edited, or deleted.
- Existing custom field keys and types are immutable.
- Existing fields are hidden with `x-hidden: true`; historical payload values are not rewritten.
- New fields are optional; the UI never exposes a required-field toggle.
- Deleting a custom Skill permanently deletes all of its Assets after an Asset-count confirmation.
- Use TDD and commit each independently passing task.

---

### Task 1: Enforce compatible custom-Skill schema updates

**Files:**
- Create: `theme_v2_service/app/domains/assets/skill_schema.py`
- Modify: `theme_v2_service/app/domains/assets/schemas.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/domains/assets/api.py`
- Test: `theme_v2_service/tests/integration/test_asset_service.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**
- Produces: `validate_custom_skill_update(skill: UserSkill, command: UserSkillUpdate) -> None`.
- Produces: `SkillUpdateConflict(code: str, message: str)` mapped to HTTP 409.
- Extends: `UserSkillUpdate.expected_updated_at: datetime | None`.

- [ ] **Step 1: Write failing service tests for add/relabel/hide and incompatible key/type changes**

```python
async def test_custom_skill_schema_update_preserves_keys_and_allows_new_optional_field(session):
    skill = await _custom_skill(session, schema={"type": "object", "properties": {
        "duration": {"type": "number", "title": "时长"}
    }})
    updated = await update_user_skill(session, "user-1", skill.id, UserSkillUpdate(
        schema={"type": "object", "properties": {
            "duration": {"type": "number", "title": "训练时长"},
            "location": {"type": "string", "title": "地点", "x-hidden": False},
        }}
    ))
    assert updated.schema_json["properties"]["location"]["type"] == "string"

async def test_custom_skill_schema_update_rejects_existing_type_change(session):
    skill = await _custom_skill(session, schema={"type": "object", "properties": {
        "duration": {"type": "number", "title": "时长"}
    }})
    with pytest.raises(SkillUpdateConflict) as error:
        await update_user_skill(session, "user-1", skill.id, UserSkillUpdate(
            schema={"type": "object", "properties": {
                "duration": {"type": "string", "title": "时长"}
            }}
        ))
    assert error.value.code == "field_type_changed"
```

- [ ] **Step 2: Run the focused service tests and verify failure**

Run: `cd theme_v2_service && pytest tests/integration/test_asset_service.py -k 'custom_skill_schema_update' -q`

Expected: FAIL because `SkillUpdateConflict` and compatibility validation do not exist.

- [ ] **Step 3: Implement compatibility validation and optimistic revision checking**

```python
class SkillUpdateConflict(ValueError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message

def validate_custom_skill_update(skill: UserSkill, command: UserSkillUpdate) -> None:
    if skill.global_skill_id is not None and (
        command.display_name is not None or command.schema_definition is not None
    ):
        raise SkillUpdateConflict("system_skill_protected", "system Skill is protected")
    if command.expected_updated_at is not None and skill.updated_at != _utc_naive(command.expected_updated_at):
        raise SkillUpdateConflict("stale_skill_revision", "Skill changed since it was opened")
    if command.schema_definition is None:
        return
    current = _properties(skill.schema_json)
    proposed = _properties(command.schema_definition)
    for key, definition in current.items():
        if key not in proposed:
            raise SkillUpdateConflict("field_removed", f"field {key} must be hidden")
        if _field_type(definition) != _field_type(proposed[key]):
            raise SkillUpdateConflict("field_type_changed", f"field {key} type changed")
    if not any(not bool(value.get("x-hidden")) for value in proposed.values()):
        raise SkillUpdateConflict("no_visible_fields", "at least one field must remain visible")
```

Add `expected_updated_at` to `UserSkillUpdate`, call validation before mutation, and return structured HTTP 409 details:

```python
except service.SkillUpdateConflict as exc:
    raise HTTPException(status_code=409, detail={"code": exc.code, "message": exc.message}) from exc
```

- [ ] **Step 4: Add and run API contract tests**

Run: `cd theme_v2_service && pytest tests/contract/test_asset_api.py -k 'user_skill_update' -q`

Expected: PASS for compatible custom updates, built-in protection, and stale revision conflicts.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/assets/skill_schema.py theme_v2_service/app/domains/assets/schemas.py theme_v2_service/app/domains/assets/service.py theme_v2_service/app/domains/assets/api.py theme_v2_service/tests/integration/test_asset_service.py theme_v2_service/tests/contract/test_asset_api.py
git commit -m "feat: validate custom skill schema updates"
```

### Task 2: Add deletion impact and cascading custom-Skill deletion

**Files:**
- Modify: `theme_v2_service/app/domains/assets/schemas.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/domains/assets/api.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**
- Produces: `SkillDeletionImpact(skill_id: str, asset_count: int)`.
- Produces: `SkillDeletionResult(skill_id: str, deleted_asset_count: int)`.
- Produces endpoints `GET /api/user-skills/{id}/deletion-impact` and `DELETE /api/user-skills/{id}`.

- [ ] **Step 1: Write failing delete contract tests**

```python
async def test_delete_custom_skill_reports_and_cascades_assets(client, session, auth_headers):
    skill, assets = await _skill_with_assets(session, count=2)
    impact = await client.get(f"/api/user-skills/{skill.id}/deletion-impact", headers=auth_headers)
    assert impact.json() == {"skill_id": skill.id, "asset_count": 2}
    deleted = await client.delete(f"/api/user-skills/{skill.id}", headers=auth_headers)
    assert deleted.json() == {"skill_id": skill.id, "deleted_asset_count": 2}
    assert await session.get(UserSkill, skill.id) is None

async def test_delete_builtin_skill_is_rejected(client, builtin_skill, auth_headers):
    response = await client.delete(f"/api/user-skills/{builtin_skill.id}", headers=auth_headers)
    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "system_skill_protected"
```

- [ ] **Step 2: Run tests and verify failure**

Run: `cd theme_v2_service && pytest tests/contract/test_asset_api.py -k 'delete_custom_skill or delete_builtin_skill' -q`

Expected: FAIL with 405 because delete endpoints do not exist.

- [ ] **Step 3: Implement count and delete services**

```python
async def skill_deletion_impact(session, user_id: str, skill_id: str) -> SkillDeletionImpact | None:
    skill = await get_user_skill(session, user_id, skill_id)
    if skill is None:
        return None
    _require_custom_skill(skill)
    count = await session.scalar(select(func.count(Asset.id)).where(
        Asset.user_id == user_id, Asset.user_skill_id == skill_id
    ))
    return SkillDeletionImpact(skill_id=skill_id, asset_count=int(count or 0))

async def delete_user_skill(session, user_id: str, skill_id: str) -> SkillDeletionResult | None:
    impact = await skill_deletion_impact(session, user_id, skill_id)
    if impact is None:
        return None
    skill = await get_user_skill(session, user_id, skill_id)
    await session.delete(skill)
    await session.flush()
    return SkillDeletionResult(skill_id=skill_id, deleted_asset_count=impact.asset_count)
```

- [ ] **Step 4: Run contract tests**

Run: `cd theme_v2_service && pytest tests/contract/test_asset_api.py -k 'skill' -q`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/assets/schemas.py theme_v2_service/app/domains/assets/service.py theme_v2_service/app/domains/assets/api.py theme_v2_service/tests/contract/test_asset_api.py
git commit -m "feat: delete custom skills with their assets"
```

### Task 3: Build the Flutter custom-Skill management controller

**Files:**
- Modify: `mobile/lib/theme_v2/library/create_skill/skill_configuration_repository.dart`
- Create: `mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart`
- Test: `mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart`

**Interfaces:**
- Produces: `SkillManagementRepository.load/save/deletionImpact/delete`.
- Produces: `SkillManagementController` with editable fields, locked original keys/types, visibility, save, and delete state.

- [ ] **Step 1: Write failing controller tests**

```dart
test('existing key and type stay locked while a location field can be added', () async {
  final repository = FakeSkillManagementRepository(tennisSkill);
  final controller = SkillManagementController(repository: repository, userSkillId: 'tennis');
  await controller.load();
  expect(controller.updateExistingKey('duration', 'minutes'), isFalse);
  expect(controller.updateExistingType('duration', 'string'), isFalse);
  controller.addField(key: 'location', label: '地点', type: 'string');
  expect(controller.fields.last.required, isFalse);
  expect(await controller.save(), isTrue);
  expect(repository.savedSchema['properties']['location']['type'], 'string');
});
```

- [ ] **Step 2: Run test and verify failure**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_management_controller_test.dart`

Expected: FAIL because the management controller does not exist.

- [ ] **Step 3: Implement repository and controller**

```dart
abstract interface class SkillManagementRepository {
  Future<ConfigurableSkill> load(String userSkillId);
  Future<ConfigurableSkill> save(String userSkillId, SkillManagementDraft draft);
  Future<int> deletionImpact(String userSkillId);
  Future<int> delete(String userSkillId);
}

@immutable
class SkillManagementField {
  const SkillManagementField({required this.key, required this.label, required this.type,
    required this.meaning, required this.original, this.hidden = false});
  final String key;
  final String label;
  final String type;
  final String meaning;
  final bool original;
  final bool hidden;
}
```

Serialize fields as JSON Schema properties, always omit them from the root `required` list, and set `x-hidden` for hidden originals. Send `expected_updated_at`, `schema`, `display_name`, `description`, and `render_spec` in one PATCH.

- [ ] **Step 4: Run controller and existing configuration tests**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill/skill_management_controller_test.dart test/theme_v2/library/create_skill/skill_configuration_repository_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/create_skill/skill_configuration_repository.dart mobile/lib/theme_v2/library/create_skill/skill_management_controller.dart mobile/test/theme_v2/library/create_skill/skill_management_controller_test.dart
git commit -m "feat: add custom skill management state"
```

### Task 4: Expose edit and delete actions in the custom container

**Files:**
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill_action.dart`
- Modify: `mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`
- Test: `mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

**Interfaces:**
- Consumes: `SkillManagementController` from Task 3.
- Produces: `showThemeV2SkillManagementLaunch(context, userSkillId:, onDeleted:)`.

- [ ] **Step 1: Write failing widget tests for discoverable custom actions and deletion count**

```dart
testWidgets('custom container exposes edit and delete actions', (tester) async {
  await tester.pumpWidget(customContainerHarness());
  expect(find.byKey(const ValueKey('custom-skill-edit')), findsOneWidget);
  expect(find.byKey(const ValueKey('custom-skill-delete')), findsOneWidget);
});

testWidgets('delete confirmation displays affected record count', (tester) async {
  await tester.pumpWidget(skillManagementHarness(assetCount: 4));
  await tester.tap(find.byKey(const ValueKey('custom-skill-delete')));
  await tester.pumpAndSettle();
  expect(find.textContaining('4 条记录'), findsOneWidget);
  expect(find.byKey(const ValueKey('custom-skill-delete-confirm')), findsOneWidget);
});
```

- [ ] **Step 2: Run widget tests and verify failure**

Run: `cd mobile && flutter test test/theme_v2/library/asset/asset_list_page_test.dart test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart`

Expected: FAIL because custom management actions and full edit mode are absent.

- [ ] **Step 3: Implement custom-only actions and edit UI**

Add an optional `onManageSkill` action to the asset list title area. For `LibraryContainerType.custom`, pass a callback that opens the management sheet; do not pass it for built-ins.

The management sheet uses two stages:

```dart
enum SkillManagementStage { fields, card }
```

The fields stage shows display name, description, reorderable fields, locked key/type labels for originals, editable label/meaning, hide toggle, and add-field action. The card stage reuses `CardFieldSelector`. The footer saves the complete draft. A destructive section loads impact and requires a second explicit confirmation before `DELETE`.

- [ ] **Step 4: Run widget tests and targeted analysis**

Run: `cd mobile && flutter test test/theme_v2/library/create_skill test/theme_v2/library/asset/asset_list_page_test.dart`

Run: `cd mobile && flutter analyze lib/theme_v2/library test/theme_v2/library`

Expected: tests PASS and analyzer reports no issues.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/theme_v2/library/create_skill_action.dart mobile/lib/theme_v2/library/create_skill/theme_v2_skill_wizard.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart mobile/test/theme_v2/library/create_skill/theme_v2_skill_wizard_test.dart
git commit -m "feat: expose custom skill edit and delete"
```
