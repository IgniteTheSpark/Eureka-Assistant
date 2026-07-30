# Theme V2 Search, Asset Icons, and Manual Recents Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the non-functional Session search affordance, make every Asset surface use one canonical Skill emoji, and replace the manual-record picker's static “常用” section with the current user's four most recently manually created Skills.

**Architecture:** Keep `/api/skills` as the canonical Skill catalog and add a small user-scoped `/api/skills/recent-manual` read model derived from persisted Assets, Events, and Contacts. Flutter joins the recent machine names back to the eligible catalog instead of persisting device-local usage. A shared Flutter resolver owns Asset identity for Calendar and Library surfaces, while first-class Event/Contact fallback icons are mirrored by the asset-detail backend envelope.

**Tech Stack:** Flutter/Dart widget and unit tests, FastAPI, SQLAlchemy async ORM, MySQL-backed contract scripts, Docker Compose.

---

## Product invariants

- Do not add Asset/global search. Keep the real Library filtering and attendee search.
- Do not restore Reports/总结 or external tasks.
- Flash is not an Asset Skill and keeps its lightning icon.
- Custom Asset icon is `UserSkill.render_spec.icon`; built-in fallbacks are:
  - Event `📅`
  - Contact `👤`
  - Todo `📋`
  - Notes/legacy idea/misc `✍️`
- “最近” contains up to four distinct, currently eligible Skills ordered by newest successful manual creation.
- A manual creation counts only after an Asset/Event/Contact row has persisted.
- Flash/agent-created rows, report-created rows, external calendar rows, edits, failed creates, and cancelled creates do not count.
- Recent history is derived, user-scoped, and cross-device. Deleting the last qualifying row for a Skill removes that Skill from the derived list.
- If the recent endpoint alone fails, show `最近暂不可用` and keep the full catalog usable.
- If no qualifying recent Skill exists, show `暂无`.

## Task 1: Remove the fake Session history search

**Files:**

- Modify: `mobile/test/theme_v2/session/session_state_test.dart`
- Modify: `mobile/lib/theme_v2/session/session_history_drawer.dart`

### Step 1: Write the failing widget assertion

Extend the existing history-width test so the drawer must not expose a `TextField` or the `搜索` label:

```dart
expect(find.byType(TextField), findsNothing);
expect(find.text('搜索'), findsNothing);
```

Keep the existing width and close-action assertions so removing the field cannot regress the drawer shell.

### Step 2: Run the focused test and confirm RED

Run:

```bash
cd mobile
flutter test test/theme_v2/session/session_state_test.dart
```

Expected: failure because the current read-only search `TextField` is still present.

### Step 3: Remove only the fake search affordance

Delete the read-only `TextField` block from `SessionHistoryDrawer`. Preserve the title, close button, base spacing, list, empty state, and all navigation behavior.

### Step 4: Run the focused test and confirm GREEN

Run:

```bash
cd mobile
flutter test test/theme_v2/session/session_state_test.dart
```

Expected: all Session state tests pass.

### Step 5: Commit

```bash
git add mobile/lib/theme_v2/session/session_history_drawer.dart mobile/test/theme_v2/session/session_state_test.dart
git commit -m "fix(theme-v2): remove fake session search"
```

## Task 2: Centralize Flutter Asset icon resolution

**Files:**

- Modify: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`
- Modify: `mobile/test/theme_v2/calendar/calendar_day_detail_test.dart`
- Modify: `mobile/lib/timeline/timeline.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_components.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_day_detail.dart`

### Step 1: Write failing Calendar icon tests

Add a custom Skill fixture with:

```dart
'feeding': const SkillMeta('🍼', '宝贝饮食', 'amber')
```

Render a Calendar Asset whose `skillName` is `feeding`, then assert:

```dart
expect(find.text('🍼'), findsOneWidget);
expect(find.byIcon(Icons.note_outlined), findsNothing);
```

Add focused assertions for Event `📅`, Todo `📋`, and Contact `👤`. Preserve a separate Flash assertion for `Icons.bolt_outlined` so Asset refactoring cannot change Flash identity.

### Step 2: Run the focused tests and confirm RED

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart
```

Expected: Flow/custom Asset fails because `CalendarRecordRow` ignores the registry and renders `Icons.note_outlined`.

### Step 3: Add one public canonical resolver

In `mobile/lib/timeline/timeline.dart`, keep `resolveMeta` as the canonical machine-name resolver and add an item-aware helper:

```dart
SkillMeta resolveTimelineItemMeta(
  TimelineItem item,
  Map<String, SkillMeta> registry,
) {
  if (item.kind == 'event') return resolveMeta('event', registry);
  if (item.kind == 'contact') return resolveMeta('contact', registry);
  final skillName = item.skillName?.trim();
  if (skillName != null && skillName.isNotEmpty) {
    return resolveMeta(skillName, registry);
  }
  return const SkillMeta('•', '记录');
}
```

Do not pass Flash/input-turn rows through this helper; Flash remains a separate entity presentation.

### Step 4: Use the resolver in shared Calendar rows

In `CalendarRecordRow`:

- keep `Icons.bolt_outlined` only for `input_turn`;
- otherwise render `Text(resolveTimelineItemMeta(item, skills).icon)`;
- retain existing timing, semantics, muted color, title truncation, and hit target.

Update the Day detail row to call the same resolver rather than duplicating Event/Contact/custom switches.

### Step 5: Run Calendar tests and confirm GREEN

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart test/theme_v2/calendar/calendar_schedule_grid_test.dart
```

Expected: custom and built-in Asset emoji are consistent; Flash remains lightning.

### Step 6: Commit

```bash
git add mobile/lib/timeline/timeline.dart mobile/lib/theme_v2/calendar/calendar_components.dart mobile/lib/theme_v2/calendar/calendar_day_detail.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart mobile/test/theme_v2/calendar/calendar_day_detail_test.dart
git commit -m "refactor(theme-v2): centralize calendar asset icons"
```

## Task 3: Align Library cards and asset-detail envelopes

**Files:**

- Modify: `mobile/test/theme_v2/library/asset/asset_record_test.dart`
- Modify: `mobile/test/theme_v2/library/asset/asset_list_page_test.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_record.dart`
- Modify: `mobile/lib/theme_v2/library/asset/asset_list_page.dart`
- Modify: `backend/scripts/test_asset_detail_contract.py`
- Modify: `backend/api/asset_details.py`

### Step 1: Write failing Library adapter tests

Add assertions that first-class adapters and list headers use the canonical fallbacks:

```dart
expect(event.card.mark, '📅');
expect(contact.card.mark, '👤');
```

Retain an existing custom Asset fixture with an explicit `render_spec.icon`, and assert the adapter does not substitute a generic glyph.

### Step 2: Extend the backend detail contract first

In `backend/scripts/test_asset_detail_contract.py`, seed one Event and one Contact for the contract user. Call:

```text
GET /api/asset-details/event/{event_id}
GET /api/asset-details/contact/{contact_id}
```

Assert:

```python
assert event_body["skill"]["icon"] == "📅"
assert contact_body["skill"]["icon"] == "👤"
```

Keep the existing custom Asset assertion that its envelope icon comes from `UserSkill.render_spec.icon`.

### Step 3: Run focused tests and confirm RED

Run:

```bash
cd mobile
flutter test test/theme_v2/library/asset/asset_record_test.dart test/theme_v2/library/asset/asset_list_page_test.dart
cd ../backend
docker compose exec -T backend python -m scripts.test_asset_detail_contract
```

Expected: Event/Contact fail on the old `▣`/`♙` marks.

### Step 4: Replace duplicate first-class glyphs

Change the Flutter Event and Contact adapter marks to `📅` and `👤`. Ensure list-page fallbacks use the same constants. Do not change the custom Asset path: it must continue to read `RenderSpec.icon`.

Change the backend detail envelope to return:

```python
"icon": "📅"  # event
"icon": "👤"  # contact
```

### Step 5: Run focused tests and confirm GREEN

Run:

```bash
cd mobile
flutter test test/theme_v2/library/asset/asset_record_test.dart test/theme_v2/library/asset/asset_list_page_test.dart
cd ../backend
docker compose exec -T backend python -m scripts.test_asset_detail_contract
```

Expected: Library list, detail envelope, and Calendar now share the same identity rules.

### Step 6: Commit

```bash
git add mobile/lib/theme_v2/library/asset/asset_record.dart mobile/lib/theme_v2/library/asset/asset_list_page.dart mobile/test/theme_v2/library/asset/asset_record_test.dart mobile/test/theme_v2/library/asset/asset_list_page_test.dart backend/api/asset_details.py backend/scripts/test_asset_detail_contract.py
git commit -m "fix(theme-v2): unify asset identity icons"
```

## Task 4: Add the derived recent-manual Skills endpoint

**Files:**

- Create: `backend/scripts/test_manual_skill_recents.py`
- Modify: `backend/api/skills.py`

### Step 1: Write the failing backend contract

Create a self-cleaning ASGI contract script that:

1. creates two isolated test users;
2. provisions at least five eligible `GlobalSkill`/`UserSkill` pairs with unique names;
3. inserts manual Assets with controlled `created_at` timestamps;
4. inserts a manual Event and manual Contact;
5. inserts exclusions:
   - Asset with `source_input_turn_id`;
   - Asset with `source_report_id`;
   - Event with `source_input_turn_id`;
   - Event with `sync_source='google'`;
   - Contact with `source_input_turn_id`;
6. calls `/api/skills/recent-manual` with the first user's auth override;
7. asserts newest-first distinct names, a maximum of four, and no excluded records;
8. calls the endpoint as the second user and asserts no cross-user leakage;
9. deletes all seeded rows in foreign-key-safe order in `finally`.

Expected response:

```json
{"ok": true, "skill_names": ["contact", "event", "skill_b", "skill_a"]}
```

The exact test timestamps must make this order deterministic.

### Step 2: Run the contract and confirm RED

Run:

```bash
cd backend
docker compose exec -T backend python -m scripts.test_manual_skill_recents
```

Expected: 404 because the endpoint does not exist.

### Step 3: Implement the derived query

In `backend/api/skills.py`:

- import `Event` and `Contact`;
- define `_RECENT_MANUAL_LIMIT = 4`;
- declare `@router.get("/skills/recent-manual")` before dynamic `/skills/{...}` routes;
- select `GlobalSkill.name` and `max(Asset.created_at)` for the current user where:

```python
Asset.source_input_turn_id.is_(None)
Asset.source_report_id.is_(None)
```

- select `max(Event.created_at)` for the current user where:

```python
Event.source_input_turn_id.is_(None)
or_(Event.sync_source.is_(None), Event.sync_source == "manual")
```

- select `max(Contact.created_at)` for the current user where:

```python
Contact.source_input_turn_id.is_(None)
```

- merge tuples `(machine_name, timestamp)`, sort by timestamp descending and machine name ascending as the deterministic tie-breaker, deduplicate by machine name, take four, and return `{"ok": True, "skill_names": names}`.

Return machine names only; do not duplicate display names or icons from `/api/skills`.

### Step 4: Run the contract and confirm GREEN

Run:

```bash
cd backend
docker compose exec -T backend python -m scripts.test_manual_skill_recents
```

Expected: exact ordering, exclusions, cap, and user isolation pass.

### Step 5: Commit

```bash
git add backend/api/skills.py backend/scripts/test_manual_skill_recents.py
git commit -m "feat(skills): expose recent manual creations"
```

## Task 5: Replace “常用” with the resilient “最近” catalog

**Files:**

- Modify: `mobile/test/theme_v2/calendar/calendar_manual_record_picker_test.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_manual_record_picker.dart`
- Modify call sites found by: `rg -n "CalendarSkillLoader|fetchCalendarSkillOptions|showCalendarManualRecordPicker" mobile/lib mobile/test`

### Step 1: Write failing pure and widget tests

Introduce a catalog model in the test:

```dart
const CalendarSkillCatalog(
  options: options,
  recentNames: ['coffee', 'todo', 'coffee', 'missing', 'event'],
)
```

Assert:

- the recent join preserves server order;
- duplicate `coffee` is removed;
- `missing` is omitted and not backfilled;
- no more than four eligible cards render;
- the section label is `最近`;
- recent cards render in one four-column row;
- the full `全部 Skills` grid remains unchanged;
- empty recents render `暂无`;
- `recentUnavailable: true` renders `最近暂不可用`;
- a partial recent failure does not render the full-sheet `Skill 加载失败`;
- a catalog failure still renders the existing retry state.

Update existing loader tests from `Future<List<CalendarSkillOption>>` to `Future<CalendarSkillCatalog>`.

### Step 2: Run the focused test and confirm RED

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_manual_record_picker_test.dart
```

Expected: compile/assertion failures because the catalog model and “最近” state do not exist.

### Step 3: Add the catalog model and parsers

Add:

```dart
@immutable
class CalendarSkillCatalog {
  const CalendarSkillCatalog({
    required this.options,
    this.recentNames = const [],
    this.recentUnavailable = false,
  });

  final List<CalendarSkillOption> options;
  final List<String> recentNames;
  final bool recentUnavailable;
}
```

Add a parser that accepts only non-empty strings from `skill_names`, preserves order, deduplicates, and caps at four.

Add a join helper that maps names to the currently eligible `CalendarSkillOption`s from `parseCalendarSkillOptions`. It must not fill holes with other catalog entries.

Change:

```dart
typedef CalendarSkillLoader = Future<CalendarSkillCatalog> Function();
```

### Step 4: Fetch catalog and recents with partial-failure semantics

Replace `fetchCalendarSkillOptions` with:

```dart
Future<CalendarSkillCatalog> fetchCalendarSkillCatalog(ApiClient api) async {
  final options = parseCalendarSkillOptions(await api.getJson('/api/skills'));
  try {
    final response = await api.getJson('/api/skills/recent-manual');
    return CalendarSkillCatalog(
      options: options,
      recentNames: parseRecentManualSkillNames(response),
    );
  } catch (_) {
    return CalendarSkillCatalog(
      options: options,
      recentUnavailable: true,
    );
  }
}
```

The catalog request is required and keeps the existing retry behavior. Only the recent request is best-effort.

### Step 5: Implement the one-row recent section

Update the `FutureBuilder` and `_PickerContent` to consume `CalendarSkillCatalog`.

Render:

- `_SectionLabel('最近')`;
- `暂无` for an empty successful result;
- `最近暂不可用` for partial failure;
- otherwise a non-scrollable `Row`/four-column grid, one row only, with `Expanded` compact tiles;
- maximum four items;
- no generated placeholders;
- the existing two-column scrollable `全部 Skills` grid below.

Recent cards and full-catalog cards must pass the exact same `CalendarSkillOption` to `onSelected`.

### Step 6: Update all call sites

Change every production caller from `fetchCalendarSkillOptions(api)` to `fetchCalendarSkillCatalog(api)`. Do not add a post-create local mutation; reopening the picker re-derives state from successfully persisted backend rows.

### Step 7: Run focused tests and confirm GREEN

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_manual_record_picker_test.dart
```

Expected: ordering, cap, empty, partial error, full error, selection, and mascot lifecycle pass.

### Step 8: Commit

```bash
git add mobile/lib/theme_v2/calendar/calendar_manual_record_picker.dart mobile/test/theme_v2/calendar/calendar_manual_record_picker_test.dart
git add $(rg -l "fetchCalendarSkillCatalog" mobile/lib)
git commit -m "feat(theme-v2): show recent manual skills"
```

## Task 6: Regression, static analysis, and device verification

**Files:**

- Modify only if failures reveal an in-scope regression.

### Step 1: Format changed Dart files

Run:

```bash
cd mobile
dart format lib/timeline/timeline.dart lib/theme_v2/session/session_history_drawer.dart lib/theme_v2/calendar/calendar_components.dart lib/theme_v2/calendar/calendar_day_detail.dart lib/theme_v2/calendar/calendar_manual_record_picker.dart lib/theme_v2/library/asset/asset_record.dart lib/theme_v2/library/asset/asset_list_page.dart test/theme_v2/session/session_state_test.dart test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart test/theme_v2/calendar/calendar_manual_record_picker_test.dart test/theme_v2/library/asset/asset_record_test.dart test/theme_v2/library/asset/asset_list_page_test.dart
```

### Step 2: Run the Theme V2 regression set

Run:

```bash
cd mobile
flutter test test/theme_v2/session test/theme_v2/calendar test/theme_v2/library
```

Expected: all tests pass. Update a golden only when the changed UI is intentional and inspect both light and dark images before accepting it.

### Step 3: Run backend contracts

Run:

```bash
cd backend
docker compose exec -T backend python -m scripts.test_manual_skill_recents
docker compose exec -T backend python -m scripts.test_asset_detail_contract
docker compose exec -T backend python -m scripts.test_unified_asset_provenance
```

Expected: all contracts pass.

### Step 4: Run static analysis

Run:

```bash
cd mobile
flutter analyze lib/timeline/timeline.dart lib/theme_v2/session/session_history_drawer.dart lib/theme_v2/calendar lib/theme_v2/library/asset test/theme_v2/session/session_state_test.dart test/theme_v2/calendar test/theme_v2/library/asset
```

Expected: no errors or warnings introduced by this change.

### Step 5: Build and install on the connected Android device

Run:

```bash
cd mobile
flutter devices
flutter build apk --debug
```

If device `RFCY71B21YK` is connected:

```bash
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
$ADB -s RFCY71B21YK install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s RFCY71B21YK reverse tcp:8000 tcp:8000
$ADB -s RFCY71B21YK shell am force-stop com.eureka.mindapp
$ADB -s RFCY71B21YK shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Verify on-device:

1. Session history has no fake search field and retains normal spacing.
2. The same custom Asset shows the same emoji in Flow, Month/day detail, Library list, and detail.
3. Event, Contact, Todo, Notes, and Flash use their expected identities.
4. A new account initially shows `最近 / 暂无`.
5. Successfully create five distinct manual records; reopening the picker shows only the newest four distinct Skills in one row.
6. Cancelled and failed creation do not change recents.
7. Flash-created and externally synced records do not enter recents.
8. The full Skill catalog remains usable if the recent endpoint is temporarily unavailable.
9. Reports/总结 and external tasks remain hidden.

### Step 6: Inspect the final diff and commit any verification-only fixes

Run:

```bash
git status --short
git diff --check
git diff --stat
```

Stage only files belonging to this implementation; leave all pre-existing unrelated design/spec changes untouched.

