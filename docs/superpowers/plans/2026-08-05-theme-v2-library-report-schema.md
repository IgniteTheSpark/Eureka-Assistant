# Theme V2 Library Report and Schema Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Report a normal configurable Library container and ensure custom asset fields are always bounded by the active skill schema.

**Architecture:** The Theme V2 service validates payload keys at the Asset domain boundary. Flutter derives detail/list fields from the authoritative payload schema. Report joins the existing Library container model instead of keeping a privileged standalone entry.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Pydantic 2, pytest, Dart, Flutter, shared_preferences.

## Global Constraints

- Preserve existing Report generation, presentation templates, and Report detail routes.
- Keep the Library maximum at six pinned containers.
- Report is default-pinned once for existing installs, but remains removable and re-addable.
- Do not display or accept payload fields excluded by a closed schema.
- Preserve unrelated dirty worktree files.

---

### Task 1: Enforce the custom Asset schema boundary in the service

**Files:**
- Create: `theme_v2_service/app/domains/assets/validation.py`
- Modify: `theme_v2_service/app/domains/assets/service.py`
- Modify: `theme_v2_service/app/domains/assets/api.py`
- Test: `theme_v2_service/tests/unit/test_asset_payload_validation.py`
- Test: `theme_v2_service/tests/contract/test_asset_api.py`

**Interfaces:**
- Produces: `normalize_payload_schema(schema_json) -> dict` for full JSON Schema and legacy shorthand schemas.
- Produces: `validate_asset_payload(payload, schema_json) -> None`.
- Rejects unknown keys whenever the normalized root uses `additionalProperties: false`.

- [ ] **Step 1: Write failing validation and API tests**

```python
with pytest.raises(AssetPayloadInvalid):
    validate_asset_payload(
        {"distance": 5, "acceptance_marker": "forbidden"},
        {"type": "object", "properties": {"distance": {"type": "number"}},
         "additionalProperties": False},
    )
```

Cover legacy shorthand normalization, required keys, primitive types, and an
API `422` for a forbidden field on both create and update.

- [ ] **Step 2: Run and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/unit/test_asset_payload_validation.py tests/contract/test_asset_api.py -q`

Expected: import failure or API accepts the unknown field.

- [ ] **Step 3: Implement validation at create and update boundaries**

Normalize shorthand into an object schema, validate the merged update payload,
and map the domain error to a public `422` without exposing internal data.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/app/domains/assets/validation.py theme_v2_service/app/domains/assets/service.py theme_v2_service/app/domains/assets/api.py theme_v2_service/tests/unit/test_asset_payload_validation.py theme_v2_service/tests/contract/test_asset_api.py
git commit -m "fix(theme-v2): enforce asset schema boundaries"
```

### Task 2: Render only schema-authorized Asset fields

**Files:**
- Modify: `mobile/lib/theme_v2/asset_detail/asset_detail_repository.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_record.dart`
- Test: `mobile/test/theme_v2/asset_detail/asset_detail_repository_test.dart`
- Test: `mobile/test/theme_v2/library/asset/asset_record_test.dart`

**Interfaces:**
- Closed schema: render schema properties only, in schema/render order.
- Open or absent schema: retain the current best-effort payload fallback.

- [ ] **Step 1: Write failing repository and adapter tests**

Seed a running asset whose payload contains `distance` and
`acceptance_marker`, while the skill schema contains only `distance`. Assert
the detail and list record contain `distance` and omit `acceptance_marker`.

- [ ] **Step 2: Run and verify RED**

Run: `cd mobile && flutter test test/theme_v2/asset_detail/asset_detail_repository_test.dart test/theme_v2/library/asset/asset_record_test.dart`

Expected: FAIL because payload-only keys are appended.

- [ ] **Step 3: Make schema authority explicit in both adapters**

Preserve `additionalProperties` while decoding the schema. Append payload-only
keys only when the schema is absent or explicitly open.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/asset_detail/asset_detail_repository.dart mobile/lib/theme_v2/library/asset/asset_record.dart mobile/test/theme_v2/asset_detail/asset_detail_repository_test.dart mobile/test/theme_v2/library/asset/asset_record_test.dart
git commit -m "fix(library): hide fields outside the skill schema"
```

### Task 3: Model Report as a standard Library container

**Files:**
- Modify: `mobile/lib/theme_v2/library/library_models.dart`
- Modify: `mobile/lib/theme_v2/library/library_repository.dart`
- Modify: `mobile/lib/theme_v2/library/library_controller.dart`
- Modify: `mobile/lib/theme_v2/library/library_hub.dart`
- Modify: `mobile/lib/theme_v2/library/theme_v2_library_page.dart`
- Modify: `mobile/lib/theme_v2/library/library_components.dart`
- Test: `mobile/test/theme_v2/library/library_controller_test.dart`
- Test: `mobile/test/theme_v2/library/library_repository_test.dart`
- Test: `mobile/test/theme_v2/library/theme_v2_library_navigation_test.dart`

**Interfaces:**
- Adds: `LibraryContainerType.report` and stable container ID `system:report`.
- Removes: the standalone `_ReportEntry` from `LibraryHub`.
- Preserves: `ReportContainerPage` as the container destination.

- [ ] **Step 1: Write failing model, persistence, and navigation tests**

Assert Report appears inside `allContainers`, is included in fresh defaults,
uses one of six pinned slots, can be removed/re-added, and opens the existing
Report container page when tapped.

- [ ] **Step 2: Run and verify RED**

Run: `cd mobile && flutter test test/theme_v2/library/library_controller_test.dart test/theme_v2/library/library_repository_test.dart test/theme_v2/library/theme_v2_library_navigation_test.dart`

Expected: FAIL because Report is not a `LibraryContainerSummary`.

- [ ] **Step 3: Integrate Report into the normal container pipeline**

Add the system summary and its report count, route the normal tile tap to
`ReportContainerPage`, remove `_ReportEntry`, and give Report the same layout,
pin, reorder, and unpin behavior as other system containers.

- [ ] **Step 4: Add a one-time default-pin preference migration**

Read the legacy key once. If no new-version key exists, insert `system:report`
into the bounded default order, persist the new key, and never force Report
back after the user removes it.

- [ ] **Step 5: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/theme_v2/library/library_models.dart mobile/lib/theme_v2/library/library_repository.dart mobile/lib/theme_v2/library/library_controller.dart mobile/lib/theme_v2/library/library_hub.dart mobile/lib/theme_v2/library/theme_v2_library_page.dart mobile/lib/theme_v2/library/library_components.dart mobile/test/theme_v2/library/library_controller_test.dart mobile/test/theme_v2/library/library_repository_test.dart mobile/test/theme_v2/library/theme_v2_library_navigation_test.dart
git commit -m "feat(library): make reports a configurable container"
```

### Task 4: Repair only known local acceptance pollution

**Files:**
- Modify: `theme_v2_service/scripts/repair_local_acceptance_data.py`
- Modify: `theme_v2_service/tests/unit/test_repair_local_acceptance_data.py`

**Interfaces:**
- Removes `acceptance_marker` and equivalent test-only keys only from local
  records whose skill schema excludes them.
- Is idempotent and supports `--dry-run`.

- [ ] **Step 1: Extend the failing repair test**

Assert the repair removes `acceptance_marker`, preserves valid running fields,
and makes no second-pass mutation.

- [ ] **Step 2: Run and verify RED**

Run: `docker compose -f docker-compose.theme-v2.yml run --rm test pytest tests/unit/test_repair_local_acceptance_data.py -q`

Expected: FAIL because the script does not repair the marker.

- [ ] **Step 3: Implement the bounded repair and dry-run report**

Do not rewrite arbitrary production payloads. Resolve each local record's
skill schema and remove only explicit test-only keys excluded by a closed
schema.

- [ ] **Step 4: Run and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add theme_v2_service/scripts/repair_local_acceptance_data.py theme_v2_service/tests/unit/test_repair_local_acceptance_data.py
git commit -m "chore(theme-v2): repair local acceptance payloads"
```

## Final Verification

- [ ] Run all focused backend tests from Tasks 1 and 4.
- [ ] Run all focused Flutter tests from Tasks 2 and 3.
- [ ] Rebuild the isolated Theme V2 service and migrate it to head.
- [ ] Open Library on the connected phone: Report is a normal pinned tile and
      can be removed/re-added without exceeding six.
- [ ] Open the running record: `acceptance_marker` is absent and valid fields remain.
- [ ] Generate one Report and open it through the normal Report container.
