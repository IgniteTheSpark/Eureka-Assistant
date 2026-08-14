import 'package:eureka/theme_v2/calendar/calendar_models.dart';
import 'package:eureka/theme_v2/calendar/calendar_components.dart';
import 'package:eureka/theme_v2/calendar/calendar_time_layout.dart';
import 'package:eureka/timeline/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_fixtures.dart';

void main() {
  TimelineItem item({
    required String id,
    required DateTime at,
    String kind = 'event',
    String? skillName,
    DateTime? endAt,
    bool allDay = false,
    bool hasClockTime = false,
    bool hasScheduledTime = false,
    String period = '',
    DateTime? createdAt,
  }) {
    return TimelineItem(
      kind: kind,
      id: id,
      effectiveAt: at,
      createdAt: createdAt,
      title: id,
      subtitle: '',
      skillName: skillName,
      sessionId: null,
      derived: const {},
      endAt: endAt,
      allDay: allDay,
      hasClockTime: hasClockTime,
      hasScheduledTime: hasScheduledTime,
      period: period,
    );
  }

  CalendarRecord record({
    required String id,
    required DateTime at,
    String kind = 'event',
    String? skillName,
    DateTime? endAt,
    bool allDay = false,
    bool hasClockTime = false,
    bool hasScheduledTime = false,
    String period = '',
    DateTime? createdAt,
  }) {
    return CalendarRecord.fromTimeline(
      item(
        id: id,
        at: at,
        kind: kind,
        skillName: skillName,
        endAt: endAt,
        allDay: allDay,
        hasClockTime: hasClockTime,
        hasScheduledTime: hasScheduledTime,
        period: period,
        createdAt: createdAt,
      ),
    );
  }

  group('CalendarData', () {
    test('buckets and orders only by backend effectiveAt', () {
      final createdDay = DateTime(2026, 7, 1, 8);
      final effectiveDay = DateTime(2026, 7, 9);
      final fromJson = TimelineItem.fromJson({
        'kind': 'asset',
        'id': 'from-json',
        'effective_at': '2026-07-09T11:00:00',
        'created_at': createdDay.toIso8601String(),
        'title': 'from-json',
        'skill_name': 'notes',
      });
      final data = CalendarData([
        item(id: 'later', at: effectiveDay.add(const Duration(hours: 13))),
        item(id: 'tie-b', at: effectiveDay.add(const Duration(hours: 11))),
        fromJson,
        item(id: 'tie-a', at: effectiveDay.add(const Duration(hours: 11))),
      ], const {});

      expect(data.byDay.keys, [effectiveDay]);
      expect(data.byDay[effectiveDay]!.map((entry) => entry.id), [
        'from-json',
        'tie-a',
        'tie-b',
        'later',
      ]);
      expect(data.byDay.containsKey(DateTime(2026, 7, 1)), isFalse);
    });

    test('materializes a one-shot iterable exactly once', () {
      var iterations = 0;
      final at = DateTime(2026, 7, 9, 11);
      final sourceItem = item(id: 'one-shot', at: at);

      Iterable<TimelineItem> oneShot() sync* {
        iterations++;
        if (iterations > 1) {
          throw StateError('CalendarData iterated its source more than once');
        }
        yield sourceItem;
      }

      final data = CalendarData(oneShot(), const {});

      expect(iterations, 1);
      expect(data.items, [sourceItem]);
      expect(
        identical(data.byDay[DateTime(2026, 7, 9)]!.single, sourceItem),
        isTrue,
      );
      expect(identical(data.records.single.item, sourceItem), isTrue);
      expect(() => data.items.add(sourceItem), throwsUnsupportedError);
    });

    test('keeps asset and flash counts independent for a local day', () {
      final day = DateTime(2026, 7, 3);
      final flash = item(id: 'flash', at: day, kind: 'input_turn');
      final asset = item(
        id: 'asset',
        at: day.add(const Duration(hours: 9)),
        kind: 'asset',
        skillName: 'notes',
        hasClockTime: true,
      );
      final data = CalendarData([flash, asset], const {});

      expect(data.day(day).assetCount, 1);
      expect(data.day(day).flashCount, 1);
      expect(data.day(day).assets.single.id, 'asset');
      expect(data.day(day).flashes.single.id, 'flash');

      final flashOnly = CalendarData([flash], const {}).day(day);
      expect(flashOnly.assetCount, 0);
      expect(flashOnly.flashCount, 1);
    });
  });

  group('calendarDistanceLabel', () {
    final today = DateTime(2026, 7, 30);

    test('uses natural day and week copy with correct plurality', () {
      expect(calendarDistanceLabel(today, today), 'TODAY');
      expect(
        calendarDistanceLabel(DateTime(2026, 7, 31), today),
        '1 DAY LATER',
      );
      expect(calendarDistanceLabel(DateTime(2026, 7, 28), today), '2 DAYS AGO');
      expect(calendarDistanceLabel(DateTime(2026, 7, 23), today), '1 WEEK AGO');
      expect(
        calendarDistanceLabel(DateTime(2026, 7, 15), today),
        '2 WEEKS AGO',
      );
    });

    test('uses stable calendar month and year units', () {
      expect(
        calendarDistanceLabel(DateTime(2026, 8, 30), today),
        '1 MONTH LATER',
      );
      expect(
        calendarDistanceLabel(DateTime(2026, 5, 30), today),
        '2 MONTHS AGO',
      );
      expect(calendarDistanceLabel(DateTime(2025, 7, 30), today), '1 YEAR AGO');
      expect(
        calendarDistanceLabel(DateTime(2028, 7, 30), today),
        '2 YEARS LATER',
      );
    });
  });

  group('CalendarRecord classification', () {
    test('uses backend event, todo, clock, and period flags', () {
      final at = DateTime(2026, 7, 9, 14);
      final event = record(id: 'event', at: at);
      final allDay = record(id: 'all-day', at: at, allDay: true);
      final scheduledTodo = record(
        id: 'scheduled',
        at: at,
        kind: 'asset',
        skillName: 'todo',
        hasScheduledTime: true,
      );
      final captureFallbackTodo = record(
        id: 'fallback',
        at: at,
        kind: 'asset',
        skillName: 'todo',
        hasClockTime: true,
        hasScheduledTime: false,
      );
      final clockAsset = record(
        id: 'clock',
        at: at,
        kind: 'asset',
        skillName: 'notes',
        hasClockTime: true,
      );
      final notesCreationTime = record(
        id: 'notes-creation-time',
        at: at,
        kind: 'asset',
        skillName: 'notes',
      );
      final periodAsset = record(
        id: 'period',
        at: at,
        kind: 'asset',
        skillName: 'notes',
        period: '下午',
      );
      final contactCaptureFallback = record(
        id: 'contact',
        at: DateTime(2026, 7, 9, 9, 42),
        kind: 'contact',
      );
      final fuzzyPeriodWithCaptureClock = record(
        id: 'fuzzy-period',
        at: DateTime(2026, 7, 9, 9, 42),
        kind: 'asset',
        skillName: 'expense',
        period: '晚上',
      );
      final dateOnlyAsset = record(
        id: 'date-only',
        at: DateTime(2026, 7, 9),
        kind: 'asset',
        skillName: 'notes',
      );

      expect(event.timing, CalendarRecordTiming.timed);
      expect(allDay.timing, CalendarRecordTiming.allDay);
      expect(scheduledTodo.timing, CalendarRecordTiming.timed);
      expect(captureFallbackTodo.timing, CalendarRecordTiming.untimed);
      expect(clockAsset.timing, CalendarRecordTiming.timed);
      expect(notesCreationTime.timing, CalendarRecordTiming.timed);
      expect(periodAsset.timing, CalendarRecordTiming.untimed);
      expect(periodAsset.period, '下午');
      expect(contactCaptureFallback.timing, CalendarRecordTiming.timed);
      expect(fuzzyPeriodWithCaptureClock.timing, CalendarRecordTiming.untimed);
      expect(dateOnlyAsset.timing, CalendarRecordTiming.untimed);
    });

    test('uses creation time before id to break effective-time ties', () {
      final at = DateTime(2026, 7, 9, 11);
      final data = CalendarData([
        item(id: 'b', at: at, createdAt: DateTime(2026, 7, 9, 10, 1)),
        item(id: 'c', at: at, createdAt: DateTime(2026, 7, 9, 10)),
        item(id: 'a', at: at, createdAt: DateTime(2026, 7, 9, 10, 1)),
      ], const {});

      expect(data.byDay[DateTime(2026, 7, 9)]!.map((item) => item.id), [
        'c',
        'a',
        'b',
      ]);
    });

    testWidgets('notes render their creation clock instead of no time', (
      tester,
    ) async {
      final note = record(
        id: 'note-created-in-afternoon',
        at: DateTime(2026, 7, 9),
        createdAt: DateTime(2026, 7, 9, 14, 26),
        kind: 'asset',
        skillName: 'notes',
      );

      await tester.pumpWidget(
        calendarTestHost(
          CalendarRecordRow(
            ditherSourceId: 'test-note',
            record: note,
            skills: const {'notes': SkillMeta('📝', '随记')},
            onTap: () {},
          ),
        ),
      );

      expect(note.timing, CalendarRecordTiming.timed);
      expect(find.text('14:26'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      expect(find.text('—'), findsNothing);
    });
  });

  group('calendar time layout', () {
    test('uses valid event endAt including a cross-midnight duration', () {
      final sameDay = record(
        id: 'same-day',
        at: DateTime(2026, 7, 9, 9),
        endAt: DateTime(2026, 7, 9, 10, 15),
      );
      final crossMidnight = record(
        id: 'cross-midnight',
        at: DateTime(2026, 7, 9, 23, 30),
        endAt: DateTime(2026, 7, 10, 0, 30),
      );

      final slots = layoutCalendarTime([crossMidnight, sameDay]);

      expect(
        slots.singleWhere((slot) => slot.id == 'same-day').duration,
        const Duration(minutes: 75),
      );
      final overnight = slots.singleWhere(
        (slot) => slot.id == 'cross-midnight',
      );
      expect(overnight.duration, const Duration(minutes: 60));
      expect(overnight.startMinute, 23 * 60 + 30);
      expect(overnight.endMinute, 24 * 60 + 30);
    });

    test('falls back to 30 minutes for missing or invalid endAt', () {
      final at = DateTime(2026, 7, 9, 10);
      final slots = layoutCalendarTime([
        record(id: 'missing', at: at),
        record(id: 'equal', at: at, endAt: at),
        record(
          id: 'before',
          at: at,
          endAt: at.subtract(const Duration(minutes: 1)),
        ),
      ]);

      expect(slots.map((slot) => slot.duration).toSet(), {
        const Duration(minutes: 30),
      });
    });

    test('gives a positive sub-minute event a one-minute UI slot', () {
      final start = DateTime(2026, 7, 9, 10, 0, 30);
      final slot = layoutCalendarTime([
        record(
          id: 'sub-minute',
          at: start,
          endAt: DateTime(2026, 7, 9, 10, 0, 45),
        ),
      ]).single;

      expect(slot.startMinute, 10 * 60);
      expect(slot.endMinute, 10 * 60 + 1);
      expect(slot.duration, const Duration(minutes: 1));
    });

    test(
      'rounds a positive non-aligned duration up to its visible end minute',
      () {
        final start = DateTime(2026, 7, 9, 10, 0, 30);
        final slot = layoutCalendarTime([
          record(
            id: 'half-hour',
            at: start,
            endAt: DateTime(2026, 7, 9, 10, 30),
          ),
        ]).single;

        expect(slot.startMinute, 10 * 60);
        expect(slot.endMinute, 10 * 60 + 30);
        expect(slot.duration, const Duration(minutes: 30));
      },
    );

    test('excludes untimed records from overlap layout', () {
      final at = DateTime(2026, 7, 9, 10);
      final slots = layoutCalendarTime([
        record(
          id: 'scheduled',
          at: at,
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: true,
        ),
        record(
          id: 'capture-fallback',
          at: at,
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: false,
        ),
      ]);

      expect(slots.map((slot) => slot.id), ['scheduled']);
    });

    test('adjacent records do not overlap', () {
      final day = DateTime(2026, 7, 9);
      final slots = layoutCalendarTime([
        record(
          id: 'first',
          at: day.add(const Duration(hours: 9)),
          endAt: day.add(const Duration(hours: 10)),
        ),
        record(
          id: 'second',
          at: day.add(const Duration(hours: 10)),
          endAt: day.add(const Duration(hours: 11)),
        ),
      ]);

      expect(slots.map((slot) => slot.columnIndex), [0, 0]);
      expect(slots.map((slot) => slot.columnCount), [1, 1]);
    });

    test('transitive overlap shares one deterministic cluster', () {
      final day = DateTime(2026, 7, 9);
      final slots = layoutCalendarTime([
        record(
          id: 'c',
          at: day.add(const Duration(hours: 10)),
          endAt: day.add(const Duration(hours: 11)),
        ),
        record(
          id: 'a',
          at: day.add(const Duration(hours: 9)),
          endAt: day.add(const Duration(hours: 10)),
        ),
        record(
          id: 'b',
          at: day.add(const Duration(hours: 9, minutes: 30)),
          endAt: day.add(const Duration(hours: 10, minutes: 30)),
        ),
      ]);

      expect(slots.map((slot) => slot.id), ['a', 'b', 'c']);
      expect(slots.map((slot) => slot.columnIndex), [0, 1, 0]);
      expect(slots.map((slot) => slot.columnCount), [2, 2, 2]);
    });

    test('ties use end descending then id for stable column assignment', () {
      final day = DateTime(2026, 7, 9, 9);
      List<CalendarTimeLayoutEntry> arrange(List<String> ids) =>
          layoutCalendarTime([
            for (final id in ids)
              record(id: id, at: day, endAt: day.add(const Duration(hours: 1))),
          ]);

      final forward = arrange(['b', 'a']);
      final reverse = arrange(['a', 'b']);

      expect(forward.map((slot) => slot.id), ['a', 'b']);
      expect(reverse.map((slot) => slot.id), ['a', 'b']);
      expect(forward.map((slot) => slot.columnIndex), [0, 1]);
      expect(reverse.map((slot) => slot.columnIndex), [0, 1]);
    });
  });

  group('CalendarTodoBand', () {
    test('retains every same-minute scheduled todo in a 15-minute band', () {
      final at = DateTime(2026, 7, 9, 9, 30);
      final bands = buildCalendarTodoBands([
        record(
          id: 'b',
          at: at,
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: true,
        ),
        record(
          id: 'a',
          at: at,
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: true,
        ),
        record(
          id: 'same-visible-minute',
          at: at.add(const Duration(seconds: 1)),
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: true,
        ),
        record(
          id: 'different-minute',
          at: at.add(const Duration(minutes: 1)),
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: true,
        ),
        record(
          id: 'unscheduled',
          at: at,
          kind: 'asset',
          skillName: 'todo',
          hasScheduledTime: false,
        ),
      ]);

      expect(bands, hasLength(1));
      expect(bands.single.startAt, at);
      expect(bands.single.collapsedDuration, const Duration(minutes: 15));
      expect(bands.single.todos.map((todo) => todo.id), [
        'a',
        'b',
        'same-visible-minute',
      ]);
    });
  });
}
