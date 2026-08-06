# Theme V2 Canonical Entity Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every built-in entity use one canonical icon on Today, Calendar, Library, Session cards, lists, and detail surfaces while preserving each custom Skill's configured icon.

**Architecture:** Move built-in icon identity into one dependency-light mobile resolver. All built-in presentation paths normalize through it after reading server metadata; custom Skills keep their configured render icon. Persisted Session cards include a display snapshot, but the mobile resolver remains the safe fallback for historical or incomplete cards.

**Tech Stack:** Dart, Flutter widget tests, Theme V2 FastAPI card DTOs, pytest.

## Global Constraints

- `docs/superpowers/specs/2026-08-05-theme-v2-legacy-agent-migration-design.md` is authoritative.
- Canonical built-ins are: Todo `📋`, Event `📅`, Contact `👤`, Notes `✍️`, Expense `💳`.
- Do not rewrite custom Skill icons or introduce a database uniqueness rule for presentation metadata.
- Preserve existing uncommitted edits in `mobile/lib/render/render_spec.dart`, `mobile/lib/theme_v2/library/library_repository.dart`, and their tests.
- Use test-first RED → GREEN cycles; stage only the intentional icon hunks.

---

### Task 1: Create one canonical built-in icon resolver

**Files:**
- Create: `mobile/lib/theme_v2/foundation/canonical_entity_identity.dart`
- Modify: `mobile/lib/timeline/timeline.dart`
- Modify: `mobile/lib/render/render_spec.dart`
- Test: `mobile/test/theme_v2/foundation/canonical_entity_identity_test.dart`
- Test: `mobile/test/timeline_theme_v2_service_regression_test.dart`

**Interfaces:**
- Produces: `canonicalEntityKey(String)` and `resolveEntityIcon(String, {String? configuredIcon})`.
- Produces: canonical icon constants without importing `timeline.dart` or `render_spec.dart`.
- Changes: `resolveMeta`, `synthesizeSpec`, `coreRecordRenderSpec`, and `buildCard` normalize built-in icons after server metadata is read.

- [x] **Step 1: Write failing resolver tests**

Assert aliases `calendar → event` and `idea|misc|note → notes`; assert a conflicting server icon cannot change built-in Contact/Expense; assert `running_training` retains `🏃`.

- [x] **Step 2: Run focused tests and verify RED**

```bash
cd mobile && flutter test \
  test/theme_v2/foundation/canonical_entity_identity_test.dart \
  test/timeline_theme_v2_service_regression_test.dart
```

- [x] **Step 3: Implement and adopt the resolver**

Keep the new module free of API/render dependencies so `timeline.dart` and `render_spec.dart` can both import it without a cycle. Replace the todo-only pin and the inline `✅ → 📋` rewrite with canonical normalization for every built-in.

- [x] **Step 4: Run focused tests and require GREEN**

Run the Step 2 command and require PASS.

### Task 2: Render canonical icons in every Library surface

**Files:**
- Modify: `mobile/lib/theme_v2/library/library_repository.dart`
- Modify: `mobile/lib/theme_v2/library/library_components.dart`
- Test: `mobile/test/theme_v2/library/library_repository_test.dart`
- Test: `mobile/test/theme_v2/library/library_components_test.dart`

**Interfaces:**
- `_mark(...)` normalizes system containers and keeps custom Skill icons.
- `_LibraryPinnedTile` visibly renders `container.mark` in every mosaic size.

- [x] **Step 1: Add failing repository and widget tests**

Cover conflicting server icons for Expense and Contact, a custom running icon, and visible icon keys on large/compact pinned tiles.

- [x] **Step 2: Run focused tests and verify RED**

```bash
cd mobile && flutter test \
  test/theme_v2/library/library_repository_test.dart \
  test/theme_v2/library/library_components_test.dart
```

- [x] **Step 3: Normalize repository marks and add the pinned-tile glyph**

Use container identity rather than label text. Keep count, configure controls, semantics, and mosaic geometry intact.

- [x] **Step 4: Run focused tests and require GREEN**

Run the Step 2 command and require PASS.

### Task 3: Persist and consume Session card display snapshots

**Files:**
- Create: `theme_v2_service/app/domains/capture/presenter.py`
- Modify: `theme_v2_service/app/domains/capture/jobs.py`
- Modify: `mobile/lib/theme_v2/capture/capture_session_controller.dart`
- Test: `theme_v2_service/tests/unit/test_capture_presenter.py`
- Test: `theme_v2_service/tests/integration/test_capture_jobs.py`
- Test: `mobile/test/theme_v2/capture/capture_session_page_test.dart`

**Interfaces:**
- Produces: `present_capture_result(...) -> list[dict]` with `card_type`, `title`, `subtitle`, `icon`, `accent_color`, provenance, and live entity reference.
- Persisted cards stay readable if a later skill lookup fails or an entity is deleted.

- [x] **Step 1: Write failing presenter/card reload tests**

Assert Expense and Contact cards carry `💳` and `👤`; assert custom cards use their `render_spec_json.icon`; assert a historical card renders from its snapshot without refetching Skill metadata.

- [x] **Step 2: Run backend and Flutter tests and verify RED**

```bash
docker compose -f docker-compose.theme-v2.yml run --rm -w /app test \
  python -m pytest -q tests/unit/test_capture_presenter.py tests/integration/test_capture_jobs.py
cd mobile && flutter test test/theme_v2/capture/capture_session_page_test.dart
```

- [x] **Step 3: Implement the Theme V2 presenter and snapshot adapter**

Do not let presentation failure roll back a successful domain mutation. Fall back to source text plus canonical identity and retain the live `asset_id`, `event_id`, or `contact_id` for navigation.

- [x] **Step 4: Run tests and require GREEN**

Run the Step 2 commands and require PASS.

### Task 4: Cross-surface regression and device acceptance

**Files:**
- Modify only when a failing test requires it: files from Tasks 1–3.

- [x] **Step 1: Run Home, Calendar, Library, Session, list, and detail suites**

```bash
cd mobile && flutter test \
  test/theme_v2/home/theme_v2_asset_bubble_field_test.dart \
  test/theme_v2/calendar/calendar_flow_test.dart \
  test/theme_v2/library/library_components_test.dart \
  test/theme_v2/library/library_repository_test.dart \
  test/theme_v2/library/asset/asset_record_test.dart \
  test/theme_v2/capture/capture_session_page_test.dart
```

- [x] **Step 2: Analyze touched Dart files**

```bash
cd mobile && flutter analyze \
  lib/theme_v2/foundation/canonical_entity_identity.dart \
  lib/timeline/timeline.dart \
  lib/render/render_spec.dart \
  lib/theme_v2/library/library_repository.dart \
  lib/theme_v2/library/library_components.dart
```

- [ ] **Step 3: Install on the connected phone and verify five surfaces**

Verify Expense and Contact on Today bubbles, Calendar flow/day detail, Library mosaic/directory/recent/list/detail, and a reloaded Flash Session card. Verify the running custom Skill still uses its own icon.

- [ ] **Step 4: Commit only the completed icon vertical slice**

Do not include Pen changes or unrelated existing mobile edits.
