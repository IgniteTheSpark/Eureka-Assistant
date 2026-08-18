# Cross-Day Event Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correctly create one event from context-dependent cross-midnight voice ranges and project that event into every covered date in the Theme V2 Calendar Flow.

**Architecture:** The flash event skill resolves implicit clock ranges along a forward timeline, while the event MCP tool provides a deterministic 12-hour roll-forward safety net only when the end period/date was implicit. The persisted timeline remains canonical and unique; Flutter derives read-only `CalendarFlowSlice` values per visible date without duplicating events.

**Tech Stack:** Python 3, Google ADK/MCP tools, SQLAlchemy, Dart 3, Flutter widget tests.

## Global Constraints

- Timed event intervals use `[start_at, end_at)` semantics.
- Persist exactly one event and one `event_id`; never persist display slices.
- A complete start/end range must not fall back to todo when event creation fails.
- Explicit date/period words override automatic nearest-clock inference.
- Only Calendar Flow gains cross-day projection in this change; month and year views keep their existing data buckets.
- No new runtime dependency.

---

## File Structure

- `backend/mcp_server/tools.py`: pure forward-end normalization and final event-range validation.
- `backend/mcp_server/server.py`: exposes the opt-in `roll_forward_end` MCP argument.
- `backend/skills/flash-event-skill/SKILL.md`: source-text rules and examples for implicit end clocks.
- `backend/agents/intent_normalizer.py`: shared complete-range predicate.
- `backend/agents/flash_pipeline.py`: prevents ranged events from degrading to todo and preserves actionable error text.
- `backend/scripts/test_cross_day_event_contract.py`: executable backend regression contract.
- `mobile/lib/theme_v2/calendar/calendar_models.dart`: immutable flow-only slice projection.
- `mobile/lib/theme_v2/calendar/calendar_flow_view.dart`: consumes projected slices and renders continuation labels.
- `mobile/lib/theme_v2/calendar/calendar_components.dart`: optional row time/continuation presentation inputs.
- `mobile/test/theme_v2/calendar/calendar_time_layout_test.dart`: pure projection tests.
- `mobile/test/theme_v2/calendar/calendar_flow_test.dart`: widget display and shared-detail identity tests.

---

### Task 1: Normalize implicit event end clocks along a forward timeline

**Files:**
- Modify: `backend/mcp_server/tools.py:779`
- Modify: `backend/mcp_server/server.py:305`
- Modify: `backend/skills/flash-event-skill/SKILL.md:74`
- Create: `backend/scripts/test_cross_day_event_contract.py`

**Interfaces:**
- Produces: `_normalize_event_end(start_dt: datetime, end_dt: datetime, *, roll_forward_end: bool) -> datetime`.
- Produces: optional `roll_forward_end: int = 0` on `create_event` and `tool_create_event`.
- Consumes: existing ISO-8601 parsing and Asia/Shanghai fallback in `create_event`.

- [ ] **Step 1: Write the failing pure normalization tests**

Create `backend/scripts/test_cross_day_event_contract.py` with direct assertions:

```python
from datetime import datetime, timedelta, timezone

from mcp_server.tools import _normalize_event_end

CN = timezone(timedelta(hours=8))


def dt(hour: int, day: int = 18) -> datetime:
    return datetime(2026, 8, day, hour, tzinfo=CN)


def test_nearest_implicit_end_rolls_in_twelve_hour_steps() -> None:
    assert _normalize_event_end(dt(23), dt(12), roll_forward_end=True) == dt(0, 19)
    assert _normalize_event_end(dt(23), dt(2), roll_forward_end=True) == dt(2, 19)
    assert _normalize_event_end(dt(11), dt(12), roll_forward_end=True) == dt(12)
    assert _normalize_event_end(dt(11), dt(2), roll_forward_end=True) == dt(14)


def test_explicit_invalid_end_is_rejected() -> None:
    try:
        _normalize_event_end(dt(23), dt(14), roll_forward_end=False)
    except ValueError as error:
        assert str(error) == "invalid_event_range"
    else:
        raise AssertionError("explicit non-forward range must fail")


if __name__ == "__main__":
    test_nearest_implicit_end_rolls_in_twelve_hour_steps()
    test_explicit_invalid_end_is_rejected()
    print("ok - cross-day event range contract")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && python scripts/test_cross_day_event_contract.py`

Expected: FAIL with `ImportError: cannot import name '_normalize_event_end'`.

- [ ] **Step 3: Implement the pure normalization helper**

Add before `create_event` in `backend/mcp_server/tools.py`:

```python
from datetime import timedelta


def _normalize_event_end(start_dt, end_dt, *, roll_forward_end: bool):
    if end_dt > start_dt:
        return end_dt
    if not roll_forward_end:
        raise ValueError("invalid_event_range")
    candidate = end_dt
    while candidate <= start_dt:
        candidate += timedelta(hours=12)
    return candidate
```

Call it after both datetimes have timezones. Extend `create_event` with a final keyword parameter `roll_forward_end: int = 0`. On `ValueError`, return:

```python
return _err(
    "invalid_event_range: end_at must be later than start_at; "
    "resolve an implicit end clock to its nearest later occurrence"
)
```

- [ ] **Step 4: Expose the opt-in MCP argument without changing manual API behavior**

Add the final argument to `tool_create_event` and forward it by keyword:

```python
roll_forward_end: int = 0,
```

Document it as `1 only when source_text omitted the end date and end period`. The REST `/api/events` endpoint continues omitting it, so manually submitted invalid ranges are rejected instead of guessed.

- [ ] **Step 5: Update the event skill contract and examples**

Replace the same-day-only rule with:

```markdown
- 先解析 start_at，再沿时间轴向后解析 end_at。
- 结束钟点没有日期/上午下午信息时，选择 start_at 之后最近的合理出现，并在 tool_create_event 传 roll_forward_end=1。
- 明确说了日期或上午/下午/晚上时，传 roll_forward_end=0，严格使用明确语义。
- 「晚上11点到12点」→ 23:00 到次日 00:00。
- 「晚上11点到2点」→ 23:00 到次日 02:00。
```

Update the create-call documentation so the agent always passes `roll_forward_end` explicitly.

- [ ] **Step 6: Run backend normalization and existing attendee contracts**

Run:

```bash
cd backend
python scripts/test_cross_day_event_contract.py
python scripts/test_flash_event_attendees_contract.py
python scripts/test_event_card_contract.py
```

Expected: all scripts print `ok` and exit 0.

- [ ] **Step 7: Commit Task 1**

```bash
git add backend/mcp_server/tools.py backend/mcp_server/server.py backend/skills/flash-event-skill/SKILL.md backend/scripts/test_cross_day_event_contract.py
git commit -m "fix(events): resolve implicit end clocks forward"
```

---

### Task 2: Keep complete event ranges out of the todo fallback and expose failures

**Files:**
- Modify: `backend/agents/intent_normalizer.py:20`
- Modify: `backend/agents/flash_pipeline.py:607`
- Modify: `backend/scripts/test_cross_day_event_contract.py`

**Interfaces:**
- Produces: `has_complete_time_range(source_text: str) -> bool`.
- Produces: `event_failure_should_fallback_to_todo(source_text: str) -> bool`.
- Consumes: the existing `_RANGE_RE` grammar used to route ranged custom skills to events.

- [ ] **Step 1: Add failing predicate and summary tests**

Extend `backend/scripts/test_cross_day_event_contract.py`:

```python
from agents.intent_normalizer import (
    event_failure_should_fallback_to_todo,
    has_complete_time_range,
)


def test_complete_ranges_never_fall_back_to_todo() -> None:
    source = "今天晚上11点到12点有一个线上会议"
    assert has_complete_time_range(source)
    assert not event_failure_should_fallback_to_todo(source)
    assert event_failure_should_fallback_to_todo("明天晚上8点开会")
```

Call this new test from the script's existing `if __name__ == "__main__"` block. Add an AST/static assertion that `flash_pipeline.py` calls `event_failure_should_fallback_to_todo(source)` in its `itype == "event"` branch and retains the event error for complete ranges.

- [ ] **Step 2: Run the contract to verify it fails**

Run: `cd backend && python scripts/test_cross_day_event_contract.py`

Expected: FAIL because both public predicates are absent.

- [ ] **Step 3: Implement the shared range predicates**

Add to `backend/agents/intent_normalizer.py`:

```python
def has_complete_time_range(source_text: str) -> bool:
    return bool(_RANGE_RE.search(source_text or ""))


def event_failure_should_fallback_to_todo(source_text: str) -> bool:
    return not has_complete_time_range(source_text)
```

Use `has_complete_time_range` inside `_normalize_scheduled_custom_intent` so routing and fallback share one definition.

- [ ] **Step 4: Restrict the pipeline fallback**

Import `event_failure_should_fallback_to_todo`. Replace the unconditional event-to-todo fallback with:

```python
if itype == "event" and not result.get("event_id"):
    if event_failure_should_fallback_to_todo(source):
        fallback_intent = {"type": "todo", "source_text": source}
        return await _run_intent(
            fallback_intent, user_text, session_id, source_input_turn_id,
            today_str, user_id,
        )
    result["ok"] = False
    result["skill"] = "event-skill"
    result["error"] = (
        result.get("error")
        or "无法确定日程的有效结束时间，请补充结束时间语境"
    )
```

- [ ] **Step 5: Preserve the actionable error as the completion summary**

Before calling `generate_flash_summary` in `_aggregate`, collect failed result messages. When at least one exists, use its first concrete `error`/`message` as `summary`; only call the reply agent when there are no failures. This ensures the session shows the reason even when error cards are not rendered as assets.

```python
errors = [
    (r.get("error") or r.get("message") or "").strip()
    for r in asset_results if not r.get("ok")
]
errors = [message for message in errors if message]
summary = errors[0] if errors else await generate_flash_summary(...)
```

- [ ] **Step 6: Run the backend regression suite**

Run:

```bash
cd backend
python scripts/test_cross_day_event_contract.py
python scripts/test_intent_normalizer.py
python scripts/test_flash_reply_agent.py
python scripts/test_event_card_contract.py
```

Expected: all scripts exit 0; the cross-day contract confirms ranged events stay events.

- [ ] **Step 7: Commit Task 2**

```bash
git add backend/agents/intent_normalizer.py backend/agents/flash_pipeline.py backend/scripts/test_cross_day_event_contract.py
git commit -m "fix(flash): preserve ranged event failures"
```

---

### Task 3: Project canonical events into per-day Calendar Flow slices

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_models.dart:9`
- Modify: `mobile/test/theme_v2/calendar/calendar_time_layout_test.dart:68`

**Interfaces:**
- Produces: immutable `CalendarFlowSlice` with `record`, `day`, `visibleStart`, `visibleEnd`, `continuesFromPreviousDay`, and `continuesIntoNextDay`.
- Produces: `CalendarData.flowByDay: Map<DateTime, List<CalendarFlowSlice>>`.
- Consumes: canonical `CalendarRecord` and half-open event interval.

- [ ] **Step 1: Write failing pure projection tests**

Add a `Calendar Flow slices` group to `calendar_time_layout_test.dart`:

```dart
test('midnight end belongs only to the starting day', () {
  final data = CalendarData([
    item(
      id: 'event-midnight',
      at: DateTime(2026, 8, 18, 23),
      endAt: DateTime(2026, 8, 19),
    ),
  ], const {});

  expect(data.flowByDay[DateTime(2026, 8, 18)], hasLength(1));
  expect(data.flowByDay[DateTime(2026, 8, 19)], isNull);
});

test('cross-midnight event creates two slices with one identity', () {
  final data = CalendarData([
    item(
      id: 'event-cross-day',
      at: DateTime(2026, 8, 18, 23),
      endAt: DateTime(2026, 8, 19, 2),
    ),
  ], const {});

  final first = data.flowByDay[DateTime(2026, 8, 18)]!.single;
  final second = data.flowByDay[DateTime(2026, 8, 19)]!.single;
  expect(first.record.id, second.record.id);
  expect(first.continuesIntoNextDay, isTrue);
  expect(second.continuesFromPreviousDay, isTrue);
  expect(second.visibleStart, DateTime(2026, 8, 19));
  expect(second.visibleEnd, DateTime(2026, 8, 19, 2));
});
```

- [ ] **Step 2: Run the focused Flutter test to verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_time_layout_test.dart
```

Expected: compile failure because `CalendarData.flowByDay` does not exist.

- [ ] **Step 3: Implement immutable slice projection**

Add `CalendarFlowSlice` and `bucketCalendarFlowRecords` to `calendar_models.dart`. For each non-input record:

```dart
if (!record.isEvent || record.item.allDay || record.endAt == null ||
    !record.endAt!.isAfter(record.effectiveAt)) {
  addSingleDaySlice(record);
  continue;
}

var day = calendarDayOf(record.effectiveAt);
while (day.isBefore(record.endAt!)) {
  final nextDay = day.add(const Duration(days: 1));
  final visibleStart = record.effectiveAt.isAfter(day)
      ? record.effectiveAt
      : day;
  final visibleEnd = record.endAt!.isBefore(nextDay)
      ? record.endAt!
      : nextDay;
  if (visibleStart.isBefore(visibleEnd)) addSlice(...);
  day = nextDay;
}
```

Build `flowByDay` from the already materialized `snapshot` in `CalendarData` so one-shot iterables remain single-pass. Sort slices by `visibleStart`, then canonical record ordering, and expose unmodifiable lists/maps.

- [ ] **Step 4: Run pure calendar tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_time_layout_test.dart
```

Expected: all tests pass, including the existing one-shot materialization test.

- [ ] **Step 5: Commit Task 3**

```bash
git add mobile/lib/theme_v2/calendar/calendar_models.dart mobile/test/theme_v2/calendar/calendar_time_layout_test.dart
git commit -m "feat(calendar): project cross-day flow slices"
```

---

### Task 4: Render continuation slices and keep one detail target

**Files:**
- Modify: `mobile/lib/theme_v2/calendar/calendar_flow_view.dart:88`
- Modify: `mobile/lib/theme_v2/calendar/calendar_components.dart:158`
- Modify: `mobile/test/theme_v2/calendar/calendar_flow_test.dart:360`

**Interfaces:**
- Consumes: `CalendarData.flowByDay` and `CalendarFlowSlice` from Task 3.
- Produces: Flow row labels `跨至明日` and `承接昨日`.
- Preserves: `ValueChanged<CalendarRecord> onOpenRecord`, using the canonical record from every slice.

- [ ] **Step 1: Write the failing widget test**

Add to `calendar_flow_test.dart`:

```dart
testWidgets('cross-day slices render on both days and open one event', (tester) async {
  final day = DateTime(2026, 8, 18);
  final data = CalendarData([
    calendarFixtureItem(
      id: 'event-cross-day',
      title: '线上会议',
      at: DateTime(2026, 8, 18, 23),
      endAt: DateTime(2026, 8, 19, 2),
    ),
  ], const {});
  final opened = <String>[];

  await tester.pumpWidget(calendarTestHost(CalendarFlowView(
    data: data,
    controller: CalendarController(),
    today: day,
    onOpenDay: (_) {},
    onRequestManualRecord: (_) {},
    onOpenRecord: (record) => opened.add(record.id),
    onOpenFlash: (_) {},
  )));
  await tester.pumpAndSettle();

  expect(find.text('跨至明日'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('calendar-flow-record-event-cross-day-2026-08-18')));
  await tester.drag(find.byKey(const ValueKey('calendar-flow-scroll')), const Offset(0, -500));
  await tester.pumpAndSettle();
  expect(find.text('承接昨日'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('calendar-flow-record-event-cross-day-2026-08-19')));
  expect(opened, ['event-cross-day', 'event-cross-day']);
});
```

- [ ] **Step 2: Run the widget test to verify it fails**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_flow_test.dart --plain-name "cross-day slices render on both days and open one event"
```

Expected: FAIL because the continuation labels and flow-specific keys are absent.

- [ ] **Step 3: Let record rows accept flow presentation overrides**

Extend `CalendarRecordRow` with optional `DateTime? displayAtOverride`, `String? continuationLabel`, and `Key? rowKey`. Use the override for its time label and semantics, render the continuation label after the title with muted mono styling, and use `rowKey ?? ValueKey('calendar-record-${record.id}')` for the `InkWell`.

- [ ] **Step 4: Convert Calendar Flow from records to slices**

Change `_FlowDay`, `_FlowBandGroup`, `_flowBandGroups`, and `_flowBandFor` to consume `CalendarFlowSlice`. Read slices from `widget.data.flowByDay[day]`, while flash counts continue to come from canonical `byDay` input turns.

For each row:

```dart
final continuationLabel = slice.continuesFromPreviousDay
    ? '承接昨日'
    : slice.continuesIntoNextDay
        ? '跨至明日'
        : null;
CalendarRecordRow(
  rowKey: ValueKey(
    'calendar-flow-record-${slice.record.id}-${calendarDayKey(slice.day)}',
  ),
  record: slice.record,
  displayAtOverride: slice.visibleStart,
  continuationLabel: continuationLabel,
  onTap: () => onOpenRecord(slice.record),
  ...
)
```

Update extent and visible-day calculations to use slice counts, so continuation-only days are not rendered as empty placeholders.

- [ ] **Step 5: Run focused and neighboring Flutter tests**

Run:

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_time_layout_test.dart
flutter test test/theme_v2/calendar/calendar_flow_test.dart
flutter test test/theme_v2/calendar/calendar_day_detail_test.dart
flutter test test/theme_v2/calendar/calendar_schedule_grid_test.dart
```

Expected: all tests pass; legacy rows retain their original keys and time labels outside Flow.

- [ ] **Step 6: Run targeted analysis**

Run:

```bash
cd mobile
flutter analyze lib/theme_v2/calendar/calendar_models.dart lib/theme_v2/calendar/calendar_flow_view.dart lib/theme_v2/calendar/calendar_components.dart test/theme_v2/calendar/calendar_time_layout_test.dart test/theme_v2/calendar/calendar_flow_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 7: Commit Task 4**

```bash
git add mobile/lib/theme_v2/calendar/calendar_flow_view.dart mobile/lib/theme_v2/calendar/calendar_components.dart mobile/test/theme_v2/calendar/calendar_flow_test.dart
git commit -m "feat(calendar): show cross-day event continuations"
```

---

### Task 5: Verify the original voice scenario and the complete change set

**Files:**
- Modify only if verification exposes a defect in files already listed above.

**Interfaces:**
- Consumes: all previous task outputs.
- Produces: fresh backend, Flutter, analyzer, and Android build evidence.

- [ ] **Step 1: Run all cross-day backend contracts**

```bash
cd backend
python scripts/test_cross_day_event_contract.py
python scripts/test_intent_normalizer.py
python scripts/test_flash_event_attendees_contract.py
python scripts/test_event_card_contract.py
python scripts/test_flash_reply_agent.py
```

Expected: every command exits 0.

- [ ] **Step 2: Run all affected Flutter tests**

```bash
cd mobile
flutter test test/theme_v2/calendar/calendar_time_layout_test.dart test/theme_v2/calendar/calendar_flow_test.dart test/theme_v2/calendar/calendar_day_detail_test.dart test/theme_v2/calendar/calendar_schedule_grid_test.dart
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Build the same product configuration used on the phone**

```bash
cd mobile
flutter build apk --debug --dart-define=THEME_V2=true --dart-define=TODAY_DOT_EXPERIMENT=true
```

Expected: `build/app/outputs/flutter-apk/app-debug.apk` is produced successfully.

- [ ] **Step 4: Install and manually exercise the original scenario**

Install without clearing data, then record:

> 今天晚上 11 点到 12 点，有一个线上会议，和小飞还有卓一起参加，主要讨论套利策略。

Verify one event is created, the flash session contains a completed event card, and Calendar Flow shows the event only on the starting date because the end is exactly next-day midnight.

Then record “今天晚上 11 点到 2 点有线上会议” and verify two Flow slices open one detail.

- [ ] **Step 5: Inspect the final diff and commit any verification-only correction**

Run `git diff --check` and `git status --short`. If no correction was necessary, do not create an empty commit. If a correction was necessary, rerun its focused test and commit only the already-scoped files with message `fix(events): close cross-day verification gap`.
