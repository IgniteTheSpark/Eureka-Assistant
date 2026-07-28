# Theme V2 Calendar Revamp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Theme V2 Calendar with the Flow, Month, Year, Day Detail, Schedule, and Manual Record behavior defined by the 2026-07-29 Calendar handoff without regressing mature record/editor flows.

**Architecture:** Keep the existing Timeline and editor APIs, add explicit Calendar day projections and Calendar-local route state, and replace legacy Calendar UI with focused Theme V2 components. The app shell continues to own the floating dock; full editors and Flash routes use the existing Navigator.

**Tech Stack:** Flutter, Dart, Material, existing Theme V2 tokens, `flutter_test`, golden tests

## Global Constraints

- Only implement `spec/design/theme-v2-calendar-handoff.md` and Pencil Section `qIbQZ`.
- Do not modify Today, Goal, Library, Inbox, Device, Session, or non-Calendar UI.
- Preserve user-owned uncommitted design/spec files and stage exact implementation files only.
- Light and Dark must share one component tree.
- Minimum interactive target is `44 × 44`.
- Baseline viewport is `411 × 960`.
- Flow/Month/Year programmatic scale motion is 420 ms; sticky rail and draft motion are 260 ms; Picker close is 160 ms.
- Picker selection does not create a record; only editor save creates.
- Use device-local calendar dates; do not add an IANA timezone backend contract in this round.
- Follow strict red-green-refactor cycles and commit each independently testable task.

---

### Task 1: Calendar day projection, natural distance, and route state

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_models.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_components.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_controller.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_time_layout_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_mode_state_test.dart`

**Interfaces:**
- Produces: `CalendarDayData CalendarData.day(DateTime date)`
- Produces: `String calendarDistanceLabel(DateTime day, DateTime today)`
- Produces: `CalendarSurface`, `CalendarController.openDay`, `openSchedule`, `backToDay`, `backToOverview`
- Consumes: `TimelineItem.effectiveAt`, `CalendarRecord.fromTimeline`

- [ ] **Step 1: Write failing day-projection and formatter tests**

```dart
test('day projection keeps asset and flash counts independent', () {
  final day = DateTime(2026, 7, 3);
  final data = CalendarData([
    calendarFixtureItem(id: 'flash', at: day, kind: 'input_turn'),
  ], const {});
  expect(data.day(day).assetCount, 0);
  expect(data.day(day).flashCount, 1);
});

test('distance formatter uses stable calendar units', () {
  final today = DateTime(2026, 7, 30);
  expect(calendarDistanceLabel(today, today), 'TODAY');
  expect(calendarDistanceLabel(DateTime(2026, 7, 31), today), '1 DAY LATER');
  expect(calendarDistanceLabel(DateTime(2026, 7, 23), today), '1 WEEK AGO');
  expect(calendarDistanceLabel(DateTime(2026, 8, 30), today), '1 MONTH LATER');
  expect(calendarDistanceLabel(DateTime(2025, 7, 30), today), '1 YEAR AGO');
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_time_layout_test.dart test/theme_v2/calendar/calendar_mode_state_test.dart
```

Expected: compilation failures for `CalendarData.day`, `CalendarDayData`, or `CalendarSurface`.

- [ ] **Step 3: Implement the minimal projection, formatter, and route state**

```dart
enum CalendarSurface { overview, dayDetail, schedule }

class CalendarDayData {
  const CalendarDayData({
    required this.day,
    required this.assets,
    required this.flashes,
  });
  final DateTime day;
  final List<CalendarRecord> assets;
  final List<TimelineItem> flashes;
  int get assetCount => assets.length;
  int get flashCount => flashes.length;
}
```

`CalendarData.day` must read the existing immutable `byDay` bucket, exclude `input_turn` from Assets, and retain it in flashes. `CalendarController` must clear inline drafts when changing Calendar-local dates and must not change scale when opening Day Detail.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the command from Step 2.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/calendar_models.dart mobile/lib/theme_v2/calendar/calendar_components.dart mobile/lib/theme_v2/calendar/calendar_controller.dart mobile/test/theme_v2/calendar/calendar_time_layout_test.dart mobile/test/theme_v2/calendar/calendar_mode_state_test.dart
git commit -m "refactor(calendar): model handoff day and route state"
```

### Task 2: Replace Flow click rules and empty-day confirmation

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_sticky_date_rail.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`

**Interfaces:**
- Consumes: `CalendarData.day`, `CalendarController.openDay`
- Produces: `ValueChanged<DateTime> onRequestManualRecord`
- Produces: keys `calendar-empty-confirmation-YYYY-MM-DD` and `calendar-empty-manual-YYYY-MM-DD`

- [ ] **Step 1: Replace obsolete tests with failing handoff behavior**

```dart
testWidgets('populated date opens Day Detail on first tap', (tester) async {
  DateTime? opened;
  await tester.pumpWidget(flow(onOpenDay: (day) => opened = day));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('calendar-date-2026-07-03')));
  expect(opened, DateTime(2026, 7, 3));
});

testWidgets('empty date reveals Manual Record before opening picker', (tester) async {
  DateTime? requested;
  await tester.pumpWidget(flow(onRequestManualRecord: (day) => requested = day));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('calendar-date-2026-07-05')));
  await tester.pump();
  expect(find.byKey(const ValueKey('calendar-empty-confirmation-2026-07-05')), findsOneWidget);
  expect(requested, isNull);
  await tester.tap(find.byKey(const ValueKey('calendar-empty-manual-2026-07-05')));
  expect(requested, DateTime(2026, 7, 5));
});
```

Also assert `1 DAY LATER` exists and `+1 DAY` does not.

- [ ] **Step 2: Run Flow tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart
```

Expected: the first-tap and confirmation assertions fail against the current implementation.

- [ ] **Step 3: Implement Flow sibling layers and two-step empty action**

Use one ScrollController and one day sequence. Date rail plus Flash count must share the same `Transform.translate`. Give both the date label and content blank region a `HitTestBehavior.opaque` Day Detail action for populated days. Store only the currently confirmed empty date in Flow state; changing days replaces it.

The empty confirmation must render exactly:

```text
7月5日 · 暂无记录
手动记录
```

Do not render `空闲`, “再次点击”, or quick-create teaching copy.

- [ ] **Step 4: Run Flow tests and verify GREEN**

Run the command from Step 2.

Expected: all Flow tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/calendar_flow_view.dart mobile/lib/theme_v2/calendar/calendar_sticky_date_rail.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart
git commit -m "feat(calendar): align flow rail and empty-day actions"
```

### Task 3: Add handoff Day Detail

**Files:**
- Create: `mobile/lib/theme_v2/calendar/calendar_day_detail.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_day_detail_test.dart`

**Interfaces:**
- Consumes: `CalendarDayData`, `CalendarRecordRow`
- Produces: `CalendarDayDetail`
- Produces callbacks: `onBack`, `onOpenSchedule`, `onOpenFlash`, `onManualRecord`, `onOpenRecord`

- [ ] **Step 1: Write failing populated and Asset-empty tests**

```dart
testWidgets('Asset empty keeps Flash and independent actions', (tester) async {
  await tester.pumpWidget(dayDetail(assetCount: 0, flashCount: 5));
  expect(find.text('0 项记录'), findsOneWidget);
  expect(find.text('闪念 5'), findsOneWidget);
  expect(find.text('今天还没有记录'), findsOneWidget);
  expect(find.text('手动记录'), findsNWidgets(2));
  expect(find.text('日程'), findsOneWidget);
});

testWidgets('zero Flash remains actionable', (tester) async {
  var opened = false;
  await tester.pumpWidget(dayDetail(flashCount: 0, onOpenFlash: () => opened = true));
  await tester.tap(find.bySemanticsLabel('7月3日，0 条闪念，查看闪念'));
  expect(opened, isTrue);
});
```

Add band tests ensuring empty morning/afternoon/evening/omitted-time sections do not render and real sections preserve effective-time order.

- [ ] **Step 2: Run the new test and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_day_detail_test.dart
```

Expected: compilation failure because `calendar_day_detail.dart` does not exist.

- [ ] **Step 3: Implement Day Detail**

Build the handoff header, independent 44-pixel Manual/Schedule actions, always-visible Flash row, two-pixel time axis, and data-driven bands. Asset empty must depend only on `assets.isEmpty` and contain no tutorial copy.

Use these band rules:

```dart
String dayBand(CalendarRecord record) {
  if (!record.isTimed) return '没说时间';
  final hour = record.effectiveAt.hour;
  if (hour < 12) return '上午';
  if (hour < 18) return '下午';
  return '晚上';
}
```

- [ ] **Step 4: Run Day Detail tests and verify GREEN**

Run the command from Step 2.

Expected: all Day Detail tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/calendar_day_detail.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_day_detail_test.dart
git commit -m "feat(calendar): add handoff day detail"
```

### Task 4: Add Manual Record Skill Picker and editor dispatch

**Files:**
- Create: `mobile/lib/theme_v2/calendar/calendar_manual_record_picker.dart`
- Create: `mobile/lib/theme_v2/calendar/calendar_editor_router.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_manual_record_picker_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_editor_adapter_test.dart`

**Interfaces:**
- Produces: `CalendarSkillOption`
- Produces: `Future<List<CalendarSkillOption>> fetchCalendarSkillOptions(ApiClient api)`
- Produces: `Future<CalendarSkillOption?> showCalendarManualRecordPicker(...)`
- Produces: `Future<void> openCalendarSkillEditor(BuildContext, CalendarSkillOption, DateTime)`

- [ ] **Step 1: Write failing picker and adapter tests**

```dart
testWidgets('picker combines ordered system and custom skills', (tester) async {
  await tester.pumpWidget(picker(options: const [
    CalendarSkillOption.event(),
    CalendarSkillOption.asset(name: 'todo', displayName: '待办', userSkillId: 'todo-id'),
    CalendarSkillOption.asset(name: 'running', displayName: '跑步训练', userSkillId: 'run-id'),
  ]));
  expect(find.text('常用'), findsOneWidget);
  expect(find.text('全部 Skills'), findsOneWidget);
  expect(find.bySemanticsLabel('手动记录：跑步训练'), findsWidgets);
});

testWidgets('load failure remains in sheet and retries', (tester) async {
  expect(find.text('Skill 加载失败'), findsOneWidget);
  await tester.tap(find.text('重试'));
  expect(loadCount, 2);
});
```

Adapter tests must assert Event receives `presetDate`, Contact opens `ContactForm`, ordinary Skill opens `AssetEditPage` with the same `presetDate`, and no create API call happens before editor save.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_manual_record_picker_test.dart test/theme_v2/calendar/calendar_editor_adapter_test.dart
```

Expected: compilation failure for the new Picker and adapter types.

- [ ] **Step 3: Implement Picker repository, presentation, and dispatch**

Parse `/api/skills` in backend order, exclude disabled, `qa`, and `external_ref`, and add:

```dart
const CalendarSkillOption.event()
```

because Event is first-class and absent from `UserSkill`. Present a 630-pixel maximum bottom sheet with a blurred scrim, fixed common section, and internally scrollable two-column all-Skills grid. Long labels use one-line ellipsis while Semantics exposes the full label.

Dispatch:

```dart
switch (option.kind) {
  case CalendarSkillKind.event:
    return EventForm(presetDate: effectiveDate);
  case CalendarSkillKind.contact:
    return const ContactForm();
  case CalendarSkillKind.asset:
    return AssetEditPage(
      payload: const {},
      cardType: option.name,
      title: '',
      spec: option.renderSpec,
      displayName: option.displayName,
      presetDate: effectiveDate,
    );
}
```

- [ ] **Step 4: Run picker and adapter tests and verify GREEN**

Run the command from Step 2.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/calendar_manual_record_picker.dart mobile/lib/theme_v2/calendar/calendar_editor_router.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_manual_record_picker_test.dart mobile/test/theme_v2/calendar/calendar_editor_adapter_test.dart
git commit -m "feat(calendar): add manual record skill picker"
```

### Task 5: Align Schedule trays, same-time blocks, todo mutation, and draft

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_inline_draft.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_schedule_grid_test.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_inline_draft_test.dart`

**Interfaces:**
- Consumes: `CalendarDayData`, `layoutCalendarTime`, `CalendarController.inlineDraft`
- Produces: `CalendarScheduleView`
- Produces callback: `Future<void> Function(CalendarRecord) onToggleTodo`

- [ ] **Step 1: Write failing handoff Schedule tests**

Add tests that:

- zero all-day/untimed trays are absent;
- four untimed todos keep a 92-pixel tray and scroll internally;
- a meeting, training, and 3-todo band at the same time produce three non-overlapping blocks;
- expanded todos do not merge with neighboring events;
- inline draft displays `16:00–16:30`;
- draft failure retains Retry;
- tapping a todo checkbox invokes `onToggleTodo` with the individual record.

- [ ] **Step 2: Run Schedule tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_schedule_grid_test.dart test/theme_v2/calendar/calendar_inline_draft_test.dart
```

Expected: the fixed tray geometry, explicit time copy, or todo mutation assertions fail.

- [ ] **Step 3: Implement unified Schedule**

Keep the top bounds stable:

```dart
const allDayHeight = 54.0;
const unscheduledHeight = 92.0;
const hourGridHeight = 566.0;
```

Only allocate a tray when its count is nonzero. Give the unscheduled list its own vertical controller above three rows and retain horizontal PageView gestures. Use the existing overlap layout for independent blocks; represent a same-minute todo group as one layout record, then expand inside that block.

Todo completion calls the existing `/api/assets/{id}` payload patch and bumps `dataRevision`.

- [ ] **Step 4: Run Schedule tests and verify GREEN**

Run the command from Step 2.

Expected: all Schedule and inline-draft tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/calendar_schedule_grid.dart mobile/lib/theme_v2/calendar/calendar_inline_draft.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_schedule_grid_test.dart mobile/test/theme_v2/calendar/calendar_inline_draft_test.dart
git commit -m "feat(calendar): align schedule interactions and trays"
```

### Task 6: Align Month, Year, Calendar shell, and refresh persistence

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_month_view.dart`
- Modify: `mobile/lib/theme_v2/calendar/calendar_year_view.dart`
- Modify: `mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart`
- Test: `mobile/test/theme_v2/calendar/calendar_flow_test.dart`

**Interfaces:**
- Consumes: `CalendarController`, `CalendarData.day`
- Produces: stable Flow/Month/Year `PageView`
- Produces: stale-while-revalidate Calendar loading/error behavior

- [ ] **Step 1: Write failing navigation and persistence tests**

Add widget tests that:

- Month selection updates a real Asset summary and opens Day Detail without a second-tap hint;
- Year month selection changes focus month and scale;
- refresh preserves `CalendarMode.year`, selected date, and Flow controller identity;
- retry does not reset to Today;
- initial loading keeps Calendar structure keys mounted.

- [ ] **Step 2: Run Flow/shell tests and verify RED**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart
```

Expected: one-tap Month or refresh-persistence assertions fail.

- [ ] **Step 3: Implement Progressive Month/Year and stale refresh**

Keep the `PageController` and all three scale children mounted. Cache the last successful `CalendarData`; display skeleton/error only inside the active content region. Do not overlay a global “empty Calendar” message because empty dates are valid Flow content.

Programmatic scale changes use:

```dart
pages.animateToPage(
  mode.index,
  duration: ThemeV2Motion.duration(context, ThemeV2MotionToken.fluid),
  curve: ThemeV2Motion.easeFluid,
);
```

- [ ] **Step 4: Run Flow/shell tests and verify GREEN**

Run the command from Step 2.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar/calendar_month_view.dart mobile/lib/theme_v2/calendar/calendar_year_view.dart mobile/lib/theme_v2/calendar/theme_v2_calendar_page.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart
git commit -m "feat(calendar): finish progressive scales and stable refresh"
```

### Task 7: Replace golden coverage and audit accessibility

**Files:**
- Modify: `mobile/test/theme_v2/calendar/calendar_test_fixtures.dart`
- Modify: `mobile/test/theme_v2/calendar/theme_v2_calendar_golden_test.dart`
- Replace: `mobile/test/theme_v2/calendar/goldens/*.png`
- Modify as required: `mobile/lib/theme_v2/calendar/*.dart`

**Interfaces:**
- Consumes: completed Calendar surfaces
- Produces: 411-pixel Light/Dark regression images for every whitelist state

- [ ] **Step 1: Add all whitelist golden cases**

Create golden cases for:

- Flow resting and sticky threshold;
- Month and Year;
- populated and Asset-empty Day Detail;
- Schedule default, same-time expanded, and inline draft;
- Manual Record Picker;
- each case in Light and Dark at 411 by 960.

- [ ] **Step 2: Generate goldens**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/theme_v2_calendar_golden_test.dart --update-goldens
```

Expected: exit 0 and all expected PNGs updated.

- [ ] **Step 3: Inspect generated images against Pencil**

Compare each generated state against the matching whitelist node. Correct clipping, dock inset, rail alignment, sheet height, tray geometry, long-copy behavior, and Light/Dark token errors in production code rather than masking differences in test fixtures.

- [ ] **Step 4: Run goldens without update and accessibility tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/theme_v2_calendar_golden_test.dart test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart test/theme_v2/calendar/calendar_manual_record_picker_test.dart test/theme_v2/calendar/calendar_schedule_grid_test.dart
```

Expected: all tests pass and no semantics assertion is smaller than 44 pixels.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/theme_v2/calendar mobile/test/theme_v2/calendar
git commit -m "test(calendar): cover handoff states and accessibility"
```

### Task 8: Full verification, Android build, and real-device compatibility audit

**Files:**
- Modify only if verification exposes a Calendar regression.

**Interfaces:**
- Consumes: all completed Calendar tasks
- Produces: verified APK and real-device audit evidence

- [ ] **Step 1: Format and analyze exact Calendar changes**

Run:

```bash
cd mobile
dart format lib/theme_v2/calendar test/theme_v2/calendar
flutter analyze lib/theme_v2/calendar test/theme_v2/calendar
```

Expected: formatter exits 0; analyzer reports no issues.

- [ ] **Step 2: Run the full Calendar suite**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Build the Android debug APK**

Run:

```bash
cd mobile
flutter build apk --debug
```

Expected: exit 0 and `mobile/build/app/outputs/flutter-apk/app-debug.apk` exists.

- [ ] **Step 4: Install and launch on the connected Android device**

Run:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb reverse tcp:8000 tcp:8000
adb shell am force-stop com.eureka.mindapp
adb shell monkey -p com.eureka.mindapp -c android.intent.category.LAUNCHER 1
```

Expected: install success and the Theme V2 app launches.

- [ ] **Step 5: Execute the real-device checklist**

Verify:

- Flow rail, watermark, first-tap populated date, and two-step empty date;
- Month/Year swipe and Today reset;
- populated and Asset-empty Day Detail, including Flash 0 and Flash > 0;
- Picker open/close, scroll, error/retry seam, Event/Contact/Asset editor dispatch, and preset date;
- Schedule all-day, untimed internal scroll, overlap, same-time expanded todos, completion, inline draft cancel/retry/save;
- record detail for Event, Contact, Asset, and source-session fallback;
- refresh retains scale/date/scroll;
- dark mode and text scaling do not clip Calendar actions;
- no obsolete `+N DAY`, second-tap, quick-create, or “今天记一笔” copy;
- editors, Flash, and save-return refresh behavior from the mature Calendar remain reachable.

- [ ] **Step 6: Review the final diff and commit verification fixes**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace errors; only Calendar implementation/tests and the two approved planning documents are part of this work.

Stage only exact files changed by this plan and commit any final Calendar-only fixes.

